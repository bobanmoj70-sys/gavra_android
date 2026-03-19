-- ============================================================
-- V3 GPS AUTO-ACTIVATION SISTEM - SQL TABELA & FUNCTIONS
-- Automatski pokreće GPS tracking 15 minuta pre polaska
-- Pošalje push notifikacije vozaču i putnicima
-- ============================================================

-- ============================================================
-- 1. GLAVNA TABELA: v3_gps_activation_schedule
-- Sadrži raspored GPS aktivacije za sve termine
-- OPTIMIZED: Usklađeno sa v3_gps_raspored arhitekturom
-- ============================================================
CREATE TABLE IF NOT EXISTS public.v3_gps_activation_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vozac_id UUID NOT NULL REFERENCES public.v3_vozaci(id) ON DELETE CASCADE,
  datum DATE NOT NULL,
  vreme TIME NOT NULL,                        -- Standardizovano: vreme umesto polazak_vreme
  grad TEXT NOT NULL CHECK (grad IN ('BC', 'VS')),  -- Standardizovano: grad umesto polazak_mesto
  activation_time TIMESTAMPTZ NOT NULL,        -- GPS aktivacija (15 min pre)
  polazak_vreme TIMESTAMPTZ NOT NULL,          -- Puno vreme polaska
  putnici_count INTEGER DEFAULT 0,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'activated', 'completed', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Optimized unique constraint sa standardizovanim imenima
  UNIQUE(vozac_id, datum, vreme, grad)
);

-- Performance indexes - optimized for new schema
CREATE INDEX IF NOT EXISTS idx_v3_gps_activation_status_pending 
  ON v3_gps_activation_schedule(status) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_v3_gps_activation_timing 
  ON v3_gps_activation_schedule(activation_time, status);
CREATE INDEX IF NOT EXISTS idx_v3_gps_activation_vozac_datum 
  ON v3_gps_activation_schedule(vozac_id, datum);
CREATE INDEX IF NOT EXISTS idx_v3_gps_activation_putnik_count 
  ON v3_gps_activation_schedule(putnici_count) WHERE putnici_count > 0;

-- ============================================================
-- 2. FUNKCIJA: fn_v3_populate_gps_activation_schedule - OPTIMIZED
-- Automatska popolnava tabelu na osnovu v3_gps_raspored
-- OPTIMIZED: Koristi novu putnik_id arhitekturu za 100% tačnost
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_populate_gps_activation_schedule()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_termin        record;
  v_putnici_count integer;
  v_datum         date;
  v_polazak_ts    timestamptz;
  v_aktivacija_ts timestamptz;
  v_inserted      integer := 0;
  v_updated       integer := 0;
  v_current_ts    timestamptz := now();
  v_cleanup_count integer := 0;
BEGIN
  -- Popuni za danas, sutra + prekosutra (3 dana unapred)
  FOR i IN 0..2 LOOP
    v_datum := CURRENT_DATE + (i || ' days')::interval;
    
    -- OPTIMIZED: Prolazi kroz SVE vozače koji imaju termine (iz oba izvora)
    FOR v_termin IN 
      WITH svi_vozac_termini AS (
        -- Vozači iz v3_gps_raspored (unified assignments)
        SELECT DISTINCT rt.vozac_id, rt.vreme, rt.grad
        FROM public.v3_gps_raspored rt
        WHERE rt.datum = v_datum AND rt.aktivno = true
      )
      SELECT vozac_id, vreme, grad FROM svi_vozac_termini
      ORDER BY vreme, grad, vozac_id  -- Deterministic ordering
    LOOP
      -- Izračunaj timestamp-ove
      v_polazak_ts := v_datum + v_termin.vreme;
      v_aktivacija_ts := v_polazak_ts - interval '15 minutes';
      
      -- OPTIMIZED: Kombinovani count za OVOG SPECIFIČNOG vozača
      -- 1. Putnici iz v3_gps_raspored (unified assignments)
      -- Broji putnike za ovaj termin iz v3_gps_raspored
      SELECT COUNT(DISTINCT putnik_id) INTO v_putnici_count
      FROM public.v3_gps_raspored rt
      WHERE rt.vozac_id = v_termin.vozac_id
        AND rt.datum = v_datum
        AND rt.vreme = v_termin.vreme
        AND rt.grad = v_termin.grad
        AND rt.aktivno = true;
      
      -- Skip empty schedules
      IF v_putnici_count = 0 THEN
        CONTINUE;
      END IF;
      
      -- OPTIMIZED: Insert/update sa boljom conflict resolution
      INSERT INTO public.v3_gps_activation_schedule (
        vozac_id,
        datum,
        vreme,
        grad,
        polazak_vreme,
        activation_time,
        putnici_count,
        status,
        created_at
      ) VALUES (
        v_termin.vozac_id,
        v_datum,
        v_termin.vreme,
        v_termin.grad,
        v_polazak_ts,
        v_aktivacija_ts,
        v_putnici_count,
        CASE 
          WHEN v_aktivacija_ts <= v_current_ts THEN 'completed'
          ELSE 'pending'
        END,
        v_current_ts
      )
      ON CONFLICT (vozac_id, datum, vreme, grad)
      DO UPDATE SET
        polazak_vreme = EXCLUDED.polazak_vreme,
        activation_time = EXCLUDED.activation_time,
        putnici_count = EXCLUDED.putnici_count,
        status = CASE 
          WHEN EXCLUDED.activation_time <= v_current_ts THEN 'completed'
          WHEN v3_gps_activation_schedule.status = 'activated' THEN 'activated'
          ELSE 'pending'
        END,
        updated_at = v_current_ts
      WHERE v3_gps_activation_schedule.putnici_count != EXCLUDED.putnici_count
         OR v3_gps_activation_schedule.polazak_vreme != EXCLUDED.polazak_vreme;
      
      -- Track stats
      IF FOUND THEN
        v_updated := v_updated + 1;
      ELSE
        v_inserted := v_inserted + 1;
      END IF;
    END LOOP;
  END LOOP;
  
  -- OPTIMIZED: Cleanup old completed records (older than 7 days)
  DELETE FROM public.v3_gps_activation_schedule 
  WHERE datum < CURRENT_DATE - interval '7 days'
    AND status = 'completed';
  
  GET DIAGNOSTICS v_cleanup_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'inserted', v_inserted,
    'updated', v_updated,
    'total_processed', v_inserted + v_updated,
    'cleaned_up', v_cleanup_count,
    'datum_range', format('%s to %s', CURRENT_DATE, CURRENT_DATE + interval '2 days'),
    'timestamp', v_current_ts
  );
END;
$$;

-- ============================================================
-- 3. FUNKCIJA: fn_v3_gps_activator - OPTIMIZED
-- Označava termine kao 'activated' kada je vreme za GPS start
-- OPTIMIZED: Bolje performance i error handling
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_gps_activator()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_activated integer := 0;
  v_current_time timestamptz := now();
  v_activation_window interval := interval '2 minutes'; -- Expanded window
BEGIN
  -- OPTIMIZED: Aktiviraj termine sa proširenim window-om za reliability
  UPDATE public.v3_gps_activation_schedule
  SET 
    status = 'activated',
    updated_at = v_current_time
  WHERE status = 'pending'
    AND activation_time <= v_current_time
    AND activation_time >= v_current_time - v_activation_window
    AND putnici_count > 0; -- Only activate schedules with passengers
  
  GET DIAGNOSTICS v_activated = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'activated', v_activated,
    'timestamp', v_current_time
  );
END;
$$;

-- ============================================================
-- 4. FUNKCIJA: Cleanup završenih termina (performanse)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_cleanup_gps_activation()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_deleted integer;
BEGIN
  -- Obriši termine starije od 3 dana
  DELETE FROM public.v3_gps_activation_schedule
  WHERE created_at < now() - interval '3 days';
  
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'deleted', v_deleted,
    'timestamp', now()
  );
END;
$$;

-- ============================================================
-- 5. CRON JOBS - AUTOMATSKO POKRETANJE
-- ============================================================

-- Ukloni postojeće cron job-ove ako postoje
SELECT cron.unschedule('v3-gps-populate-schedule')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-gps-populate-schedule'
);

SELECT cron.unschedule('v3-gps-activator')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-gps-activator'
);

SELECT cron.unschedule('v3-gps-activation-cleanup')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-gps-activation-cleanup'
);

-- Popunjava tabelu svaki dan u 01:00
SELECT cron.schedule(
  'v3-gps-populate-schedule',
  '0 1 * * *',  -- svaki dan u 01:00
  $$ SELECT public.fn_v3_populate_gps_activation_schedule() $$
);

-- Aktivator - svakih 30 sekundi proverava da li treba aktivirati GPS
SELECT cron.schedule(
  'v3-gps-activator',
  '*/30 * * * * *',  -- svakih 30 sekundi
  $$ SELECT public.fn_v3_gps_activator() $$
);

-- Cleanup starih podataka - jednom dnevno u 02:30
SELECT cron.schedule(
  'v3-gps-activation-cleanup',
  '30 2 * * *',  -- svaki dan u 02:30
  $$ SELECT public.fn_v3_cleanup_gps_activation() $$
);

-- ============================================================
-- 6. TRIGGER: Aktivacija GPS-a triggering push notifications
-- (Već postoji u push_triggers.sql kao tr_v3_notify_gps_tracking_start)
-- ============================================================

-- NAPOMENA: Push notification trigger već postoji u push_triggers.sql:
-- fn_v3_notify_gps_tracking_start() se poziva kada se status promeni na 'activated'

-- ============================================================
-- 7. HELPER FUNKCIJE ZA MONITORING I DEBUG
-- ============================================================

-- Funkcija za pregled današnjih GPS aktivacija
CREATE OR REPLACE FUNCTION public.fn_v3_gps_activation_today()
RETURNS TABLE(
  vozac_ime text,
  polazak_mesto text,
  polazak_vreme time,
  aktivacija_vreme timestamptz,
  putnici_count integer,
  status text,
  vreme_do_aktivacije interval
)
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    v.ime_prezime,
    gas.polazak_mesto,
    gas.polazak_vreme,
    gas.aktivacija_vreme,
    gas.putnici_count,
    gas.status,
    CASE 
      WHEN gas.aktivacija_vreme > now() THEN gas.aktivacija_vreme - now()
      ELSE interval '0'
    END as vreme_do_aktivacije
  FROM public.v3_gps_activation_schedule gas
  JOIN public.v3_vozaci v ON gas.vozac_id = v.id
  WHERE gas.datum = CURRENT_DATE
  ORDER BY gas.aktivacija_vreme;
END;
$$;

-- Funkcija za statistike GPS aktivacije
CREATE OR REPLACE FUNCTION public.fn_v3_gps_activation_stats()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_pending integer;
  v_activated integer;
  v_completed integer;
  v_total integer;
BEGIN
  SELECT 
    COUNT(*) FILTER (WHERE status = 'pending'),
    COUNT(*) FILTER (WHERE status = 'activated'),
    COUNT(*) FILTER (WHERE status = 'completed'),
    COUNT(*)
  INTO v_pending, v_activated, v_completed, v_total
  FROM public.v3_gps_activation_schedule
  WHERE datum >= CURRENT_DATE - interval '1 day'
    AND datum <= CURRENT_DATE + interval '1 day';
  
  RETURN jsonb_build_object(
    'pending', v_pending,
    'activated', v_activated,
    'completed', v_completed,
    'total', v_total,
    'timestamp', now()
  );
END;
$$;

-- ============================================================
-- DEPLOY NOTES:
-- 1. Pokrenuti ovaj fajl u Supabase SQL Editor
-- 2. Pozvati fn_v3_populate_gps_activation_schedule() za prvi put
-- 3. Testirati: SELECT * FROM fn_v3_gps_activation_today();
-- 4. Monitoriraj: SELECT public.fn_v3_gps_activation_stats();
-- ============================================================

-- Inicijalna populacija (pozovi jednom za testiranje)
SELECT public.fn_v3_populate_gps_activation_schedule();

-- ============================================================
-- 8. FUNKCIJA: Ažuriranje putnici_count u postojećim zapisima
-- Poziva se kada se dodaju novi putnici nakon kreiranja schedule-a
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_update_putnici_count_in_schedule()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_updated integer := 0;
BEGIN
  -- ONEMOGUĆENO: Koristi obrisane tabele v3_raspored_termin/putnik
  RETURN jsonb_build_object(
    'status', 'disabled',
    'message', 'Function disabled - uses deleted tables'
  );
END;
$$;