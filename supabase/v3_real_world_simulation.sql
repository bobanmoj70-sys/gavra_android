-- ============================================================
-- V3 REAL WORLD SIMULATION - Complete Testing Suite
-- Kompletna simulacija radnog dana sa realnim scenarijima
-- Testira GPS activation schedule funkcionalnost
-- ============================================================

-- ============================================================
-- 1. SIMULACIJA FUNKCIJA: Kreira realan radni dan
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_simulate_workday(
  p_datum date DEFAULT CURRENT_DATE + interval '1 day',
  p_cleanup_before boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_vozac_ana uuid;
  v_vozac_marko uuid;
  v_vozac_jovana uuid;
  v_putnik_1 uuid;
  v_putnik_2 uuid;
  v_putnik_3 uuid;
  v_putnik_4 uuid;
  v_putnik_5 uuid;
  v_termin_count integer := 0;
  v_result jsonb;
BEGIN
  -- Cleanup postojećih test podataka ako je potrebno
  IF p_cleanup_before THEN
    DELETE FROM v3_raspored_termin WHERE datum = p_datum;
    DELETE FROM v3_gps_activation_schedule WHERE datum = p_datum;
  END IF;

  -- Uzmi test vozače (ili kreiraj ako ne postoje)
  SELECT id INTO v_vozac_ana FROM v3_vozaci WHERE ime ILIKE '%ana%' LIMIT 1;
  SELECT id INTO v_vozac_marko FROM v3_vozaci WHERE ime ILIKE '%marko%' LIMIT 1;
  SELECT id INTO v_vozac_jovana FROM v3_vozaci WHERE ime ILIKE '%jovana%' LIMIT 1;
  
  -- Uzmi test putnike
  SELECT id INTO v_putnik_1 FROM v3_putnici LIMIT 1 OFFSET 0;
  SELECT id INTO v_putnik_2 FROM v3_putnici LIMIT 1 OFFSET 1;
  SELECT id INTO v_putnik_3 FROM v3_putnici LIMIT 1 OFFSET 2;
  SELECT id INTO v_putnik_4 FROM v3_putnici LIMIT 1 OFFSET 3;
  SELECT id INTO v_putnik_5 FROM v3_putnici LIMIT 1 OFFSET 4;

  -- SCENARIO 1: Ana vozač - jutnji termin BC sa 3 putnika
  IF v_vozac_ana IS NOT NULL THEN
    INSERT INTO v3_raspored_termin (vozac_id, datum, vreme, grad, putnik_id, aktivno)
    VALUES 
      (v_vozac_ana, p_datum, '07:00'::time, 'BC', v_putnik_1, true),
      (v_vozac_ana, p_datum, '07:00'::time, 'BC', v_putnik_2, true),
      (v_vozac_ana, p_datum, '07:00'::time, 'BC', v_putnik_3, true);
    v_termin_count := v_termin_count + 3;
  END IF;

  -- SCENARIO 2: Marko vozač - popodnevni termin VS sa 2 putnika
  IF v_vozac_marko IS NOT NULL THEN
    INSERT INTO v3_raspored_termin (vozac_id, datum, vreme, grad, putnik_id, aktivno)
    VALUES 
      (v_vozac_marko, p_datum, '14:30'::time, 'VS', v_putnik_4, true),
      (v_vozac_marko, p_datum, '14:30'::time, 'VS', v_putnik_5, true);
    v_termin_count := v_termin_count + 2;
  END IF;

  -- SCENARIO 3: Jovana vozač - večernji termin BC sa 1 putnik
  IF v_vozac_jovana IS NOT NULL THEN
    INSERT INTO v3_raspored_termin (vozac_id, datum, vreme, grad, putnik_id, aktivno)
    VALUES 
      (v_vozac_jovana, p_datum, '18:45'::time, 'BC', v_putnik_1, true);
    v_termin_count := v_termin_count + 1;
  END IF;

  -- SCENARIO 4: Ana vozač - drugi termin VS sa 2 putnika (test multiple terms per vozac)
  IF v_vozac_ana IS NOT NULL THEN
    INSERT INTO v3_raspored_termin (vozac_id, datum, vreme, grad, putnik_id, aktivno)
    VALUES 
      (v_vozac_ana, p_datum, '12:15'::time, 'VS', v_putnik_2, true),
      (v_vozac_ana, p_datum, '12:15'::time, 'VS', v_putnik_3, true);
    v_termin_count := v_termin_count + 2;
  END IF;

  -- Pokreni GPS populate funkciju
  SELECT fn_v3_populate_gps_activation_schedule() INTO v_result;

  RETURN jsonb_build_object(
    'simulation_success', true,
    'datum', p_datum,
    'created_entries', v_termin_count,
    'unique_terms_expected', 4, -- Ana 07:00 BC, Ana 12:15 VS, Marko 14:30 VS, Jovana 18:45 BC
    'gps_populate_result', v_result,
    'vozaci_used', jsonb_build_array(
      coalesce(v_vozac_ana::text, 'ana_not_found'),
      coalesce(v_vozac_marko::text, 'marko_not_found'),
      coalesce(v_vozac_jovana::text, 'jovana_not_found')
    ),
    'timestamp', now()
  );
END;
$$;

-- ============================================================
-- 2. VALIDACIJA FUNKCIJA: Proverava rezultate simulacije
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_validate_simulation(
  p_datum date DEFAULT CURRENT_DATE + interval '1 day'
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_raspored_count integer;
  v_gps_schedule_count integer;
  v_unique_terms integer;
  v_total_putnici integer;
  v_gps_putnici_total integer;
  v_details jsonb;
  v_mismatch_count integer := 0;
  rec record;
BEGIN
  -- Osnovne statistike
  SELECT COUNT(*) INTO v_raspored_count 
  FROM v3_raspored_termin 
  WHERE datum = p_datum AND putnik_id IS NOT NULL;

  SELECT COUNT(*) INTO v_gps_schedule_count 
  FROM v3_gps_activation_schedule 
  WHERE datum = p_datum;

  SELECT COUNT(DISTINCT (vozac_id, vreme, grad)) INTO v_unique_terms
  FROM v3_raspored_termin 
  WHERE datum = p_datum AND putnik_id IS NOT NULL;

  SELECT SUM(putnici_count) INTO v_gps_putnici_total
  FROM v3_gps_activation_schedule 
  WHERE datum = p_datum;

  -- Detaljana validacija po terminima
  v_details := '[]'::jsonb;
  FOR rec IN 
    SELECT 
      rt.vozac_id,
      rt.vreme,
      rt.grad,
      COUNT(*) as raspored_putnici,
      COALESCE(gps.putnici_count, 0) as gps_putnici,
      gps.status as gps_status,
      gps.activation_time
    FROM v3_raspored_termin rt
    LEFT JOIN v3_gps_activation_schedule gps ON (
      gps.vozac_id = rt.vozac_id AND 
      gps.datum = rt.datum AND 
      gps.vreme = rt.vreme AND 
      gps.grad = rt.grad
    )
    WHERE rt.datum = p_datum AND rt.putnik_id IS NOT NULL AND rt.aktivno = true
    GROUP BY rt.vozac_id, rt.vreme, rt.grad, gps.putnici_count, gps.status, gps.activation_time
    ORDER BY rt.vreme
  LOOP
    -- Check for mismatches
    IF rec.raspored_putnici != rec.gps_putnici THEN
      v_mismatch_count := v_mismatch_count + 1;
    END IF;
    
    -- Add to details
    v_details := v_details || jsonb_build_object(
      'vozac_id', rec.vozac_id,
      'vreme', rec.vreme,
      'grad', rec.grad,
      'raspored_putnici', rec.raspored_putnici,
      'gps_putnici', rec.gps_putnici,
      'match', rec.raspored_putnici = rec.gps_putnici,
      'gps_status', rec.gps_status,
      'activation_time', rec.activation_time
    );
  END LOOP;

  RETURN jsonb_build_object(
    'validation_success', v_mismatch_count = 0,
    'datum', p_datum,
    'statistics', jsonb_build_object(
      'raspored_total_entries', v_raspored_count,
      'gps_schedule_entries', v_gps_schedule_count,
      'unique_terms', v_unique_terms,
      'total_putnici_raspored', v_raspored_count,
      'total_putnici_gps', v_gps_putnici_total,
      'mismatch_count', v_mismatch_count
    ),
    'term_details', v_details,
    'validation_passed', v_mismatch_count = 0 AND v_gps_schedule_count = v_unique_terms,
    'timestamp', now()
  );
END;
$$;

-- ============================================================
-- 3. STRESS TEST FUNKCIJA: Testira performance sa velikim brojem termina
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_stress_test_gps(
  p_datum date DEFAULT CURRENT_DATE + interval '1 day',
  p_term_count integer DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_start_time timestamptz;
  v_end_time timestamptz;
  v_duration interval;
  v_vozaci uuid[];
  v_putnici uuid[];
  v_inserted integer := 0;
  i integer;
  v_random_vozac uuid;
  v_random_putnik uuid;
  v_random_time time;
  v_random_grad text;
  v_result jsonb;
BEGIN
  v_start_time := now();
  
  -- Cleanup
  DELETE FROM v3_raspored_termin WHERE datum = p_datum;
  DELETE FROM v3_gps_activation_schedule WHERE datum = p_datum;
  
  -- Get available vozaci and putnici
  SELECT array_agg(id) INTO v_vozaci FROM v3_vozaci LIMIT 10;
  SELECT array_agg(id) INTO v_putnici FROM v3_putnici LIMIT 20;
  
  -- Generate random terms
  FOR i IN 1..p_term_count LOOP
    v_random_vozac := v_vozaci[1 + (random() * (array_length(v_vozaci, 1) - 1))::integer];
    v_random_putnik := v_putnici[1 + (random() * (array_length(v_putnici, 1) - 1))::integer];
    v_random_time := (interval '6 hours' + (random() * interval '12 hours'))::time;
    v_random_grad := CASE WHEN random() < 0.5 THEN 'BC' ELSE 'VS' END;
    
    INSERT INTO v3_raspored_termin (vozac_id, datum, vreme, grad, putnik_id, aktivno)
    VALUES (v_random_vozac, p_datum, v_random_time, v_random_grad, v_random_putnik, true);
    
    v_inserted := v_inserted + 1;
  END LOOP;
  
  -- Run GPS populate
  SELECT fn_v3_populate_gps_activation_schedule() INTO v_result;
  
  v_end_time := now();
  v_duration := v_end_time - v_start_time;
  
  RETURN jsonb_build_object(
    'stress_test_success', true,
    'datum', p_datum,
    'entries_created', v_inserted,
    'execution_time_ms', extract(epoch from v_duration) * 1000,
    'gps_populate_result', v_result,
    'performance_rating', CASE 
      WHEN extract(epoch from v_duration) < 1 THEN 'excellent'
      WHEN extract(epoch from v_duration) < 5 THEN 'good'
      WHEN extract(epoch from v_duration) < 10 THEN 'acceptable'
      ELSE 'needs_optimization'
    END,
    'timestamp', v_end_time
  );
END;
$$;

-- ============================================================
-- 4. COMPREHENSIVE TEST: Kombinuje sve test scenarije
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_comprehensive_test()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_simulation_result jsonb;
  v_validation_result jsonb;
  v_stress_result jsonb;
  v_test_datum date := CURRENT_DATE + interval '1 day';
BEGIN
  -- 1. Run workday simulation
  SELECT fn_v3_simulate_workday(v_test_datum, true) INTO v_simulation_result;
  
  -- 2. Validate simulation results
  SELECT fn_v3_validate_simulation(v_test_datum) INTO v_validation_result;
  
  -- 3. Run stress test
  SELECT fn_v3_stress_test_gps(v_test_datum + interval '1 day', 30) INTO v_stress_result;
  
  RETURN jsonb_build_object(
    'comprehensive_test_success', true,
    'test_datum', v_test_datum,
    'simulation', v_simulation_result,
    'validation', v_validation_result,
    'stress_test', v_stress_result,
    'all_tests_passed', 
      (v_simulation_result->>'simulation_success')::boolean AND
      (v_validation_result->>'validation_passed')::boolean AND
      (v_stress_result->>'stress_test_success')::boolean,
    'timestamp', now()
  );
END;
$$;

-- Usage examples:
-- SELECT fn_v3_simulate_workday();                    -- Basic simulation
-- SELECT fn_v3_validate_simulation();                 -- Validate results
-- SELECT fn_v3_stress_test_gps(CURRENT_DATE + 1, 100); -- Stress test
-- SELECT fn_v3_comprehensive_test();                  -- Complete test suite