-- HMS push tokeni u svim notify funkcijama.
--
-- Sve funkcije koje grade v_tokens za public.notify_push sada ukljucuju
-- push_token_hms / push_token_hms_2 kolone (provider 'hms') pored postojecih
-- FCM kolona. Token kolona sama odredjuje provider -- push_token_provider
-- kolona se ne koristi jer sa dva device slota provider moze da se razlikuje.
--
-- Funkcije su kompletne poslednje verzije (CREATE OR REPLACE) sa dodatim
-- UNION granama; potpisi i logika su nepromenjeni.

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

    UNION

    SELECT jsonb_build_object('token', a.push_token_hms, 'provider', 'hms') AS tkn
    FROM public.v3_auth a
    JOIN target_putnici tp ON tp.putnik_id = a.id
    WHERE a.push_token_hms IS NOT NULL AND btrim(a.push_token_hms) <> ''

    UNION

    SELECT jsonb_build_object('token', a.push_token_hms_2, 'provider', 'hms') AS tkn
    FROM public.v3_auth a
    JOIN target_putnici tp ON tp.putnik_id = a.id
    WHERE a.push_token_hms_2 IS NOT NULL AND btrim(a.push_token_hms_2) <> ''
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
  'Push putnicima da je vozač krenuo — race-safe: najpre atomically claim preko UPDATE ... RETURNING, pa notify. Ukljucuje HMS tokene.';


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

    union

    select jsonb_build_object('token', a.push_token_hms, 'provider', 'hms') as tkn
    from public.v3_auth a
    where a.tip = 'vozac' and a.push_token_hms is not null and btrim(a.push_token_hms) <> ''

    union

    select jsonb_build_object('token', a.push_token_hms_2, 'provider', 'hms') as tkn
    from public.v3_auth a
    where a.tip = 'vozac' and a.push_token_hms_2 is not null and btrim(a.push_token_hms_2) <> ''
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

CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_zahtev_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tokens jsonb;
  v_title text;
  v_body text;
  v_data jsonb;
  v_grad text;
  v_vreme text;
  v_ime text;
  v_termin text;
  v_recipient uuid;
  v_alt_pre text;
  v_alt_posle text;
  v_title_en text;
  v_title_ru text;
  v_title_de text;
  v_body_en text;
  v_body_ru text;
  v_body_de text;
BEGIN
  IF old.status IS NOT DISTINCT FROM new.status THEN
    IF NOT (
      new.status = 'alternativa'
      AND (
        old.alternativa_pre_at IS DISTINCT FROM new.alternativa_pre_at
        OR old.alternativa_posle_at IS DISTINCT FROM new.alternativa_posle_at
      )
    ) THEN
      RETURN new;
    END IF;
  END IF;

  v_recipient := COALESCE(new.created_by, new.updated_by);
  IF v_recipient IS NULL THEN
    RETURN new;
  END IF;

  v_grad := CASE
    WHEN new.grad = 'BC' THEN 'Bela Crkva'
    WHEN new.grad = 'VS' THEN 'Vrsac'
    ELSE new.grad
  END;

  SELECT COALESCE(NULLIF(BTRIM(a.ime), ''), 'putnik')
  INTO v_ime
  FROM public.v3_auth a
  WHERE a.id = v_recipient
  LIMIT 1;

  SELECT jsonb_agg(tkn)
  INTO v_tokens
  FROM (
    SELECT jsonb_build_object('token', a.push_token, 'provider', 'fcm') AS tkn
    FROM public.v3_auth a
    WHERE a.id = v_recipient
      AND a.push_token IS NOT NULL
      AND BTRIM(a.push_token) <> ''
    UNION
    SELECT jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') AS tkn
    FROM public.v3_auth a
    WHERE a.id = v_recipient
      AND a.push_token_2 IS NOT NULL
      AND BTRIM(a.push_token_2) <> ''
    UNION
    SELECT jsonb_build_object('token', a.push_token_hms, 'provider', 'hms') AS tkn
    FROM public.v3_auth a
    WHERE a.id = v_recipient
      AND a.push_token_hms IS NOT NULL
      AND BTRIM(a.push_token_hms) <> ''
    UNION
    SELECT jsonb_build_object('token', a.push_token_hms_2, 'provider', 'hms') AS tkn
    FROM public.v3_auth a
    WHERE a.id = v_recipient
      AND a.push_token_hms_2 IS NOT NULL
      AND BTRIM(a.push_token_hms_2) <> ''
  ) s;

  IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN
    RETURN new;
  END IF;

  v_vreme := COALESCE(
    to_char(new.polazak_at, 'HH24:MI'),
    to_char(new.trazeni_polazak_at, 'HH24:MI'),
    ''
  );

  v_termin := CASE
    WHEN v_vreme <> '' THEN format('%s %s u %s', to_char(new.datum::date, 'DD.MM.YYYY.'), v_grad, v_vreme)
    ELSE format('%s %s', to_char(new.datum::date, 'DD.MM.YYYY.'), v_grad)
  END;

  IF new.status = 'odobreno' THEN
    v_title := 'Zahtev odobren';
    v_body  := format('Postovani %s, vas zahtev za termin %s je odobren.', v_ime, v_termin);
    v_title_en := 'Request approved';
    v_body_en  := format('Dear %s, your request for %s has been approved.', v_ime, v_termin);
    v_title_ru := 'Заявка одобрена';
    v_body_ru  := format('Уважаемый(ая) %s, ваша заявка на %s одобрена.', v_ime, v_termin);
    v_title_de := 'Anfrage genehmigt';
    v_body_de  := format('Sehr geehrte(r) %s, Ihre Anfrage für %s wurde genehmigt.', v_ime, v_termin);
    v_data  := jsonb_build_object(
      'type', 'v3_zahtev_odobren',
      'entity_id', new.id,
      'zahtev_id', new.id,
      'recipient_id', v_recipient,
      'id', new.id,
      'datum', new.datum,
      'grad', new.grad,
      'vreme', v_vreme,
      'status', new.status,
      'screen', 'v3_putnik_profil',
      'title_sr', v_title,
      'title_en', v_title_en,
      'title_ru', v_title_ru,
      'title_de', v_title_de,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de
    );

  ELSIF new.status = 'alternativa' THEN
    v_alt_pre   := COALESCE(to_char(new.alternativa_pre_at,   'HH24:MI'), '');
    v_alt_posle := COALESCE(to_char(new.alternativa_posle_at, 'HH24:MI'), '');

    v_title := 'Informacija o dostupnosti termina';
    v_body  := 'Trenutno nema slobodnih mesta u zeljenom terminu. Pripremili smo najblize dostupne alternative za Vas.';
    v_title_en := 'Appointment availability update';
    v_body_en  := 'There are currently no free spots in the requested time slot. We have prepared the closest available alternatives for you.';
    v_title_ru := 'Информация о доступности термина';
    v_body_ru  := 'В настоящее время нет свободных мест в желаемое время. Мы подготовили для вас ближайшие доступные альтернативы.';
    v_title_de := 'Information zur Terminverfügbarkeit';
    v_body_de  := 'Im gewünschten Termin sind derzeit keine freien Plätze verfügbar. Wir haben die nächstgelegenen verfügbaren Alternativen für Sie vorbereitet.';

    v_data  := jsonb_build_object(
      'type',               'v3_alternativa',
      'zahtev_id',          new.id,
      'recipient_id',       v_recipient,
      'alt_pre',            v_alt_pre,
      'alt_posle',          v_alt_posle,
      'datum',              new.datum,
      'grad',               new.grad,
      'status',             new.status,
      'screen',             'v3_putnik_profil',
      'action_pre_label',   CASE WHEN v_alt_pre   <> '' THEN v_alt_pre   ELSE null END,
      'action_posle_label', CASE WHEN v_alt_posle <> '' THEN v_alt_posle ELSE null END,
      'action_reject_label','Odbij',
      'title_sr', v_title,
      'title_en', v_title_en,
      'title_ru', v_title_ru,
      'title_de', v_title_de,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de
    );

  ELSIF new.status = 'odbijeno' THEN
    v_title := 'Termin popunjen';
    v_body  := 'Nazalost, u terminu ' || COALESCE(v_vreme, '') || ' nema slobodnih mesta (' || v_grad || ').';
    v_title_en := 'Time slot full';
    v_body_en  := 'Unfortunately, there are no free spots at ' || COALESCE(v_vreme, '') || ' (' || v_grad || ').';
    v_title_ru := 'Термин заполнен';
    v_body_ru  := 'К сожалению, в термине ' || COALESCE(v_vreme, '') || ' нет свободных мест (' || v_grad || ').';
    v_title_de := 'Termin ausgebucht';
    v_body_de  := 'Leider sind im Termin ' || COALESCE(v_vreme, '') || ' keine freien Plätze verfügbar (' || v_grad || ').';
    v_data  := jsonb_build_object(
      'type', 'v3_zahtev_odbijen',
      'entity_id', new.id,
      'zahtev_id', new.id,
      'recipient_id', v_recipient,
      'id', new.id,
      'datum', new.datum,
      'grad', new.grad,
      'status', new.status,
      'screen', 'v3_putnik_profil',
      'title_sr', v_title,
      'title_en', v_title_en,
      'title_ru', v_title_ru,
      'title_de', v_title_de,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de
    );

  ELSIF new.status = 'otkazano' THEN
    v_title := 'Prevoz otkazan';
    v_body  := 'Vas prevoz za ' || COALESCE(v_vreme, '') || ' (' || v_grad || ') je otkazan.';
    v_title_en := 'Ride cancelled';
    v_body_en  := 'Your ride at ' || COALESCE(v_vreme, '') || ' (' || v_grad || ') has been cancelled.';
    v_title_ru := 'Поездка отменена';
    v_body_ru  := 'Ваша поездка в ' || COALESCE(v_vreme, '') || ' (' || v_grad || ') отменена.';
    v_title_de := 'Fahrt storniert';
    v_body_de  := 'Ihre Fahrt um ' || COALESCE(v_vreme, '') || ' (' || v_grad || ') wurde storniert.';
    v_data  := jsonb_build_object(
      'type', 'v3_otkazano',
      'entity_id', new.id,
      'zahtev_id', new.id,
      'recipient_id', v_recipient,
      'id', new.id,
      'datum', new.datum,
      'grad', new.grad,
      'status', new.status,
      'screen', 'v3_putnik_profil',
      'title_sr', v_title,
      'title_en', v_title_en,
      'title_ru', v_title_ru,
      'title_de', v_title_de,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de
    );
  END IF;

  IF v_title IS NOT NULL THEN
    PERFORM public.notify_push(v_tokens, v_title, v_body, v_data);
  END IF;

  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_operativna_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  v_tokens  jsonb;
  v_title   text;
  v_body    text;
  v_data    jsonb;
  v_grad    text;
  v_vreme   text;
  v_datum   text;
  v_ime     text;
  v_recipient uuid;
  v_title_en text;
  v_title_ru text;
  v_title_de text;
  v_body_en text;
  v_body_ru text;
  v_body_de text;
BEGIN
  -- Okida samo kada se postavi polazak_at (INSERT sa polazak_at, ili UPDATE koji mijenja polazak_at)
  IF TG_OP = 'INSERT' THEN
    IF NEW.polazak_at IS NULL THEN
      RETURN NEW;
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    -- Okida samo ako se polazak_at promijenio i nije NULL
    IF NEW.polazak_at IS NOT DISTINCT FROM OLD.polazak_at THEN
      RETURN NEW;
    END IF;
    IF NEW.polazak_at IS NULL THEN
      RETURN NEW;
    END IF;
  END IF;

  v_recipient := NEW.created_by;
  IF v_recipient IS NULL THEN
    RETURN NEW;
  END IF;

  -- Dohvati ime i tokene putnika
  SELECT
    COALESCE(NULLIF(BTRIM(a.ime), ''), 'putnik'),
    (
      SELECT jsonb_agg(tkn)
      FROM (
        SELECT jsonb_build_object('token', a2.push_token, 'provider', 'fcm') AS tkn
        FROM public.v3_auth a2
        WHERE a2.id = v_recipient
          AND a2.push_token IS NOT NULL
          AND BTRIM(a2.push_token) <> ''
        UNION
        SELECT jsonb_build_object('token', a2.push_token_2, 'provider', 'fcm') AS tkn
        FROM public.v3_auth a2
        WHERE a2.id = v_recipient
          AND a2.push_token_2 IS NOT NULL
          AND BTRIM(a2.push_token_2) <> ''
        UNION
        SELECT jsonb_build_object('token', a2.push_token_hms, 'provider', 'hms') AS tkn
        FROM public.v3_auth a2
        WHERE a2.id = v_recipient
          AND a2.push_token_hms IS NOT NULL
          AND BTRIM(a2.push_token_hms) <> ''
        UNION
        SELECT jsonb_build_object('token', a2.push_token_hms_2, 'provider', 'hms') AS tkn
        FROM public.v3_auth a2
        WHERE a2.id = v_recipient
          AND a2.push_token_hms_2 IS NOT NULL
          AND BTRIM(a2.push_token_hms_2) <> ''
      ) s
    )
  INTO v_ime, v_tokens
  FROM public.v3_auth a
  WHERE a.id = v_recipient
  LIMIT 1;

  IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN
    RETURN NEW;
  END IF;

  v_grad := CASE
    WHEN NEW.grad = 'BC' THEN 'Bela Crkva'
    WHEN NEW.grad = 'VS' THEN 'Vrsac'
    ELSE NEW.grad
  END;

  v_vreme := TO_CHAR(NEW.polazak_at, 'HH24:MI');
  v_datum := TO_CHAR(NEW.datum::date, 'DD.MM.YYYY.');

  v_title := 'Termin odobren';
  v_body  := FORMAT('Postovani %s, vas termin %s %s u %s je odobren.', v_ime, v_datum, v_grad, v_vreme);
  v_title_en := 'Appointment approved';
  v_body_en  := FORMAT('Dear %s, your appointment on %s %s at %s has been approved.', v_ime, v_datum, v_grad, v_vreme);
  v_title_ru := 'Термин одобрен';
  v_body_ru  := FORMAT('Уважаемый(ая) %s, ваш термин %s %s в %s одобрен.', v_ime, v_datum, v_grad, v_vreme);
  v_title_de := 'Termin genehmigt';
  v_body_de  := FORMAT('Sehr geehrte(r) %s, Ihr Termin am %s %s um %s wurde genehmigt.', v_ime, v_datum, v_grad, v_vreme);

  v_data := jsonb_build_object(
    'type',         'zahtev_status',
    'status',       'odobreno',
    'v3_auth_id',   v_recipient,
    'request_id',   '',
    'grad',         NEW.grad,
    'datum',        NEW.datum,
    'vreme',        v_vreme,
    'screen',       'v3_putnik_profil',
    'title_sr', v_title,
    'title_en', v_title_en,
    'title_ru', v_title_ru,
    'title_de', v_title_de,
    'body_sr', v_body,
    'body_en', v_body_en,
    'body_ru', v_body_ru,
    'body_de', v_body_de
  );

  PERFORM public.notify_push(v_tokens, v_title, v_body, v_data);

  RETURN NEW;
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

  v_free := v_max - v_occupied;
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
