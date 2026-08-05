-- Multi-driver na istom slotu (datum,grad,vreme):
--   v3_trenutna_dodela_slot  = zajednički kontejner termina
--   v3_trenutna_dodela       = individualna dodela (vozac_v3_auth_id = čiji je putnik)
--
-- Push "vozač krenuo" ide SAMO putnicima iz dodele tog vozača, jednom po putniku.
-- Slot.vozac_v3_auth_id / slot.auto_notified_at VIŠE NISU izvor istine za notify.

ALTER TABLE public.v3_trenutna_dodela
  ADD COLUMN IF NOT EXISTS driver_started_notified_at timestamptz;

COMMENT ON COLUMN public.v3_trenutna_dodela.driver_started_notified_at IS
  'Kada je ovom putniku poslat push da je NJEGOV vozač krenuo. Idempotencija po individualnoj dodeli (multi-driver safe).';

-- Notify: isključivo preko v3_trenutna_dodela.vozac_v3_auth_id (bez OR na slot owner).
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

  -- Putnici OVOG vozača na terminu, još neobavešteni, aktivni.
  SELECT coalesce(array_agg(td.termin_id), '{}'::uuid[])
  INTO v_termin_ids
  FROM public.v3_trenutna_dodela td
  INNER JOIN public.v3_operativna_nedelja o ON o.id = td.termin_id
  WHERE td.vozac_v3_auth_id = p_vozac_id
    AND td.driver_started_notified_at IS NULL
    AND o.created_by IS NOT NULL
    AND o.otkazano_at IS NULL
    AND o.pokupljen_at IS NULL
    AND o.datum = p_datum
    AND upper(trim(coalesce(o.grad, ''))) = v_grad
    AND date_trunc('minute', o.polazak_at) = date_trunc('minute', p_vreme);

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

  -- Idempotencija po individualnoj dodeli (i ako nema tokena — ne spamuj ponovo).
  UPDATE public.v3_trenutna_dodela
  SET driver_started_notified_at = now()
  WHERE termin_id = ANY (v_termin_ids)
    AND vozac_v3_auth_id = p_vozac_id
    AND driver_started_notified_at IS NULL;

  RETURN jsonb_build_object(
    'ok', true,
    'notified', v_notified,
    'event_id', v_event_id,
    'termin_count', coalesce(array_length(v_termin_ids, 1), 0)
  );
END;
$$;

COMMENT ON FUNCTION public.v3_notify_passengers_driver_started(uuid, date, text, time) IS
  'Push putnicima da je vozač krenuo — samo putnici iz v3_trenutna_dodela za p_vozac_id. Multi-driver safe.';

-- Stari trigger na slot.tracking_started_at + slot.vozac + auto_notified_at
-- radi samo za "prvog" vozača. Notify sada zove activateSlotWithRetry (RPC).
DROP TRIGGER IF EXISTS trg_v3_notify_passengers_on_tracking_start ON public.v3_trenutna_dodela_slot;

DROP FUNCTION IF EXISTS public.v3_notify_passengers_on_tracking_start();
