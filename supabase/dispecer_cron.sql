-- =====================================================
-- DISPECER CRON - REPAIR / LIVE SYNC
-- =====================================================
-- Ovo je usklađeno sa stvarnim stanjem baze.
-- U bazi već postoje:
--   - fn_v3_dispatcher()
--   - set_zahtev_scheduled_at()
--   - process_pending_zahtevi_slots()
--   - process_pending_zahtevi_v2()
--   - process_pending_zahtevi_final()
--
-- Trenutni problem u bazi:
--   cron job "simple-dispatcher" direktno radi UPDATE i preskače
--   slots/kapacitet logiku. To znači da može odobriti zahtev bez
--   provere kapaciteta i bez alternative.

BEGIN;

-- 1) Kompatibilni wrapper za ručno pokretanje iz SQL editora
CREATE OR REPLACE FUNCTION public.process_pending_zahtevi()
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
    RETURN QUERY SELECT * FROM public.process_pending_zahtevi_slots();
END;
$$;

CREATE OR REPLACE FUNCTION public.manual_process_zahtevi()
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
    RETURN QUERY SELECT * FROM public.process_pending_zahtevi_slots();
END;
$$;

-- 2) Pregled zahteva koji čekaju obradu
CREATE OR REPLACE FUNCTION public.get_pending_zahtevi_status()
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
            WHEN z.scheduled_at > NOW() THEN EXTRACT(EPOCH FROM (z.scheduled_at - NOW()))::INTEGER / 60
            ELSE 0
        END AS remaining_minutes
    FROM v3_zahtevi z
    JOIN v3_putnici p ON p.id = z.putnik_id
    WHERE z.status = 'obrada'
      AND z.aktivno = true
    ORDER BY z.scheduled_at ASC;
END;
$$;

-- 3) Zamena postojećeg cron job-a sa ispravnom logikom
DO $$
DECLARE
    old_job_id INT;
BEGIN
    SELECT jobid
    INTO old_job_id
    FROM cron.job
    WHERE jobname = 'simple-dispatcher';

    IF old_job_id IS NOT NULL THEN
        PERFORM cron.unschedule(old_job_id);
    END IF;
END $$;

SELECT cron.schedule(
    'dispecer-slots',
    '*/1 * * * *',
    'SELECT * FROM public.process_pending_zahtevi();'
);

COMMIT;

-- Provera:
-- SELECT * FROM cron.job ORDER BY jobid;
-- SELECT * FROM public.get_pending_zahtevi_status();
-- SELECT * FROM public.manual_process_zahtevi();