-- =====================================================
-- DISPECER CRON JOB - Automatska obrada zahteva
-- =====================================================
-- Kreiran: 2026-03-22
-- Funkcionalnost: Automatski procesira zahteve prema dispecer pravilima

-- ── 1. FUNKCIJA ZA OBRADU ZAHTEVA ──────────────────────
CREATE OR REPLACE FUNCTION process_pending_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    zahtev_record RECORD;
    putnik_record RECORD;
    cekanje_minuta INTEGER;
    current_time TIMESTAMPTZ := NOW();
    processed INT := 0;
    approved INT := 0;
    alternative INT := 0;
    capacity_check BOOLEAN;
    should_approve BOOLEAN;
BEGIN
    -- Procesiramo sve zahteve koji čekaju obradu i kojima je vreme isteklo
    FOR zahtev_record IN 
        SELECT z.*, p.tip_putnika, p.ime_prezime
        FROM v3_zahtevi z
        JOIN v3_putnici p ON z.putnik_id = p.id
        WHERE z.status = 'obrada'
          AND z.aktivno = true
          AND z.scheduled_at IS NOT NULL
          AND z.scheduled_at <= current_time
    LOOP
        -- Primeni dispecer pravila čekanja
        IF zahtev_record.tip_putnika = 'ucenik' AND zahtev_record.grad = 'BC' THEN
            -- Učenik BC: proveravamo da li je za sutra do 16h
            IF zahtev_record.datum = CURRENT_DATE + INTERVAL '1 day' 
               AND zahtev_record.zeljeno_vreme <= '16:00'::TIME THEN
                cekanje_minuta := 5;
                capacity_check := false; -- Garantovano
            ELSE
                cekanje_minuta := 10;
                capacity_check := true;
            END IF;
        ELSIF zahtev_record.tip_putnika = 'radnik' AND zahtev_record.grad = 'BC' THEN
            cekanje_minuta := 5;
            capacity_check := true;
        ELSIF zahtev_record.tip_putnika IN ('ucenik', 'radnik') AND zahtev_record.grad = 'VS' THEN
            cekanje_minuta := 10;
            capacity_check := true;
        ELSIF zahtev_record.tip_putnika = 'posiljka' THEN
            cekanje_minuta := 10;
            capacity_check := false; -- Ne zauzima mesta
        ELSIF zahtev_record.tip_putnika = 'dnevni' THEN
            -- Dnevni putnici nikad automatski - admin ručno
            CONTINUE;
        ELSE
            -- Default fallback
            cekanje_minuta := 10;
            capacity_check := true;
        END IF;

        should_approve := true;

        -- Proveravamo kapacitet ako je potrebno
        IF capacity_check THEN
            -- Jednostavna provera: da li već ima više od 8 putnika za to vreme
            -- (ovo možeš proširiti sa kompleksnijom logikom)
            DECLARE
                existing_count INTEGER;
            BEGIN
                SELECT COUNT(*)
                INTO existing_count
                FROM v3_gps_raspored gr
                WHERE gr.datum = zahtev_record.datum
                  AND gr.grad = zahtev_record.grad
                  AND gr.vreme = zahtev_record.zeljeno_vreme
                  AND gr.aktivno = true;
                
                IF existing_count >= 8 THEN
                    should_approve := false;
                END IF;
            END;
        END IF;

        processed := processed + 1;

        IF should_approve THEN
            -- ODOBRI ZAHTEV
            UPDATE v3_zahtevi 
            SET 
                status = 'odobreno',
                dodeljeno_vreme = zeljeno_vreme,
                updated_at = current_time,
                updated_by = 'dispecer_cron'
            WHERE id = zahtev_record.id;

            approved := approved + 1;

            -- Kreiraj termin u GPS rasporedu
            INSERT INTO v3_gps_raspored (
                putnik_id,
                vozac_id,
                datum,
                grad,
                vreme,
                nav_bar_type,
                aktivno,
                gps_status,
                created_by
            ) VALUES (
                zahtev_record.putnik_id,
                NULL, -- Vozač će biti dodeljen kasnije
                zahtev_record.datum,
                zahtev_record.grad,
                zahtev_record.zeljeno_vreme,
                'zimski', -- Default, možeš proširiti logiku
                true,
                'pending',
                'dispecer_cron'
            );

        ELSE
            -- PONUDI ALTERNATIVU
            DECLARE
                alt_pre TIME;
                alt_posle TIME;
            BEGIN
                -- Generiši alternative vremena (15 min pre/posle)
                alt_pre := zahtev_record.zeljeno_vreme - INTERVAL '15 minutes';
                alt_posle := zahtev_record.zeljeno_vreme + INTERVAL '15 minutes';

                UPDATE v3_zahtevi 
                SET 
                    status = 'alternativa',
                    alt_vreme_pre = alt_pre,
                    alt_vreme_posle = alt_posle,
                    alt_napomena = 'Automatska ponuda - kapacitet popunjen za željeno vreme',
                    updated_at = current_time,
                    updated_by = 'dispecer_cron'
                WHERE id = zahtev_record.id;

                alternative := alternative + 1;
            END;
        END IF;

    END LOOP;

    -- Vratimo rezultate
    RETURN QUERY SELECT 
        processed,
        approved,
        alternative,
        FORMAT('Obrađeno %s zahteva - %s odobreno, %s alternativa', 
               processed, approved, alternative);
END;
$$;

-- ── 2. CRON JOB SETUP ─────────────────────────────────
-- Omogući pg_cron extension (potrebno admin privilegije)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Паметан cron - покреће се само када има захтева за обраду
-- SELECT cron.schedule(
--     'dispecer-smart',
--     '*/5 * * * *',
--     $$ DO $$ BEGIN
--         IF EXISTS (SELECT 1 FROM v3_zahtevi WHERE aktivno=true AND status='obrada' AND scheduled_at IS NOT NULL AND scheduled_at<=NOW()) THEN
--             PERFORM process_pending_zahtevi_slots();
--         END IF;
--     END $$; $$
-- );

-- ── 3. HELPER FUNKCIJE ───────────────────────────────
-- Funkcija za manuelno pokretanje dispecer obrade
CREATE OR REPLACE FUNCTION manual_process_zahtevi()
RETURNS TABLE (
    processed_count INT,
    approved_count INT,
    alternative_count INT,
    log_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY SELECT * FROM process_pending_zahtevi();
END;
$$;

-- Funkcija za pregled pending zahteva
CREATE OR REPLACE FUNCTION get_pending_zahtevi_status()
RETURNS TABLE (
    zahtev_id UUID,
    putnik_ime TEXT,
    tip_putnika TEXT,
    datum DATE,
    grad TEXT,
    zeljeno_vreme TIME,
    created_at TIMESTAMPTZ,
    scheduled_at TIMESTAMPTZ,
    remaining_minutes INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY 
    SELECT 
        z.id,
        p.ime_prezime,
        p.tip_putnika,
        z.datum,
        z.grad,
        z.zeljeno_vreme,
        z.created_at,
        z.scheduled_at,
        CASE 
            WHEN z.scheduled_at > NOW() THEN 
                EXTRACT(EPOCH FROM (z.scheduled_at - NOW()))::INTEGER / 60
            ELSE 0
        END as remaining_minutes
    FROM v3_zahtevi z
    JOIN v3_putnici p ON z.putnik_id = p.id
    WHERE z.status = 'obrada' 
      AND z.aktivno = true
    ORDER BY z.scheduled_at ASC;
END;
$$;

-- ══════════════════════════════════════════════════════
-- USAGE EXAMPLES:
-- ══════════════════════════════════════════════════════
-- 
-- 1. Manuelno pokreni dispecer obradu:
-- SELECT * FROM manual_process_zahtevi();
--
-- 2. Pregled pending zahteva:
-- SELECT * FROM get_pending_zahtevi_status();
--
-- 3. Setup паметан cron job (admin) - покреће се само када има посла:
-- SELECT cron.schedule('dispecer', '*/5 * * * *', $$ DO $$ BEGIN IF EXISTS (SELECT 1 FROM v3_zahtevi WHERE aktivno=true AND status='obrada' AND scheduled_at IS NOT NULL AND scheduled_at<=NOW()) THEN PERFORM process_pending_zahtevi_slots(); END IF; END $$; $$);
--
-- 4. Pregled cron job-ova:
-- SELECT * FROM cron.job;
--
-- 5. Ukloni cron job:
-- SELECT cron.unschedule('dispecer-auto-process');
-- ══════════════════════════════════════════════════════