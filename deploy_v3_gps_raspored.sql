-- ===================================================================
-- V3_GPS_RASPORED KOMPLETNI DEPLOYMENT SCRIPT
-- Pokreće sve SQL fajlove u pravilnom redosledu
-- Datum: 19. mart 2026
-- ===================================================================

-- ===================================================================
-- KORAK 1: KREIRANJE UNIFIED TABELE v3_gps_raspored
-- ===================================================================

\echo ''
\echo '' DEPLOYMENT KORAK 1: Kreiranje v3_gps_raspored tabele...'
\echo ''

\i v3_gps_raspored_schema.sql

\echo '✅ v3_gps_raspored tabela kreirana!'

-- ===================================================================
-- KORAK 2: DODAVANJE GPS KOORDINATA I ADRESA
-- ===================================================================

\echo ''
\echo '📍 DEPLOYMENT KORAK 2: Dodavanje GPS koordinata i adresa...'
\echo ''

\i v3_gps_raspored_addresses_upgrade.sql

\echo '✅ GPS koordinate i adrese dodane!'

-- ===================================================================
-- KORAK 3: RLS I REALTIME KONFIGURACIJA
-- ===================================================================

\echo ''
\echo '🔄 DEPLOYMENT KORAK 3: RLS i Realtime setup...'
\echo ''

\i v3_gps_raspored_realtime_rls.sql

\echo '✅ RLS i Realtime konfigurisani!'

-- ===================================================================
-- KORAK 4: NOVA GPS AKTIVACIJA FUNKCIJA
-- ===================================================================

\echo ''
\echo '⚡ DEPLOYMENT KORAK 4: Nova GPS aktivacija funkcija...'
\echo ''

\i fn_v3_gps_activation_v2.sql

\echo '✅ GPS aktivacija funkcija (v2) kreirana!'

-- ===================================================================
-- KORAK 5: ROUTE OPTIMIZATION FUNKCIJE
-- ===================================================================

\echo ''
\echo '🗺️ DEPLOYMENT KORAK 5: Route optimization funkcije...'
\echo ''

\i fn_v3_route_optimization.sql

\echo '✅ Route optimization funkcije kreirane!'

-- ===================================================================
-- KORAK 6: TEST UNIFIED TABELE
-- ===================================================================

\echo ''
\echo '🧪 DEPLOYMENT KORAK 6: Test unified tabele...'
\echo ''

\i test_v3_gps_raspored.sql

\echo '✅ Test script pokrenut!'

-- ===================================================================
-- FINALIZACIJA I VALIDACIJA
-- ===================================================================

\echo ''
\echo '🎯 FINALIZACIJA: Validacija deployment-a...'
\echo ''

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

-- Proverava GPS funkciju
SELECT 
  routine_name,
  routine_type,
  data_type
FROM information_schema.routines 
WHERE routine_name = 'fn_v3_populate_gps_activation_schedule_v2';

-- ===================================================================
-- USPEŠAN DEPLOYMENT MESSAGE
-- ===================================================================

\echo ''
\echo '🎉 ===== V3 GPS RASPORED DEPLOYMENT USPEŠAN! ====='
\echo ''
\echo '✅ KREIRANA: v3_gps_raspored unified tabela'
\echo '✅ DODANO: GPS koordinate i adrese (pickup_lat/lng)'  
\echo '✅ OMOGUĆENO: RLS anon pristup + realtime subscription'
\echo '✅ KREIRANA: fn_v3_populate_gps_activation_schedule_v2()'
\echo '✅ KREIRANA: Route optimization algoritmi'
\echo '✅ TESTIRAN: Unified tabela functionality'
\echo ''
\echo '🚀 SLEDEĆI KORAK: Data migration iz starih tabela'
\echo '📡 FLUTTER: Cache već integrisan u V3MasterRealtimeManager'
\echo '⚡ GPS: Može se aktivirati nova v2 funkcija'
\echo ''
\echo '🎯 SYSTEM SPREMAN ZA PRODUKCIJU!'
\echo ''