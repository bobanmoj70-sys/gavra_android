-- ============================================================
-- V2 DIGITALNI DISPEČER — SQL funkcija + pg_cron job
-- Zamjenjuje v2PokreniDispecera() u Dart kodu (v2_polasci_service.dart)
-- Pokretati u Supabase SQL Editoru.
-- ============================================================

-- ============================================================
-- 1. GLAVNA FUNKCIJA
-- ============================================================
CREATE OR REPLACE FUNCTION public.v2_pokreni_dispecera()
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_req         record;
  v_kapaciteti  record;
  v_tip         text;
  v_minuta      int;
  v_provera_kap boolean;
  v_ima_mesta   boolean;
  v_zauzeto     int;
  v_max_mesta   int;
  v_novi_status text;
  v_alt1        text;  -- alternativno_vreme_1
  v_alt2        text;  -- alternativno_vreme_2
  v_processed   int := 0;
  v_now         timestamptz := now();
BEGIN

  -- 1. Za svaki pending zahtev (osim dnevnih) po redu kreiranja
  FOR v_req IN
    SELECT
      p.id,
      p.grad,
      p.dan,
      p.zeljeno_vreme,
      p.broj_mesta,
      p.putnik_tabela,
      p.updated_at,
      p.created_at
    FROM v2_polasci p
    WHERE p.status = 'obrada'
      AND p.putnik_tabela != 'v2_dnevni'   -- dnevni uvijek idu na ručnu obradu
    ORDER BY p.created_at ASC
  LOOP

    -- 2. Tip putnika iz tabele
    v_tip := CASE v_req.putnik_tabela
      WHEN 'v2_radnici'  THEN 'radnik'
      WHEN 'v2_ucenici'  THEN 'ucenik'
      WHEN 'v2_posiljke' THEN 'posiljka'
      ELSE 'radnik'
    END;

    -- 3. Pravila čekanja i provjere kapaciteta po gradu/tipu
    IF upper(v_req.grad) = 'BC' THEN
      IF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at) < 16 THEN
        -- BC učenik pre 16h: 5 min, garantovano mjesto (bez provjere)
        v_minuta      := 5;
        v_provera_kap := false;
      ELSIF v_tip = 'ucenik' AND EXTRACT(HOUR FROM v_req.created_at) >= 16 THEN
        -- BC učenik posle 16h: obrađuje se u 20h, SA provjekom
        v_minuta      := 0;   -- uslov je sat, ne minute
        v_provera_kap := true;
      ELSIF v_tip = 'posiljka' THEN
        -- BC pošiljka: 10 min, bez provjeke (ne zauzima mjesto)
        v_minuta      := 10;
        v_provera_kap := false;
      ELSE
        -- BC radnik i ostali: 5 min, SA provjekom
        v_minuta      := 5;
        v_provera_kap := true;
      END IF;
    ELSIF upper(v_req.grad) = 'VS' THEN
      IF v_tip = 'posiljka' THEN
        -- VS pošiljka: 10 min, bez provjeke
        v_minuta      := 10;
        v_provera_kap := false;
      ELSE
        -- VS radnik/učenik: 10 min, SA provjekom
        v_minuta      := 10;
        v_provera_kap := true;
      END IF;
    ELSE
      -- Nepoznat grad: 5 min, SA provjekom
      v_minuta      := 5;
      v_provera_kap := true;
    END IF;

    -- 4. Provjera da li je vrijeme čekanja isteklo
    -- Specijalni slučaj: BC učenik posle 16h → obradi tek u 20h
    IF v_tip = 'ucenik'
       AND upper(v_req.grad) = 'BC'
       AND EXTRACT(HOUR FROM v_req.created_at) >= 16
    THEN
      IF EXTRACT(HOUR FROM v_now) < 20 THEN
        CONTINUE;  -- Još nije 20h, preskoči
      END IF;
    ELSE
      -- Regularni uslov: čekanje u minutama
      IF EXTRACT(EPOCH FROM (v_now - v_req.updated_at)) / 60.0 < v_minuta THEN
        CONTINUE;  -- Još nije dovoljno čekao
      END IF;
    END IF;

    -- 5. Provjera kapaciteta
    IF NOT v_provera_kap
       OR (v_tip = 'ucenik' AND upper(v_req.grad) = 'BC'
           AND EXTRACT(HOUR FROM v_req.created_at) < 16)
    THEN
      v_ima_mesta := true;
    ELSE
      SELECT COALESCE(kp.max_mesta, 8)
        INTO v_max_mesta
        FROM v2_kapacitet_polazaka kp
       WHERE kp.grad = upper(v_req.grad)
         AND kp.vreme = v_req.zeljeno_vreme
         AND kp.aktivan = true
       LIMIT 1;

      IF v_max_mesta IS NULL THEN
        v_max_mesta := 8;
      END IF;

      SELECT COALESCE(SUM(p2.broj_mesta), 0)
        INTO v_zauzeto
        FROM v2_polasci p2
       WHERE p2.grad    = upper(v_req.grad)
         AND p2.dan     = v_req.dan
         AND p2.zeljeno_vreme = v_req.zeljeno_vreme
         AND p2.status  IN ('obrada', 'odobreno')
         AND p2.id     != v_req.id;

      v_ima_mesta := (v_max_mesta - v_zauzeto) >= COALESCE(v_req.broj_mesta, 1);
    END IF;

    -- 6. Odluka i alternativna vremena
    IF v_ima_mesta THEN
      v_novi_status := 'odobreno';
      v_alt1 := NULL;
      v_alt2 := NULL;
    ELSE
      v_novi_status := 'odbijeno';

      -- Alternativa ranije (prvo slobodno prije željenog vremena)
      SELECT kp.vreme::text INTO v_alt1
        FROM v2_kapacitet_polazaka kp
       WHERE kp.grad = upper(v_req.grad)
         AND kp.vreme < v_req.zeljeno_vreme
         AND kp.aktivan = true
         AND (kp.max_mesta - COALESCE((
               SELECT SUM(p3.broj_mesta)
                 FROM v2_polasci p3
                WHERE p3.grad = upper(v_req.grad)
                  AND p3.dan  = v_req.dan
                  AND p3.zeljeno_vreme = kp.vreme
                  AND p3.status IN ('obrada', 'odobreno')
                  AND p3.id  != v_req.id
             ), 0)) >= COALESCE(v_req.broj_mesta, 1)
       ORDER BY kp.vreme DESC
       LIMIT 1;

      -- Alternativa kasnije
      SELECT kp.vreme::text INTO v_alt2
        FROM v2_kapacitet_polazaka kp
       WHERE kp.grad = upper(v_req.grad)
         AND kp.vreme > v_req.zeljeno_vreme
         AND kp.aktivan = true
         AND (kp.max_mesta - COALESCE((
               SELECT SUM(p3.broj_mesta)
                 FROM v2_polasci p3
                WHERE p3.grad = upper(v_req.grad)
                  AND p3.dan  = v_req.dan
                  AND p3.zeljeno_vreme = kp.vreme
                  AND p3.status IN ('obrada', 'odobreno')
                  AND p3.id  != v_req.id
             ), 0)) >= COALESCE(v_req.broj_mesta, 1)
       ORDER BY kp.vreme ASC
       LIMIT 1;
    END IF;

    -- 7. Update statusa
    UPDATE v2_polasci
       SET status           = v_novi_status,
           processed_at     = v_now,
           updated_at       = v_now,
           dodeljeno_vreme  = CASE WHEN v_novi_status = 'odobreno' THEN v_req.zeljeno_vreme ELSE dodeljeno_vreme END,
           alternativno_vreme_1 = v_alt1,
           alternativno_vreme_2 = v_alt2
     WHERE id = v_req.id;

    v_processed := v_processed + 1;

  END LOOP;

  RETURN jsonb_build_object('processed', v_processed, 'ts', v_now);
END;
$$;


-- ============================================================
-- 2. pg_cron JOB — pokreće se svake minute
-- Zahtjeva pg_cron ekstenziju (uključena na Supabase Pro/Team)
-- ============================================================

-- Obriši stari job ako postoji
SELECT cron.unschedule('v2-dispecer')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'v2-dispecer'
);

SELECT cron.schedule(
  'v2-dispecer',
  '* * * * *',   -- svake minute
  $$ SELECT public.v2_pokreni_dispecera() $$
);


-- ============================================================
-- NAPOMENA: Nakon što ovo deployuješ u Supabase, obriši
-- _dispecerTimer iz v2_home_screen.dart i poziv
-- V2PolasciService.v2PokreniDispecera().
-- ============================================================
