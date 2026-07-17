-- Dodaje kolone za praćenje automatskog pripremanja termina 10 min pre polaska
ALTER TABLE public.v3_trenutna_dodela_slot
  ADD COLUMN IF NOT EXISTS auto_prepared_at timestamptz,
  ADD COLUMN IF NOT EXISTS auto_notified_at timestamptz;

COMMENT ON COLUMN public.v3_trenutna_dodela_slot.auto_prepared_at IS 'Kada su waypoints automatski kreirani 10 min pre polaska';
COMMENT ON COLUMN public.v3_trenutna_dodela_slot.auto_notified_at IS 'Kada je automatska push notifikacija poslata putnicima';
