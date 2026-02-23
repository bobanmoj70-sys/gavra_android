-- ==========================================
-- DIGITALNI DISPEČER - SQL LOGIKA (V1.0)
-- ==========================================

-- 1. POMOĆNA FUNKCIJA: Dobavljanje imena dana (pon, uto...) iz datuma
CREATE OR REPLACE FUNCTION get_dan_kratica(target_date date)
RETURNS text AS $$
BEGIN
    RETURN CASE EXTRACT(DOW FROM target_date)
        WHEN 1 THEN 'pon'
        WHEN 2 THEN 'uto'
        WHEN 3 THEN 'sre'
        WHEN 4 THEN 'cet'
        WHEN 5 THEN 'pet'
        WHEN 6 THEN 'sub'
        WHEN 0 THEN 'ned'
    END;
END;
$$ LANGUAGE plpgsql;

-- 1A. POMOĆNA FUNKCIJA: Pravila čekanja po gradu i tipu putnika
--
-- ⛔⛔⛔ NE MIJENJATI - ZACEMENTIRANA PRAVILA ⛔⛔⛔
-- Ova pravila su dogovorena i potvrđena 21.02.2026.
-- Svaka izmjena mora biti eksplicitno odobrena od vlasnika projekta.
--
-- PRAVILA ČEKANJA (vrijede za SVE putničke tipove):
--
--   BC - RADNIK   : 5 minuta čekanja, SA provjerom kapaciteta
--   BC - UČENIK   : (za sutra, zahtjev poslat PRIJE 16:00) → 5 min, BEZ provjere kapaciteta (garantovano mjesto)
--   BC - UČENIK   : (zahtjev poslat POSLE 16:00) → čeka do 20:00h, SA provjerom kapaciteta
--   BC - POŠILJKA : 5 minuta čekanja, BEZ provjere kapaciteta (ne zauzima mjesto)
--   BC - default  : 5 minuta čekanja, SA provjerom kapaciteta
--
--   VS - RADNIK   : 10 minuta čekanja, SA provjerom kapaciteta
--   VS - UČENIK   : 10 minuta čekanja, SA provjerom kapaciteta
--   VS - POŠILJKA : 5 minuta čekanja, BEZ provjere kapaciteta (ne zauzima mjesto)
--   VS - default  : 10 minuta čekanja, SA provjerom kapaciteta
--
--   DNEVNI putnici: NIKAD ne prolaze kroz auto-obradu → uvijek status 'manual' (admin odobrava ručno)
--
-- NAPOMENA: p_created_at parametar se prosleđuje updated_at vrijednost iz seat_requests
--           (čekanje se mjeri od posljednje izmjene, ne od prvog insert-a)
-- ⛔⛔⛔ KRAJ ZACEMENTIRANIH PRAVILA ⛔⛔⛔
CREATE OR REPLACE FUNCTION get_cekanje_pravilo(
    p_tip text,
    p_grad text,
    p_datum date,
    p_created_at timestamptz
) RETURNS TABLE(
    minuta_cekanja integer,
    provera_kapaciteta boolean
) AS $$
BEGIN
    -- BC PRAVILA
    IF upper(p_grad) = 'BC' THEN
        -- ⛔ BC Učenik (za sutra, pre 16h): 5 min, BEZ provere kapaciteta - garantovano mesto
        IF lower(p_tip) = 'ucenik' 
           AND p_datum = (CURRENT_DATE + 1)
           AND EXTRACT(HOUR FROM p_created_at) < 16
        THEN
            RETURN QUERY SELECT 5, false;
        -- ⛔ BC Radnik: 5 min, SA proverom kapaciteta
        ELSIF lower(p_tip) = 'radnik' THEN
            RETURN QUERY SELECT 5, true;
        -- ⛔ BC Učenik (posle 16h): čeka do 20h, SA proverom kapaciteta
        ELSIF lower(p_tip) = 'ucenik' 
              AND p_datum = (CURRENT_DATE + 1)
              AND EXTRACT(HOUR FROM p_created_at) >= 16
        THEN
            RETURN QUERY SELECT 0, true; -- Specijalni slučaj, obrađuje se u 20h
        -- ⛔ BC Pošiljka: 5 min, BEZ provere (ne zauzima mesto)
        ELSIF lower(p_tip) = 'posiljka' THEN
            RETURN QUERY SELECT 5, false;
        ELSE
            -- ⛔ BC Default: 5 min, SA proverom kapaciteta
            RETURN QUERY SELECT 5, true;
        END IF;
    
    -- VS PRAVILA
    ELSIF upper(p_grad) = 'VS' THEN
        -- ⛔ VS Radnik: 10 min, SA proverom kapaciteta
        IF lower(p_tip) = 'radnik' THEN
            RETURN QUERY SELECT 10, true;
        -- ⛔ VS Učenik: 10 min, SA proverom kapaciteta
        ELSIF lower(p_tip) = 'ucenik' THEN
            RETURN QUERY SELECT 10, true;
        -- ⛔ VS Pošiljka: 5 min, BEZ provere (ne zauzima mesto)
        ELSIF lower(p_tip) = 'posiljka' THEN
            RETURN QUERY SELECT 5, false;
        ELSE
            -- ⛔ VS Default: 10 min, SA proverom kapaciteta
            RETURN QUERY SELECT 10, true;
        END IF;
    
    -- DEFAULT (nepoznat grad)
    ELSE
        RETURN QUERY SELECT 5, true;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- 2. POMOĆNA FUNKCIJA: Provera slobodnih mesta
CREATE OR REPLACE FUNCTION proveri_slobodna_mesta(target_grad text, target_vreme time, target_datum date)
RETURNS integer AS $$
DECLARE
    max_mesta_val integer;
    zauzeto_val integer;
BEGIN
    -- 1. Dohvati max mesta iz kapaciteta
    SELECT kp.max_mesta INTO max_mesta_val 
    FROM kapacitet_polazaka kp
    WHERE kp.grad = UPPER(target_grad) AND kp.vreme = target_vreme AND kp.aktivan = true;
    
    IF max_mesta_val IS NULL THEN max_mesta_val := 8; END IF;

    -- 2. Prebroj putnike koji već ZAUZIMAJU mesto kod dispečera u tabeli SEAT_REQUESTS
    -- Računamo one koji su PENDING (čekaju obradu), MANUAL (čekaju admina) ili APPROVED/CONFIRMED
    SELECT COALESCE(SUM(sr.broj_mesta), 0) INTO zauzeto_val
    FROM seat_requests sr
    WHERE sr.datum = target_datum
      AND sr.grad = UPPER(target_grad)
      AND sr.zeljeno_vreme::time = target_vreme
      AND sr.status IN ('pending', 'manual', 'approved', 'confirmed');

    RETURN max_mesta_val - zauzeto_val;
END;
$$ LANGUAGE plpgsql;

-- 3. GLAVNA FUNKCIJA: Obrada pojedinačnog zahteva (UNIVERZALNA za BC i VS)
CREATE OR REPLACE FUNCTION obradi_seat_request(req_id uuid)
RETURNS void AS $$
DECLARE
    req_record record;
    putnik_record record;
    ima_mesta boolean;
    slobodno_mesta integer;
    novi_status text;
    v_alt_1 time;
    v_alt_2 time;
BEGIN
    -- 1. Dohvati podatke o zahtevu i putniku
    SELECT * INTO req_record FROM seat_requests s WHERE s.id = req_id;
    IF NOT FOUND OR req_record.status != 'pending' THEN RETURN; END IF;

    SELECT * INTO putnik_record FROM registrovani_putnici r WHERE r.id = req_record.putnik_id;
    IF NOT FOUND THEN RETURN; END IF;

    -- 2. PROVERA KAPACITETA prema pravilima (poziva se get_cekanje_pravilo)
    -- BC učenici (pre 16h za sutra) NE PROVERAVAJU kapacitet - garantovano mesto
    IF lower(putnik_record.tip) = 'ucenik' 
       AND upper(req_record.grad) = 'BC' 
       AND req_record.datum = (CURRENT_DATE + 1)
       AND EXTRACT(HOUR FROM req_record.created_at) < 16
    THEN
        ima_mesta := true;
    ELSE
        slobodno_mesta := proveri_slobodna_mesta(req_record.grad, req_record.zeljeno_vreme, req_record.datum);
        ima_mesta := (slobodno_mesta >= req_record.broj_mesta);
    END IF;

    -- 3. ODREĐIVANJE NOVOG STATUSA I LOGIČNIH ALTERNATIVA
    IF ima_mesta THEN
        novi_status := 'approved';
    ELSE
        novi_status := 'rejected';
        
        -- Pronađi PRVI slobodan termin PRE željenog vremena
        SELECT vreme INTO v_alt_1
        FROM kapacitet_polazaka 
        WHERE grad = UPPER(req_record.grad) 
          AND aktivan = true 
          AND proveri_slobodna_mesta(req_record.grad, vreme, req_record.datum) >= req_record.broj_mesta
          AND vreme < req_record.zeljeno_vreme
        ORDER BY vreme DESC
        LIMIT 1;
        
        -- Pronađi PRVI slobodan termin POSLE željenog vremena
        SELECT vreme INTO v_alt_2
        FROM kapacitet_polazaka 
        WHERE grad = UPPER(req_record.grad) 
          AND aktivan = true 
          AND proveri_slobodna_mesta(req_record.grad, vreme, req_record.datum) >= req_record.broj_mesta
          AND vreme > req_record.zeljeno_vreme
        ORDER BY vreme ASC
        LIMIT 1;
    END IF;

    -- 4. AŽURIRAJ SEAT_REQUESTS
    UPDATE seat_requests 
    SET status = novi_status, 
        alternative_vreme_1 = v_alt_1,
        alternative_vreme_2 = v_alt_2,
        processed_at = now(),
        updated_at = now()
    WHERE id = req_id;
END;
$$ LANGUAGE plpgsql;

-- 4. PERIODIČNA FUNKCIJA: Koju će aplikacija ili mini-cron pozivati
CREATE OR REPLACE FUNCTION dispecer_cron_obrada()
RETURNS jsonb AS $$
DECLARE
    v_req record;
    processed_records jsonb := '[]'::jsonb;
    current_req_data jsonb;
    cekanje_pravilo record;
BEGIN
    -- Pronađi sve koji čekaju obradu prema pravilima čekanja
    -- Koristi get_cekanje_pravilo() da odredi vreme čekanja za svaki tip/grad
    FOR v_req IN 
        SELECT sr.id, sr.grad, sr.datum, sr.updated_at, rp.tip
        FROM seat_requests sr
        JOIN registrovani_putnici rp ON sr.putnik_id = rp.id
        WHERE sr.status = 'pending' 
          AND lower(rp.tip) != 'dnevni' -- ⛔ NE MIJENJATI: Dnevni putnici NIKAD ne prolaze auto-obradu → manual
    LOOP
        -- Proveri pravilo čekanja za ovaj zahtev
        -- VAŽNO: Koristimo updated_at (ne created_at) da bi reset vremena radio
        -- kad putnik promijeni termin - čekanje kreće od posljednje izmjene
        SELECT * INTO cekanje_pravilo 
        FROM get_cekanje_pravilo(
            v_req.tip, 
            v_req.grad, 
            v_req.datum, 
            v_req.updated_at
        );
        
        -- Ako je vreme isteklo, obradi zahtev
        -- Specijalni slučaj: BC učenik posle 16h čeka do 20h
        IF (
            -- BC učenik posle 16h: obrađuje se u 20h
            (lower(v_req.tip) = 'ucenik' 
             AND upper(v_req.grad) = 'BC' 
             AND v_req.datum = (CURRENT_DATE + 1)
             AND EXTRACT(HOUR FROM v_req.updated_at) >= 16
             AND EXTRACT(HOUR FROM now()) >= 20)
            OR
            -- Svi ostali: proveri da li je vreme čekanja isteklo
            ((EXTRACT(EPOCH FROM (now() - v_req.updated_at)) / 60) >= cekanje_pravilo.minuta_cekanja
             AND NOT (lower(v_req.tip) = 'ucenik' 
                      AND upper(v_req.grad) = 'BC' 
                      AND v_req.datum = (CURRENT_DATE + 1)
                      AND EXTRACT(HOUR FROM v_req.updated_at) >= 16))
        ) THEN
            PERFORM obradi_seat_request(v_req.id);
            
            SELECT jsonb_build_object(
                'id', s.id,
                'putnik_id', s.putnik_id,
                'zeljeno_vreme', s.zeljeno_vreme::text,
                'status', s.status,
                'grad', s.grad,
                'datum', s.datum::text,
                'ime_putnika', rp.putnik_ime,
                'alternative_vreme_1', s.alternative_vreme_1::text,
                'alternative_vreme_2', s.alternative_vreme_2::text
            ) INTO current_req_data
            FROM seat_requests s
            JOIN registrovani_putnici rp ON s.putnik_id = rp.id
            WHERE s.id = v_req.id;

            processed_records := processed_records || jsonb_build_array(current_req_data);
        END IF;
    END LOOP;

    RETURN processed_records;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 5. POMOĆNA FUNKCIJA: Atomski update polaska (SADA RADI PREKO SEAT_REQUESTS)
-- ==========================================
CREATE OR REPLACE FUNCTION update_putnik_polazak_v2(
    p_id UUID,
    p_dan TEXT,
    p_grad TEXT,
    p_vreme TEXT,
    p_status TEXT DEFAULT NULL,
    p_ceka_od TEXT DEFAULT NULL, -- Ignorišemo, koristimo created_at u seat_requests
    p_otkazano TEXT DEFAULT NULL,
    p_otkazano_vreme TEXT DEFAULT NULL,
    p_otkazao_vozac TEXT DEFAULT NULL
) RETURNS void AS $$
DECLARE
    target_date date;
    grad_clean text;
    final_status text;
    existing_id uuid;
    p_broj_mesta integer;
    putnik_tip text;
BEGIN
    -- 0. Dohvati tip putnika
    SELECT tip INTO putnik_tip FROM registrovani_putnici WHERE id = p_id;
    
    -- 1. Odredi datum za p_dan (npr 'pon')
    -- Tražimo sledeći datum koji odgovara krativci dana, uključujući i danas ako još nije prošao
    SELECT d INTO target_date
    FROM (
        SELECT CURRENT_DATE + i as d
        FROM generate_series(0, 7) i
    ) dates
    WHERE get_dan_kratica(d) = lower(p_dan)
    LIMIT 1;

    -- 2. Očisti grad (bc2 -> BC, vs2 -> VS)
    grad_clean := UPPER(replace(p_grad, '2', ''));

    -- 3. Odredi status
    -- Ako je dnevni putnik -> automatski 'manual' (admin obrađuje)
    IF lower(putnik_tip) = 'dnevni' THEN
        final_status := 'manual';
    ELSE
        final_status := COALESCE(p_status, 'pending');
    END IF;
    
    IF p_vreme IS NULL OR p_vreme = '' OR p_vreme = 'null' THEN
        final_status := 'cancelled';
    END IF;

    -- 4. Dohvati broj mesta putnika
    SELECT broj_mesta INTO p_broj_mesta FROM registrovani_putnici WHERE id = p_id;
    IF p_broj_mesta IS NULL THEN p_broj_mesta := 1; END IF;

    -- 5. UPSERT u seat_requests za taj datum i putnika
    -- Prvo proveri da li već postoji zahtev za taj datum i taj smer (grad)
    SELECT id INTO existing_id 
    FROM seat_requests 
    WHERE putnik_id = p_id AND datum = target_date AND grad = grad_clean;

    IF existing_id IS NOT NULL THEN
        UPDATE seat_requests 
        SET zeljeno_vreme = CASE 
                WHEN p_vreme IS NULL OR p_vreme = '' OR p_vreme = 'null' THEN zeljeno_vreme 
                ELSE p_vreme::time 
            END,
            status = final_status,
            updated_at = now()
        WHERE id = existing_id;
    ELSE
        INSERT INTO seat_requests (putnik_id, grad, zeljeno_vreme, datum, status, broj_mesta, created_at, updated_at)
        VALUES (
            p_id, 
            grad_clean, 
            CASE WHEN p_vreme IS NULL OR p_vreme = '' OR p_vreme = 'null' THEN NULL ELSE p_vreme::time END, 
            target_date, 
            final_status, 
            p_broj_mesta, 
            now(), 
            now()
        );
    END IF;

    UPDATE registrovani_putnici 
    SET updated_at = now()
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql;

-- ==========================================
-- 6. TRIGGERI ZA NOTIFIKACIJE I SINHRONIZACIJU
-- ==========================================
-- ⛔ NE MIJENJATI OVDJE - notify_seat_request_update() je definisana u push_triggers.sql
-- Trigger na tabeli seat_requests je: seat_request_status_changed → notify_seat_request_update()

-- ==========================================
-- 7. ČIŠĆENJE STARIH SEAT_REQUESTS: Nedeljno brisanje redova starijih od 30 dana
-- Historija je u voznje_log - seat_requests je operativna tabela
-- ==========================================
CREATE OR REPLACE FUNCTION ocisti_stare_seat_requests()
RETURNS jsonb AS $$
DECLARE
    v_obrisano integer;
BEGIN
    DELETE FROM seat_requests
    WHERE datum < CURRENT_DATE - INTERVAL '30 days';

    GET DIAGNOSTICS v_obrisano = ROW_COUNT;

    RETURN jsonb_build_object(
        'obrisano', v_obrisano,
        'vreme', now()
    );
END;
$$ LANGUAGE plpgsql;

-- CRON JOB: Čišćenje svake nedjelje u 03:00 UTC (04:00 srpskog)
SELECT cron.schedule(
    'ciscenje-seat-requests',
    '0 3 * * 0',
    $$ SELECT ocisti_stare_seat_requests() $$
);

-- ==========================================
-- 9. PODSETNIK RADNICIMA: Subota 10:00 - push notifikacija radnicima koji nisu zakazali
-- ==========================================
CREATE OR REPLACE FUNCTION posalji_podsetnik_radnicima()
RETURNS jsonb AS $$
DECLARE
    v_tokens jsonb;
    v_putnik record;
    v_payload jsonb;
    v_sent integer := 0;
BEGIN
    FOR v_putnik IN
        SELECT DISTINCT rp.id, rp.putnik_ime
        FROM registrovani_putnici rp
        JOIN seat_requests sr ON sr.putnik_id = rp.id
        WHERE lower(rp.tip) = 'radnik'
          AND sr.status = 'bez_polaska'
          AND NOT EXISTS (
              SELECT 1 FROM seat_requests sr2
              WHERE sr2.putnik_id = rp.id
                AND sr2.status IN ('pending', 'manual', 'approved', 'confirmed')
          )
    LOOP
        SELECT jsonb_agg(jsonb_build_object('token', token, 'provider', provider))
        INTO v_tokens
        FROM push_tokens
        WHERE putnik_id = v_putnik.id;

        IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN CONTINUE; END IF;

        PERFORM net.http_post(
            url := (SELECT value FROM server_secrets WHERE key = 'EDGE_FUNCTION_URL' LIMIT 1) || '/send-push-notification',
            headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || (SELECT value FROM server_secrets WHERE key = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1)),
            body := jsonb_build_object(
                'tokens', v_tokens,
                'title', '🚌 Novi raspored',
                'body', 'Molimo vas da ažurirate polaske za narednu nedelju.',
                'data', jsonb_build_object('type', 'podsetnik_raspored')
            )
        );
        v_sent := v_sent + 1;
    END LOOP;

    RETURN jsonb_build_object('poslato', v_sent, 'vreme', now());
END;
$$ LANGUAGE plpgsql;

-- CRON JOB: Podsetnik radnicima svake subote u 09:00 UTC (10:00 srpskog)
SELECT cron.schedule(
    'podsetnik-radnici-subota',
    '0 9 * * 6',
    $$ SELECT posalji_podsetnik_radnicima() $$
);

-- ============================================================
-- SEKCIJA 9: SERVER SECRETS (OBAVEZNO PODESITI PRE POKRETANJA)
-- ============================================================
-- Ovi ključevi se čuvaju u tabeli server_secrets i koriste se
-- od strane Edge funkcija i SQL trigera za slanje notifikacija.
--
-- NAPOMENA: Ovo su primeri vrednosti. Pravi ključevi se mogu
-- naći u: C:\Users\Bojan\Desktop\AI BACKUP\secrets\huawei\HUAWEI.txt
--         i Supabase Dashboard → Project Settings → API
--
-- Pokretati samo jednom pri inicijalnom setup-u (ili pri rotaciji ključeva):

/*
INSERT INTO server_secrets (key, value) VALUES
    -- Supabase (Project Settings → API)
    ('SUPABASE_URL',              'https://gjtabtwudbrmfeyjiicu.supabase.co'),
    ('SUPABASE_ANON_KEY',         '<anon key iz Supabase Dashboard>'),
    ('SUPABASE_SERVICE_ROLE_KEY', '<service_role key iz Supabase Dashboard>'),
    ('EDGE_FUNCTION_URL',         'https://gjtabtwudbrmfeyjiicu.supabase.co/functions/v1'),

    -- Firebase (za FCM push - Android/iOS vozači i putnici)
    -- Preuzeti iz: Firebase Console → Project Settings → Service Accounts → Generate new private key
    ('FIREBASE_SERVICE_ACCOUNT',  '<JSON sadržaj firebase service account fajla>'),

    -- Huawei HMS Push Kit (za Huawei uređaje)
    -- VAŽNO: Koristiti OAuth 2.0 client kredencijale, NE AppGallery Connect API kredencijale!
    -- Preuzeti iz: HUAWEI.txt → "OAuth 2.0 client" sekcija
    -- client_id  = App ID (kratki broj, npr. 116046535)
    -- client_secret = OAuth secret (ebae022b...)
    ('HUAWEI_APP_ID',             '116046535'),
    ('HUAWEI_CLIENT_ID',          '116046535'),
    ('HUAWEI_CLIENT_SECRET',      'ebae022b57aeda6ff61826da26ba2493d946879b098adf72e5ea792f2a71f498')

ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
*/

-- Provjera trenutnih vrednosti:
-- SELECT key, LEFT(value, 40) || '...' as preview FROM server_secrets ORDER BY key;
