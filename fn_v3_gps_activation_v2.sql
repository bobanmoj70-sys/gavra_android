-- ===================================================================
-- NOVA GPS FUNKCIJA - fn_v3_populate_gps_activation_schedule_v2
-- Čita iz v3_gps_raspored umesto iz starih tabela
-- ===================================================================

CREATE OR REPLACE FUNCTION public.fn_v3_populate_gps_activation_schedule_v2()
RETURNS JSON AS $$
DECLARE
  v_current_ts TIMESTAMP WITH TIME ZONE := now();
  v_datum DATE;
  v_vozac_termin RECORD;
  v_polazak_ts TIMESTAMP WITH TIME ZONE;
  v_aktivacija_ts TIMESTAMP WITH TIME ZONE;
  v_putnici_count INTEGER;
  v_current_nav_type TEXT;
  v_processed_count INTEGER := 0;
  v_inserted_count INTEGER := 0;
  v_updated_count INTEGER := 0;
BEGIN
  RAISE NOTICE '[GPS_V2] Starting GPS activation schedule population at %', v_current_ts;
  
  -- Čita trenutni nav_bar_type iz settings
  SELECT nav_bar_type INTO v_current_nav_type 
  FROM public.v3_app_settings 
  WHERE id = 'global';
  
  IF v_current_nav_type IS NULL THEN
    v_current_nav_type := 'zimski'; -- Default fallback
    RAISE WARNING '[GPS_V2] nav_bar_type not found in settings, using default: %', v_current_nav_type;
  ELSE
    RAISE NOTICE '[GPS_V2] Using nav_bar_type: %', v_current_nav_type;
  END IF;

  -- Process next 3 days
  FOR i IN 0..2 LOOP
    v_datum := CURRENT_DATE + (i || ' days')::interval;
    RAISE NOTICE '[GPS_V2] Processing date: %', v_datum;
    
    -- NOVA LOGIKA: GROUP BY vozac_id per termin iz v3_gps_raspored
    FOR v_vozac_termin IN 
      SELECT 
        vozac_id, 
        grad, 
        vreme, 
        COUNT(*) as putnici_count,
        MIN(polazak_vreme) as polazak_vreme,
        MIN(activation_time) as activation_time
      FROM public.v3_gps_raspored 
      WHERE datum = v_datum 
        AND nav_bar_type = v_current_nav_type 
        AND aktivno = true
      GROUP BY vozac_id, grad, vreme
      HAVING COUNT(*) > 0
      ORDER BY vreme, grad, vozac_id
    LOOP
      v_processed_count := v_processed_count + 1;
      
      -- Use pre-computed timestamps from trigger
      v_polazak_ts := v_vozac_termin.polazak_vreme;
      v_aktivacija_ts := v_vozac_termin.activation_time;
      v_putnici_count := v_vozac_termin.putnici_count;
      
      RAISE DEBUG '[GPS_V2] Processing vozac: %, termin: % % %, putnici: %', 
        v_vozac_termin.vozac_id, v_datum, v_vozac_termin.grad, v_vozac_termin.vreme, v_putnici_count;
      
      -- Insert/Update v3_gps_activation_schedule
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
        v_vozac_termin.vozac_id,
        v_datum,
        v_vozac_termin.vreme,
        v_vozac_termin.grad,
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
      
      -- Track changes
      IF FOUND THEN
        v_updated_count := v_updated_count + 1;
      ELSE
        v_inserted_count := v_inserted_count + 1;
      END IF;
      
    END LOOP;
  END LOOP;

  RAISE NOTICE '[GPS_V2] Completed: processed=%, inserted=%, updated=%', 
    v_processed_count, v_inserted_count, v_updated_count;

  RETURN json_build_object(
    'success', true,
    'processed_count', v_processed_count,
    'inserted_count', v_inserted_count, 
    'updated_count', v_updated_count,
    'nav_bar_type', v_current_nav_type,
    'processed_at', v_current_ts
  );

EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING '[GPS_V2] Error: % - %', SQLSTATE, SQLERRM;
    RETURN json_build_object(
      'success', false,
      'error', SQLERRM,
      'sqlstate', SQLSTATE
    );
END;
$$ LANGUAGE plpgsql;