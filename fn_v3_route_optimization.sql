-- ===================================================================
-- ROUTE OPTIMIZATION funkcija za v3_gps_raspored
-- Optimizuje redosled pokupljanja putnika na osnovu GPS koordinata
-- ===================================================================

CREATE OR REPLACE FUNCTION public.fn_v3_optimize_pickup_route(
  p_vozac_id UUID,
  p_datum DATE,
  p_grad TEXT,
  p_vreme TIME
) RETURNS JSON AS $$
DECLARE
  v_route_data RECORD;
  v_optimized_route JSON;
  v_start_lat NUMERIC := 44.0165; -- Default centar Beograda
  v_start_lng NUMERIC := 21.0059; -- Default centar Novog Sada
  v_putnik_count INTEGER := 0;
  v_updated_count INTEGER := 0;
  v_current_lat NUMERIC;
  v_current_lng NUMERIC;
  v_route_order INTEGER := 1;
  v_estimated_time TIMESTAMP WITH TIME ZONE;
  v_polazak_vreme TIMESTAMP WITH TIME ZONE;
BEGIN
  
  -- Get polazak_vreme for time calculations
  SELECT polazak_vreme INTO v_polazak_vreme
  FROM public.v3_gps_raspored 
  WHERE vozac_id = p_vozac_id 
    AND datum = p_datum 
    AND grad = p_grad 
    AND vreme = p_vreme 
    AND aktivno = true
  LIMIT 1;
  
  IF v_polazak_vreme IS NULL THEN
    RETURN json_build_object(
      'success', false,
      'error', 'No schedule found for specified driver and time'
    );
  END IF;

  -- Set starting coordinates based on grad
  IF p_grad = 'BC' THEN
    v_start_lat := 44.0165; -- Belgrade center  
    v_start_lng := 20.9114;
  ELSIF p_grad = 'VS' THEN
    v_start_lat := 45.2671; -- Novi Sad center
    v_start_lng := 19.8335;
  END IF;

  v_current_lat := v_start_lat;
  v_current_lng := v_start_lng;

  -- Simple nearest neighbor optimization algorithm
  -- Start from center and always pick closest unvisited point
  FOR v_route_data IN
    WITH unoptimized_points AS (
      SELECT 
        id,
        putnik_id,
        pickup_lat,
        pickup_lng,
        pickup_naziv,
        ROW_NUMBER() OVER () as original_order
      FROM public.v3_gps_raspored
      WHERE vozac_id = p_vozac_id
        AND datum = p_datum 
        AND grad = p_grad
        AND vreme = p_vreme
        AND aktivno = true
        AND pickup_lat IS NOT NULL 
        AND pickup_lng IS NOT NULL
      ORDER BY id
    ),
    optimized_sequence AS (
      WITH RECURSIVE route_optimization AS (
        -- Start with closest point to center
        (SELECT 
          id, putnik_id, pickup_lat, pickup_lng, pickup_naziv,
          1 as route_order,
          pickup_lat as current_lat,
          pickup_lng as current_lng,
          ARRAY[id] as visited_ids
        FROM unoptimized_points
        ORDER BY 
          -- Distance from start point
          SQRT(POWER(pickup_lat - v_start_lat, 2) + POWER(pickup_lng - v_start_lng, 2))
        LIMIT 1)
        
        UNION ALL
        
        -- Recursively find nearest unvisited point
        SELECT 
          up.id, up.putnik_id, up.pickup_lat, up.pickup_lng, up.pickup_naziv,
          ro.route_order + 1,
          up.pickup_lat,
          up.pickup_lng,
          ro.visited_ids || up.id
        FROM route_optimization ro
        CROSS JOIN LATERAL (
          SELECT id, putnik_id, pickup_lat, pickup_lng, pickup_naziv
          FROM unoptimized_points up2
          WHERE NOT (up2.id = ANY(ro.visited_ids))
          ORDER BY 
            -- Distance from current position
            SQRT(POWER(up2.pickup_lat - ro.current_lat, 2) + POWER(up2.pickup_lng - ro.current_lng, 2))
          LIMIT 1
        ) up
        WHERE ro.route_order < (SELECT COUNT(*) FROM unoptimized_points)
      )
      SELECT * FROM route_optimization
    )
    SELECT * FROM optimized_sequence
    ORDER BY route_order
  LOOP
    v_putnik_count := v_putnik_count + 1;
    
    -- Calculate estimated pickup time (assume 2 minutes between stops)
    v_estimated_time := v_polazak_vreme - INTERVAL '30 minutes' + (v_route_order - 1) * INTERVAL '2 minutes';
    
    -- Update route_order and estimated_pickup_time
    UPDATE public.v3_gps_raspored 
    SET 
      route_order = v_route_order,
      estimated_pickup_time = v_estimated_time,
      updated_at = now()
    WHERE id = v_route_data.id;
    
    v_updated_count := v_updated_count + 1;
    v_route_order := v_route_order + 1;
    
    -- Update current position for next iteration
    v_current_lat := v_route_data.pickup_lat;
    v_current_lng := v_route_data.pickup_lng;
  END LOOP;

  -- Build response
  v_optimized_route := json_build_object(
    'success', true,
    'vozac_id', p_vozac_id,
    'datum', p_datum,
    'grad', p_grad, 
    'vreme', p_vreme,
    'putnik_count', v_putnik_count,
    'updated_count', v_updated_count,
    'start_coordinates', json_build_object('lat', v_start_lat, 'lng', v_start_lng),
    'optimization_completed_at', now()
  );

  RAISE NOTICE '[ROUTE_OPT] Optimized route for vozac % on % % %: % putnika', 
    p_vozac_id, p_datum, p_grad, p_vreme, v_putnik_count;

  RETURN v_optimized_route;

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING '[ROUTE_OPT] Error: % - %', SQLSTATE, SQLERRM;
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$ LANGUAGE plpgsql;

-- ===================================================================
-- Convenience funkcija za optimizaciju svih ruta za datum
-- ===================================================================

CREATE OR REPLACE FUNCTION public.fn_v3_optimize_all_routes_for_date(p_datum DATE)
RETURNS JSON AS $$
DECLARE
  v_schedule_record RECORD;
  v_optimization_result JSON;
  v_total_optimized INTEGER := 0;
  v_results JSON[] := '{}';
BEGIN
  
  -- Optimize route for each unique vozac/datum/grad/vreme combination
  FOR v_schedule_record IN
    SELECT DISTINCT vozac_id, datum, grad, vreme, COUNT(*) as putnik_count
    FROM public.v3_gps_raspored
    WHERE datum = p_datum
      AND aktivno = true
      AND pickup_lat IS NOT NULL
      AND pickup_lng IS NOT NULL
    GROUP BY vozac_id, datum, grad, vreme
    HAVING COUNT(*) > 1  -- Only optimize routes with multiple pickups
    ORDER BY datum, grad, vreme, vozac_id
  LOOP
    
    -- Optimize this specific route
    SELECT public.fn_v3_optimize_pickup_route(
      v_schedule_record.vozac_id,
      v_schedule_record.datum,
      v_schedule_record.grad,
      v_schedule_record.vreme
    ) INTO v_optimization_result;
    
    -- Collect results
    v_results := v_results || v_optimization_result;
    v_total_optimized := v_total_optimized + 1;
    
  END LOOP;

  RETURN json_build_object(
    'success', true,
    'date', p_datum,
    'total_routes_optimized', v_total_optimized,
    'results', array_to_json(v_results),
    'completed_at', now()
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$ LANGUAGE plpgsql;

-- ===================================================================
-- COMMENTS
-- ===================================================================

COMMENT ON FUNCTION public.fn_v3_optimize_pickup_route IS 
'Optimizes pickup route for single driver using nearest neighbor algorithm based on GPS coordinates';

COMMENT ON FUNCTION public.fn_v3_optimize_all_routes_for_date IS 
'Optimizes pickup routes for all drivers on specified date - use for daily route planning';