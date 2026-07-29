-- Refactor: waypoints_json -> normalized columns
-- 1) Add optimized_order to slot (global OSRM order, array of termin_ids)
ALTER TABLE public.v3_trenutna_dodela_slot
  ADD COLUMN IF NOT EXISTS optimized_order uuid[] DEFAULT '{}'::uuid[];

COMMENT ON COLUMN public.v3_trenutna_dodela_slot.optimized_order IS 'Globalni OSRM redosled termin_id-ova za slot';

-- 2) Add optimized_order to eta_results (per-driver order at compute time)
ALTER TABLE public.v3_eta_results
  ADD COLUMN IF NOT EXISTS optimized_order uuid[] DEFAULT '{}'::uuid[];

COMMENT ON COLUMN public.v3_eta_results.optimized_order IS 'Po-vozacki optimizovan redosled termin_id-ova u trenutku racunanja ETA';

-- 3) Drop legacy waypoints_json column (replaced by normalized columns)
ALTER TABLE public.v3_trenutna_dodela_slot
  DROP COLUMN IF EXISTS waypoints_json;
