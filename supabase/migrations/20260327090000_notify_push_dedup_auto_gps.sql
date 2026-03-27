-- Hotfix: dedup metapodaci + auto GPS RPC
-- Datum: 2026-03-27
-- Ciljevi:
-- 1) notify_push šalje event/dedup metapodatke ka Edge funkciji
-- 2) fn_v3_notify_putnik_on_zahtev_update prosleđuje recipient/entity podatke
-- 3) dodaje fn_v3_trigger_auto_gps_start RPC koji Flutter app očekuje

-- =====================================================
-- 1) notify_push: prosledi dedup metapodatke ka Edge funkciji
-- =====================================================
CREATE OR REPLACE FUNCTION public.notify_push(
  tokens jsonb,
  title text,
  body text,
  data jsonb DEFAULT NULL::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  supabase_url text;
  anon_key text;

  firebase_admin_sdk text;
  firebase_sa_078c775e7b11 text;
  firebase_sa_81779c4cc1fa text;

  huawei_hms_client_id text;
  huawei_hms_client_secret text;
  huawei_oauth_client_id text;
  huawei_oauth_client_secret text;
  huawei_app_id text;

  payload_data jsonb;
  payload_event_id text;
  payload_type text;
  payload_entity_id text;
  payload_recipient_id text;
BEGIN
  SELECT decrypted_secret
  INTO supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO firebase_admin_sdk
  FROM vault.decrypted_secrets
  WHERE name = 'firebase_admin_sdk'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO firebase_sa_078c775e7b11
  FROM vault.decrypted_secrets
  WHERE name = 'firebase_sa_078c775e7b11'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO firebase_sa_81779c4cc1fa
  FROM vault.decrypted_secrets
  WHERE name = 'firebase_sa_81779c4cc1fa'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO huawei_hms_client_id
  FROM vault.decrypted_secrets
  WHERE name = 'huawei_hms_client_id'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO huawei_hms_client_secret
  FROM vault.decrypted_secrets
  WHERE name = 'huawei_hms_client_secret'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO huawei_oauth_client_id
  FROM vault.decrypted_secrets
  WHERE name = 'huawei_oauth_client_id'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret
  INTO huawei_oauth_client_secret
  FROM vault.decrypted_secrets
  WHERE name = 'huawei_oauth_client_secret'
  ORDER BY updated_at DESC
  LIMIT 1;

  huawei_app_id := huawei_oauth_client_id;
  payload_data := COALESCE(data, '{}'::jsonb);

  payload_event_id := NULLIF(BTRIM(payload_data->>'event_id'), '');
  payload_type := NULLIF(BTRIM(payload_data->>'type'), '');
  payload_entity_id := COALESCE(
    NULLIF(BTRIM(payload_data->>'entity_id'), ''),
    NULLIF(BTRIM(payload_data->>'zahtev_id'), ''),
    NULLIF(BTRIM(payload_data->>'id'), '')
  );
  payload_recipient_id := COALESCE(
    NULLIF(BTRIM(payload_data->>'recipient_id'), ''),
    NULLIF(BTRIM(payload_data->>'putnik_id'), ''),
    NULLIF(BTRIM(payload_data->>'vozac_id'), '')
  );

  IF supabase_url IS NULL OR supabase_url = '' THEN
    RAISE NOTICE 'Push notification error: missing vault secret supabase_url';
    RETURN;
  END IF;

  IF anon_key IS NULL OR anon_key = '' THEN
    RAISE NOTICE 'Push notification error: missing vault secret supabase_anon_key';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := supabase_url || '/functions/v1/send-push-notification',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || anon_key,
      'apikey', anon_key
    ),
    body := jsonb_build_object(
      'tokens', tokens,
      'title', title,
      'body', body,
      'event_id', payload_event_id,
      'type', payload_type,
      'entity_id', payload_entity_id,
      'recipient_id', payload_recipient_id,
      'data', payload_data,
      'data_only',
        CASE
          WHEN payload_data ? 'data_only' THEN (payload_data->>'data_only')::boolean
          ELSE false
        END,
      '_secrets', jsonb_strip_nulls(
        jsonb_build_object(
          'firebase_admin_sdk', firebase_admin_sdk,
          'firebase_sa_078c775e7b11', firebase_sa_078c775e7b11,
          'firebase_sa_81779c4cc1fa', firebase_sa_81779c4cc1fa,
          'huawei_hms_client_id', huawei_hms_client_id,
          'huawei_hms_client_secret', huawei_hms_client_secret,
          'huawei_oauth_client_id', huawei_oauth_client_id,
          'huawei_oauth_client_secret', huawei_oauth_client_secret,
          'huawei_app_id', huawei_app_id
        )
      )
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Push notification error: %', SQLERRM;
END;
$function$;

-- =====================================================
-- 2) Dopuna putnik update notifikacije sa dedup poljima
-- =====================================================
CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_zahtev_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_tokens jsonb;
  v_title  text;
  v_body   text;
  v_data   jsonb;
  v_grad   text;
  v_vreme  text;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  v_grad := CASE
    WHEN NEW.grad = 'BC' THEN 'Bela Crkva'
    WHEN NEW.grad = 'VS' THEN 'Vršac'
    ELSE NEW.grad
  END;

  SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
  INTO v_tokens
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
    AND push_token IS NOT NULL
    AND push_token <> ''
  LIMIT 1;

  IF v_tokens IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.status IN ('odobreno', 'alternativa', 'ponuda') THEN
    RETURN NEW;
  END IF;

  v_vreme := COALESCE(
    to_char(NEW.dodeljeno_vreme, 'HH24:MI'),
    CASE
      WHEN NULLIF(BTRIM(NEW.zeljeno_vreme), '') IS NULL THEN NULL
      WHEN BTRIM(NEW.zeljeno_vreme) ~ '^\d{1,2}:\d{2}(:\d{2})?$' THEN to_char((BTRIM(NEW.zeljeno_vreme))::time, 'HH24:MI')
      ELSE BTRIM(NEW.zeljeno_vreme)
    END,
    ''
  );

  IF NEW.status = 'odbijeno' THEN
    v_title := '❌ Termin popunjen';
    v_body  := 'Nažalost, u terminu ' || v_vreme || ' nema slobodnih mesta (' || v_grad || ').';
    v_data  := jsonb_build_object(
      'type', 'v3_zahtev_odbijen',
      'entity_id', NEW.id,
      'zahtev_id', NEW.id,
      'recipient_id', NEW.putnik_id,
      'putnik_id', NEW.putnik_id,
      'id', NEW.id,
      'grad', NEW.grad,
      'status', NEW.status
    );
  ELSIF NEW.status = 'otkazano' THEN
    v_title := '🚫 Prevoz otkazan';
    v_body  := 'Vaš prevoz za ' || v_vreme || ' (' || v_grad || ') je otkazan.';
    v_data  := jsonb_build_object(
      'type', 'v3_otkazano',
      'entity_id', NEW.id,
      'zahtev_id', NEW.id,
      'recipient_id', NEW.putnik_id,
      'putnik_id', NEW.putnik_id,
      'id', NEW.id,
      'grad', NEW.grad,
      'status', NEW.status
    );
  END IF;

  IF v_title IS NOT NULL THEN
    PERFORM notify_push(v_tokens, v_title, v_body, v_data);
  END IF;

  RETURN NEW;
END;
$function$;

-- =====================================================
-- 3) RPC: fn_v3_trigger_auto_gps_start
--    App ga zove iz lib/main.dart
-- =====================================================
CREATE OR REPLACE FUNCTION public.fn_v3_trigger_auto_gps_start(
  p_vozac_id uuid,
  p_polazak_vreme text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_now_local timestamp;
  v_today date;
  v_tomorrow date;

  v_target_time time;
  v_target_grad text;

  v_row record;
  v_vozac_ime text;
  v_putnici_count integer;
BEGIN
  IF p_vozac_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Nedostaje vozac_id.'
    );
  END IF;

  SELECT ime_prezime
  INTO v_vozac_ime
  FROM public.v3_vozaci
  WHERE id = p_vozac_id
  LIMIT 1;

  IF v_vozac_ime IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Vozač nije pronađen.'
    );
  END IF;

  v_now_local := timezone('Europe/Belgrade', now());
  v_today := v_now_local::date;
  v_tomorrow := v_today + 1;

  -- Parsiranje grad tokena
  IF upper(coalesce(p_polazak_vreme, '')) like '%BC%' THEN
    v_target_grad := 'BC';
  ELSIF upper(coalesce(p_polazak_vreme, '')) like '%VS%' THEN
    v_target_grad := 'VS';
  ELSE
    v_target_grad := NULL;
  END IF;

  -- Parsiranje HH:MM iz stringa
  BEGIN
    v_target_time := substring(coalesce(p_polazak_vreme, '') from '(\d{1,2}:\d{2})')::time;
  EXCEPTION WHEN OTHERS THEN
    v_target_time := NULL;
  END;

  -- Biramo najrelevantniji slot (danas/sutra, aktivan, nije otkazan/odbijen)
  -- Ako je prosleđen target time/grad, prioritet je exact match.
  WITH kandidat AS (
    SELECT
      o.datum,
      o.grad,
      coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) as slot_time,
      abs(extract(epoch from (
        ((o.datum::timestamp + coalesce(o.dodeljeno_vreme, o.zeljeno_vreme)) - v_now_local)
      ))) as score,
      CASE
        WHEN v_target_time IS NOT NULL
             AND coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) = v_target_time
             AND (v_target_grad IS NULL OR o.grad = v_target_grad)
          THEN 0
        ELSE 1
      END as priority
    FROM public.v3_operativna_nedelja o
    WHERE o.vozac_id = p_vozac_id
      AND o.aktivno = true
      AND o.putnik_id IS NOT NULL
      AND o.status_final NOT IN ('otkazano', 'odbijeno')
      AND o.datum BETWEEN v_today AND v_tomorrow
      AND coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) IS NOT NULL
      AND (v_target_grad IS NULL OR o.grad = v_target_grad)
  )
  SELECT *
  INTO v_row
  FROM kandidat
  ORDER BY priority ASC, score ASC
  LIMIT 1;

  IF v_row.datum IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Nema aktivnih termina za auto GPS start.'
    );
  END IF;

  SELECT count(*)::int
  INTO v_putnici_count
  FROM public.v3_operativna_nedelja o
  WHERE o.vozac_id = p_vozac_id
    AND o.aktivno = true
    AND o.putnik_id IS NOT NULL
    AND o.status_final NOT IN ('otkazano', 'odbijeno')
    AND o.datum = v_row.datum
    AND o.grad = v_row.grad
    AND coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) = v_row.slot_time;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Auto GPS slot pronađen.',
    'vozac_id', p_vozac_id,
    'vozac_ime', v_vozac_ime,
    'datum', v_row.datum,
    'grad', v_row.grad,
    'vreme', to_char(v_row.slot_time, 'HH24:MI'),
    'putnici_count', coalesce(v_putnici_count, 0)
  );
END;
$function$;
