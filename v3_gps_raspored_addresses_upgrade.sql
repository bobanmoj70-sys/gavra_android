-- ===================================================================
-- UPGRADE v3_gps_raspored sa ADRESAMA i KOORDINATAMA
-- Dodavanje GPS routing funkcionalnosti
-- ===================================================================

-- Dodavanje kolona za adrese i koordinate
ALTER TABLE public.v3_gps_raspored 
ADD COLUMN IF NOT EXISTS adresa_id UUID REFERENCES public.v3_adrese(id),
ADD COLUMN IF NOT EXISTS pickup_lat NUMERIC(10,7),  
ADD COLUMN IF NOT EXISTS pickup_lng NUMERIC(10,7),
ADD COLUMN IF NOT EXISTS pickup_naziv TEXT,
ADD COLUMN IF NOT EXISTS route_order INTEGER, -- Redosled za optimizaciju rute
ADD COLUMN IF NOT EXISTS estimated_pickup_time TIMESTAMP WITH TIME ZONE; -- Procenjeno vreme pokupljanja

-- Index za GPS routing optimizaciju
CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_route_optimization 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme, route_order) 
WHERE aktivno = true;

-- Index za GPS koordinate proximity search
CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_gps_coords 
ON public.v3_gps_raspored(pickup_lat, pickup_lng) 
WHERE aktivno = true AND pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL;

-- ===================================================================
-- TRIGGER za auto-populate koordinata iz adresa
-- ===================================================================

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

  -- If we have putnik's address, use it; otherwise use manually set adresa_id
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

-- Replace old trigger with new one
DROP TRIGGER IF EXISTS tr_v3_gps_raspored_compute_times ON public.v3_gps_raspored;
CREATE TRIGGER tr_v3_gps_raspored_populate_data
  BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
  FOR EACH ROW
  EXECUTE FUNCTION fn_v3_gps_raspored_populate_coordinates();

-- ===================================================================
-- COMMENTS za nove kolone
-- ===================================================================

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