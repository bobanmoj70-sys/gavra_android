-- ============================================================
-- V3 GPS TRACKING OPTIMIZACIJA - SQL TRIGGERS & FUNCTIONS
-- Zamenjuje Timer logiku iz V3VozacScreen sa server-side optimizacijama
-- Koristi isti pattern kao Uber/Tesla/Google Maps
-- ============================================================

-- ============================================================
-- 1. PAMETNI GPS FILTER TRIGGER
-- Filtrira nepotrebne GPS pozive na database nivou
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_smart_gps_filter()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_last_lat      numeric;
  v_last_lng      numeric;
  v_last_updated  timestamptz;
  v_distance      numeric;
  v_time_diff     interval;
BEGIN
  -- Pronađi poslednju poziciju istog vozača
  SELECT lat, lng, updated_at 
  INTO v_last_lat, v_last_lng, v_last_updated
  FROM v3_vozac_lokacije
  WHERE vozac_id = NEW.vozac_id
  ORDER BY updated_at DESC 
  LIMIT 1;
  
  -- Ako je prva pozicija, automatski prihvati
  IF v_last_lat IS NULL THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;
  
  -- Izračunaj udaljenost između pozicija (Haversine formula)
  v_distance := 6371000 * acos(
    LEAST(1.0, GREATEST(-1.0,
      cos(radians(v_last_lat)) * cos(radians(NEW.lat)) *
      cos(radians(NEW.lng) - radians(v_last_lng)) +
      sin(radians(v_last_lat)) * sin(radians(NEW.lat))
    ))
  );
  
  -- Vreme od poslednjeg update-a
  v_time_diff := now() - v_last_updated;
  
  -- PAMETNA LOGIKA: Prihvati update samo ako:
  -- 1. Vozač se pomerio > 50 metara ILI
  -- 2. Prošlo je > 2 minuta od poslednjeg update-a (obavezni heartbeat)
  IF v_distance > 50 OR v_time_diff > interval '2 minutes' THEN
    NEW.updated_at := now();
    RETURN NEW;  -- Prihvati update
  ELSE
    -- Log odbačene pozive za debug (opcionalno)
    -- RAISE NOTICE 'GPS update odbačen: vozac=%, distance=%m, time=%', 
    --   NEW.vozac_id, round(v_distance), extract(seconds from v_time_diff);
    RETURN NULL; -- Odbaci update - vozač nije se dovoljno pomerio
  END IF;
END;
$$;

-- Aktiviraj trigger PRE upisa u tabelu
DROP TRIGGER IF EXISTS tr_v3_smart_gps_filter ON v3_vozac_lokacije;
CREATE TRIGGER tr_v3_smart_gps_filter
  BEFORE INSERT OR UPDATE ON v3_vozac_lokacije
  FOR EACH ROW EXECUTE FUNCTION fn_v3_smart_gps_filter();

-- ============================================================
-- 2. GPS VALIDACIJA TRIGGER
-- Automatska validacija i korekcija GPS koordinata
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_validate_gps_coordinates()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Proverava GPS koordinate za Srbiju (lat 42-46, lng 19-23)
  IF NEW.lat < 42 OR NEW.lat > 46 OR NEW.lng < 19 OR NEW.lng > 23 THEN
    -- Pokušaj da nađeš poslednju validnu poziciju istog vozača
    SELECT lat, lng INTO NEW.lat, NEW.lng
    FROM v3_vozac_lokacije 
    WHERE vozac_id = NEW.vozac_id 
      AND lat BETWEEN 42 AND 46 
      AND lng BETWEEN 19 AND 23
    ORDER BY updated_at DESC 
    LIMIT 1;
    
    -- Fallback na default koordinate ako nema validnih pozicija
    IF NEW.lat IS NULL OR NEW.lat < 42 OR NEW.lat > 46 THEN
      NEW.lat := CASE WHEN UPPER(NEW.grad) = 'BC' THEN 44.8972 ELSE 45.1167 END;
      NEW.lng := CASE WHEN UPPER(NEW.grad) = 'BC' THEN 21.4247 ELSE 21.3036 END;
    END IF;
  END IF;
  
  -- Validacija brzine (maksimalno 200 km/h)
  IF NEW.brzina IS NOT NULL AND NEW.brzina > 200 THEN
    NEW.brzina := NULL;
  END IF;
  
  -- Validacija bearing (0-360 stepeni)
  IF NEW.bearing IS NOT NULL AND (NEW.bearing < 0 OR NEW.bearing > 360) THEN
    NEW.bearing := NULL;
  END IF;
  
  RETURN NEW;
END;
$$;

-- Aktiviraj validaciju PRE smart filter-a
DROP TRIGGER IF EXISTS tr_v3_validate_gps ON v3_vozac_lokacije;
CREATE TRIGGER tr_v3_validate_gps
  BEFORE INSERT OR UPDATE ON v3_vozac_lokacije
  FOR EACH ROW EXECUTE FUNCTION fn_v3_validate_gps_coordinates();

-- ============================================================
-- 3. AUTOMATSKI GPS CLEANUP FUNKCIJE
-- Zamenjuje Timer cleanup logiku iz Dart koda
-- ============================================================

-- Funkcija za deaktivaciju starih vozača
CREATE OR REPLACE FUNCTION public.fn_v3_deactivate_stale_drivers()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_deactivated int;
BEGIN
  -- Deaktiviraj vozače koji nisu slali GPS > 3 minuta
  UPDATE v3_vozac_lokacije 
  SET aktivno = false 
  WHERE aktivno = true 
    AND updated_at < now() - interval '3 minutes';
  
  GET DIAGNOSTICS v_deactivated = ROW_COUNT;
  
  -- Log rezultat (opcionalno)
  IF v_deactivated > 0 THEN
    RAISE NOTICE 'Deaktivirano % vozača zbog neaktivnosti', v_deactivated;
  END IF;
END;
$$;

-- Funkcija za brisanje starih GPS pozicija (performanse)
CREATE OR REPLACE FUNCTION public.fn_v3_cleanup_old_gps_data()
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted int;
BEGIN
  -- Obriši GPS pozicije starije od 7 dana (čuva bazu kompaktnom)
  DELETE FROM v3_vozac_lokacije 
  WHERE updated_at < now() - interval '7 days';
  
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  
  -- Log rezultat (opcionalno)
  IF v_deleted > 0 THEN
    RAISE NOTICE 'Obrisano % starih GPS pozicija', v_deleted;
  END IF;
END;
$$;

-- ============================================================
-- 4. CRON JOBS - AUTOMATSKO POKRETANJE
-- Zamenjuje Timer logiku iz aplikacije
-- ============================================================

-- Ukloni postojeće cron job-ove ako postoje
SELECT cron.unschedule('v3-gps-deactivate')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-gps-deactivate'
);

SELECT cron.unschedule('v3-gps-cleanup')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-gps-cleanup'
);

-- Deaktivacija starih vozača - svakih 30 sekundi
SELECT cron.schedule(
  'v3-gps-deactivate',
  '*/30 * * * * *',  -- svakih 30 sekundi
  $$ SELECT public.fn_v3_deactivate_stale_drivers() $$
);

-- Cleanup starih podataka - jednom dnevno u 02:00
SELECT cron.schedule(
  'v3-gps-cleanup',
  '0 2 * * *',  -- svaki dan u 02:00
  $$ SELECT public.fn_v3_cleanup_old_gps_data() $$
);

-- ============================================================
-- 5. HELPER FUNKCIJE ZA MONITORING
-- ============================================================

-- Funkcija za statistike GPS trackinga
CREATE OR REPLACE FUNCTION public.fn_v3_gps_stats()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_aktivni_vozaci   int;
  v_ukupno_pozicija  int;
  v_danas_pozicija   int;
  v_prosek_pozicija  numeric;
BEGIN
  -- Broji aktivne vozače
  SELECT COUNT(*) INTO v_aktivni_vozaci
  FROM v3_vozac_lokacije 
  WHERE aktivno = true;
  
  -- Broji ukupne pozicije
  SELECT COUNT(*) INTO v_ukupno_pozicija
  FROM v3_vozac_lokacije;
  
  -- Broji danas pozicije  
  SELECT COUNT(*) INTO v_danas_pozicija
  FROM v3_vozac_lokacije
  WHERE DATE(updated_at) = CURRENT_DATE;
  
  -- Prosek pozicija po vozaču danas
  SELECT ROUND(v_danas_pozicija::numeric / NULLIF(v_aktivni_vozaci, 0), 1)
  INTO v_prosek_pozicija;
  
  RETURN jsonb_build_object(
    'aktivni_vozaci', v_aktivni_vozaci,
    'ukupno_pozicija', v_ukupno_pozicija, 
    'danas_pozicija', v_danas_pozicija,
    'prosek_po_vozacu', COALESCE(v_prosek_pozicija, 0),
    'timestamp', now()
  );
END;
$$;

-- ============================================================
-- DEPLOY NOTES:
-- 1. Pokrenuti ovaj fajl u Supabase SQL Editor
-- 2. Ukloniti Timer logiku iz V3VozacScreen.dart
-- 3. Zameniti sa Geolocator.getPositionStream()
-- 4. Testirati sa SELECT public.fn_v3_gps_stats();
-- ============================================================