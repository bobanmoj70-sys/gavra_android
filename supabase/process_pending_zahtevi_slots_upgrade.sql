-- =====================================================
-- Upgrade dispatcher slots processing:
-- kada nema mesta u zeljenom terminu, pronadji prvo PRE i prvo POSLE
-- i upiši ih u alt_vreme_pre / alt_vreme_posle.
-- Push notifikaciju šalje postojeći trigger tr_v3_zahtevi_push_on_alternativa.
-- =====================================================

CREATE OR REPLACE FUNCTION public.process_pending_zahtevi_slots()
RETURNS TABLE(processed_count integer, approved_count integer, alternative_count integer, log_message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    zahtev_record RECORD;
    current_ts TIMESTAMPTZ := NOW();
    processed INT := 0;
    approved INT := 0;
    alternative INT := 0;
    capacity_check BOOLEAN;
    should_approve BOOLEAN;
    max_kapacitet INTEGER;
    existing_count INTEGER;
    best_alt_pre TIME;
    best_alt_posle TIME;
    alt_reason TEXT;
BEGIN
    FOR zahtev_record IN
        SELECT z.*, p.tip_putnika, p.ime_prezime
        FROM v3_zahtevi z
        JOIN v3_putnici p ON z.putnik_id = p.id
        WHERE z.status = 'obrada'
          AND z.aktivno = true
          AND z.scheduled_at IS NOT NULL
          AND z.scheduled_at <= current_ts
        ORDER BY z.scheduled_at ASC, z.created_at ASC, z.id ASC
        FOR UPDATE OF z SKIP LOCKED
    LOOP
        should_approve := true;
        capacity_check := true;
        best_alt_pre := NULL;
        best_alt_posle := NULL;
        alt_reason := 'Kapacitet popunjen ili slot nedostupan';

        IF zahtev_record.tip_putnika = 'ucenik'
           AND zahtev_record.grad = 'BC'
           AND zahtev_record.datum::date = (CURRENT_DATE + INTERVAL '1 day')::date
           AND zahtev_record.zeljeno_vreme <= '16:00'::TIME THEN
            capacity_check := false;
        ELSIF zahtev_record.tip_putnika = 'posiljka' THEN
            capacity_check := false;
        END IF;

        IF capacity_check THEN
            SELECT ks.max_mesta INTO max_kapacitet
            FROM v3_kapacitet_slots ks
            WHERE ks.grad = zahtev_record.grad
              AND ks.vreme = zahtev_record.zeljeno_vreme
              AND ks.datum = zahtev_record.datum::date
              AND ks.aktivno = true
            LIMIT 1;

            IF max_kapacitet IS NULL THEN
                should_approve := false;
                alt_reason := 'Željeni slot ne postoji u kapacitetima';
            ELSE
                SELECT COUNT(*) INTO existing_count
                FROM v3_operativna_nedelja o
                WHERE o.datum::date = zahtev_record.datum::date
                  AND o.grad = zahtev_record.grad
                  AND COALESCE(o.dodeljeno_vreme, o.zeljeno_vreme) = zahtev_record.zeljeno_vreme
                  AND o.status_final = 'odobreno'
                  AND o.aktivno = true;

                IF existing_count >= max_kapacitet THEN
                    should_approve := false;
                    alt_reason := 'Željeni slot je popunjen';
                END IF;
            END IF;
        END IF;

        processed := processed + 1;

        IF should_approve THEN
            UPDATE v3_zahtevi
            SET
                status = 'odobreno',
                dodeljeno_vreme = zeljeno_vreme,
                alt_vreme_pre = NULL,
                alt_vreme_posle = NULL,
                alt_napomena = NULL,
                updated_at = current_ts,
                updated_by = 'dispecer_slots'
            WHERE id = zahtev_record.id;

            approved := approved + 1;
        ELSE
            IF capacity_check THEN
                WITH usage_by_slot AS (
                    SELECT
                        ks.vreme,
                        ks.max_mesta,
                        COALESCE(occ.used_count, 0) AS used_count
                    FROM v3_kapacitet_slots ks
                    LEFT JOIN (
                        SELECT
                            COALESCE(o.dodeljeno_vreme, o.zeljeno_vreme) AS vreme,
                            COUNT(*)::int AS used_count
                        FROM v3_operativna_nedelja o
                        WHERE o.datum::date = zahtev_record.datum::date
                          AND o.grad = zahtev_record.grad
                          AND o.status_final = 'odobreno'
                          AND o.aktivno = true
                        GROUP BY COALESCE(o.dodeljeno_vreme, o.zeljeno_vreme)
                    ) occ ON occ.vreme = ks.vreme
                    WHERE ks.grad = zahtev_record.grad
                      AND ks.datum = zahtev_record.datum::date
                      AND ks.aktivno = true
                )
                SELECT MAX(vreme)
                INTO best_alt_pre
                FROM usage_by_slot
                WHERE vreme < zahtev_record.zeljeno_vreme
                                    AND vreme >= (zahtev_record.zeljeno_vreme - INTERVAL '180 minutes')
                  AND used_count < max_mesta;

                WITH usage_by_slot AS (
                    SELECT
                        ks.vreme,
                        ks.max_mesta,
                        COALESCE(occ.used_count, 0) AS used_count
                    FROM v3_kapacitet_slots ks
                    LEFT JOIN (
                        SELECT
                            COALESCE(o.dodeljeno_vreme, o.zeljeno_vreme) AS vreme,
                            COUNT(*)::int AS used_count
                        FROM v3_operativna_nedelja o
                        WHERE o.datum::date = zahtev_record.datum::date
                          AND o.grad = zahtev_record.grad
                          AND o.status_final = 'odobreno'
                          AND o.aktivno = true
                        GROUP BY COALESCE(o.dodeljeno_vreme, o.zeljeno_vreme)
                    ) occ ON occ.vreme = ks.vreme
                    WHERE ks.grad = zahtev_record.grad
                      AND ks.datum = zahtev_record.datum::date
                      AND ks.aktivno = true
                )
                SELECT MIN(vreme)
                INTO best_alt_posle
                FROM usage_by_slot
                WHERE vreme > zahtev_record.zeljeno_vreme
                                    AND vreme <= (zahtev_record.zeljeno_vreme + INTERVAL '180 minutes')
                  AND used_count < max_mesta;
            END IF;

            IF best_alt_pre IS NULL AND best_alt_posle IS NULL THEN
                alt_reason := alt_reason || ' - nema slobodnih termina pre/posle';
            END IF;

            UPDATE v3_zahtevi
            SET
                status = 'alternativa',
                alt_vreme_pre = best_alt_pre,
                alt_vreme_posle = best_alt_posle,
                alt_napomena = alt_reason,
                updated_at = current_ts,
                updated_by = 'dispecer_slots'
            WHERE id = zahtev_record.id;

            alternative := alternative + 1;
        END IF;
    END LOOP;

    RETURN QUERY SELECT
        processed,
        approved,
        alternative,
        FORMAT('Obrađeno %s zahteva - %s odobreno, %s alternativa (najbliži pre/posle slot)',
               processed, approved, alternative);
END;
$function$;
