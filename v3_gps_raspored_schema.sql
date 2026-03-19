-- ===================================================================
-- NOVA UNIFIED TABELA: v3_gps_raspored
-- Zamenjuje: v3_raspored_termin + v3_raspored_putnik
-- Datum kreiranja: 19. mart 2026
-- ===================================================================

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

-- ===================================================================
-- INDEXES za optimalne performanse
-- ===================================================================

-- GPS CRON job query optimization - PER DRIVER
CREATE INDEX idx_v3_gps_raspored_gps_per_vozac 
ON public.v3_gps_raspored(vozac_id, activation_time, gps_status) 
WHERE aktivno = true AND gps_status IN ('pending', 'activated');

-- Count passengers per driver for GPS activation
CREATE INDEX idx_v3_gps_raspored_putnik_count 
ON public.v3_gps_raspored(vozac_id, datum, grad, vreme) 
WHERE aktivno = true;

-- Admin panel filter queries
CREATE INDEX idx_v3_gps_raspored_admin_filter 
ON public.v3_gps_raspored(datum, nav_bar_type, aktivno);

-- Vozac dashboard queries
CREATE INDEX idx_v3_gps_raspored_vozac 
ON public.v3_gps_raspored(vozac_id, datum) 
WHERE aktivno = true;

-- Putnik lookup queries  
CREATE INDEX idx_v3_gps_raspored_putnik 
ON public.v3_gps_raspored(putnik_id, datum) 
WHERE aktivno = true;

-- Schedule type queries (current nav_bar_type filtering)
CREATE INDEX idx_v3_gps_raspored_nav_type 
ON public.v3_gps_raspored(nav_bar_type, datum, grad, vreme) 
WHERE aktivno = true;

-- ===================================================================
-- AUTO-UPDATE TRIGGERS
-- ===================================================================

-- Auto-compute polazak_vreme and activation_time
CREATE OR REPLACE FUNCTION fn_v3_gps_raspored_compute_times()
RETURNS TRIGGER AS $$
BEGIN
  -- Compute polazak_vreme: datum + vreme
  NEW.polazak_vreme := NEW.datum + NEW.vreme;
  
  -- Compute activation_time: 15 minutes before departure
  NEW.activation_time := NEW.polazak_vreme - INTERVAL '15 minutes';
  
  -- Update timestamp
  NEW.updated_at := now();
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER tr_v3_gps_raspored_compute_times
  BEFORE INSERT OR UPDATE ON public.v3_gps_raspored
  FOR EACH ROW
  EXECUTE FUNCTION fn_v3_gps_raspored_compute_times();

-- ===================================================================
-- COMMENTS za dokumentaciju
-- ===================================================================

COMMENT ON TABLE public.v3_gps_raspored IS 
'Unified schedule table - replaces v3_raspored_termin and v3_raspored_putnik. 
Each record represents one passenger assigned to one driver for specific timeslot.
Multiple drivers can work same timeslot based on passenger demand.';

COMMENT ON COLUMN public.v3_gps_raspored.nav_bar_type IS 
'Schedule type: zimski/letnji/praznici - determines which departure times are valid';

COMMENT ON COLUMN public.v3_gps_raspored.gps_status IS 
'GPS automation status PER DRIVER: pending -> activated -> completed/skipped/cancelled.
Each driver gets individual GPS activation for their assigned passengers.';

COMMENT ON COLUMN public.v3_gps_raspored.polazak_vreme IS 
'Computed departure timestamp: datum + vreme (auto-calculated by trigger)';

COMMENT ON COLUMN public.v3_gps_raspored.activation_time IS 
'Computed GPS activation timestamp: polazak_vreme - 15min (auto-calculated by trigger)';

COMMENT ON CONSTRAINT uk_putnik_vozac_schedule ON public.v3_gps_raspored IS 
'Ensures one passenger can only be assigned to one driver per timeslot - prevents double booking';

COMMENT ON CONSTRAINT ck_valid_schedule ON public.v3_gps_raspored IS 
'Validates departure times against schedule type rules from V2RouteConfig';

-- ===================================================================
-- GPS INTEGRATION NOTES
-- ===================================================================

/*
GPS ACTIVATION LOGIC - PER DRIVER APPROACH:

1. CRON job will GROUP BY vozac_id, datum, grad, vreme to count passengers per driver
2. Each driver gets separate GPS activation record in v3_gps_activation_schedule  
3. Example: BC 07:00 with 3 drivers = 3 separate GPS activations
   - Driver1: 8 passengers -> GPS activation 06:45
   - Driver2: 8 passengers -> GPS activation 06:45  
   - Driver3: 8 passengers -> GPS activation 06:45

4. Passengers track their assigned driver's GPS individually
5. No false data - each driver's location is accurate for their passengers

NEW GPS FUNCTION LOGIC:
SELECT vozac_id, COUNT(*) as putnici_count
FROM v3_gps_raspored 
WHERE datum = target_date 
  AND nav_bar_type = current_nav_type 
  AND aktivno = true
GROUP BY vozac_id, datum, grad, vreme
HAVING COUNT(*) > 0;
*/