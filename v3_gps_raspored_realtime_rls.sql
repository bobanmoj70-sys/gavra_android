-- ===================================================================
-- REALTIME i RLS KONFIGURACIJA za v3_gps_raspored
-- Uključuje anonymous pristup i live subscription support
-- ===================================================================

-- 1. ENABLE ROW LEVEL SECURITY
ALTER TABLE public.v3_gps_raspored ENABLE ROW LEVEL SECURITY;

-- 2. DROP postojeće RLS polise
DROP POLICY IF EXISTS "anon_all" ON public.v3_gps_raspored;

-- 3. KREIRAJ anon RLS policy (anonymous full access)
CREATE POLICY "anon_all" ON public.v3_gps_raspored 
  FOR ALL TO anon 
  USING (true) 
  WITH CHECK (true);

-- 4. REPLICA IDENTITY za realtime
ALTER TABLE public.v3_gps_raspored REPLICA IDENTITY FULL;

-- 5. DODAVANJE u supabase_realtime publication
DO $$
BEGIN
  -- Proverava da li publication postoji
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- Dodaje tabelu u publication
    PERFORM pg_catalog.pg_publication_add_table('supabase_realtime', 'public.v3_gps_raspored');
    RAISE NOTICE 'Added v3_gps_raspored to supabase_realtime publication';
  ELSE
    -- Kreira publication sa tabelom
    CREATE PUBLICATION supabase_realtime FOR TABLE public.v3_gps_raspored;
    RAISE NOTICE 'Created supabase_realtime publication with v3_gps_raspored';
  END IF;
EXCEPTION
  WHEN others THEN
    -- Ako tabela već postoji u publication, ignoriši grešku
    IF SQLSTATE = '23505' OR SQLERRM LIKE '%already exists%' THEN
      RAISE NOTICE 'v3_gps_raspored already in supabase_realtime publication';
    ELSE
      RAISE;
    END IF;
END $$;

-- ===================================================================
-- VERIFIKACIJA SETUP-a
-- ===================================================================

-- Proverava RLS status
SELECT 
  schemaname,
  tablename,
  rowsecurity,
  forcenewconstraints as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename = 'v3_gps_raspored';

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
  AND tablename = 'v3_gps_raspored';

-- Proverava realtime publication
SELECT 
  p.pubname,
  n.nspname as schema_name,
  c.relname as table_name,
  p.pubinsert,
  p.pubupdate,
  p.pubdelete
FROM pg_publication p
JOIN pg_publication_rel pr ON p.oid = pr.prpubid
JOIN pg_class c ON pr.prrelid = c.oid
JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE p.pubname = 'supabase_realtime'
  AND n.nspname = 'public'
  AND c.relname = 'v3_gps_raspored';

-- ===================================================================
-- USPEŠAN SETUP MESSAGE
-- ===================================================================

DO $$
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '✅ v3_gps_raspored REALTIME & RLS SETUP COMPLETE!';
  RAISE NOTICE '';
  RAISE NOTICE '📍 RLS: Enabled sa anon full access';
  RAISE NOTICE '🔄 REALTIME: Dodano u supabase_realtime publication';  
  RAISE NOTICE '📡 REPLICA IDENTITY: FULL za live updates';
  RAISE NOTICE '';
  RAISE NOTICE '🚀 Flutter app može sada da koristi:';
  RAISE NOTICE '   supabase.from("v3_gps_raspored").stream()';
  RAISE NOTICE '';
END $$;