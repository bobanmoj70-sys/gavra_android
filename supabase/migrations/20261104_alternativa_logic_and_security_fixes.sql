-- Popravke alternativa/mesto_oslobodjeno logike i push toka:
--
-- 1) process_pending_zahtevi_slots: posiljke se vise NE racunaju kao zauzeta
--    mesta (konzistentno sa fn_v3_offer_freed_seats i v3-alternativa-action
--    koji posiljke iskljucuju). Ranije je slot sa posiljkama mogao lazno
--    izgledati pun pa su putnici nepotrebno dobijali alternativu.
-- 2) Zahtev bez ijedne dostupne alternative (±180 min) ide direktno u
--    'odbijeno' umesto u 'alternativa' bez opcija — ranije je stizala
--    zbunjujuca notifikacija "Izaberite dostupni termin" bez ijednog termina.
--    Takav zahtev ostaje u redu za mesto_oslobodjeno ponude po trazenom terminu.
-- 3) Novo polje alternativa_offered_at: 10-min rok za odgovor se meri od
--    trenutka slanja ponude, a ne od updated_at — koji set_updated_at trigger
--    pumpa na svaku izmenu reda pa je rok mogao da se resetuje.
-- 4) fn_v3_offer_freed_seats: kandidati moraju imati bar jedan push token —
--    ponuda tokenless korisniku je nevidljiva (bez push-a) a mesto bi bilo
--    rezervisano 10 minuta.
-- 5) fn_v3_alternativa_action: atomicki RPC za accept/reject koji edge
--    funkcija poziva — FOR UPDATE lock na zahtevu (serijalizuje duple akcije)
--    + FOR UPDATE lock na kapacitet_slots redu (serijalizuje konkurentne
--    accept-e na istom slotu = anti-overbooking poslednjeg mesta) + provera
--    identiteta pozivaoca (push token ili hardware/installation id mora
--    odgovarati vlasniku zahteva; nalozi bez ijednog identifikatora se
--    propustaju kao i do sada — legacy stanje).

ALTER TABLE public.v3_zahtevi
  ADD COLUMN IF NOT EXISTS alternativa_offered_at timestamptz;

CREATE OR REPLACE FUNCTION public.process_pending_zahtevi_slots()
 RETURNS TABLE(processed integer, approved integer, alternative integer, message text)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
    zahtev_record record;
    current_ts timestamptz := now();
    local_today date := (now() at time zone 'Europe/Belgrade')::date;
    processed int := 0;
    approved int := 0;
    alternative int := 0;
    capacity_check boolean;
    should_approve boolean;
    max_kapacitet integer;
    existing_mesta integer;
    best_alt_pre time;
    best_alt_posle time;
    alt_reason text;
    v_trazeni time;
    prijava_vreme time;
begin
    for zahtev_record in
        select z.*, a.tip as tip_putnika, a.ime as ime_prezime
        from v3_zahtevi z
        left join v3_auth a on a.id = z.created_by
        where z.status = 'obrada'
          and z.scheduled_at is not null
          and z.scheduled_at <= current_ts
          and not exists (
              select 1
              from public.v3_app_settings s
              cross join lateral jsonb_array_elements(coalesce(s.neradni_dani::jsonb, '[]'::jsonb)) d(day_obj)
              where d.day_obj->>'date' ~ '^\d{4}-\d{2}-\d{2}$'
                and (d.day_obj->>'date')::date = z.datum::date
          )
        order by z.scheduled_at asc, z.created_at asc, z.id asc
        for update of z skip locked
    loop
        should_approve := true;
        capacity_check := true;
        best_alt_pre := null;
        best_alt_posle := null;
        alt_reason := 'Trenutno nema slobodnih mesta za zeljeni termin.';

        v_trazeni := zahtev_record.trazeni_polazak_at;
        prijava_vreme := (coalesce(zahtev_record.created_at, current_ts) at time zone 'Europe/Belgrade')::time;

        if zahtev_record.tip_putnika = 'dnevni' then
            if prijava_vreme < '16:00'::time then
                if zahtev_record.datum::date <> local_today then
                    update v3_zahtevi
                    set status = 'odbijeno',
                        alternativa_pre_at = null,
                        alternativa_posle_at = null,
                        alternativa_offered_at = null,
                        updated_at = current_ts,
                        updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
                    where id = zahtev_record.id;
                    processed := processed + 1;
                    continue;
                end if;
            else
                if zahtev_record.datum::date <> (local_today + interval '1 day')::date then
                    update v3_zahtevi
                    set status = 'odbijeno',
                        alternativa_pre_at = null,
                        alternativa_posle_at = null,
                        alternativa_offered_at = null,
                        updated_at = current_ts,
                        updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
                    where id = zahtev_record.id;
                    processed := processed + 1;
                    continue;
                end if;
            end if;
        end if;

        if zahtev_record.tip_putnika = 'posiljka' then
            capacity_check := false;
        end if;

        if capacity_check then
            select ks.max_mesta into max_kapacitet
            from v3_kapacitet_slots ks
            where ks.grad = zahtev_record.grad
              and ks.vreme = v_trazeni
              and ks.datum = zahtev_record.datum::date
            limit 1;

            if max_kapacitet is null then
                continue;
            else
                -- Posiljke ne zauzimaju mesto (kao u offer_freed_seats/edge).
                select count(*)::int into existing_mesta
                from v3_operativna_nedelja o
                left join v3_auth pa on pa.id = o.created_by
                where o.datum::date = zahtev_record.datum::date
                  and o.grad = zahtev_record.grad
                  and o.polazak_at = v_trazeni
                  and o.otkazano_at is null
                  and lower(btrim(coalesce(pa.tip, ''))) <> 'posiljka';

                if (existing_mesta + 1) > max_kapacitet then
                    should_approve := false;
                end if;
            end if;
        end if;

        processed := processed + 1;

        if should_approve then
            update v3_zahtevi
            set status = 'odobreno',
                polazak_at = v_trazeni,
                alternativa_pre_at = null,
                alternativa_posle_at = null,
                alternativa_offered_at = null,
                updated_at = current_ts,
                updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
            where id = zahtev_record.id;
            approved := approved + 1;
        else
            if capacity_check then
                with usage_by_slot as (
                    select ks.vreme, ks.max_mesta,
                           coalesce(occ.used_mesta, 0) as used_mesta
                    from v3_kapacitet_slots ks
                    left join (
                        select o.polazak_at as vreme, count(*)::int as used_mesta
                        from v3_operativna_nedelja o
                        left join v3_auth pa on pa.id = o.created_by
                        where o.datum::date = zahtev_record.datum::date
                          and o.grad = zahtev_record.grad
                          and o.otkazano_at is null
                          and o.polazak_at is not null
                          and lower(btrim(coalesce(pa.tip, ''))) <> 'posiljka'
                        group by o.polazak_at
                    ) occ on occ.vreme = ks.vreme
                    where ks.grad = zahtev_record.grad
                      and ks.datum = zahtev_record.datum::date
                )
                select max(vreme) into best_alt_pre
                from usage_by_slot
                where vreme < v_trazeni
                  and vreme >= (v_trazeni - interval '180 minutes')
                  and (used_mesta + 1) <= max_mesta;

                with usage_by_slot as (
                    select ks.vreme, ks.max_mesta,
                           coalesce(occ.used_mesta, 0) as used_mesta
                    from v3_kapacitet_slots ks
                    left join (
                        select o.polazak_at as vreme, count(*)::int as used_mesta
                        from v3_operativna_nedelja o
                        left join v3_auth pa on pa.id = o.created_by
                        where o.datum::date = zahtev_record.datum::date
                          and o.grad = zahtev_record.grad
                          and o.otkazano_at is null
                          and o.polazak_at is not null
                          and lower(btrim(coalesce(pa.tip, ''))) <> 'posiljka'
                        group by o.polazak_at
                    ) occ on occ.vreme = ks.vreme
                    where ks.grad = zahtev_record.grad
                      and ks.datum = zahtev_record.datum::date
                )
                select min(vreme) into best_alt_posle
                from usage_by_slot
                where vreme > v_trazeni
                  and vreme <= (v_trazeni + interval '180 minutes')
                  and (used_mesta + 1) <= max_mesta;
            end if;

            if best_alt_pre is not null and best_alt_posle is not null then
                alt_reason := 'Trenutno nema slobodnih mesta za zeljeni termin, ali imate slobodne termine pre i posle.';
            elsif best_alt_pre is not null then
                alt_reason := 'Trenutno nema slobodnih mesta za zeljeni termin, ali imate slobodan raniji termin.';
            elsif best_alt_posle is not null then
                alt_reason := 'Trenutno nema slobodnih mesta za zeljeni termin, ali imate slobodan kasniji termin.';
            else
                alt_reason := alt_reason || ' Nema slobodnih termina pre/posle.';
            end if;

            -- Bez ijedne dostupne alternative ne nudimo prazan izbor —
            -- zahtev ide direktno u 'odbijeno' (stize iskren "Termin popunjen"
            -- push) i ostaje u redu za mesto_oslobodjeno ponude.
            if best_alt_pre is null and best_alt_posle is null then
                update v3_zahtevi
                set status = 'odbijeno',
                    alternativa_pre_at = null,
                    alternativa_posle_at = null,
                    alternativa_offered_at = null,
                    updated_at = current_ts,
                    updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
                where id = zahtev_record.id;
            else
                update v3_zahtevi
                set status = 'alternativa',
                    alternativa_pre_at = best_alt_pre,
                    alternativa_posle_at = best_alt_posle,
                    alternativa_offered_at = current_ts,
                    updated_at = current_ts,
                    updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
                where id = zahtev_record.id;
                alternative := alternative + 1;
            end if;
        end if;
    end loop;

    return query select
        processed,
        approved,
        alternative,
        format('Obradjeno %s zahteva - %s odobreno, %s alternativa', processed, approved, alternative);
end;
$function$;

-- Rok za odgovor se meri od alternativa_offered_at (fallback updated_at za
-- redove nastale pre ove kolone), ne od updated_at koji bilo koja izmena pumpa.
CREATE OR REPLACE FUNCTION public.expire_unanswered_alternativa_10m()
 RETURNS TABLE(expired_count integer, log_message text)
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_count integer := 0;
BEGIN
  UPDATE public.v3_zahtevi z
  SET
    status = 'odbijeno',
    alternativa_pre_at = NULL,
    alternativa_posle_at = NULL,
    alternativa_offered_at = NULL,
    updated_at = now(),
    updated_by = '4feffa3a-8b4d-4e28-9b8b-c0af3c48ea4e'::uuid
  WHERE z.status = 'alternativa'
    AND COALESCE(z.alternativa_offered_at, z.updated_at) <= now() - interval '10 minutes';

  GET DIAGNOSTICS v_count = ROW_COUNT;

  RETURN QUERY
  SELECT v_count, format('Alternativa timeout: zatvoreno %s zahteva.', v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_v3_offer_freed_seats(
  p_datum date,
  p_grad text,
  p_vreme text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_grad text := upper(btrim(coalesce(p_grad, '')));
  v_vreme text := public.v3_norm_hhmm(p_vreme);
  v_now_bg timestamp;
  v_max integer := 0;
  v_occupied integer := 0;
  v_pending integer := 0;
  v_free integer := 0;
  v_offered integer := 0;
  r record;
  v_tokens jsonb;
  v_grad_label text;
  v_title text;
  v_body text;
  v_data jsonb;
BEGIN
  IF p_datum IS NULL OR v_grad = '' OR v_vreme = '' THEN
    RETURN 0;
  END IF;

  -- Samoizlečenje: istekle ponude za ovaj slot označi odbijenim pre računanja.
  -- Tako mehanizam radi i kada pg_cron (fn_v3_expire_mesto_ponuda) nije aktivan.
  UPDATE public.v3_zahtevi
  SET mesto_ponuda = false,
      mesto_ponuda_odbijena = true,
      mesto_ponuda_at = null,
      updated_at = now()
  WHERE status = 'odbijeno'
    AND COALESCE(mesto_ponuda, false) = true
    AND COALESCE(mesto_ponuda_odbijena, false) = false
    AND COALESCE(mesto_ponuda_at, updated_at) <= now() - interval '10 minutes'
    AND datum = p_datum
    AND upper(btrim(coalesce(grad, ''))) = v_grad
    AND public.v3_norm_hhmm(trazeni_polazak_at::text) = v_vreme;

  v_now_bg := timezone('Europe/Belgrade', now());
  IF v_now_bg::date > p_datum THEN
    RETURN 0;
  END IF;
  IF v_now_bg::date = p_datum AND to_char(v_now_bg, 'HH24:MI') >= v_vreme THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(MAX(ks.max_mesta), 0)
  INTO v_max
  FROM public.v3_kapacitet_slots ks
  WHERE upper(btrim(ks.grad)) = v_grad
    AND ks.datum = p_datum
    AND public.v3_norm_hhmm(ks.vreme::text) = v_vreme;

  IF v_max <= 0 THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*)::int
  INTO v_occupied
  FROM public.v3_operativna_nedelja o
  LEFT JOIN public.v3_auth a ON a.id = o.created_by
  WHERE o.datum = p_datum
    AND upper(btrim(coalesce(o.grad, ''))) = v_grad
    AND public.v3_norm_hhmm(o.polazak_at::text) = v_vreme
    AND o.otkazano_at IS NULL
    AND lower(btrim(coalesce(a.tip, ''))) <> 'posiljka';

  -- Aktivne ponude za isti slot zauzimaju mesto dok ne isteknu ili se odgovori.
  SELECT COUNT(*)::int
  INTO v_pending
  FROM public.v3_zahtevi z
  WHERE z.status = 'odbijeno'
    AND COALESCE(z.mesto_ponuda, false) = true
    AND COALESCE(z.mesto_ponuda_odbijena, false) = false
    AND z.datum = p_datum
    AND upper(btrim(coalesce(z.grad, ''))) = v_grad
    AND public.v3_norm_hhmm(z.trazeni_polazak_at::text) = v_vreme;

  v_free := v_max - v_occupied - v_pending;
  IF v_free <= 0 THEN
    RETURN 0;
  END IF;

  v_grad_label := CASE
    WHEN v_grad = 'BC' THEN 'Bela Crkva'
    WHEN v_grad = 'VS' THEN 'Vrsac'
    ELSE v_grad
  END;

  FOR r IN
    SELECT z.id, z.created_by, z.updated_by, z.datum, z.grad, z.trazeni_polazak_at
    FROM public.v3_zahtevi z
    WHERE z.status = 'odbijeno'
      AND COALESCE(z.mesto_ponuda, false) = false
      AND COALESCE(z.mesto_ponuda_odbijena, false) = false
      AND z.datum = p_datum
      AND upper(btrim(coalesce(z.grad, ''))) = v_grad
      AND public.v3_norm_hhmm(z.trazeni_polazak_at::text) = v_vreme
      AND z.created_by IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_auth a
        WHERE a.id = z.created_by
          AND lower(btrim(coalesce(a.tip, ''))) = 'posiljka'
      )
      -- Samo kandidati sa bar jednim push tokenom — tokenless korisnik ne moze
      -- da dobije ponudu, a mesto bi bilo rezervisano 10 minuta.
      AND EXISTS (
        SELECT 1
        FROM public.v3_auth a
        WHERE a.id = z.created_by
          AND (
            btrim(coalesce(a.push_token, '')) <> ''
            OR btrim(coalesce(a.push_token_2, '')) <> ''
            OR btrim(coalesce(a.push_token_hms, '')) <> ''
            OR btrim(coalesce(a.push_token_hms_2, '')) <> ''
          )
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_zahtevi z2
        WHERE z2.created_by = z.created_by
          AND z2.datum = z.datum
          AND upper(btrim(coalesce(z2.grad, ''))) = v_grad
          AND z2.id <> z.id
          AND z2.status IN ('obrada', 'odobreno', 'alternativa')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_zahtevi z3
        WHERE z3.created_by = z.created_by
          AND z3.datum = z.datum
          AND upper(btrim(coalesce(z3.grad, ''))) = v_grad
          AND z3.status = 'otkazano'
          AND public.v3_norm_hhmm(coalesce(z3.polazak_at, z3.trazeni_polazak_at)::text) = v_vreme
      )
    ORDER BY z.created_at ASC NULLS LAST, z.id ASC
    LIMIT v_free
  LOOP
    UPDATE public.v3_zahtevi
    SET mesto_ponuda = true,
        mesto_ponuda_at = now(),
        updated_at = now()
    WHERE id = r.id
      AND status = 'odbijeno'
      AND COALESCE(mesto_ponuda, false) = false
      AND COALESCE(mesto_ponuda_odbijena, false) = false;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    SELECT jsonb_agg(tkn)
    INTO v_tokens
    FROM (
      SELECT jsonb_build_object('token', a.push_token, 'provider', 'fcm') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token IS NOT NULL
        AND btrim(a.push_token) <> ''
      UNION
      SELECT jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token_2 IS NOT NULL
        AND btrim(a.push_token_2) <> ''
      UNION
      SELECT jsonb_build_object('token', a.push_token_hms, 'provider', 'hms') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token_hms IS NOT NULL
        AND btrim(a.push_token_hms) <> ''
      UNION
      SELECT jsonb_build_object('token', a.push_token_hms_2, 'provider', 'hms') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token_hms_2 IS NOT NULL
        AND btrim(a.push_token_hms_2) <> ''
    ) s;

    IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN
      v_offered := v_offered + 1;
      CONTINUE;
    END IF;

    v_title := 'Oslobodilo se mesto';
    v_body := 'Oslobodilo se mesto u terminu ' || v_vreme || ' (' || v_grad_label || '). Prihvati ili odbij.';

    v_data := jsonb_build_object(
      'type', 'v3_alternativa',
      'offer_kind', 'mesto_oslobodjeno',
      'zahtev_id', r.id,
      'recipient_id', r.created_by,
      'alt_pre', v_vreme,
      'alt_posle', '',
      'datum', r.datum,
      'grad', r.grad,
      'status', 'odbijeno',
      'screen', 'v3_putnik_profil',
      'action_pre_label', 'Prihvati',
      'action_reject_label', 'Ne',
      'title_sr', v_title,
      'title_en', 'A seat opened up',
      'title_ru', 'Освободилось место',
      'title_de', 'Ein Platz ist frei geworden',
      'title_zh', '有空位了',
      'body_sr', v_body,
      'body_en', 'A seat opened up at ' || v_vreme || ' (' || v_grad_label || '). Accept or decline.',
      'body_ru', 'Освободилось место в ' || v_vreme || ' (' || v_grad_label || '). Примите или отклоните.',
      'body_de', 'Ein Platz ist um ' || v_vreme || ' (' || v_grad_label || ') frei geworden. Annehmen oder ablehnen.',
      'body_zh', v_vreme || '（' || v_grad_label || '）有空位了。请选择接受或拒绝。'
    );

    PERFORM public.notify_push(v_tokens, v_title, v_body, v_data);
    v_offered := v_offered + 1;
  END LOOP;

  RETURN v_offered;
END;
$function$;

-- Atomicki accept/reject za alternativu i mesto_oslobodjeno.
-- Edge funkcija (v3-alternativa-action) je samo HTTP wrapper oko ovog RPC-ja.
--
-- Atomarnost:
--  - FOR UPDATE na v3_zahtevi redu: duple/konkurentne akcije na istom zahtevu
--    se serijalizuju; druga akcija vidi vec izmenjen status.
--  - FOR UPDATE na v3_kapacitet_slots redu: konkurentni accept-i za isti slot
--    se serijalizuju — occupied count se radi dok je slot zakljucan, pa dva
--    accept-a ne mogu istovremeno da prodju proveru poslednjeg mesta.
--
-- Identitet pozivaoca: mora da posalje bar jedan identifikator koji odgovara
-- vlasniku zahteva — push token (device_token) ili hardware_id /
-- installation_id iz v3_auth slotova. Nalozi bez ijednog upisanog
-- identifikatora (legacy) prolaze kao i do sada.
CREATE OR REPLACE FUNCTION public.fn_v3_alternativa_action(
  p_zahtev_id uuid,
  p_action text,
  p_device_token text DEFAULT '',
  p_hardware_id text DEFAULT '',
  p_installation_id text DEFAULT ''
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_zahtev public.v3_zahtevi%ROWTYPE;
  v_auth public.v3_auth%ROWTYPE;
  v_auth_found boolean;
  v_status text;
  v_is_mesto boolean;
  v_is_posiljka boolean;
  v_selected text;
  v_grad text;
  v_max integer := 0;
  v_occupied integer := 0;
  v_device_ok boolean;
  v_has_device_identity boolean;
  v_offer_kind text := '';
BEGIN
  IF p_zahtev_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'missing_zahtev_id');
  END IF;

  IF p_action IS NULL OR p_action NOT IN ('accept_pre', 'accept_posle', 'reject') THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'invalid_action');
  END IF;

  -- Row lock na zahtevu — serijalizuje duple akcije na istom zahtevu.
  SELECT * INTO v_zahtev
  FROM public.v3_zahtevi z
  WHERE z.id = p_zahtev_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'zahtev_not_found');
  END IF;

  -- Provera identiteta pozivaoca pre bilo kakvih statusnih provera — napadac
  -- ne sme da zakljuci stanje zahteva po razlicitim reason kodovima.
  SELECT * INTO v_auth FROM public.v3_auth a WHERE a.id = v_zahtev.created_by;
  v_auth_found := FOUND;

  IF v_auth_found THEN
    -- IN nad NULL vrednostima vraca NULL (ne false) — coalesce na false da
    -- pogresni kredencijali ne bi preskocili proveru.
    v_device_ok := coalesce(
      (btrim(coalesce(p_device_token, '')) <> '' AND p_device_token IN (
        v_auth.push_token, v_auth.push_token_2, v_auth.push_token_hms, v_auth.push_token_hms_2))
      OR (btrim(coalesce(p_hardware_id, '')) <> '' AND p_hardware_id IN (
        v_auth.hardware_id, v_auth.hardware_id_2))
      OR (btrim(coalesce(p_installation_id, '')) <> '' AND p_installation_id IN (
        v_auth.installation_id, v_auth.installation_id_2)),
      false
    );

    v_has_device_identity :=
      btrim(coalesce(v_auth.push_token, '')) <> ''
      OR btrim(coalesce(v_auth.push_token_2, '')) <> ''
      OR btrim(coalesce(v_auth.push_token_hms, '')) <> ''
      OR btrim(coalesce(v_auth.push_token_hms_2, '')) <> ''
      OR btrim(coalesce(v_auth.hardware_id, '')) <> ''
      OR btrim(coalesce(v_auth.hardware_id_2, '')) <> ''
      OR btrim(coalesce(v_auth.installation_id, '')) <> ''
      OR btrim(coalesce(v_auth.installation_id_2, '')) <> '';

    IF v_has_device_identity AND NOT v_device_ok THEN
      RETURN jsonb_build_object('ok', false, 'reason', 'unauthorized');
    END IF;
  END IF;

  v_status := lower(btrim(coalesce(v_zahtev.status, '')));
  v_is_mesto := coalesce(v_zahtev.mesto_ponuda, false) AND v_status = 'odbijeno';
  IF v_is_mesto THEN
    v_offer_kind := 'mesto_oslobodjeno';
  END IF;

  IF v_status <> 'alternativa' AND NOT v_is_mesto THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'zahtev_not_in_alternativa', 'status', v_status);
  END IF;

  -- Istekla mesto ponuda (10 min): oznaci odbijenom i ponudi sledecem u redu.
  IF v_is_mesto AND coalesce(v_zahtev.mesto_ponuda_at, v_zahtev.updated_at) <= now() - interval '10 minutes' THEN
    UPDATE public.v3_zahtevi
    SET mesto_ponuda = false,
        mesto_ponuda_odbijena = true,
        mesto_ponuda_at = null,
        updated_at = now()
    WHERE id = v_zahtev.id;

    IF v_zahtev.datum IS NOT NULL
       AND btrim(coalesce(v_zahtev.grad, '')) <> ''
       AND v_zahtev.trazeni_polazak_at IS NOT NULL THEN
      BEGIN
        PERFORM public.fn_v3_offer_freed_seats(
          v_zahtev.datum,
          v_zahtev.grad::text,
          public.v3_norm_hhmm(v_zahtev.trazeni_polazak_at::text)
        );
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'fn_v3_alternativa_action offer next: %', SQLERRM;
      END;
    END IF;

    RETURN jsonb_build_object('ok', false, 'reason', 'offer_expired', 'offer_kind', 'mesto_oslobodjeno');
  END IF;

  IF p_action = 'reject' THEN
    IF v_is_mesto THEN
      UPDATE public.v3_zahtevi
      SET mesto_ponuda = false,
          mesto_ponuda_odbijena = true,
          mesto_ponuda_at = null,
          updated_at = now()
      WHERE id = v_zahtev.id;

      IF v_zahtev.datum IS NOT NULL
         AND btrim(coalesce(v_zahtev.grad, '')) <> ''
         AND v_zahtev.trazeni_polazak_at IS NOT NULL THEN
        BEGIN
          PERFORM public.fn_v3_offer_freed_seats(
            v_zahtev.datum,
            v_zahtev.grad::text,
            public.v3_norm_hhmm(v_zahtev.trazeni_polazak_at::text)
          );
        EXCEPTION WHEN OTHERS THEN
          RAISE WARNING 'fn_v3_alternativa_action offer next: %', SQLERRM;
        END;
      END IF;

      RETURN jsonb_build_object('ok', true, 'action', 'reject', 'zahtev_id', v_zahtev.id, 'offer_kind', 'mesto_oslobodjeno');
    END IF;

    -- Status prelazi u 'odbijeno' — DB triggeri (transfer_to_operativna_nedelja,
    -- notify_putnik) odradjuju operativnu sinhronizaciju i push potvrdu.
    UPDATE public.v3_zahtevi
    SET status = 'odbijeno',
        alternativa_pre_at = null,
        alternativa_posle_at = null,
        alternativa_offered_at = null,
        updated_at = now()
    WHERE id = v_zahtev.id;

    RETURN jsonb_build_object('ok', true, 'action', 'reject', 'zahtev_id', v_zahtev.id);
  END IF;

  -- ACCEPT: izabrani termin dolazi iz baze (ne iz payload-a) — payload se ne
  -- moze iskoristiti za biranje proizvoljnog termina.
  v_selected := CASE
    WHEN v_is_mesto THEN public.v3_norm_hhmm(v_zahtev.trazeni_polazak_at::text)
    WHEN p_action = 'accept_pre' THEN public.v3_norm_hhmm(v_zahtev.alternativa_pre_at::text)
    ELSE public.v3_norm_hhmm(v_zahtev.alternativa_posle_at::text)
  END;

  IF v_selected = '' THEN
    RETURN jsonb_build_object('ok', false, 'reason', 'selected_alternativa_missing', 'action', p_action);
  END IF;

  v_is_posiljka := v_auth_found AND lower(btrim(coalesce(v_auth.tip, ''))) = 'posiljka';
  v_grad := upper(btrim(coalesce(v_zahtev.grad, '')));

  IF NOT v_is_posiljka THEN
    -- Slot lock: konkurentni accept-i za isti slot se serijalizuju ovde,
    -- dok lock drzimo occupied count je tacan (anti-overbooking).
    PERFORM 1
    FROM public.v3_kapacitet_slots ks
    WHERE upper(btrim(ks.grad)) = v_grad
      AND ks.datum = v_zahtev.datum
      AND public.v3_norm_hhmm(ks.vreme::text) = v_selected
    FOR UPDATE;

    SELECT COALESCE(MAX(ks.max_mesta), 0)
    INTO v_max
    FROM public.v3_kapacitet_slots ks
    WHERE upper(btrim(ks.grad)) = v_grad
      AND ks.datum = v_zahtev.datum
      AND public.v3_norm_hhmm(ks.vreme::text) = v_selected;

    IF v_max <= 0 THEN
      IF v_is_mesto THEN
        -- Ponuda se skida ali zahtev ostaje u redu (ne odbijena) — vlasnik je
        -- hteo mesto, moze mu se ponovo ponuditi kad se sledece oslobodi.
        UPDATE public.v3_zahtevi
        SET mesto_ponuda = false, mesto_ponuda_at = null, updated_at = now()
        WHERE id = v_zahtev.id;
      END IF;
      RETURN jsonb_build_object('ok', false, 'reason', 'no_capacity_slot', 'selected_time', v_selected,
                                'offer_kind', v_offer_kind);
    END IF;

    SELECT COUNT(*)::int
    INTO v_occupied
    FROM public.v3_operativna_nedelja o
    LEFT JOIN public.v3_auth a ON a.id = o.created_by
    WHERE o.datum = v_zahtev.datum
      AND upper(btrim(coalesce(o.grad, ''))) = v_grad
      AND public.v3_norm_hhmm(o.polazak_at::text) = v_selected
      AND o.otkazano_at IS NULL
      AND lower(btrim(coalesce(a.tip, ''))) <> 'posiljka';

    IF v_occupied >= v_max THEN
      IF v_is_mesto THEN
        UPDATE public.v3_zahtevi
        SET mesto_ponuda = false, mesto_ponuda_at = null, updated_at = now()
        WHERE id = v_zahtev.id;
      END IF;
      RETURN jsonb_build_object('ok', false, 'reason', 'selected_slot_full', 'selected_time', v_selected,
                                'max_mesta', v_max, 'occupied', v_occupied,
                                'offer_kind', v_offer_kind);
    END IF;
  END IF;

  UPDATE public.v3_zahtevi
  SET status = 'odobreno',
      polazak_at = v_selected::time,
      alternativa_pre_at = null,
      alternativa_posle_at = null,
      alternativa_offered_at = null,
      mesto_ponuda = false,
      mesto_ponuda_at = null,
      updated_at = now()
  WHERE id = v_zahtev.id;

  RETURN jsonb_build_object('ok', true, 'action', p_action, 'zahtev_id', v_zahtev.id,
                            'selected_time', v_selected, 'offer_kind', v_offer_kind);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.fn_v3_alternativa_action(uuid, text, text, text, text) TO service_role;
