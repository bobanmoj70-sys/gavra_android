-- Tabela za dedup vremenskih upozorenja (jedan alert po gradu+uslovu+danu)
CREATE TABLE IF NOT EXISTS "public"."v3_weather_alerts_sent" (
    "id" uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    "grad" text NOT NULL,
    "condition_code" text NOT NULL,
    "alert_date" date NOT NULL,
    "severity" text,
    "created_at" timestamptz NOT NULL DEFAULT now(),
    UNIQUE ("grad", "condition_code", "alert_date")
);

ALTER TABLE "public"."v3_weather_alerts_sent" ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'v3_weather_alerts_sent' AND policyname = 'Allow all'
  ) THEN
    CREATE POLICY "Allow all" ON "public"."v3_weather_alerts_sent"
      FOR ALL TO authenticated, anon, service_role USING (true) WITH CHECK (true);
  END IF;
END
$$;

GRANT ALL ON TABLE "public"."v3_weather_alerts_sent" TO "anon";
GRANT ALL ON TABLE "public"."v3_weather_alerts_sent" TO "authenticated";
GRANT ALL ON TABLE "public"."v3_weather_alerts_sent" TO "service_role";

-- RPC koju poziva v3-weather-alert edge funkcija: šalje push svim vozačima
-- (tip='vozac') za dati grad + tip opasnog vremenskog uslova, sa dedup po danu.
CREATE OR REPLACE FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text,
    "p_condition_code" text,
    "p_severity" text,
    "p_title_sr" text,
    "p_body_sr" text,
    "p_title_en" text,
    "p_body_en" text,
    "p_title_ru" text,
    "p_body_ru" text,
    "p_title_de" text,
    "p_body_de" text
) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_grad text := upper(trim(coalesce(p_grad, '')));
  v_condition text := lower(trim(coalesce(p_condition_code, '')));
  v_today date := (now() at time zone 'Europe/Belgrade')::date;
  v_claimed boolean := false;
  v_tokens jsonb;
  v_notified integer := 0;
  v_event_id text;
begin
  insert into public.v3_weather_alerts_sent (grad, condition_code, alert_date, severity)
  values (v_grad, v_condition, v_today, p_severity)
  on conflict (grad, condition_code, alert_date) do nothing;

  get diagnostics v_claimed = row_count;

  if not v_claimed then
    return jsonb_build_object('ok', true, 'skipped', true, 'reason', 'already_sent_today');
  end if;

  with token_rows as (
    select jsonb_build_object('token', a.push_token, 'provider', 'fcm') as tkn
    from public.v3_auth a
    where a.tip = 'vozac' and a.push_token is not null and btrim(a.push_token) <> ''

    union

    select jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') as tkn
    from public.v3_auth a
    where a.tip = 'vozac' and a.push_token_2 is not null and btrim(a.push_token_2) <> ''
  )
  select coalesce(jsonb_agg(tkn), '[]'::jsonb), count(*)
  into v_tokens, v_notified
  from token_rows;

  if v_notified = 0 then
    return jsonb_build_object('ok', true, 'notified', 0);
  end if;

  v_event_id := format('weather_alert:%s:%s:%s', v_grad, v_condition, v_today::text);

  perform public.notify_push(
    v_tokens,
    p_title_sr,
    p_body_sr,
    jsonb_build_object(
      'type', 'weather_alert',
      'event_id', v_event_id,
      'grad', v_grad,
      'condition_code', v_condition,
      'severity', p_severity,
      'screen', 'v3_vozac',
      'title_sr', p_title_sr,
      'title_en', p_title_en,
      'title_ru', p_title_ru,
      'title_de', p_title_de,
      'body_sr', p_body_sr,
      'body_en', p_body_en,
      'body_ru', p_body_ru,
      'body_de', p_body_de
    )
  );

  return jsonb_build_object('ok', true, 'notified', v_notified, 'event_id', v_event_id);
end;
$$;

ALTER FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text
) OWNER TO "postgres";

GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text
) TO "anon";
GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text
) TO "authenticated";
GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text
) TO "service_role";

-- Funkcija koja se poziva iz pg_cron i okida v3-weather-alert edge funkciju
CREATE OR REPLACE FUNCTION "public"."v3_trigger_weather_alert"()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_supabase_url text;
  v_anon_key text;
BEGIN
  SELECT decrypted_secret INTO v_supabase_url
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_url'
  ORDER BY updated_at DESC
  LIMIT 1;

  SELECT decrypted_secret INTO v_anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'supabase_anon_key'
  ORDER BY updated_at DESC
  LIMIT 1;

  IF v_supabase_url IS NULL OR v_supabase_url = '' THEN
    RAISE NOTICE 'v3_trigger_weather_alert: missing supabase_url vault secret';
    RETURN;
  END IF;

  IF v_anon_key IS NULL OR v_anon_key = '' THEN
    RAISE NOTICE 'v3_trigger_weather_alert: missing supabase_anon_key vault secret';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/v3-weather-alert',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_anon_key,
      'apikey', v_anon_key
    ),
    body := '{}'::jsonb
  );
END;
$$;

COMMENT ON FUNCTION public.v3_trigger_weather_alert IS 'Poziva v3-weather-alert edge funkciju svakih 30 minuta radi provere opasnih vremenskih uslova (sneg, poledica, magla, oluja, ekstremna vrucina)';

-- Zakazi cron job da radi svakih 30 minuta
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'v3-weather-alert') THEN
      PERFORM cron.unschedule('v3-weather-alert');
    END IF;
    PERFORM cron.schedule(
      'v3-weather-alert',
      '*/30 * * * *',
      'SELECT public.v3_trigger_weather_alert();'
    );
  END IF;
END
$$;
