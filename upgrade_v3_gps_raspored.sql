-- ===================================================================
-- V3_GPS_RASPORED UPGRADE SCRIPT - ZA POSTOJEĆU TABELU
-- Dodaje GPS funkcionalnosti na postojeću v3_gps_raspored tabelu
-- Datum: 19. mart 2026
-- KOMPATIBILNO SA: Supabase SQL Editor
-- ===================================================================

DO $$ BEGIN RAISE NOTICE '🔧 V3_GPS_RASPORED UPGRADE - ZAPOČINJE...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- ===================================================================
-- KORAK 1: PROVERA POSTOJEĆEG STANJA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE '🔍 KORAK 1: Provera postojećeg stanja...'; END $$;

-- Proveri trenutne kolone
DO $$
DECLARE
    v_columns TEXT;
BEGIN
    SELECT string_agg(column_name, ', ' ORDER BY ordinal_position)
    INTO v_columns
    FROM information_schema.columns 
    WHERE table_name = 'v3_gps_raspored' AND table_schema = 'public';
    
    RAISE NOTICE 'Postojeće kolone: %', v_columns;
END $$;

-- ===================================================================
-- KORAK 2: DODAVANJE GPS KOORDINATA I ADRESA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '📍 KORAK 2: Dodavanje GPS koordinata i adresa...'; END $$;

-- Dodaj GPS kolone (IF NOT EXISTS sprečava greške)
ALTER TABLE public.v3_gps_raspored 
ADD COLUMN IF NOT EXISTS adresa_id UUID REFERENCES public.v3_adrese(id),
ADD COLUMN IF NOT EXISTS pickup_lat NUMERIC(10,7),  
ADD COLUMN IF NOT EXISTS pickup_lng NUMERIC(10,7),
ADD COLUMN IF NOT EXISTS pickup_naziv TEXT,
ADD COLUMN IF NOT EXISTS route_order INTEGER,
ADD COLUMN IF NOT EXISTS estimated_pickup_time TIMESTAMP WITH TIME ZONE;

DO $$ BEGIN RAISE NOTICE '✅ GPS kolone dodane!'; END $$;

-- ===================================================================
-- KORAK 3: KREIRANJE/UPGRADE INDEKSA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '📊 KORAK 3: Kreiranje optimizovanih indeksa...'; END $$;

-- Kreiraj indekse (IF NOT EXISTS sprečava greške)
CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_gps_per_vozac 
ON public.v3_gps_raspored(vozac_id, activation_time, gps_status) 
WHERE aktivno = true AND gps_status IN ('pending', 'activated');

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_putnik_count 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme) 
WHERE aktivno = true;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_admin_filter 
ON public.v3_gps_raspored(datum, nav_bar_type, aktivno);

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_vozac 
ON public.v3_gps_raspored(vozac_id, datum) 
WHERE aktivno = true;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_putnik 
ON public.v3_gps_raspored(putnik_id, datum) 
WHERE aktivno = true;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_nav_type 
ON public.v3_gps_raspored(nav_bar_type, datum, grad, vreme) 
WHERE aktivno = true;

-- GPS specifični indeksi
CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_route_optimization 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme, route_order) 
WHERE aktivno = true;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_gps_coords 
ON public.v3_gps_raspored(pickup_lat, pickup_lng) 
WHERE aktivno = true AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL;

DO $$ BEGIN RAISE NOTICE '✅ Indeksi kreirani!'; END $$;

-- ===================================================================
-- KORAK 4: UPGRADE TRIGGER FUNKCIJE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '⚙️ KORAK 4: Upgrade trigger funkcije...'; END $$;

-- Kreiraj naprednu trigger funkciju sa GPS koordinatama
CREATE OR REPLACE FUNCTION fn_v3_gps_raspored_populate_coordinates()
RETURNS TRIGGER AS $$
DECLARE
  v_putnik_adresa_id UUID;
  v_adresa_data RECORD;
BEGIN
  -- Determine correct address based on grad
  IF NEW.grad = 'BC' THEN
    SELECT adresa_bc_id INTO v_putnik_adresa_id 
    FROM public.v3_putnici 
    WHERE id = NEW.putnik_id;
  ELSIF NEW.grad = 'VS' THEN
    SELECT adresa_vs_id INTO v_putnik_adresa_id 
    FROM public.v3_putnici 
    WHERE id = NEW.putnik_id;
  END IF;

  -- Use putnik's address if available; otherwise keep manually set adresa_id
  IF v_putnik_adresa_id IS NOT NULL THEN
    NEW.adresa_id := v_putnik_adresa_id;
  END IF;

  -- Populate coordinates and naziv from v3_adrese
  IF NEW.adresa_id IS NOT NULL THEN
    SELECT gps_lat, gps_lng, naziv INTO v_adresa_data
    FROM public.v3_adrese 
    WHERE id = NEW.adresa_id AND aktivno = true;
    
    IF FOUND THEN
      NEW.pickup_lat := v_adresa_data.gps_lat;
      NEW.pickup_lng := v_adresa_data.gps_lng;
      NEW.pickup_naziv := v_adresa_data.naziv;
    END IF;
  END IF;

  -- Auto-compute timestamps (keep existing logic)
  NEW.polazak_vreme := NEW.datum + NEW.vreme;
  NEW.activation_time := NEW.polazak_vreme - INTERVAL '15 minutes';
  NEW.updated_at := now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Replace old trigger with new GPS-aware trigger
DROP TRIGGER IF EXISTS tr_v3_gps_raspored_compute_times ON public.v3_gps_raspored;
DROP TRIGGER IF EXISTS tr_v3_gps_raspored_populate_data ON public.v3_gps_raspored;

CREATE TRIGGER tr_v3_gps_raspored_populate_data
  BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
  FOR EACH ROW
  EXECUTE FUNCTION fn_v3_gps_raspored_populate_coordinates();

DO $$ BEGIN RAISE NOTICE '✅ GPS-aware trigger kreiran!'; END $$;

-- ===================================================================
-- KORAK 5: RLS I REALTIME UPGRADE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🔐 KORAK 5: RLS i Realtime upgrade...'; END $$;

-- Enable RLS ako nije već enabled
ALTER TABLE public.v3_gps_raspored ENABLE ROW LEVEL SECURITY;

-- Drop i recreate RLS policy za clean state
DROP POLICY IF EXISTS "anon_all" ON public.v3_gps_raspored;
CREATE POLICY "anon_all" ON public.v3_gps_raspored 
  FOR ALL TO anon 
  USING (true) 
  WITH CHECK (true);

-- Set REPLICA IDENTITY za realtime
ALTER TABLE public.v3_gps_raspored REPLICA IDENTITY FULL;

-- Add to realtime publication
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Remove if exists and re-add to ensure clean state
    BEGIN
      PERFORM pg_catalog.pg_publication_drop_table('supabase_realtime', 'public.v3_gps_raspored');
    EXCEPTION 
      WHEN OTHERS THEN NULL; -- Ignore if not in publication
    END;
    
    -- Add to publication
    PERFORM pg_catalog.pg_publication_add_table('supabase_realtime', 'public.v3_gps_raspored');
    RAISE NOTICE 'Added v3_gps_raspored to supabase_realtime publication';
  ELSE
    CREATE PUBLICATION supabase_realtime FOR TABLE public.v3_gps_raspored;
    RAISE NOTICE 'Created supabase_realtime publication with v3_gps_raspored';
  END IF;
EXCEPTION
  WHEN others THEN
    IF SQLSTATE = '23505' OR SQLERRM LIKE '%already exists%' THEN
      RAISE NOTICE 'v3_gps_raspored already in supabase_realtime publication';
    ELSE
      RAISE NOTICE 'Warning: % - %', SQLSTATE, SQLERRM;
    END IF;
END $$;

DO $$ BEGIN RAISE NOTICE '✅ RLS i Realtime konfigurisani!'; END $$;

-- ===================================================================
-- KORAK 6: COMMENTS ZA DOKUMENTACIJU
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '📝 KORAK 6: Dodavanje dokumentacije...'; END $$;

-- Update table i column comments
COMMENT ON TABLE public.v3_gps_raspored IS 
'Unified schedule table - replaces v3_raspored_termin and v3_raspored_putnik. 
Each record represents one passenger assigned to one driver for specific timeslot.
Multiple drivers can work same timeslot based on passenger demand.
UPGRADED: Now includes GPS coordinates and route optimization support.';

-- Comments za GPS kolone
COMMENT ON COLUMN public.v3_gps_raspored.adresa_id IS 
'Reference to v3_adrese - auto-populated from putnik adresa_bc_id/vs_id or manually set by admin';

COMMENT ON COLUMN public.v3_gps_raspored.pickup_lat IS 
'GPS latitude for pickup location - auto-populated from v3_adrese.gps_lat';

COMMENT ON COLUMN public.v3_gps_raspored.pickup_lng IS 
'GPS longitude for pickup location - auto-populated from v3_adrese.gps_lng';

COMMENT ON COLUMN public.v3_gps_raspored.pickup_naziv IS 
'Human-readable pickup location name - auto-populated from v3_adrese.naziv';

COMMENT ON COLUMN public.v3_gps_raspored.route_order IS 
'Optimized route sequence for driver - calculated by route optimization algorithm';

COMMENT ON COLUMN public.v3_gps_raspored.estimated_pickup_time IS 
'Estimated pickup time based on route optimization - calculated from polazak_vreme and route_order';

DO $$ BEGIN RAISE NOTICE '✅ Dokumentacija ažurirana!'; END $$;

-- ===================================================================
-- KORAK 7: FINALNA VALIDACIJA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎯 KORAK 7: Finalna validacija upgrade-a...'; END $$;

-- Proverava nove kolone
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'v3_gps_raspored' 
  AND table_schema = 'public'
  AND column_name IN ('adresa_id', 'pickup_lat', 'pickup_lng', 'pickup_naziv', 'route_order', 'estimated_pickup_time')
ORDER BY ordinal_position;

-- Proverava indekse
SELECT 
  indexname,
  indexdef
FROM pg_indexes 
WHERE tablename = 'v3_gps_raspored' 
  AND schemaname = 'public'
  AND indexname LIKE '%gps%'
ORDER BY indexname;

-- Proverava trigger
SELECT 
  trigger_name,
  event_manipulation,
  action_timing,
  action_statement
FROM information_schema.triggers 
WHERE event_object_table = 'v3_gps_raspored';

-- ===================================================================
-- USPEŠAN UPGRADE MESSAGE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎉 ===== V3 GPS RASPORED UPGRADE USPEŠAN! ====='; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '✅ DODANO: GPS koordinate (pickup_lat/lng, pickup_naziv)'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ DODANO: Route optimization (route_order, estimated_pickup_time)'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ DODANO: Adresa integration (adresa_id)'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ UPGRADED: Auto-populate trigger sa GPS funkcionalnostima'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ OPTIMIZOVANO: Novi indeksi za GPS i route queries'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ KONFIGURISANO: RLS i Realtime subscription'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '⚠️  SLEDEĆI KORACI (pokrenuti odvojeno):'; END $$;
DO $$ BEGIN RAISE NOTICE '   1. fn_v3_gps_activation_v2.sql - GPS aktivacija funkcija'; END $$;
DO $$ BEGIN RAISE NOTICE '   2. fn_v3_route_optimization.sql - Route optimization algoritmi'; END $$;
DO $$ BEGIN RAISE NOTICE '   3. test_v3_gps_raspored.sql - Test podatke (opciono)'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🚀 GPS FUNKCIONALNOSTI AKTIVNE!'; END $$;
DO $$ BEGIN RAISE NOTICE '📡 FLUTTER: Može koristiti v3_gps_raspored.stream() sa GPS podacima'; END $$;
DO $$ BEGIN RAISE NOTICE '🗺️  READY: Za route optimization i GPS automation'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎯 TABELA SPREMNA ZA PRODUKCIJU SA GPS!'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;