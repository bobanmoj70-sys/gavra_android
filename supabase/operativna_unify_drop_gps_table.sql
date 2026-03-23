-- =====================================================
-- Operativna kao jedini izvor istine + gašenje fizičke v3_gps_raspored tabele
-- =====================================================
-- Cilj:
-- 1) Proširi v3_operativna_nedelja kolona-ma potrebnim za GPS/tracking
-- 2) Backfill podataka iz postojeće v3_gps_raspored
-- 3) Ukloni sync operativna -> gps (više nije potreban)
-- 4) Fizičku tabelu preimenuj u legacy i izloži kompatibilni VIEW v3_gps_raspored
--
-- Napomena:
-- - Ovaj skript ne briše legacy backup tabelu odmah, radi rollback sigurnosti.
-- - Nakon stabilizacije može se obrisati public.v3_gps_raspored_legacy.

BEGIN;

-- 1) Proširenje v3_operativna_nedelja
ALTER TABLE public.v3_operativna_nedelja
  ADD COLUMN IF NOT EXISTS vozac_id uuid,
  ADD COLUMN IF NOT EXISTS nav_bar_type text,
  ADD COLUMN IF NOT EXISTS adresa_id uuid,
  ADD COLUMN IF NOT EXISTS pickup_lat numeric,
  ADD COLUMN IF NOT EXISTS pickup_lng numeric,
  ADD COLUMN IF NOT EXISTS pickup_naziv text,
  ADD COLUMN IF NOT EXISTS route_order integer,
  ADD COLUMN IF NOT EXISTS estimated_pickup_time timestamptz,
  ADD COLUMN IF NOT EXISTS polazak_vreme timestamptz,
  ADD COLUMN IF NOT EXISTS activation_time timestamptz,
  ADD COLUMN IF NOT EXISTS gps_status text DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS notification_sent boolean DEFAULT false;

-- FK veze (ako već ne postoje)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'v3_operativna_nedelja_vozac_id_fkey'
  ) THEN
    ALTER TABLE public.v3_operativna_nedelja
      ADD CONSTRAINT v3_operativna_nedelja_vozac_id_fkey
      FOREIGN KEY (vozac_id) REFERENCES public.v3_vozaci(id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'v3_operativna_nedelja_adresa_id_fkey'
  ) THEN
    ALTER TABLE public.v3_operativna_nedelja
      ADD CONSTRAINT v3_operativna_nedelja_adresa_id_fkey
      FOREIGN KEY (adresa_id) REFERENCES public.v3_adrese(id);
  END IF;
END $$;

-- 2) Backfill iz postojeće GPS tabele
WITH gps_match AS (
  SELECT DISTINCT ON (g.putnik_id, g.datum, g.grad, g.vreme)
    g.putnik_id,
    g.datum,
    g.grad,
    g.vreme,
    g.vozac_id,
    g.nav_bar_type,
    g.adresa_id,
    g.pickup_lat,
    g.pickup_lng,
    g.pickup_naziv,
    g.route_order,
    g.estimated_pickup_time,
    g.polazak_vreme,
    g.activation_time,
    g.gps_status,
    g.notification_sent
  FROM public.v3_gps_raspored g
  WHERE g.putnik_id IS NOT NULL
  ORDER BY g.putnik_id, g.datum, g.grad, g.vreme, g.updated_at DESC NULLS LAST, g.created_at DESC NULLS LAST
)
UPDATE public.v3_operativna_nedelja o
SET
  vozac_id = gm.vozac_id,
  nav_bar_type = gm.nav_bar_type,
  adresa_id = COALESCE(o.adresa_id_override, gm.adresa_id),
  pickup_lat = gm.pickup_lat,
  pickup_lng = gm.pickup_lng,
  pickup_naziv = gm.pickup_naziv,
  route_order = gm.route_order,
  estimated_pickup_time = gm.estimated_pickup_time,
  polazak_vreme = gm.polazak_vreme,
  activation_time = gm.activation_time,
  gps_status = COALESCE(gm.gps_status, o.gps_status, 'pending'),
  notification_sent = COALESCE(gm.notification_sent, o.notification_sent, false)
FROM gps_match gm
WHERE o.putnik_id = gm.putnik_id
  AND o.datum = gm.datum
  AND o.grad = gm.grad
  AND COALESCE(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme) = gm.vreme;

-- 3) Popuni adresa/koordinate iz putnika+adrese gde fali
UPDATE public.v3_operativna_nedelja o
SET adresa_id = COALESCE(
      o.adresa_id_override,
      CASE
        WHEN upper(o.grad) = 'BC' THEN p.adresa_bc_id
        WHEN upper(o.grad) = 'VS' THEN p.adresa_vs_id
        ELSE NULL
      END
    )
FROM public.v3_putnici p
WHERE p.id = o.putnik_id
  AND o.vozac_id IS NOT NULL
  AND o.adresa_id IS NULL;

UPDATE public.v3_operativna_nedelja o
SET
  pickup_lat = a.gps_lat,
  pickup_lng = a.gps_lng,
  pickup_naziv = a.naziv
FROM public.v3_adrese a
WHERE o.adresa_id = a.id
  AND (o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR o.pickup_naziv IS NULL);

-- 4) Recompute polazak/activation gde fali
UPDATE public.v3_operativna_nedelja o
SET
  polazak_vreme = (o.datum + COALESCE(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme)),
  activation_time = (o.datum + COALESCE(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme)) - INTERVAL '15 minutes'
WHERE o.vozac_id IS NOT NULL
  AND COALESCE(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme) IS NOT NULL
  AND (o.polazak_vreme IS NULL OR o.activation_time IS NULL);

-- 5) Ukloni operativna->gps sync trigger/funkciju
DROP TRIGGER IF EXISTS tr_v3_sync_operativna_to_gps_raspored ON public.v3_operativna_nedelja;
DROP FUNCTION IF EXISTS public.fn_v3_sync_operativna_to_gps_raspored();

-- 6) GPS tabela -> legacy backup (ako već nije preimenovana)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'v3_gps_raspored'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'v3_gps_raspored_legacy'
  ) THEN
    ALTER TABLE public.v3_gps_raspored RENAME TO v3_gps_raspored_legacy;
  END IF;
END $$;

-- 7) Kompatibilni view istog imena (read/update kompatibilnost za postojeći kod)
DROP VIEW IF EXISTS public.v3_gps_raspored;
CREATE VIEW public.v3_gps_raspored AS
SELECT
  o.id,
  o.vozac_id,
  o.putnik_id,
  o.datum,
  o.grad,
  COALESCE(o.vreme, o.dodeljeno_vreme, o.zeljeno_vreme) AS vreme,
  o.nav_bar_type,
  o.aktivno,
  o.polazak_vreme,
  o.activation_time,
  COALESCE(o.gps_status, 'pending') AS gps_status,
  COALESCE(o.notification_sent, false) AS notification_sent,
  o.created_at,
  o.updated_at,
  o.created_by,
  o.updated_by,
  o.adresa_id,
  o.pickup_lat,
  o.pickup_lng,
  o.pickup_naziv,
  o.route_order,
  o.estimated_pickup_time
FROM public.v3_operativna_nedelja o
WHERE o.vozac_id IS NOT NULL;

COMMIT;

-- Optional cleanup nakon verifikacije (ručno):
-- DROP TABLE IF EXISTS public.v3_gps_raspored_legacy;
