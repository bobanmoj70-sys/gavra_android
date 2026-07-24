CREATE OR REPLACE FUNCTION "public"."v3_notify_passengers_driver_started"("p_vozac_id" "uuid", "p_datum" "date", "p_grad" "text", "p_vreme" time without time zone) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_grad text := upper(trim(coalesce(p_grad, '')));
  v_tokens jsonb;
  v_notified integer := 0;
  v_event_id text;
begin
  with target_putnici as (
    select distinct o.created_by as putnik_id
    from public.v3_operativna_nedelja o
    where o.created_by is not null
      and o.otkazano_at is null
      and o.pokupljen_at is null
      and o.datum = p_datum
      and upper(trim(coalesce(o.grad, ''))) = v_grad
      and date_trunc('minute', o.polazak_at) = date_trunc('minute', p_vreme)
      and (
        exists (
          select 1
          from public.v3_trenutna_dodela td
          where td.termin_id = o.id
            and td.vozac_v3_auth_id = p_vozac_id
        )
        or exists (
          select 1
          from public.v3_trenutna_dodela_slot ts
          where ts.vozac_v3_auth_id = p_vozac_id
            and ts.datum = p_datum
            and upper(trim(coalesce(ts.grad, ''))) = v_grad
            and date_trunc('minute', ts.vreme) = date_trunc('minute', p_vreme)
        )
      )
  ),
  token_rows as (
    select jsonb_build_object('token', a.push_token, 'provider', 'fcm') as tkn
    from public.v3_auth a
    join target_putnici tp on tp.putnik_id = a.id
    where a.push_token is not null and btrim(a.push_token) <> ''

    union

    select jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') as tkn
    from public.v3_auth a
    join target_putnici tp on tp.putnik_id = a.id
    where a.push_token_2 is not null and btrim(a.push_token_2) <> ''
  )
  select coalesce(jsonb_agg(tkn), '[]'::jsonb), count(*)
  into v_tokens, v_notified
  from token_rows;

  if v_notified = 0 then
    return jsonb_build_object('ok', true, 'notified', 0);
  end if;

  v_event_id := format(
    'driver_started:%s:%s:%s:%s',
    p_vozac_id::text,
    p_datum::text,
    v_grad,
    to_char(p_vreme, 'HH24:MI')
  );

  perform public.notify_push(
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
      'screen', 'v3_putnik_profil'
    )
  );

  return jsonb_build_object('ok', true, 'notified', v_notified, 'event_id', v_event_id);
end;
$$;


ALTER FUNCTION "public"."v3_notify_passengers_driver_started"("p_vozac_id" "uuid", "p_datum" "date", "p_grad" "text", "p_vreme" time without time zone) OWNER TO "postgres";

GRANT ALL ON FUNCTION "public"."v3_notify_passengers_driver_started"("p_vozac_id" "uuid", "p_datum" "date", "p_grad" "text", "p_vreme" time without time zone) TO "anon";
GRANT ALL ON FUNCTION "public"."v3_notify_passengers_driver_started"("p_vozac_id" "uuid", "p_datum" "date", "p_grad" "text", "p_vreme" time without time zone) TO "authenticated";
GRANT ALL ON FUNCTION "public"."v3_notify_passengers_driver_started"("p_vozac_id" "uuid", "p_datum" "date", "p_grad" "text", "p_vreme" time without time zone) TO "service_role";
