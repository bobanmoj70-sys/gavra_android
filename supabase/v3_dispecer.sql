-- ============================================================
-- V3 DIGITALNI DISPEČER — SQL funkcija + pg_cron job
-- Zamjenjuje v2_pokreni_dispecera() za V3 arhitekturu
-- Pokretati u Supabase SQL Editoru.
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
  v_alt1        text;
  v_alt2        text;
  v_processed   int := 0;
  v_now         timestamptz := now();
BEGIN

  -- 1. Za svaki zahtev na 'obradi' (osim dnevnih) po redu kreiranja
  FOR v_req IN
    SELECT
      z.id,
      z.grad,
      z.datum,
      z.dan_u_sedmici,
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
      AND p.tip_putnika != 'dnevni'   -- dnevni uvijek idu na ručnu obradu (Bojan)
    ORDER BY z.created_at ASC
  LOOP

    v_tip := lower(v_req.tip_putnika);

    -- 2. Pravila čekanja i provjere kapaciteta po gradu/tipu
    IF upper(v_req.grad) = 'BC' THEN
      IF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at) < 16 THEN
        -- BC učenik pre 16h: 5 min, garantovano mjesto (bez provjere)
        v_minuta      := 5;
        v_provera_kap := false;
      ELSIF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at) >= 16 THEN
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

    -- 3. Provjera da li je vrijeme čekanja isteklo
    -- Specijalni slučaj: BC učenik posle 16h → obradi tek u 20h
    IF v_tip = 'ucenik'
       AND upper(v_req.grad) = 'BC'
       AND EXTRACT(HOUR FROM v_req.created_at) >= 16
    THEN
      IF EXTRACT(HOUR FROM v_now) < 20 THEN
        CONTINUE;  -- Još nije 20h, preskoči
      END IF;
    ELSE
      IF EXTRACT(EPOCH FROM (v_now - v_req.updated_at)) / 60.0 < v_minuta THEN
        CONTINUE;  -- Još nije dovoljno čekao
      END IF;
    END IF;

    -- 4. Provjera kapaciteta (dinamički — bez default vrijednosti)
    IF NOT v_provera_kap THEN
      v_ima_mesta := true;
    ELSE
      -- Kapacitet čitamo iz v3_app_settings (kapacitet_bc ili kapacitet_vs)
      SELECT CASE WHEN upper(v_req.grad) = 'BC' THEN kapacitet_bc ELSE kapacitet_vs END
        INTO v_max_mesta
      FROM v3_app_settings WHERE id = 'global';

      -- Ako settings nije definisan, preskoči
      IF v_max_mesta IS NULL THEN
        CONTINUE;
      END IF;

      -- Zauzetost: suma svih aktivnih mesta u operativnom planu za isti datum/grad/vreme
      -- Koristimo v3_operativna_nedelja jer tamo idu i zahtevi (preko trigera) i ručni unosi
      SELECT COALESCE(SUM(op.broj_mesta), 0) INTO v_zauzeto
      FROM v3_operativna_nedelja op
      WHERE op.grad         = v_req.grad
        AND op.datum        = v_req.datum
        AND op.vreme        = v_req.zeljeno_vreme
        AND op.status_final IN ('obrada', 'odobreno', 'pokupljen')
        AND op.izvor_id     != v_req.id
        AND op.aktivno      = true;

      v_ima_mesta := (v_max_mesta - v_zauzeto) >= COALESCE(v_req.broj_mesta, 1);
    END IF;

    -- 5. Odluka i traženje alternativnih termina
    IF v_ima_mesta THEN
      v_novi_status := 'odobreno';
      v_alt1 := NULL;
      v_alt2 := NULL;
    ELSE
      v_novi_status := 'odbijeno';

      -- Alternativa ranije (prvo slobodno prije željenog vremena)
      SELECT op_alt1.vreme INTO v_alt1
      FROM (
        SELECT DISTINCT ON (vreme) vreme
        FROM v3_operativna_nedelja
        WHERE grad    = v_req.grad
          AND datum   = v_req.datum
          AND vreme   < v_req.zeljeno_vreme
          AND aktivno = true
      ) op_alt1
      WHERE ((SELECT CASE WHEN upper(v_req.grad) = 'BC' THEN kapacitet_bc ELSE kapacitet_vs END
                FROM v3_app_settings WHERE id = 'global') - COALESCE((
              SELECT SUM(op2.broj_mesta)
              FROM v3_operativna_nedelja op2
              WHERE op2.grad         = v_req.grad
                AND op2.datum        = v_req.datum
                AND op2.vreme        = op_alt1.vreme
                AND op2.status_final IN ('obrada', 'odobreno', 'pokupljen')
                AND op2.izvor_id     != v_req.id
                AND op2.aktivno      = true
            ), 0)) >= COALESCE(v_req.broj_mesta, 1)
      ORDER BY op_alt1.vreme DESC
      LIMIT 1;

      -- Alternativa kasnije (prvo slobodno posle željenog vremena)
      SELECT op_alt2.vreme INTO v_alt2
      FROM (
        SELECT DISTINCT ON (vreme) vreme
        FROM v3_operativna_nedelja
        WHERE grad    = v_req.grad
          AND datum   = v_req.datum
          AND vreme   > v_req.zeljeno_vreme
          AND aktivno = true
      ) op_alt2
      WHERE ((SELECT CASE WHEN upper(v_req.grad) = 'BC' THEN kapacitet_bc ELSE kapacitet_vs END
                FROM v3_app_settings WHERE id = 'global') - COALESCE((
              SELECT SUM(op3.broj_mesta)
              FROM v3_operativna_nedelja op3
              WHERE op3.grad         = v_req.grad
                AND op3.datum        = v_req.datum
                AND op3.vreme        = op_alt2.vreme
                AND op3.status_final IN ('obrada', 'odobreno', 'pokupljen')
                AND op3.izvor_id     != v_req.id
                AND op3.aktivno      = true
            ), 0)) >= COALESCE(v_req.broj_mesta, 1)
      ORDER BY op_alt2.vreme ASC
      LIMIT 1;
    END IF;

    -- 6. Update statusa zahteva
    UPDATE v3_zahtevi
    SET status          = v_novi_status,
        dodeljeno_vreme = CASE WHEN v_novi_status = 'odobreno' THEN v_req.zeljeno_vreme ELSE NULL END,
        updated_at      = v_now
    WHERE id = v_req.id;

    -- 7. Audit log u v3_audit_log
    INSERT INTO v3_audit_log
      (tip, aktor_ime, aktor_tip, putnik_id, putnik_ime, dan, grad, vreme, polazak_id, detalji, created_at)
    VALUES (
      CASE WHEN v_novi_status = 'odobreno' THEN 'dispecer_odobrio' ELSE 'dispecer_odbio' END,
      'sistem',
      'sistem',
      v_req.putnik_id,
      v_req.ime_prezime,
      v_req.dan_u_sedmici,
      v_req.grad,
      v_req.zeljeno_vreme,
      v_req.id,
      CASE
        WHEN v_novi_status = 'odobreno' THEN
          'Sistem odobrio: ' || v_req.grad || ' ' || v_req.zeljeno_vreme
        ELSE
          'Sistem odbio (puno): ' || v_req.grad || ' ' || v_req.zeljeno_vreme
          || COALESCE(' | alt1=' || v_alt1, '')
          || COALESCE(' | alt2=' || v_alt2, '')
      END,
      v_now
    );

    v_processed := v_processed + 1;

  END LOOP;

  RETURN jsonb_build_object('obradjeno_v3', v_processed, 'vreme', v_now);
END;
$$;


-- ============================================================
-- 2. pg_cron JOB — pokreće se svake minute
-- Zahtjeva pg_cron ekstenziju (uključena na Supabase Pro/Team)
-- ============================================================

-- Obriši stari job ako postoji
SELECT cron.unschedule('v3-dispecer')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v3-dispecer'
);

SELECT cron.schedule(
  'v3-dispecer',
  '* * * * *',   -- svake minute
  $$ SELECT public.fn_v3_pokreni_dispecera() $$
);
