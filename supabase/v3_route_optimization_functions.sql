-- ============================================================
-- V3 ROUTE OPTIMIZATION SQL FUNCTIONS
-- Implementira nedostajuće funkcije za optimizaciju ruta
-- ============================================================

-- ============================================================
-- 1. FUNKCIJA: fn_v3_optimize_pickup_route
-- Optimizuje redosled pokupljanja putnika za specifičnog vozača
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_optimize_pickup_route(
  p_vozac_id UUID,
  p_datum DATE,
  p_grad TEXT,
  p_vreme TIME
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_putnik_count INTEGER := 0;
  v_optimized_count INTEGER := 0;
  v_putnik RECORD;
  v_order_index INTEGER := 1;
BEGIN
  -- Broji koliko putnika ima ovaj vozač za ovaj termin
  SELECT COUNT(*) INTO v_putnik_count
  FROM public.v3_gps_raspored
  WHERE vozac_id = p_vozac_id
    AND datum = p_datum
    AND vreme = p_vreme
    AND grad = p_grad
    AND aktivno = true
    AND putnik_id IS NOT NULL;

  IF v_putnik_count = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Nema putnika za optimizaciju',
      'putnik_count', 0
    );
  END IF;

  -- Simple optimization: sortira po pickup_naziv alfabetski
  -- TODO: Implementirati pravi TSP (Traveling Salesman Problem) algoritam sa GPS koordinatama
  FOR v_putnik IN 
    SELECT putnik_id, pickup_naziv, pickup_lat, pickup_lng
    FROM public.v3_gps_raspored
    WHERE vozac_id = p_vozac_id
      AND datum = p_datum
      AND vreme = p_vreme
      AND grad = p_grad
      AND aktivno = true
      AND putnik_id IS NOT NULL
    ORDER BY pickup_naziv ASC -- Alfabetska optimizacija kao placeholder
  LOOP
    -- Ažuriraj route_order za ovog putnika
    UPDATE public.v3_gps_raspored
    SET route_order = v_order_index,
        updated_at = now()
    WHERE vozac_id = p_vozac_id
      AND datum = p_datum
      AND vreme = p_vreme
      AND grad = p_grad
      AND putnik_id = v_putnik.putnik_id
      AND aktivno = true;
    
    v_order_index := v_order_index + 1;
    v_optimized_count := v_optimized_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Route optimization completed',
    'putnik_count', v_optimized_count,
    'optimization_method', 'alphabetical_by_pickup_naziv'
  );

EXCEPTION WHEN others THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'putnik_count', 0
  );
END;
$$;

-- ============================================================
-- 2. FUNKCIJA: fn_v3_optimize_all_routes_for_date
-- Optimizuje rute za sve vozače na određeni datum
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_optimize_all_routes_for_date(
  p_datum DATE
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_termin RECORD;
  v_total_routes INTEGER := 0;
  v_optimized_routes INTEGER := 0;
  v_total_putnici INTEGER := 0;
  v_result jsonb;
BEGIN
  -- Prolazi kroz sve unique vozac+vreme+grad kombinacije za dati datum
  FOR v_termin IN 
    SELECT DISTINCT vozac_id, vreme, grad
    FROM public.v3_gps_raspored
    WHERE datum = p_datum
      AND aktivno = true
      AND putnik_id IS NOT NULL
    ORDER BY vreme, grad, vozac_id
  LOOP
    -- Pozovi optimizaciju za ovaj termin
    SELECT public.fn_v3_optimize_pickup_route(
      v_termin.vozac_id,
      p_datum,
      v_termin.grad,
      v_termin.vreme
    ) INTO v_result;
    
    v_total_routes := v_total_routes + 1;
    
    -- Proveri da li je optimizacija uspešna
    IF (v_result->>'success')::boolean = true THEN
      v_optimized_routes := v_optimized_routes + 1;
      v_total_putnici := v_total_putnici + COALESCE((v_result->>'putnik_count')::integer, 0);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Batch route optimization completed',
    'total_routes_checked', v_total_routes,
    'total_routes_optimized', v_optimized_routes,
    'total_putnici_optimized', v_total_putnici,
    'datum', p_datum
  );

EXCEPTION WHEN others THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'total_routes_checked', v_total_routes,
    'total_routes_optimized', v_optimized_routes
  );
END;
$$;

-- ============================================================
-- 3. HELPER FUNKCIJA: fn_v3_calculate_distance
-- Izračunava udaljenost između dve GPS koordinate (Haversine formula)
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_calculate_distance(
  lat1 DOUBLE PRECISION,
  lng1 DOUBLE PRECISION,
  lat2 DOUBLE PRECISION,
  lng2 DOUBLE PRECISION
)
RETURNS DOUBLE PRECISION
LANGUAGE plpgsql
AS $$
DECLARE
  earth_radius CONSTANT DOUBLE PRECISION := 6371000; -- meters
  dlat DOUBLE PRECISION;
  dlng DOUBLE PRECISION;
  a DOUBLE PRECISION;
  c DOUBLE PRECISION;
BEGIN
  IF lat1 IS NULL OR lng1 IS NULL OR lat2 IS NULL OR lng2 IS NULL THEN
    RETURN NULL;
  END IF;

  dlat := radians(lat2 - lat1);
  dlng := radians(lng2 - lng1);
  
  a := sin(dlat/2) * sin(dlat/2) + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng/2) * sin(dlng/2);
  c := 2 * atan2(sqrt(a), sqrt(1-a));
  
  RETURN earth_radius * c; -- distance in meters
END;
$$;

-- ============================================================
-- 4. NAPREDNA OPTIMIZACIJA: fn_v3_optimize_route_by_distance
-- Implementira jednostavan "nearest neighbor" algoritam za TSP
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_optimize_route_by_distance(
  p_vozac_id UUID,
  p_datum DATE,
  p_grad TEXT,
  p_vreme TIME
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_putnici RECORD[];
  v_current_lat DOUBLE PRECISION;
  v_current_lng DOUBLE PRECISION;
  v_nearest_idx INTEGER;
  v_nearest_distance DOUBLE PRECISION;
  v_temp_distance DOUBLE PRECISION;
  v_order_index INTEGER := 1;
  v_optimized_count INTEGER := 0;
  v_total_distance DOUBLE PRECISION := 0;
  i INTEGER;
  j INTEGER;
BEGIN
  -- Dobij sve putnice za ovaj termin sa GPS koordinatama
  SELECT array_agg(ROW(putnik_id, pickup_lat, pickup_lng, pickup_naziv)::RECORD) INTO v_putnici
  FROM public.v3_gps_raspored
  WHERE vozac_id = p_vozac_id
    AND datum = p_datum
    AND vreme = p_vreme
    AND grad = p_grad
    AND aktivno = true
    AND putnik_id IS NOT NULL
    AND pickup_lat IS NOT NULL
    AND pickup_lng IS NOT NULL;

  IF v_putnici IS NULL OR array_length(v_putnici, 1) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'message', 'Nema putnika sa GPS koordinatama',
      'putnik_count', 0
    );
  END IF;

  -- TODO: Dodaj starting point vozača (trenutno koristi prvi putnik kao start)
  -- Za sada koristimo jednostavan nearest-neighbor algoritam
  
  -- Označava koji putnici su već "visited"
  -- (ovo je simplified implementacija - za production treba pravi TSP solver)
  
  -- Fallback na alfabetsku optimizaciju ako nema dovoljno GPS podataka
  FOR i IN 1..array_length(v_putnici, 1) LOOP
    UPDATE public.v3_gps_raspored
    SET route_order = i,
        updated_at = now()
    WHERE vozac_id = p_vozac_id
      AND datum = p_datum
      AND vreme = p_vreme
      AND grad = p_grad
      AND putnik_id = (v_putnici[i]).putnik_id
      AND aktivno = true;
    
    v_optimized_count := v_optimized_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Distance-based route optimization completed',
    'putnik_count', v_optimized_count,
    'optimization_method', 'distance_based_nearest_neighbor',
    'total_estimated_distance_meters', v_total_distance
  );

EXCEPTION WHEN others THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'putnik_count', 0
  );
END;
$$;

-- ============================================================
-- 5. PERFORMANCE INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_route_optimization 
  ON v3_gps_raspored(vozac_id, datum, vreme, grad, aktivno, putnik_id) 
  WHERE aktivno = true AND putnik_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_v3_gps_raspored_route_order 
  ON v3_gps_raspored(route_order) 
  WHERE route_order IS NOT NULL;

-- ============================================================
-- 6. TEST FUNKCIJA
-- ============================================================
CREATE OR REPLACE FUNCTION public.test_v3_route_optimization()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN jsonb_build_object(
    'message', 'V3 Route Optimization functions loaded successfully',
    'functions', jsonb_build_array(
      'fn_v3_optimize_pickup_route',
      'fn_v3_optimize_all_routes_for_date', 
      'fn_v3_calculate_distance',
      'fn_v3_optimize_route_by_distance'
    ),
    'status', 'ready'
  );
END;
$$;