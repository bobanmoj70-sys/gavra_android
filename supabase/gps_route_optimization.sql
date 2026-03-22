-- =====================================================
-- GPS ROUTE OPTIMIZATION (v3_gps_raspored)
-- =====================================================
-- Ovaj patch dodaje funkcije koje app već poziva:
--   - fn_v3_optimize_pickup_route
--   - fn_v3_optimize_all_routes_for_date
--
-- Logika:
--   1) START = poslednja GPS pozicija vozača (v3_vozac_lokacije)
--   2) WAYPOINTS = pickup koordinate putnika iz v3_gps_raspored za termin
--   3) DEST = suprotan grad (BC -> VS, VS -> BC)
--
-- Rezultat:
--   - route_order
--   - estimated_pickup_time
--   - JSON status za app

BEGIN;

-- -----------------------------------------------------
-- Helper: Haversine udaljenost u kilometrima
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_v3_haversine_km(
  lat1 numeric,
  lng1 numeric,
  lat2 numeric,
  lng2 numeric
)
RETURNS numeric
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    6371::numeric * acos(
      LEAST(1::numeric, GREATEST(-1::numeric,
        cos(radians(lat1::double precision)) * cos(radians(lat2::double precision)) *
        cos(radians((lng2 - lng1)::double precision)) +
        sin(radians(lat1::double precision)) * sin(radians(lat2::double precision))
      ))
    )
$$;

-- -----------------------------------------------------
-- Optimizacija jedne rute (termin vozača)
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_v3_optimize_pickup_route(
  p_vozac_id uuid,
  p_datum date,
  p_grad text,
  p_vreme time
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_driver_lat numeric;
  v_driver_lng numeric;
  v_current_lat numeric;
  v_current_lng numeric;
  v_dest_lat numeric;
  v_dest_lng numeric;
  v_avg_speed_kmh numeric := 40;
  v_total_minutes numeric := 0;
  v_leg_km numeric := 0;
  v_leg_minutes numeric := 0;
  v_order integer := 1;
  v_total_putnici integer := 0;
  v_putnici_sa_koordinatama integer := 0;
  v_putnici_bez_koordinata integer := 0;
  v_updated_count integer := 0;
  v_start_source text := 'driver_gps';
  v_sel RECORD;
  v_polazak_timestamptz timestamptz;
BEGIN
  -- Ukupan broj putnika za termin
  SELECT COUNT(*)::int
  INTO v_total_putnici
  FROM public.v3_gps_raspored r
  WHERE r.vozac_id = p_vozac_id
    AND r.datum = p_datum
    AND upper(r.grad) = upper(p_grad)
    AND r.vreme = p_vreme
    AND r.aktivno = true
    AND r.putnik_id IS NOT NULL;

  IF v_total_putnici = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'putnik_count', 0,
      'updated_count', 0,
      'message', 'Nema putnika za optimizaciju.'
    );
  END IF;

  -- Putnici sa/bez koordinata
  SELECT
    COUNT(*) FILTER (WHERE pickup_lat IS NOT NULL AND pickup_lng IS NOT NULL)::int,
    COUNT(*) FILTER (WHERE pickup_lat IS NULL OR pickup_lng IS NULL)::int
  INTO v_putnici_sa_koordinatama, v_putnici_bez_koordinata
  FROM public.v3_gps_raspored r
  WHERE r.vozac_id = p_vozac_id
    AND r.datum = p_datum
    AND upper(r.grad) = upper(p_grad)
    AND r.vreme = p_vreme
    AND r.aktivno = true
    AND r.putnik_id IS NOT NULL;

  IF v_putnici_sa_koordinatama = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'putnik_count', v_total_putnici,
      'updated_count', 0,
      'error', 'Putnici nemaju pickup koordinate.'
    );
  END IF;

  -- START: poslednja GPS pozicija vozača
  SELECT vl.lat, vl.lng
  INTO v_driver_lat, v_driver_lng
  FROM public.v3_vozac_lokacije vl
  WHERE vl.vozac_id = p_vozac_id
  ORDER BY vl.updated_at DESC
  LIMIT 1;

  IF v_driver_lat IS NULL OR v_driver_lng IS NULL THEN
    -- fallback: centroid pickup tačaka
    SELECT AVG(r.pickup_lat), AVG(r.pickup_lng)
    INTO v_driver_lat, v_driver_lng
    FROM public.v3_gps_raspored r
    WHERE r.vozac_id = p_vozac_id
      AND r.datum = p_datum
      AND upper(r.grad) = upper(p_grad)
      AND r.vreme = p_vreme
      AND r.aktivno = true
      AND r.putnik_id IS NOT NULL
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL;

    v_start_source := 'pickup_centroid';
  END IF;

  -- DEST: suprotan grad (grubi centar grada)
  IF upper(p_grad) = 'BC' THEN
    -- Vršac
    v_dest_lat := 45.1190;
    v_dest_lng := 21.3030;
  ELSIF upper(p_grad) = 'VS' THEN
    -- Bela Crkva
    v_dest_lat := 44.8970;
    v_dest_lng := 21.4170;
  ELSE
    -- fallback: centroid pickup tačaka
    SELECT AVG(r.pickup_lat), AVG(r.pickup_lng)
    INTO v_dest_lat, v_dest_lng
    FROM public.v3_gps_raspored r
    WHERE r.vozac_id = p_vozac_id
      AND r.datum = p_datum
      AND upper(r.grad) = upper(p_grad)
      AND r.vreme = p_vreme
      AND r.aktivno = true
      AND r.putnik_id IS NOT NULL
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL;
  END IF;

  v_current_lat := v_driver_lat;
  v_current_lng := v_driver_lng;
  v_polazak_timestamptz := (p_datum::timestamp + p_vreme::interval);

  -- Reset prethodne optimizacije za termin
  UPDATE public.v3_gps_raspored
  SET
    route_order = NULL,
    estimated_pickup_time = NULL,
    updated_at = now(),
    updated_by = 'sql:route-optimize-reset'
  WHERE vozac_id = p_vozac_id
    AND datum = p_datum
    AND upper(grad) = upper(p_grad)
    AND vreme = p_vreme
    AND aktivno = true
    AND putnik_id IS NOT NULL;

  -- Nearest-neighbor + destination bias
  LOOP
    SELECT
      r.id,
      r.pickup_lat,
      r.pickup_lng,
      public.fn_v3_haversine_km(v_current_lat, v_current_lng, r.pickup_lat, r.pickup_lng) AS leg_km,
      (
        public.fn_v3_haversine_km(v_current_lat, v_current_lng, r.pickup_lat, r.pickup_lng)
        + 0.25 * public.fn_v3_haversine_km(r.pickup_lat, r.pickup_lng, v_dest_lat, v_dest_lng)
      ) AS score
    INTO v_sel
    FROM public.v3_gps_raspored r
    WHERE r.vozac_id = p_vozac_id
      AND r.datum = p_datum
      AND upper(r.grad) = upper(p_grad)
      AND r.vreme = p_vreme
      AND r.aktivno = true
      AND r.putnik_id IS NOT NULL
      AND r.route_order IS NULL
      AND r.pickup_lat IS NOT NULL
      AND r.pickup_lng IS NOT NULL
    ORDER BY score ASC
    LIMIT 1;

    EXIT WHEN NOT FOUND;

    v_leg_km := COALESCE(v_sel.leg_km, 0);
    v_leg_minutes := CASE
      WHEN v_leg_km <= 0 THEN 0
      ELSE (v_leg_km / v_avg_speed_kmh) * 60
    END;

    v_total_minutes := v_total_minutes + v_leg_minutes;

    UPDATE public.v3_gps_raspored
    SET
      route_order = v_order,
      estimated_pickup_time = v_polazak_timestamptz + make_interval(mins => GREATEST(0, ROUND(v_total_minutes)::int)),
      gps_status = CASE WHEN gps_status = 'pending' THEN 'optimized' ELSE gps_status END,
      updated_at = now(),
      updated_by = 'sql:route-optimize'
    WHERE id = v_sel.id;

    v_current_lat := v_sel.pickup_lat;
    v_current_lng := v_sel.pickup_lng;
    v_order := v_order + 1;
    v_updated_count := v_updated_count + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'putnik_count', v_total_putnici,
    'updated_count', v_updated_count,
    'without_coordinates', v_putnici_bez_koordinata,
    'start_source', v_start_source,
    'destination', upper(CASE WHEN upper(p_grad) = 'BC' THEN 'VS' WHEN upper(p_grad) = 'VS' THEN 'BC' ELSE p_grad END),
    'message', format('Optimizovano %s/%s putnika.', v_updated_count, v_total_putnici)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'error', SQLERRM,
    'putnik_count', v_total_putnici,
    'updated_count', v_updated_count
  );
END;
$$;

-- -----------------------------------------------------
-- Optimizacija svih ruta za datum
-- -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_v3_optimize_all_routes_for_date(
  p_datum date
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_route RECORD;
  v_result jsonb;
  v_total_routes integer := 0;
  v_optimized_routes integer := 0;
  v_total_putnika integer := 0;
BEGIN
  FOR v_route IN
    SELECT DISTINCT r.vozac_id, r.grad, r.vreme
    FROM public.v3_gps_raspored r
    WHERE r.datum = p_datum
      AND r.aktivno = true
      AND r.putnik_id IS NOT NULL
    ORDER BY r.vozac_id, r.grad, r.vreme
  LOOP
    v_total_routes := v_total_routes + 1;

    v_result := public.fn_v3_optimize_pickup_route(
      v_route.vozac_id,
      p_datum,
      v_route.grad,
      v_route.vreme
    );

    IF COALESCE((v_result->>'success')::boolean, false) THEN
      v_optimized_routes := v_optimized_routes + 1;
      v_total_putnika := v_total_putnika + COALESCE((v_result->>'updated_count')::int, 0);
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'success', true,
    'datum', p_datum,
    'total_routes_scanned', v_total_routes,
    'total_routes_optimized', v_optimized_routes,
    'total_putnika_optimized', v_total_putnika,
    'message', format('Optimizovano %s/%s ruta, %s pickup tačaka.', v_optimized_routes, v_total_routes, v_total_putnika)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object(
    'success', false,
    'datum', p_datum,
    'error', SQLERRM,
    'total_routes_scanned', v_total_routes,
    'total_routes_optimized', v_optimized_routes,
    'total_putnika_optimized', v_total_putnika
  );
END;
$$;

COMMIT;

-- Provera:
-- SELECT public.fn_v3_optimize_pickup_route(
--   '00000000-0000-0000-0000-000000000000'::uuid,
--   CURRENT_DATE,
--   'BC',
--   '05:00'::time
-- );
--
-- SELECT public.fn_v3_optimize_all_routes_for_date(CURRENT_DATE);
