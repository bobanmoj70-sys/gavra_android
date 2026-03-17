-- ==========================================
-- PUSH NOTIFIKACIJE - SQL TRIGGERS & FUNCTIONS
-- ==========================================

-- 1. FUNKCIJA: Slanje notifikacije putem Edge Funkcije
CREATE OR REPLACE FUNCTION notify_push(
    p_tokens jsonb,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
) RETURNS void AS $$
BEGIN
    PERFORM net.http_post(
        url := (SELECT value FROM server_secrets WHERE key = 'SUPABASE_URL') || '/functions/v1/send-push-notification',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || (SELECT value FROM server_secrets WHERE key = 'SUPABASE_SERVICE_ROLE_KEY')
        ),
        body := jsonb_build_object(
            'tokens', p_tokens,
            'title', p_title,
            'body', p_body,
            'data', p_data
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. FUNKCIJA: Automatizacija v2_polasci Notifikacija
CREATE OR REPLACE FUNCTION notify_v2_polazak_update()
RETURNS trigger AS $$
DECLARE
    v_tokens jsonb;
    v_title text;
    v_body text;
    v_data jsonb;
    v_putnik_ime text;
    v_grad_display text;
BEGIN
    -- Novi dnevni zahtev → obavijesti admina
    IF (TG_OP = 'INSERT' AND NEW.status = 'obrada' AND NEW.putnik_tabela = 'v2_dnevni') THEN
        SELECT ime INTO v_putnik_ime FROM v2_dnevni WHERE id = NEW.putnik_id;
        v_grad_display := CASE WHEN NEW.grad = 'BC' THEN 'Bela Crkva' WHEN NEW.grad = 'VS' THEN 'Vršac' ELSE NEW.grad END;
        SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
        INTO v_tokens
        FROM v2_push_tokens
        WHERE vozac_id = (SELECT id FROM v2_vozaci WHERE ime = 'Bojan' LIMIT 1);
        IF v_tokens IS NOT NULL AND jsonb_array_length(v_tokens) > 0 THEN
            PERFORM notify_push(
                v_tokens,
                '🎟️ Novi dnevni zahtev',
                COALESCE(v_putnik_ime, 'Putnik') || ' traži vožnju u ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' (' || v_grad_display || ', ' || UPPER(NEW.dan) || ')',
                jsonb_build_object('type', 'v2_dnevni_obrada', 'id', NEW.id, 'grad', NEW.grad)
            );
        END IF;
        RETURN NEW;
    END IF;

    -- Samo ako se status mijenja
    IF (OLD.status = NEW.status) THEN RETURN NEW; END IF;

    v_grad_display := CASE WHEN NEW.grad = 'BC' THEN 'Bela Crkva' WHEN NEW.grad = 'VS' THEN 'Vršac' ELSE NEW.grad END;

    -- Dohvati tokene putnika iz v2_push_tokens (vezano za putnik_id)
    SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
    INTO v_tokens
    FROM v2_push_tokens
    WHERE putnik_id = NEW.putnik_id;

    IF v_tokens IS NOT NULL AND jsonb_array_length(v_tokens) > 0 THEN
        IF NEW.status = 'odobreno' THEN
            v_title := '✅ Mesto osigurano!';
            v_body := 'Vaš zahtev za ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' (' || v_grad_display || ') je odobren. Srećan put!';
            v_data := jsonb_build_object('type', 'v2_odobreno', 'id', NEW.id, 'grad', NEW.grad);
        ELSIF NEW.status = 'odbijeno' THEN
            IF NEW.alternative_vreme_1 IS NOT NULL OR NEW.alternative_vreme_2 IS NOT NULL THEN
                v_title := '⚠️ Termin pun - Izaberi alternativu';
                v_body := 'Termin ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' je pun. Slobodna mesta: '
                    || COALESCE(to_char(NEW.alternative_vreme_1::time, 'HH24:MI'), '')
                    || CASE WHEN NEW.alternative_vreme_1 IS NOT NULL AND NEW.alternative_vreme_2 IS NOT NULL THEN ' i ' ELSE '' END
                    || COALESCE(to_char(NEW.alternative_vreme_2::time, 'HH24:MI'), '');
                v_data := jsonb_build_object(
                    'type', 'v2_alternativa',
                    'id', NEW.id,
                    'grad', NEW.grad,
                    'dan', NEW.dan,
                    'vreme', to_char(NEW.zeljeno_vreme::time, 'HH24:MI'),
                    'putnik_id', NEW.putnik_id,
                    'alternative_1', to_char(NEW.alternative_vreme_1::time, 'HH24:MI'),
                    'alternative_2', to_char(NEW.alternative_vreme_2::time, 'HH24:MI')
                );
            ELSE
                v_title := '❌ Termin popunjen';
                v_body := 'Nažalost, u terminu ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' više nema slobodnih mesta.';
                v_data := jsonb_build_object('type', 'v2_odbijeno', 'id', NEW.id, 'grad', NEW.grad);
            END IF;
        END IF;

        IF v_title IS NOT NULL THEN
            PERFORM notify_push(v_tokens, v_title, v_body, v_data);
        END IF;
    END IF;

    -- Za otkazano → obavijesti vozače
    -- Ako je putnik otkazao (cancelled_by nije vozač) → svi vozači
    -- Ako je vozač otkazao (cancelled_by je u v2_vozaci) → ostali vozači (ne taj vozač)
    IF NEW.status = 'otkazano' THEN
        IF EXISTS (SELECT 1 FROM v2_vozaci WHERE ime = NEW.cancelled_by) THEN
            -- Vozač otkazao → šalji svim OSIM njemu
            SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
            INTO v_tokens
            FROM v2_push_tokens
            WHERE vozac_id IN (SELECT id FROM v2_vozaci)
              AND vozac_id IS DISTINCT FROM (SELECT id FROM v2_vozaci WHERE ime = NEW.cancelled_by LIMIT 1);
        ELSE
            -- Putnik otkazao → šalji svim vozačima
            SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
            INTO v_tokens
            FROM v2_push_tokens
            WHERE vozac_id IN (SELECT id FROM v2_vozaci);
        END IF;

        IF v_tokens IS NOT NULL AND jsonb_array_length(v_tokens) > 0 THEN
            -- Pokušaj da nađeš ime putnika u svim v2 tabelama
            SELECT ime INTO v_putnik_ime FROM v2_radnici WHERE id = NEW.putnik_id;
            IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_ucenici WHERE id = NEW.putnik_id; END IF;
            IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_dnevni WHERE id = NEW.putnik_id; END IF;
            IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_posiljke WHERE id = NEW.putnik_id; END IF;
            PERFORM notify_push(
                v_tokens,
                '🚫 Otkazivanje (' || v_grad_display || ')',
                COALESCE(v_putnik_ime, 'Putnik') || ' otkazao vožnju za ' || to_char(NEW.zeljeno_vreme, 'HH24:MI') || ' (' || UPPER(NEW.dan) || ')',
                jsonb_build_object('type', 'v2_otkazano', 'id', NEW.id, 'grad', NEW.grad)
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3. TRIGGER: Aktiviraj na tabeli v2_polasci
DROP TRIGGER IF EXISTS tr_v2_polazak_notification ON v2_polasci;
CREATE TRIGGER tr_v2_polazak_notification
AFTER INSERT OR UPDATE ON v2_polasci
FOR EACH ROW EXECUTE FUNCTION notify_v2_polazak_update();

-- 4. FUNKCIJA: PIN zahtev → obavijesti admina
CREATE OR REPLACE FUNCTION notify_v2_pin_zahtev()
RETURNS trigger AS $$
DECLARE
    v_tokens jsonb;
    v_putnik_ime text;
BEGIN
    IF (TG_OP = 'INSERT' AND NEW.status = 'ceka') THEN
        SELECT ime INTO v_putnik_ime FROM v2_dnevni WHERE id = NEW.putnik_id;
        IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_radnici WHERE id = NEW.putnik_id; END IF;
        IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_ucenici WHERE id = NEW.putnik_id; END IF;
        IF v_putnik_ime IS NULL THEN SELECT ime INTO v_putnik_ime FROM v2_posiljke WHERE id = NEW.putnik_id; END IF;

        SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
        INTO v_tokens
        FROM v2_push_tokens
        WHERE vozac_id = (SELECT id FROM v2_vozaci WHERE ime = 'Bojan' LIMIT 1);

        IF v_tokens IS NOT NULL AND jsonb_array_length(v_tokens) > 0 THEN
            PERFORM notify_push(
                v_tokens,
                '🔔 Novi zahtev za PIN',
                COALESCE(v_putnik_ime, 'Putnik') || ' traži PIN za pristup aplikaciji',
                jsonb_build_object('type', 'pin_zahtev', 'putnik_id', NEW.putnik_id)
            );
        END IF;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 5. TRIGGER: Aktiviraj na tabeli v2_pin_zahtevi
DROP TRIGGER IF EXISTS tr_v2_pin_zahtev_notification ON v2_pin_zahtevi;
CREATE TRIGGER tr_v2_pin_zahtev_notification
AFTER INSERT ON v2_pin_zahtevi
FOR EACH ROW EXECUTE FUNCTION notify_v2_pin_zahtev();

-- 6. FUNKCIJA: v3_zahtevi → push putnik pri promeni statusa
CREATE OR REPLACE FUNCTION notify_v3_zahtev_update()
RETURNS trigger AS $$
DECLARE
    v_tokens jsonb;
    v_title  text;
    v_body   text;
    v_data   jsonb;
    v_grad   text;
BEGIN
    IF (OLD.status = NEW.status) THEN RETURN NEW; END IF;

    v_grad := CASE WHEN NEW.grad = 'BC' THEN 'Bela Crkva' WHEN NEW.grad = 'VS' THEN 'Vršac' ELSE NEW.grad END;

    SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
    INTO v_tokens
    FROM v3_putnici
    WHERE id = NEW.putnik_id AND push_token IS NOT NULL;

    IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN RETURN NEW; END IF;

    IF NEW.status = 'odobreno' THEN
        v_title := '✅ Mesto osigurano!';
        v_body  := 'Vaš zahtev za ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' (' || v_grad || ') je odobren. Srećan put!';
        v_data  := jsonb_build_object('type', 'v3_odobreno', 'id', NEW.id, 'grad', NEW.grad);

    ELSIF NEW.status = 'odbijeno' THEN
        IF NEW.alt_vreme_pre IS NOT NULL OR NEW.alt_vreme_posle IS NOT NULL THEN
            v_title := '⚠️ Termin pun - Izaberi alternativu';
            v_body  := 'Termin ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' je pun. Slobodna mesta: '
                || COALESCE(to_char(NEW.alt_vreme_pre::time, 'HH24:MI'), '')
                || CASE WHEN NEW.alt_vreme_pre IS NOT NULL AND NEW.alt_vreme_posle IS NOT NULL THEN ' i ' ELSE '' END
                || COALESCE(to_char(NEW.alt_vreme_posle::time, 'HH24:MI'), '');
            v_data  := jsonb_build_object(
                'type', 'v3_alternativa',
                'id', NEW.id,
                'grad', NEW.grad,
                'alt_pre', to_char(NEW.alt_vreme_pre::time, 'HH24:MI'),
                'alt_posle', to_char(NEW.alt_vreme_posle::time, 'HH24:MI')
            );
        ELSE
            v_title := '❌ Termin popunjen';
            v_body  := 'Nažalost, u terminu ' || to_char(NEW.zeljeno_vreme::time, 'HH24:MI') || ' nema slobodnih mesta (' || v_grad || ').';
            v_data  := jsonb_build_object('type', 'v3_odbijeno', 'id', NEW.id, 'grad', NEW.grad);
        END IF;
    END IF;

    IF v_title IS NOT NULL THEN
        PERFORM notify_push(v_tokens, v_title, v_body, v_data);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 7. TRIGGER: Aktiviraj na tabeli v3_zahtevi
DROP TRIGGER IF EXISTS tr_v3_zahtev_notification ON v3_zahtevi;
CREATE TRIGGER tr_v3_zahtev_notification
AFTER UPDATE ON v3_zahtevi
FOR EACH ROW EXECUTE FUNCTION notify_v3_zahtev_update();

-- ==========================================
-- V3 NOVI SISTEM – PUSH NOTIFIKACIJE (2025)
-- ==========================================

-- 8. FUNKCIJA: v3_zahtevi INSERT → push adminu (Bojan)
--    Token čita iz v3_vozaci (ne v3_putnici!)
CREATE OR REPLACE FUNCTION public.fn_v3_notify_admin_on_zahtev_dnevni()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_token  text;
  v_tokens jsonb;
  v_tip    text;
  v_grad   text;
  v_naslov text;
  v_poruka text;
  v_data   jsonb;
BEGIN
  -- Šalji samo nove zahteve na obradi
  IF NEW.status != 'obrada' THEN
    RETURN NEW;
  END IF;

  -- Token admina iz v3_vozaci (Bojan)
  SELECT push_token INTO v_token
  FROM public.v3_vozaci
  WHERE LOWER(ime_prezime) LIKE '%bojan%'
    AND aktivno = true
    AND push_token IS NOT NULL AND push_token <> ''
  LIMIT 1;

  IF v_token IS NULL OR v_token = '' THEN
    RETURN NEW;
  END IF;

  v_tokens := jsonb_build_array(
    jsonb_build_object('token', v_token, 'provider', 'fcm')
  );

  -- Tip putnika za kontekst
  SELECT tip_putnika INTO v_tip
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
  LIMIT 1;

  v_grad := CASE
    WHEN NEW.grad = 'BC' THEN 'Bela Crkva'
    WHEN NEW.grad = 'VS' THEN 'Vršac'
    ELSE NEW.grad
  END;

  v_naslov := '🔔 Novi zahtev – ' || v_grad || ' ' || to_char(NEW.zeljeno_vreme, 'HH24:MI');
  v_poruka := COALESCE(NEW.ime_prezime, 'Putnik')
    || CASE WHEN v_tip IS NOT NULL THEN ' (' || v_tip || ')' ELSE '' END
    || ' · ' || to_char(NEW.datum, 'DD.MM.YYYY');

  v_data := jsonb_build_object(
    'type', 'v3_novi_zahtev',
    'id', NEW.id,
    'grad', NEW.grad,
    'tip', COALESCE(v_tip, '')
  );

  PERFORM notify_push(v_tokens, v_naslov, v_poruka, v_data);

  RETURN NEW;
END;
$$;

-- 9. TRIGGER: Aktiviraj na tabeli v3_zahtevi (INSERT)
DROP TRIGGER IF EXISTS tr_v3_notify_admin_zahtev ON v3_zahtevi;
CREATE TRIGGER tr_v3_notify_admin_zahtev
AFTER INSERT ON v3_zahtevi
FOR EACH ROW EXECUTE FUNCTION fn_v3_notify_admin_on_zahtev_dnevni();

-- 10. FUNKCIJA: v3_zahtevi UPDATE → push putniku
--     Šalje pri promeni statusa: odobreno / odbijeno (sa/bez alternative) / otkazano / ponuda
CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_zahtev_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tokens jsonb;
  v_title  text;
  v_body   text;
  v_data   jsonb;
  v_grad   text;
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  v_grad := CASE
    WHEN NEW.grad = 'BC' THEN 'Bela Crkva'
    WHEN NEW.grad = 'VS' THEN 'Vršac'
    ELSE NEW.grad
  END;

  SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
  INTO v_tokens
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
    AND push_token IS NOT NULL AND push_token <> ''
  LIMIT 1;

  IF v_tokens IS NULL THEN RETURN NEW; END IF;

  IF NEW.status = 'odobreno' THEN
    v_title := '✅ Mesto osigurano!';
    v_body  := 'Vaš zahtev za ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
      || ' (' || v_grad || ') je odobren. Srećan put!';
    v_data  := jsonb_build_object('type', 'v3_zahtev_odobren', 'id', NEW.id, 'grad', NEW.grad);

  ELSIF NEW.status = 'odbijeno' THEN
    IF NEW.alt_vreme_pre IS NOT NULL OR NEW.alt_vreme_posle IS NOT NULL THEN
      v_title := '⚠️ Termin pun – Izaberi alternativu';
      v_body  := 'Termin ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
        || ' je pun. Slobodna mesta: '
        || COALESCE(to_char(NEW.alt_vreme_pre, 'HH24:MI'), '')
        || CASE WHEN NEW.alt_vreme_pre IS NOT NULL AND NEW.alt_vreme_posle IS NOT NULL THEN ' i ' ELSE '' END
        || COALESCE(to_char(NEW.alt_vreme_posle, 'HH24:MI'), '');
      v_data  := jsonb_build_object(
        'type',      'v3_alternativa',
        'id',        NEW.id,
        'grad',      NEW.grad,
        'alt_pre',   COALESCE(to_char(NEW.alt_vreme_pre,   'HH24:MI'), ''),
        'alt_posle', COALESCE(to_char(NEW.alt_vreme_posle, 'HH24:MI'), ''),
        'data_only', true
      );
    ELSE
      v_title := '❌ Termin popunjen';
      v_body  := 'Nažalost, u terminu ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
        || ' nema slobodnih mesta (' || v_grad || ').';
      v_data  := jsonb_build_object('type', 'v3_zahtev_odbijen', 'id', NEW.id, 'grad', NEW.grad);
    END IF;

  ELSIF NEW.status = 'otkazano' THEN
    v_title := '🚫 Prevoz otkazan';
    v_body  := 'Vaš prevoz za ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
      || ' (' || v_grad || ') je otkazan.';
    v_data  := jsonb_build_object('type', 'v3_otkazano', 'id', NEW.id, 'grad', NEW.grad);

  ELSIF NEW.status = 'ponuda' THEN
    v_title := '🕐 Nova ponuda termina';
    v_body  := 'Predložen je novi termin umjesto ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
      || ' (' || v_grad || ').';
    v_data  := jsonb_build_object(
      'type',      'v3_alternativa',
      'id',        NEW.id,
      'grad',      NEW.grad,
      'alt_pre',   COALESCE(to_char(NEW.alt_vreme_pre,   'HH24:MI'), ''),
      'alt_posle', COALESCE(to_char(NEW.alt_vreme_posle, 'HH24:MI'), ''),
      'data_only', true
    );
  END IF;

  IF v_title IS NOT NULL THEN
    PERFORM notify_push(v_tokens, v_title, v_body, v_data);
  END IF;

  RETURN NEW;
END;
$$;

-- 11. TRIGGER: Aktiviraj na tabeli v3_zahtevi (UPDATE statusa)
DROP TRIGGER IF EXISTS tr_v3_notify_putnik_zahtev ON v3_zahtevi;
CREATE TRIGGER tr_v3_notify_putnik_zahtev
AFTER UPDATE OF status ON v3_zahtevi
FOR EACH ROW EXECUTE FUNCTION fn_v3_notify_putnik_on_zahtev_update();

-- ==========================================
-- 12. FUNKCIJA: v3_pin_zahtevi INSERT → push adminu
--     Admin dobija push kada putnik pošalje zahtev za PIN
-- ==========================================
CREATE OR REPLACE FUNCTION public.fn_v3_notify_admin_on_pin_zahtev()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tokens     jsonb;
  v_putnik_ime text;
BEGIN
  IF TG_OP <> 'INSERT' OR NEW.status <> 'ceka' THEN RETURN NEW; END IF;

  -- Dohvati ime putnika
  SELECT imePrezime INTO v_putnik_ime
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
  LIMIT 1;

  -- Dohvati admin token (Bojan)
  SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
  INTO v_tokens
  FROM public.v3_vozaci
  WHERE LOWER(ime_prezime) LIKE '%bojan%'
    AND push_token IS NOT NULL AND push_token <> ''
  LIMIT 1;

  IF v_tokens IS NULL THEN RETURN NEW; END IF;

  PERFORM notify_push(
    v_tokens,
    '🔔 Novi zahtev za PIN',
    COALESCE(v_putnik_ime, 'Putnik') || ' traži PIN za pristup aplikaciji'
      || CASE WHEN NEW.telefon IS NOT NULL THEN ' · ' || NEW.telefon ELSE '' END,
    jsonb_build_object(
      'type',      'v3_pin_zahtev',
      'zahtev_id', NEW.id,
      'putnik_id', NEW.putnik_id
    )
  );

  RETURN NEW;
END;
$$;

-- 12. TRIGGER: Aktiviraj na tabeli v3_pin_zahtevi (INSERT)
DROP TRIGGER IF EXISTS tr_v3_notify_admin_pin_zahtev ON v3_pin_zahtevi;
CREATE TRIGGER tr_v3_notify_admin_pin_zahtev
AFTER INSERT ON v3_pin_zahtevi
FOR EACH ROW EXECUTE FUNCTION fn_v3_notify_admin_on_pin_zahtev();

-- ==========================================
-- 13. FUNKCIJA: v3_pin_zahtevi UPDATE → push putniku
--     Putnik dobija push kada admin odbije zahtev za PIN
-- ==========================================
CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_pin_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tokens jsonb;
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  -- Push samo pri odbijanju (odobravanje → admin šalje SMS sa PIN-om)
  IF NEW.status <> 'odbijen' THEN RETURN NEW; END IF;

  SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
  INTO v_tokens
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
    AND push_token IS NOT NULL AND push_token <> ''
  LIMIT 1;

  IF v_tokens IS NULL THEN RETURN NEW; END IF;

  PERFORM notify_push(
    v_tokens,
    '❌ Zahtev za PIN odbijen',
    'Vaš zahtev za PIN je odbijen. Kontaktirajte administraciju za više informacija.',
    jsonb_build_object(
      'type',      'v3_pin_odbijen',
      'zahtev_id', NEW.id,
      'putnik_id', NEW.putnik_id
    )
  );

  RETURN NEW;
END;
$$;

-- 13. TRIGGER: Aktiviraj na tabeli v3_pin_zahtevi (UPDATE statusa)
DROP TRIGGER IF EXISTS tr_v3_notify_putnik_pin_zahtev ON v3_pin_zahtevi;
CREATE TRIGGER tr_v3_notify_putnik_pin_zahtev
AFTER UPDATE OF status ON v3_pin_zahtevi
FOR EACH ROW EXECUTE FUNCTION fn_v3_notify_putnik_on_pin_update();
