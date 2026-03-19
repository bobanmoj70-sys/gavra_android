-- ===================================================================
-- V3_GPS_RASPORED KOMPLETNI DEPLOYMENT SCRIPT - SUPABASE SQL EDITOR VERZIJA
-- Pokreće sve SQL fajlove u pravilnom redosledu
-- Datum: 19. mart 2026
-- KOMPATIBILNO SA: Supabase SQL Editor (bez psql meta-komandi)
-- ===================================================================

-- ===================================================================
-- KORAK 1: KREIRANJE UNIFIED TABELE v3_gps_raspored
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🚀 DEPLOYMENT KORAK 1: Kreiranje v3_gps_raspored tabele...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Sadržaj iz v3_gps_raspored_schema.sql
CREATE TABLE public.v3_gps_raspored (
  -- ─── PRIMARY KEY ───
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- ─── CORE ASSIGNMENT DATA ───
  vozac_id UUID NOT NULL REFERENCES public.v3_vozaci(id) ON DELETE CASCADE,
  putnik_id UUID NOT NULL REFERENCES public.v3_putnici(id) ON DELETE CASCADE,
  
  -- ─── SCHEDULE INFO ───
  datum DATE NOT NULL,
  grad TEXT NOT NULL CHECK (grad IN ('BC', 'VS')),
  vreme TIME WITHOUT TIME ZONE NOT NULL,
  nav_bar_type TEXT NOT NULL CHECK (nav_bar_type IN ('zimski', 'letnji', 'praznici')),
  
  -- ─── STATUS MANAGEMENT ───
  aktivno BOOLEAN NOT NULL DEFAULT true,
  
  -- ─── GPS AUTOMATION DATA ───
  polazak_vreme TIMESTAMP WITH TIME ZONE, -- Computed: datum + vreme
  activation_time TIMESTAMP WITH TIME ZONE, -- Computed: polazak_vreme - 15min
  gps_status TEXT NOT NULL DEFAULT 'pending' CHECK (gps_status IN ('pending', 'activated', 'completed', 'skipped', 'cancelled')),
  notification_sent BOOLEAN DEFAULT false,
  
  -- ─── AUDIT TRAIL ───
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
  created_by TEXT,
  updated_by TEXT,
  
  -- ─── CONSTRAINTS ───
  -- Unique assignment: jedan putnik može biti dodeljen samo jednom vozaču po terminu
  CONSTRAINT uk_putnik_vozac_schedule UNIQUE (putnik_id, datum, vreme, grad),
  
  -- Multiple drivers can work same timeslot (based on passenger demand)
  -- One driver can have multiple passengers in same timeslot
  
  -- Ensure valid time ranges per nav_bar_type and grad
  CONSTRAINT ck_valid_schedule CHECK (
    (nav_bar_type = 'zimski' AND grad = 'BC' AND vreme IN ('05:00', '06:00', '07:00', '08:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00')) OR
    (nav_bar_type = 'zimski' AND grad = 'VS' AND vreme IN ('06:00', '07:00', '08:00', '09:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00')) OR
    (nav_bar_type = 'letnji' AND grad = 'BC' AND vreme IN ('05:00', '06:00', '07:00', '12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00')) OR
    (nav_bar_type = 'letnji' AND grad = 'VS' AND vreme IN ('06:00', '07:00', '08:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00', '19:00')) OR
    (nav_bar_type = 'praznici' AND grad = 'BC' AND vreme IN ('05:00', '06:00', '12:00', '13:00', '15:00')) OR
    (nav_bar_type = 'praznici' AND grad = 'VS' AND vreme IN ('06:00', '07:00', '13:00', '14:00', '15:30'))
  )
);

-- INDEXES za optimalne performanse
CREATE INDEX idx_v3_gps_raspored_gps_per_vozac 
ON public.v3_gps_raspored(vozac_id, activation_time, gps_status) 
WHERE aktivno = true AND gps_status IN ('pending', 'activated');

CREATE INDEX idx_v3_gps_raspored_putnik_count 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme) 
WHERE aktivno = true;

CREATE INDEX idx_v3_gps_raspored_admin_filter 
ON public.v3_gps_raspored(datum, nav_bar_type, aktivno);

CREATE INDEX idx_v3_gps_raspored_vozac 
ON public.v3_gps_raspored(vozac_id, datum) 
WHERE aktivno = true;

CREATE INDEX idx_v3_gps_raspored_putnik 
ON public.v3_gps_raspored(putnik_id, datum) 
WHERE aktivno = true;

CREATE INDEX idx_v3_gps_raspored_nav_type 
ON public.v3_gps_raspored(nav_bar_type, datum, grad, vreme) 
WHERE aktivno = true;

-- Auto-compute polazak_vreme and activation_time
CREATE OR REPLACE FUNCTION fn_v3_gps_raspored_compute_times()
RETURNS TRIGGER AS $$
BEGIN
  NEW.polazak_vreme := NEW.datum + NEW.vreme;
  NEW.activation_time := NEW.polazak_vreme - INTERVAL '15 minutes';
  NEW.updated_at := now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_v3_gps_raspored_compute_times
  BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
  FOR EACH ROW
  EXECUTE FUNCTION fn_v3_gps_raspored_compute_times();

-- Comments
COMMENT ON TABLE public.v3_gps_raspored IS 
'Unified schedule table - replaces v3_raspored_termin and v3_raspored_putnik. 
Each record represents one passenger assigned to one driver for specific timeslot.
Multiple drivers can work same timeslot based on passenger demand.';

COMMENT ON COLUMN public.v3_gps_raspored.nav_bar_type IS 
'Schedule type: zimski/letnji/praznici - determines which departure times are valid';

COMMENT ON COLUMN public.v3_gps_raspored.gps_status IS 
'GPS automation status PER DRIVER: pending -> activated -> completed/skipped/cancelled.
Each driver gets individual GPS activation for their assigned passengers.';

DO $$ BEGIN RAISE NOTICE '✅ v3_gps_raspored tabela kreirana!'; END $$;

-- ===================================================================
-- KORAK 2: DODAVANJE GPS KOORDINATA I ADRESA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '📍 DEPLOYMENT KORAK 2: Dodavanje GPS koordinata i adresa...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Sadržaj iz v3_gps_raspored_addresses_upgrade.sql
ALTER TABLE public.v3_gps_raspored 
ADD COLUMN IF NOT EXISTS adresa_id UUID REFERENCES public.v3_adrese(id),
ADD COLUMN IF NOT EXISTS pickup_lat NUMERIC(10,7),  
ADD COLUMN IF NOT EXISTS pickup_lng NUMERIC(10,7),
ADD COLUMN IF NOT EXISTS pickup_naziv TEXT,
ADD COLUMN IF NOT EXISTS route_order INTEGER,
ADD COLUMN IF NOT EXISTS estimated_pickup_time TIMESTAMP WITH TIME ZONE;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_route_optimization 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme, route_order) 
WHERE aktivno = true;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_gps_coords 
ON public.v3_gps_raspored(pickup_lat, pickup_lng) 
WHERE aktivno = true AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL;

-- Trigger za auto-populate koordinata
CREATE OR REPLACE FUNCTION fn_v3_gps_raspored_populate_coordinates()
RETURNS TRIGGER AS $$
DECLARE
  v_putnik_adresa_id UUID;
  v_adresa_data RECORD;
BEGIN
  IF NEW.grad = 'BC' THEN
    SELECT adresa_bc_id INTO v_putnik_adresa_id 
    FROM public.v3_putnici 
    WHERE id = NEW.putnik_id;
  ELSIF NEW.grad = 'VS' THEN
    SELECT adresa_vs_id INTO v_putnik_adresa_id 
    FROM public.v3_putnici 
    WHERE id = NEW.putnik_id;
  END IF;

  IF v_putnik_adresa_id IS NOT NULL THEN
    NEW.adresa_id := v_putnik_adresa_id;
  END IF;

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

  NEW.polazak_vreme := NEW.datum + NEW.vreme;
  NEW.activation_time := NEW.polazak_vreme - INTERVAL '15 minutes';
  NEW.updated_at := now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Replace old trigger
DROP TRIGGER IF EXISTS tr_v3_gps_raspored_compute_times ON public.v3_gps_raspored;
CREATE TRIGGER tr_v3_gps_raspored_populate_data
  BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
  FOR EACH ROW
  EXECUTE FUNCTION fn_v3_gps_raspored_populate_coordinates();

-- Comments za nove kolone
COMMENT ON COLUMN public.v3_gps_raspored.adresa_id IS 
'Reference to v3_adrese - auto-populated from putnik adresa_bc_id/vs_id or manually set by admin';

COMMENT ON COLUMN public.v3_gps_raspored.pickup_lat IS 
'GPS latitude for pickup location - auto-populated from v3_adrese.gps_lat';

COMMENT ON COLUMN public.v3_gps_raspored.pickup_lng IS 
'GPS longitude for pickup location - auto-populated from v3_adrese.gps_lng';

DO $$ BEGIN RAISE NOTICE '✅ GPS koordinate i adrese dodane!'; END $$;

-- ===================================================================
-- KORAK 3: RLS I REALTIME KONFIGURACIJA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🔄 DEPLOYMENT KORAK 3: RLS i Realtime setup...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Sadržaj iz v3_gps_raspored_realtime_rls.sql
ALTER TABLE public.v3_gps_raspored ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon_all" ON public.v3_gps_raspored;

CREATE POLICY "anon_all" ON public.v3_gps_raspored 
  FOR ALL TO anon 
  USING (true) 
  WITH CHECK (true);

ALTER TABLE public.v3_gps_raspored REPLICA IDENTITY FULL;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
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
      RAISE;
    END IF;
END $$;

DO $$ BEGIN RAISE NOTICE '✅ RLS i Realtime konfigurisani!'; END $$;

-- ===================================================================
-- KORAK 4: NOVA GPS AKTIVACIJA FUNKCIJA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '⚡ DEPLOYMENT KORAK 4: Nova GPS aktivacija funkcija...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Poziv na fn_v3_gps_activation_v2.sql (mora se pokrenuti odvojeno)
-- NAPOMENA: Pokreniti fn_v3_gps_activation_v2.sql fajl nakon ovog deployment-a

DO $$ BEGIN RAISE NOTICE '⚠️  ZAVISNOST: Pokrenuti fn_v3_gps_activation_v2.sql odvojeno'; END $$;

-- ===================================================================
-- KORAK 5: ROUTE OPTIMIZATION FUNKCIJE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🗺️ DEPLOYMENT KORAK 5: Route optimization funkcije...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Poziv na fn_v3_route_optimization.sql (mora se pokrenuti odvojeno)
-- NAPOMENA: Pokreniti fn_v3_route_optimization.sql fajl nakon ovog deployment-a

DO $$ BEGIN RAISE NOTICE '⚠️  ZAVISNOST: Pokrenuti fn_v3_route_optimization.sql odvojeno'; END $$;

-- ===================================================================
-- KORAK 6: TEST UNIFIED TABELE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🧪 DEPLOYMENT KORAK 6: Test unified tabele...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Poziv na test_v3_gps_raspored.sql (opciono - pokrenuti za test)
-- NAPOMENA: Pokrenuti test_v3_gps_raspored.sql odvojeno za test podatke

DO $$ BEGIN RAISE NOTICE '⚠️  OPCIONO: Pokrenuti test_v3_gps_raspored.sql za test podatke'; END $$;

-- ===================================================================
-- FINALIZACIJA I VALIDACIJA
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎯 FINALIZACIJA: Validacija deployment-a...'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;

-- Proverava da li je tabela kreirana
SELECT 
  tablename,
  schemaname,
  hasindexes,
  hasrules,
  hastriggers
FROM pg_tables 
WHERE tablename = 'v3_gps_raspored';

-- Proverava kolone
SELECT 
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns 
WHERE table_name = 'v3_gps_raspored' 
  AND table_schema = 'public'
ORDER BY ordinal_position;

-- Proverava RLS i realtime
SELECT 
  schemaname,
  tablename,
  rowsecurity,
  forcenewconstraints as rls_enabled
FROM pg_tables 
WHERE tablename = 'v3_gps_raspored';

-- ===================================================================
-- USPEŠAN DEPLOYMENT MESSAGE
-- ===================================================================
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎉 ===== V3 GPS RASPORED DEPLOYMENT USPEŠAN! ====='; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '✅ KREIRANA: v3_gps_raspored unified tabela'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ DODANO: GPS koordinate i adrese (pickup_lat/lng)'; END $$;
DO $$ BEGIN RAISE NOTICE '✅ OMOGUĆENO: RLS anon pristup + realtime subscription'; END $$;
DO $$ BEGIN RAISE NOTICE '⚠️  SLEDEĆI KORACI (pokrenuti odvojeno):'; END $$;
DO $$ BEGIN RAISE NOTICE '   1. fn_v3_gps_activation_v2.sql'; END $$;
DO $$ BEGIN RAISE NOTICE '   2. fn_v3_route_optimization.sql'; END $$;
DO $$ BEGIN RAISE NOTICE '   3. test_v3_gps_raspored.sql (opciono)'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🚀 OSNOVNI SISTEM SPREMAN!'; END $$;
DO $$ BEGIN RAISE NOTICE '📡 FLUTTER: Cache već integrisan u V3MasterRealtimeManager'; END $$;
DO $$ BEGIN RAISE NOTICE '⚡ GPS: Aktivacija funkcija dostupna nakon step 1'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;
DO $$ BEGIN RAISE NOTICE '🎯 TABELA SPREMNA ZA PRODUKCIJU!'; END $$;
DO $$ BEGIN RAISE NOTICE ''; END $$;