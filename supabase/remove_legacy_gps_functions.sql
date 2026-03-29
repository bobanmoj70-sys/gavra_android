-- =====================================================
-- Remove legacy GPS SQL functions (targeted cleanup)
-- =====================================================
-- Funkcije za uklanjanje:
--  - public.fn_v3_validate_gps_coordinates
--  - public.fn_v3_smart_gps_filter
--  - public.fn_v3_calculate_putnici_eta
--  - public.fn_v3_auto_stop_gps_tracking
--
-- Skripta je idempotentna i bezbedna za ponavljanje.

BEGIN;

-- 1) Ukloni trigere koji direktno pozivaju ove funkcije (ako postoje)
DO $$
DECLARE
  trg RECORD;
BEGIN
  FOR trg IN
    SELECT
      n.nspname AS schema_name,
      c.relname AS table_name,
      t.tgname AS trigger_name
    FROM pg_trigger t
    JOIN pg_class c ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_proc p ON p.oid = t.tgfoid
    JOIN pg_namespace pn ON pn.oid = p.pronamespace
    WHERE NOT t.tgisinternal
      AND pn.nspname = 'public'
      AND p.proname IN (
        'fn_v3_validate_gps_coordinates',
        'fn_v3_smart_gps_filter',
        'fn_v3_calculate_putnici_eta',
        'fn_v3_auto_stop_gps_tracking'
      )
  LOOP
    EXECUTE format(
      'DROP TRIGGER IF EXISTS %I ON %I.%I;',
      trg.trigger_name,
      trg.schema_name,
      trg.table_name
    );
  END LOOP;
END $$;

-- 2) Ukloni sve overload-e navedenih funkcija (ako postoje)
DO $$
DECLARE
  fn RECORD;
BEGIN
  FOR fn IN
    SELECT
      n.nspname AS schema_name,
      p.proname AS function_name,
      pg_get_function_identity_arguments(p.oid) AS args
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'fn_v3_validate_gps_coordinates',
        'fn_v3_smart_gps_filter',
        'fn_v3_calculate_putnici_eta',
        'fn_v3_auto_stop_gps_tracking'
      )
  LOOP
    EXECUTE format(
      'DROP FUNCTION IF EXISTS %I.%I(%s) CASCADE;',
      fn.schema_name,
      fn.function_name,
      fn.args
    );
  END LOOP;
END $$;

COMMIT;

-- -----------------------------------------------------
-- Post-check (pokreni posle skripte)
-- -----------------------------------------------------
-- 1) Funkcije više ne postoje:
-- SELECT n.nspname, p.proname, pg_get_function_identity_arguments(p.oid) AS args
-- FROM pg_proc p
-- JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname='public'
--   AND p.proname IN (
--     'fn_v3_validate_gps_coordinates',
--     'fn_v3_smart_gps_filter',
--     'fn_v3_calculate_putnici_eta',
--     'fn_v3_auto_stop_gps_tracking'
--   )
-- ORDER BY p.proname;
--
-- 2) Triggeri više ne pozivaju ove funkcije:
-- SELECT c.relname, t.tgname, p.proname
-- FROM pg_trigger t
-- JOIN pg_class c ON c.oid = t.tgrelid
-- JOIN pg_proc p ON p.oid = t.tgfoid
-- JOIN pg_namespace n ON n.oid = c.relnamespace
-- JOIN pg_namespace pn ON pn.oid = p.pronamespace
-- WHERE NOT t.tgisinternal
--   AND n.nspname='public'
--   AND pn.nspname='public'
--   AND p.proname IN (
--     'fn_v3_validate_gps_coordinates',
--     'fn_v3_smart_gps_filter',
--     'fn_v3_calculate_putnici_eta',
--     'fn_v3_auto_stop_gps_tracking'
--   )
-- ORDER BY c.relname, t.tgname;
