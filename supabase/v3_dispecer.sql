-- ============================================================
-- V3 DIGITALNI DISPEČER — SQL funkcija + pg_cron job
-- Zamjenjuje v2_pokreni_dispecera() za V3 arhitekturu
-- AŽURIRANO: vreme kolona u audit_log je time (ne text), v_alt1/v_alt2 su time
-- ============================================================

-- ============================================================
-- 1. GLAVNA FUNKCIJA
-- ============================================================
CREATE OR REPLACE FUNCTION public.fn_v3_pokreni_dispecera()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_req         record;
  v_tip         text;
  v_minuta      int;
  v_provera_kap boolean;
  v_ima_mesta   boolean;
  v_zauzeto     int;
  v_max_mesta   int;
  v_novi_status text;
  v_alt1        time;
  v_alt2        time;
  v_processed   int := 0;
  v_now         timestamptz := now();
BEGIN

  -- Za svaki zahtev na 'obrada' (osim dnevnih) po redu kreiranja
  FOR v_req IN
    SELECT
      z.id,
      z.grad,
      z.datum,
      z.zeljeno_vreme,
      z.broj_mesta,
      z.putnik_id,
      z.ime_prezime,
      z.updated_at,
      z.created_at,
      p.tip_putnika
    FROM v3_zahtevi z
    JOIN v3_putnici p ON z.putnik_id = p.id
    WHERE z.status = 'obrada'
      AND z.aktivno = true
      AND p.tip_putnika != 'dnevni'
    ORDER BY z.created_at ASC
  LOOP

    v_tip := lower(v_req.tip_putnika);

    -- Pravila čekanja i provjere kapaciteta
    IF upper(v_req.grad) = 'BC' THEN
      IF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at AT TIME ZONE 'Europe/Belgrade') < 16 THEN
        -- BC učenik pre 16h: 5 min, garantovano mjesto (bez provjere)
        v_minuta      := 5;
        v_provera_kap := false;
      ELSIF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at AT TIME ZONE 'Europe/Belgrade') >= 16 THEN
        -- BC učenik posle 16h: obrađuje se u 20h, SA provjerom kapaciteta
        v_minuta      := 0;
        v_provera_kap := true;
      ELSIF v_tip = 'posiljka' THEN
        -- BC pošiljka: 10 min, bez provjere (ne zauzima putničko mjesto)
        v_minuta      := 10;
        v_provera_kap := false;
      ELSE
        -- BC radnik i ostali: 5 min, SA provjerom
        v_minuta      := 5;
        v_provera_kap := true;
      END IF;
    ELSIF upper(v_req.grad) = 'VS' THEN
      IF v_tip = 'posiljka' THEN
        -- VS pošiljka: 10 min, bez provjere
        v_minuta      := 10;
        v_provera_kap := false;
      ELSE
        -- VS radnik/učenik: 10 min, SA provjerom
        v_minuta      := 10;
        v_provera_kap := true;
      END IF;
    ELSE
      -- Nepoznat grad: 5 min, SA provjerom
      v_minuta      := 5;
      v_provera_kap := true;
    END IF;

    -- Provjera vremena čekanja
    -- Specijalni slučaj: BC učenik posle 16h → obradi tek u 20h
    IF v_tip = 'ucenik'
       AND upper(v_req.grad) = 'BC'
       AND EXTRACT(HOUR FROM v_req.created_at AT TIME ZONE 'Europe/Belgrade') >= 16
    THEN
      IF EXTRACT(HOUR FROM v_now AT TIME ZONE 'Europe/Belgrade') < 20 THEN
        CONTINUE;
      END IF;
    ELSE
      IF EXTRACT(EPOCH FROM (v_now - v_req.updated_at)) / 60.0 < v_minuta THEN
        CONTINUE;
      END IF;
    END IF;

    -- Provjera kapaciteta iz v3_kapacitet_slots (po grad + vreme + datum)
    IF NOT v_provera_kap THEN
      v_ima_mesta := true;
    ELSE
      SELECT ks.max_mesta INTO v_max_mesta
      FROM v3_kapacitet_slots ks
      WHERE ks.grad    = v_req.grad
        AND ks.vreme   = v_req.zeljeno_vreme
        AND ks.datum   = v_req.datum
        AND ks.aktivno = true
      LIMIT 1;

      -- Ako slot nije definisan, preskoči (vozač još nije postavio kapacitet)
      IF v_max_mesta IS NULL THEN
        CONTINUE;
      END IF;

      -- Zauzetost: suma aktivnih mesta u operativnom planu za isti grad/vreme/datum
      SELECT COALESCE(SUM(op.broj_mesta), 0) INTO v_zauzeto
      FROM v3_operativna_nedelja op
      WHERE op.grad         = v_req.grad
        AND op.datum        = v_req.datum
        AND op.vreme::text  = v_req.zeljeno_vreme::text
        AND op.status_final IN ('obrada', 'odobreno', 'pokupljen')
        AND op.aktivno      = true;

      v_ima_mesta := (v_max_mesta - v_zauzeto) >= COALESCE(v_req.broj_mesta, 1);
    END IF;

    -- Odluka i traženje alternativnih termina
    IF v_ima_mesta THEN
      v_novi_status := 'odobreno';
      v_alt1 := NULL;
      v_alt2 := NULL;
    ELSE
      v_novi_status := 'odbijeno';

      -- Alternativa ranije — prethodni slobodan slot iz kapacitet_slots
      SELECT ks.vreme INTO v_alt1
      FROM v3_kapacitet_slots ks
      WHERE ks.grad    = v_req.grad
        AND ks.datum   = v_req.datum
        AND ks.vreme   < v_req.zeljeno_vreme
        AND ks.aktivno = true
        AND (ks.max_mesta - COALESCE((
              SELECT SUM(op2.broj_mesta)
              FROM v3_operativna_nedelja op2
              WHERE op2.grad         = v_req.grad
                AND op2.datum        = v_req.datum
                AND op2.vreme::text  = ks.vreme::text
                AND op2.status_final IN ('obrada', 'odobreno', 'pokupljen')
                AND op2.aktivno      = true
            ), 0)) >= COALESCE(v_req.broj_mesta, 1)
      ORDER BY ks.vreme DESC
      LIMIT 1;

      -- Alternativa kasnije — sljedeći slobodan slot
      SELECT ks.vreme INTO v_alt2
      FROM v3_kapacitet_slots ks
      WHERE ks.grad    = v_req.grad
        AND ks.datum   = v_req.datum
        AND ks.vreme   > v_req.zeljeno_vreme
        AND ks.aktivno = true
        AND (ks.max_mesta - COALESCE((
              SELECT SUM(op3.broj_mesta)
              FROM v3_operativna_nedelja op3
              WHERE op3.grad         = v_req.grad
                AND op3.datum        = v_req.datum
                AND op3.vreme::text  = ks.vreme::text
                AND op3.status_final IN ('obrada', 'odobreno', 'pokupljen')
                AND op3.aktivno      = true
            ), 0)) >= COALESCE(v_req.broj_mesta, 1)
      ORDER BY ks.vreme ASC
      LIMIT 1;
    END IF;

    -- Update statusa zahteva
    UPDATE v3_zahtevi
    SET status          = v_novi_status,
        dodeljeno_vreme = CASE WHEN v_novi_status = 'odobreno' THEN v_req.zeljeno_vreme ELSE NULL END,
        alt_vreme_pre   = CASE WHEN v_novi_status = 'odbijeno' THEN v_alt1 ELSE NULL END,
        alt_vreme_posle = CASE WHEN v_novi_status = 'odbijeno' THEN v_alt2 ELSE NULL END,
        updated_at      = v_now
    WHERE id = v_req.id;

    -- Audit log
    INSERT INTO v3_audit_log
      (tip, aktor_ime, aktor_tip, putnik_id, putnik_ime, datum, grad, vreme, polazak_id, detalji, created_at)
    VALUES (
      CASE WHEN v_novi_status = 'odobreno' THEN 'dispecer_odobrio' ELSE 'dispecer_odbio' END,
      'sistem',
      'sistem',
      v_req.putnik_id,
      v_req.ime_prezime,
      v_req.datum,
      v_req.grad,
      v_req.zeljeno_vreme,
      v_req.id,
      CASE
        WHEN v_novi_status = 'odobreno' THEN
          'Sistem odobrio: ' || v_req.grad || ' ' || v_req.zeljeno_vreme::text || ' (' || v_req.datum::text || ')'
        ELSE
          'Sistem odbio (puno): ' || v_req.grad || ' ' || v_req.zeljeno_vreme::text || ' (' || v_req.datum::text || ')'
          || COALESCE(' | alt1=' || v_alt1::text, '')
          || COALESCE(' | alt2=' || v_alt2::text, '')
      END,
      v_now
    );

    v_processed := v_processed + 1;

  END LOOP;

  RETURN jsonb_build_object('obradjeno_v3', v_processed, 'vreme', v_now, 'status', 'success');
END;
$$;


-- ============================================================
-- 2. pg_cron JOB — pokreće se svake minute
-- Zahtjeva pg_cron ekstenziju (uključena na Supabase Pro/Team)
-- ============================================================

SELECT cron.unschedule('v3-dispecer')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-dispecer'
);

SELECT cron.schedule(
  'v3-dispecer',
  '* * * * *',   -- svake minute
  $$ SELECT public.fn_v3_pokreni_dispecera() $$
);