-- Dodaje p_title_zh/p_body_zh (kineski) opcione parametre RPC funkciji
-- v3_notify_vozaci_weather_alert, bez menjanja postojeceg ponasanja za
-- ostale jezike. Novi parametri imaju DEFAULT NULL kako bi stari pozivi
-- (bez zh) i dalje radili nepromenjeno.

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
    "p_body_de" text,
    "p_title_zh" text DEFAULT NULL,
    "p_body_zh" text DEFAULT NULL
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
      'title_zh', p_title_zh,
      'body_sr', p_body_sr,
      'body_en', p_body_en,
      'body_ru', p_body_ru,
      'body_de', p_body_de,
      'body_zh', p_body_zh
    )
  );

  return jsonb_build_object('ok', true, 'notified', v_notified, 'event_id', v_event_id);
end;
$$;

ALTER FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text,
    "p_title_zh" text, "p_body_zh" text
) OWNER TO "postgres";

GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text,
    "p_title_zh" text, "p_body_zh" text
) TO "anon";
GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text,
    "p_title_zh" text, "p_body_zh" text
) TO "authenticated";
GRANT ALL ON FUNCTION "public"."v3_notify_vozaci_weather_alert"(
    "p_grad" text, "p_condition_code" text, "p_severity" text,
    "p_title_sr" text, "p_body_sr" text, "p_title_en" text, "p_body_en" text,
    "p_title_ru" text, "p_body_ru" text, "p_title_de" text, "p_body_de" text,
    "p_title_zh" text, "p_body_zh" text
) TO "service_role";
