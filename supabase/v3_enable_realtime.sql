-- ============================================================
-- OMOGUĆAVANJE REALTIME-a ZA V3 TABELE
-- Anonymous (anon) pristup i realtime replication
-- ============================================================

-- Prvo proveriti da li su tabele kreirane
-- SELECT table_name FROM information_schema.tables 
-- WHERE table_schema = 'public' AND table_name LIKE 'v3_%';

-- ============================================================
-- 1. RLS (ROW LEVEL SECURITY) SA ANON PRISTUPOM
-- ============================================================

DO $$
DECLARE
  v3_tables text[] := ARRAY[
    'v3_adrese',
    'v3_vozaci', 
    'v3_vozila',
    'v3_putnici',
    'v3_zahtevi',
    'v3_pumpa_stanje',
    'v3_pumpa_rezervoar',
    'v3_raspored_termin',
    'v3_raspored_putnik',
    'v3_vozac_lokacije',
    'v3_troskovi',
    'v3_finansije_stanje',
    'v3_pin_zahtevi',
    'v3_operativna_nedelja',
    'v3_kapacitet_slots',
    'v3_app_settings',
    'v3_gps_activation_schedule'
  ];
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY v3_tables
  LOOP
    -- Proverava da li tabela postoji
    IF EXISTS (SELECT 1 FROM information_schema.tables 
               WHERE table_schema = 'public' AND table_name = table_name) THEN
      
      -- Uključuje RLS
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
      
      -- Kreira anon policy (anonymous full access)
      EXECUTE format('DROP POLICY IF EXISTS "anon_all" ON public.%I', table_name);
      EXECUTE format(
        'CREATE POLICY "anon_all" ON public.%I FOR ALL TO anon USING (true) WITH CHECK (true)',
        table_name
      );
      
      RAISE NOTICE 'RLS enabled for table: %', table_name;
    ELSE
      RAISE NOTICE 'Table does not exist: %', table_name;
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 2. REPLICA IDENTITY ZA REALTIME
-- ============================================================

DO $$
DECLARE
  v3_tables text[] := ARRAY[
    'v3_adrese',
    'v3_vozaci', 
    'v3_vozila',
    'v3_putnici',
    'v3_zahtevi',
    'v3_pumpa_stanje',
    'v3_pumpa_rezervoar',
    'v3_raspored_termin',
    'v3_raspored_putnik',
    'v3_vozac_lokacije',
    'v3_troskovi',
    'v3_finansije_stanje',
    'v3_pin_zahtevi',
    'v3_operativna_nedelja',
    'v3_kapacitet_slots',
    'v3_app_settings',
    'v3_gps_activation_schedule'
  ];
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY v3_tables
  LOOP
    -- Proverava da li tabela postoji
    IF EXISTS (SELECT 1 FROM information_schema.tables 
               WHERE table_schema = 'public' AND table_name = table_name) THEN
      
      -- Postavlja REPLICA IDENTITY za realtime
      EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY FULL', table_name);
      
      RAISE NOTICE 'REPLICA IDENTITY set for table: %', table_name;
    ELSE
      RAISE NOTICE 'Table does not exist: %', table_name;
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 3. SUPABASE REALTIME PUBLICATION
-- Dodaje tabele u realtime publication za live updates
-- ============================================================

DO $$
DECLARE
  v3_tables text[] := ARRAY[
    'v3_adrese',
    'v3_vozaci', 
    'v3_vozila',
    'v3_putnici',
    'v3_zahtevi',
    'v3_pumpa_stanje',
    'v3_pumpa_rezervoar',
    'v3_raspored_termin',
    'v3_raspored_putnik',
    'v3_vozac_lokacije',
    'v3_troskovi',
    'v3_finansije_stanje',
    'v3_pin_zahtevi',
    'v3_operativna_nedelja',
    'v3_kapacitet_slots',
    'v3_app_settings',
    'v3_gps_activation_schedule'
  ];
  table_name text;
  pub_exists boolean;
BEGIN
  -- Proverava da li publication 'supabase_realtime' postoji
  SELECT EXISTS (
    SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime'
  ) INTO pub_exists;
  
  IF NOT pub_exists THEN
    -- Kreira publication ako ne postoji
    CREATE PUBLICATION supabase_realtime;
    RAISE NOTICE 'Created publication: supabase_realtime';
  END IF;
  
  -- Dodaje svaku tabelu u publication
  FOREACH table_name IN ARRAY v3_tables
  LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables 
               WHERE table_schema = 'public' AND table_name = table_name) THEN
      
      -- Dodaje tabelu u realtime publication
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', table_name);
      
      RAISE NOTICE 'Added to realtime publication: %', table_name;
    ELSE
      RAISE NOTICE 'Table does not exist for publication: %', table_name);
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 4. VERIFIKACIJA - PROVERA STANJA
-- ============================================================

-- Proverava RLS status
SELECT 
  schemaname,
  tablename,
  rowsecurity as rls_enabled,
  hasinserts,
  hasselects,
  hasupdates,
  hasdeletes
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename LIKE 'v3_%'
ORDER BY tablename;

-- Proverava RLS policies
SELECT 
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies 
WHERE schemaname = 'public' 
  AND tablename LIKE 'v3_%'
ORDER BY tablename, policyname;

-- Proverava realtime publication
SELECT 
  pubname,
  puballtables,
  pubinsert,
  pubupdate,
  pubdelete,
  pubtruncate
FROM pg_publication 
WHERE pubname = 'supabase_realtime';

-- Proverava koje tabele su u realtime publication
SELECT 
  p.pubname,
  n.nspname as schema_name,
  c.relname as table_name
FROM pg_publication p
JOIN pg_publication_rel pr ON p.oid = pr.prpubid
JOIN pg_class c ON pr.prrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE p.pubname = 'supabase_realtime'
  AND n.nspname = 'public'
  AND c.relname LIKE 'v3_%'
ORDER BY table_name;

-- ============================================================
-- GOTOVO! 
-- ============================================================
-- Nakon pokretanja ovog skripte:
-- 1. Sve v3_ tabele imaju RLS sa anon pristupom
-- 2. Sve v3_ tabele imaju REPLICA IDENTITY FULL
-- 3. Sve v3_ tabele su u supabase_realtime publication
-- 4. Flutter app može da koristi realtime subscriptions
-- ============================================================