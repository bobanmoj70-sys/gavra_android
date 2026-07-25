-- Dodaje title_zh/body_zh (kineski) push notifikacijama koje šalju
-- fn_v3_notify_putnik_on_zahtev_update, fn_v3_notify_putnik_on_operativna_update
-- i v3_notify_passengers_driver_started, bez menjanja trigger logike,
-- uslova okidanja ili potpisa funkcija.
-- Ponašanje za korisnike bez podešenog jezika (ili sa locale_code = 'sr')
-- ostaje identično kao pre — send-push-notification edge funkcija ima
-- fallback na title_sr/body_sr kada traženi jezik ne postoji.

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
  v_title_zh text;
  v_body_en text;
  v_body_ru text;
  v_body_de text;
  v_body_zh text;
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
    v_title_zh := '请求已批准';
    v_body_zh  := format('尊敬的%s，您对%s的请求已获批准。', v_ime, v_termin);
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
      'title_zh', v_title_zh,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de,
      'body_zh', v_body_zh
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
    v_title_zh := '预约可用性信息';
    v_body_zh  := '所需时段目前没有空位。我们已为您准备了最接近的可用替代方案。';

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
      'title_zh', v_title_zh,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de,
      'body_zh', v_body_zh
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
    v_title_zh := '时段已满';
    v_body_zh  := '很遗憾，' || COALESCE(v_vreme, '') || '（' || v_grad || '）没有空位。';
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
      'title_zh', v_title_zh,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de,
      'body_zh', v_body_zh
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
    v_title_zh := '行程已取消';
    v_body_zh  := '您在' || COALESCE(v_vreme, '') || '（' || v_grad || '）的行程已被取消。';
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
      'title_zh', v_title_zh,
      'body_sr', v_body,
      'body_en', v_body_en,
      'body_ru', v_body_ru,
      'body_de', v_body_de,
      'body_zh', v_body_zh
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
  v_title_zh text;
  v_body_en text;
  v_body_ru text;
  v_body_de text;
  v_body_zh text;
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
  v_title_zh := '预约已批准';
  v_body_zh  := FORMAT('尊敬的%s，您在%s %s %s的预约已获批准。', v_ime, v_datum, v_grad, v_vreme);

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
    'title_zh', v_title_zh,
    'body_sr', v_body,
    'body_en', v_body_en,
    'body_ru', v_body_ru,
    'body_de', v_body_de,
    'body_zh', v_body_zh
  );

  PERFORM public.notify_push(v_tokens, v_title, v_body, v_data);

  RETURN NEW;
END;
$function$;


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

  return jsonb_build_object('ok', true, 'notified', v_notified, 'event_id', v_event_id);
end;
$$;
