-- Fix race condition for "driver started" passenger push notifications.
--
-- Problem:
-- Parallel RPC calls could both read the same eligible rows before either
-- updated `driver_started_notified_at`, causing duplicate pushes.
--
-- Fix:
-- Atomically claim eligible rows first via UPDATE ... RETURNING, then build
-- token list and send push only for claimed rows.

CREATE OR REPLACE FUNCTION public.v3_notify_passengers_driver_started(
  p_vozac_id uuid,
  p_datum date,
  p_grad text,
  p_vreme time without time zone
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_grad text := upper(trim(coalesce(p_grad, '')));
  v_tokens jsonb;
  v_notified integer := 0;
  v_event_id text;
  v_termin_ids uuid[];
BEGIN
  IF p_vozac_id IS NULL OR p_datum IS NULL OR v_grad = '' OR p_vreme IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_args');
  END IF;

  -- Atomic claim: only one concurrent call can claim each row.
  WITH claimed AS (
    UPDATE public.v3_trenutna_dodela td
    SET driver_started_notified_at = now()
    FROM public.v3_operativna_nedelja o
    WHERE o.id = td.termin_id
      AND td.vozac_v3_auth_id = p_vozac_id
      AND td.driver_started_notified_at IS NULL
      AND o.created_by IS NOT NULL
      AND o.otkazano_at IS NULL
      AND o.pokupljen_at IS NULL
      AND o.datum = p_datum
      AND upper(trim(coalesce(o.grad, ''))) = v_grad
      AND date_trunc('minute', o.polazak_at) = date_trunc('minute', p_vreme)
    RETURNING td.termin_id
  )
  SELECT coalesce(array_agg(DISTINCT termin_id), '{}'::uuid[])
  INTO v_termin_ids
  FROM claimed;

  IF coalesce(array_length(v_termin_ids, 1), 0) = 0 THEN
    RETURN jsonb_build_object('ok', true, 'notified', 0);
  END IF;

  WITH target_putnici AS (
    SELECT DISTINCT o.created_by AS putnik_id
    FROM public.v3_operativna_nedelja o
    WHERE o.id = ANY (v_termin_ids)
  ),
  token_rows AS (
    SELECT jsonb_build_object('token', a.push_token, 'provider', 'fcm') AS tkn
    FROM public.v3_auth a
    JOIN target_putnici tp ON tp.putnik_id = a.id
    WHERE a.push_token IS NOT NULL AND btrim(a.push_token) <> ''

    UNION

    SELECT jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') AS tkn
    FROM public.v3_auth a
    JOIN target_putnici tp ON tp.putnik_id = a.id
    WHERE a.push_token_2 IS NOT NULL AND btrim(a.push_token_2) <> ''
  )
  SELECT coalesce(jsonb_agg(tkn), '[]'::jsonb), count(*)
  INTO v_tokens, v_notified
  FROM token_rows;

  v_event_id := format(
    'driver_started:%s:%s:%s:%s',
    p_vozac_id::text,
    p_datum::text,
    v_grad,
    to_char(p_vreme, 'HH24:MI')
  );

  IF v_notified > 0 THEN
    PERFORM public.notify_push(
      v_tokens,
      'Vozač je krenuo, molimo budite spremni na vreme',
      'Procenjeno vreme dolaska možete pratiti uživo na vašem profilu.',
      jsonb_build_object(
        'type', 'putnik_eta_start',
        'event_id', v_event_id,
        'vozac_id', p_vozac_id,
        'datum', p_datum,
        'grad', v_grad,
        'vreme', to_char(p_vreme, 'HH24:MI'),
        'screen', 'v3_putnik_profil',
        'title_sr', 'Vozač je krenuo, molimo budite spremni na vreme',
        'title_en', 'Driver is on the way, please be ready on time',
        'title_ru', 'Водитель выехал, пожалуйста, будьте готовы вовремя',
        'title_de', 'Der Fahrer ist unterwegs, bitte seien Sie pünktlich bereit',
        'title_zh', '司机已出发，请准时准备好',
        'body_sr', 'Procenjeno vreme dolaska možete pratiti uživo na vašem profilu.',
        'body_en', 'You can track the estimated arrival time live on your profile.',
        'body_ru', 'Вы можете отслеживать предполагаемое время прибытия в реальном времени в своем профиле.',
        'body_de', 'Die geschätzte Ankunftszeit können Sie live in Ihrem Profil verfolgen.',
        'body_zh', '您可以在个人资料中实时跟踪预计到达时间。'
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'notified', v_notified,
    'event_id', v_event_id,
    'termin_count', coalesce(array_length(v_termin_ids, 1), 0)
  );
END;
$$;

COMMENT ON FUNCTION public.v3_notify_passengers_driver_started(uuid, date, text, time) IS
  'Push putnicima da je vozač krenuo — race-safe: najpre atomically claim preko UPDATE ... RETURNING, pa notify.';
