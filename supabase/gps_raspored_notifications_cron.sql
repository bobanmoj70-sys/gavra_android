-- =====================================================
-- GPS NOTIFIKACIJE: 15min push notifikacije + cron
-- =====================================================
-- ISTORIJA MIGRACIJE:
--   Originalno: koristilo v3_gps_raspored (zasebna tabela)
--   Migracija: v3_gps_raspored tabela je uklonjena.
--              Sve GPS kolone su premeštene u v3_operativna_nedelja.
--              Funkcije su prepisane da direktno koriste v3_operativna_nedelja.
--
-- Cilj:
-- 1) Slati push notifikacije vozaču + putnicima za konkretan termin
--    kada activation_time <= now() (15 min pre polaska)
-- 2) Obezbediti idempotentnost preko notification_sent flag-a
-- 3) Cron jobovi generišu se dinamički po aktivnim vremenskim slotovima
--
-- NAPOMENA: Trigger tr_v3_gps_raspored_populate_coordinates je uklonjen
-- zajedno sa tabelom v3_gps_raspored. Polja polazak_vreme i activation_time
-- se sada popunjavaju direktno na v3_operativna_nedelja.

BEGIN;

-- -----------------------------------------------------
-- 1) Funkcija za slanje 15-min push notifikacija za konkretan slot
--    KORISTI: v3_operativna_nedelja (WHERE vozac_id IS NOT NULL)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_v3_gps_departure_notifications_for_polazak(p_vreme time without time zone)
RETURNS TABLE(sent_terms integer, sent_tokens integer, log_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
declare
  term_rec record;
  vozac_token text;
  putnik_tokens jsonb;
  putnik_token_count integer;
  putnici_count integer;
  v_title text;
  v_body text;
  cnt_terms integer := 0;
  cnt_tokens integer := 0;
begin
  for term_rec in
    select distinct
      o.vozac_id,
      o.datum,
      o.grad,
      coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) as vreme,
      o.nav_bar_type,
      o.polazak_vreme,
      o.activation_time
    from public.v3_operativna_nedelja o
    where o.aktivno = true
      and coalesce(o.notification_sent, false) = false
      and coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) = p_vreme
      and o.polazak_vreme is not null
      and o.activation_time is not null
      and o.activation_time <= now()
      and o.polazak_vreme > now() - interval '20 minutes'
      and o.vozac_id is not null
  loop
    select count(*)::int
    into putnici_count
    from public.v3_operativna_nedelja og
    where og.vozac_id = term_rec.vozac_id
      and og.datum = term_rec.datum
      and og.grad = term_rec.grad
      and coalesce(og.dodeljeno_vreme, og.zeljeno_vreme) = term_rec.vreme
      and og.nav_bar_type = term_rec.nav_bar_type
      and og.aktivno = true
      and og.putnik_id is not null;

    -- Push VOZAČU
    select v.push_token
    into vozac_token
    from public.v3_vozaci v
    where v.id = term_rec.vozac_id
      and v.aktivno = true
      and v.push_token is not null
      and v.push_token <> ''
    limit 1;

    if vozac_token is not null then
      perform public.notify_push(
        jsonb_build_array(jsonb_build_object('token', vozac_token, 'provider', 'fcm')),
        '🚗 Vožnja kreće - GPS tracking',
        format(
          'Termin %s %s (%s putnika). Drži tracking uključen do poslednjeg pokupljenog.',
          to_char(term_rec.vreme, 'HH24:MI'),
          term_rec.grad,
          putnici_count
        ),
        jsonb_build_object(
          'type', 'gps_tracking_start',
          'vozac_id', term_rec.vozac_id,
          'datum', term_rec.datum,
          'grad', term_rec.grad,
          'polazak_vreme', term_rec.polazak_vreme,
          'vreme', to_char(term_rec.vreme, 'HH24:MI:SS'),
          'putnici_count', putnici_count,
          'nav_bar_type', term_rec.nav_bar_type,
          'action_keep_tracking', 'true'
        )
      );
      cnt_tokens := cnt_tokens + 1;
    end if;

    -- Push PUTNICIMA
    with t as (
      select distinct p.push_token as token
      from public.v3_operativna_nedelja og
      join public.v3_putnici p on p.id = og.putnik_id
      where og.vozac_id = term_rec.vozac_id
        and og.datum = term_rec.datum
        and og.grad = term_rec.grad
        and coalesce(og.dodeljeno_vreme, og.zeljeno_vreme) = term_rec.vreme
        and og.nav_bar_type = term_rec.nav_bar_type
        and og.aktivno = true
        and p.aktivno = true
        and p.push_token is not null
        and p.push_token <> ''
    )
    select
      coalesce(jsonb_agg(jsonb_build_object('token', t.token, 'provider', 'fcm')), '[]'::jsonb),
      count(*)::int
    into putnik_tokens, putnik_token_count
    from t;

    if putnik_token_count > 0 then
      v_title := '🚗 Vozač je krenuo';
      v_body := format(
        'Termin %s %s je aktivan. ETA tracking je uključen uživo.',
        to_char(term_rec.vreme, 'HH24:MI'),
        term_rec.grad
      );

      perform public.notify_push(
        putnik_tokens,
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'v3_putnik_eta_start',
          'vozac_id', term_rec.vozac_id,
          'datum', term_rec.datum,
          'grad', term_rec.grad,
          'vreme', to_char(term_rec.vreme, 'HH24:MI:SS'),
          'nav_bar_type', term_rec.nav_bar_type,
          'enable_eta_widget', 'true',
          'screen', 'v3_putnik_profil'
        )
      );

      cnt_tokens := cnt_tokens + putnik_token_count;
    end if;

    -- Označi ceo termin kao notifikovan (idempotentno)
    update public.v3_operativna_nedelja
    set
      notification_sent = true,
      gps_status = case
        when gps_status = 'pending' then 'activated'
        else gps_status
      end,
      updated_at = now(),
      updated_by = 'cron:gps-15min-notify'
    where vozac_id = term_rec.vozac_id
      and datum = term_rec.datum
      and grad = term_rec.grad
      and coalesce(dodeljeno_vreme, zeljeno_vreme) = term_rec.vreme
      and nav_bar_type = term_rec.nav_bar_type
      and aktivno = true;

    cnt_terms := cnt_terms + 1;
  end loop;

  return query
  select
    cnt_terms,
    cnt_tokens,
    format('GPS 15min notify (%s): termini=%s, tokena=%s', to_char(p_vreme, 'HH24:MI'), cnt_terms, cnt_tokens);
end;
$$;

-- -----------------------------------------------------
-- 2) Generator cron jobova (polazak - 15 min)
--    KORISTI: v3_operativna_nedelja (WHERE aktivno AND vozac_id IS NOT NULL)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.refresh_v3_gps_departure_cron_jobs()
RETURNS TABLE(created_jobs integer, log_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
declare
  old_job record;
  slot_rec record;
  notify_time time;
  cron_expr text;
  job_name text;
  created_count integer := 0;
begin
  for old_job in
    select jobid
    from cron.job
    where jobname like 'gps-15min-slot-%'
  loop
    perform cron.unschedule(old_job.jobid);
  end loop;

  for slot_rec in
    select distinct coalesce(dodeljeno_vreme, zeljeno_vreme) as vreme
    from public.v3_operativna_nedelja
    where aktivno = true
      and vozac_id is not null
      and coalesce(dodeljeno_vreme, zeljeno_vreme) is not null
    order by 1
  loop
    notify_time := slot_rec.vreme - interval '15 minutes';

    cron_expr := format(
      '%s %s * * *',
      extract(minute from notify_time)::int,
      extract(hour from notify_time)::int
    );

    job_name := format('gps-15min-slot-%s', replace(to_char(slot_rec.vreme, 'HH24:MI'), ':', ''));

    perform cron.schedule(
      job_name,
      cron_expr,
      format(
        'SELECT * FROM public.send_v3_gps_departure_notifications_for_polazak(''%s''::time);',
        to_char(slot_rec.vreme, 'HH24:MI:SS')
      )
    );

    created_count := created_count + 1;
  end loop;

  return query
  select created_count, format('Kreirano %s GPS slot cron jobova.', created_count);
end;
$$;

-- Inicijalno kreiranje slot jobova odmah nakon deploy-a
SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();

-- Dnevni refresh (u 00:10) da pokupi eventualne promene termina
DO $$
DECLARE
  old_job_id INT;
BEGIN
  SELECT jobid INTO old_job_id
  FROM cron.job
  WHERE jobname = 'gps-15min-refresh';

  IF old_job_id IS NOT NULL THEN
    PERFORM cron.unschedule(old_job_id);
  END IF;
END $$;

SELECT cron.schedule(
  'gps-15min-refresh',
  '10 0 * * *',
  'SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();'
);

COMMIT;

-- Provera nakon primene:
-- SELECT * FROM cron.job WHERE jobname LIKE 'gps-15min-%' ORDER BY jobid;
-- SELECT * FROM public.refresh_v3_gps_departure_cron_jobs();
-- SELECT * FROM public.send_v3_gps_departure_notifications_for_polazak('05:00:00'::time);
-- SELECT vozac_id, datum, grad, dodeljeno_vreme, polazak_vreme, activation_time, notification_sent, gps_status
-- FROM public.v3_operativna_nedelja
-- WHERE vozac_id IS NOT NULL AND aktivno = true
-- ORDER BY datum, grad, dodeljeno_vreme;
