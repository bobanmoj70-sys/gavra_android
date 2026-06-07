-- Automatski dodeljuje putnika vozacu koji ima slot za taj termin
-- Kad god se novi red doda/azurira u v3_operativna_nedelja,
-- proveri da li postoji aktivni slot i napravi individualnu dodelu

CREATE OR REPLACE FUNCTION auto_assign_termin_to_slot_vozac()
RETURNS TRIGGER AS $$
DECLARE
    slot_vozac_id TEXT;
    putnik_id TEXT;
    vreme_norm TEXT;
    grad_norm TEXT;
BEGIN
    -- Ako je otkazan ili pokupljen, ne dodeljuj
    IF NEW.otkazano_at IS NOT NULL OR NEW.pokupljen_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    putnik_id := NEW.created_by;
    IF putnik_id IS NULL OR putnik_id = '' THEN
        RETURN NEW;
    END IF;

    -- Normalizuj vreme na HH:MM (podrzava i TIME i TIMESTAMP)
    BEGIN
        vreme_norm := TO_CHAR(NEW.polazak_at::time, 'HH24:MI');
    EXCEPTION WHEN OTHERS THEN
        vreme_norm := SUBSTRING(NEW.polazak_at FROM 1 FOR 5);
    END;

    IF vreme_norm IS NULL OR vreme_norm = '' THEN
        BEGIN
            vreme_norm := TO_CHAR(NEW.vreme::time, 'HH24:MI');
        EXCEPTION WHEN OTHERS THEN
            vreme_norm := SUBSTRING(NEW.vreme FROM 1 FOR 5);
        END;
    END IF;

    IF vreme_norm IS NULL OR vreme_norm = '' THEN
        RETURN NEW;
    END IF;

    -- Normalizuj grad na velika slova
    grad_norm := UPPER(COALESCE(NEW.grad, ''));
    IF grad_norm = '' THEN
        RETURN NEW;
    END IF;

    -- Pronadji aktivni slot za ovaj termin
    SELECT vozac_v3_auth_id INTO slot_vozac_id
    FROM v3_trenutna_dodela_slot
    WHERE datum = NEW.datum
      AND grad = grad_norm
      AND vreme = vreme_norm
      AND status = 'aktivan'
    LIMIT 1;

    -- Ako postoji slot, napravi individualnu dodelu
    IF slot_vozac_id IS NOT NULL AND slot_vozac_id != '' THEN
        INSERT INTO v3_trenutna_dodela (termin_id, putnik_v3_auth_id, vozac_v3_auth_id, status)
        VALUES (NEW.id, putnik_id, slot_vozac_id, 'aktivan')
        ON CONFLICT (termin_id)
        DO UPDATE SET
            vozac_v3_auth_id = slot_vozac_id,
            putnik_v3_auth_id = putnik_id,
            status = 'aktivan';
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: posle svakog INSERT/UPDATE na operativna_nedelja
DROP TRIGGER IF EXISTS trg_auto_assign_termin ON v3_operativna_nedelja;
CREATE TRIGGER trg_auto_assign_termin
    AFTER INSERT OR UPDATE ON v3_operativna_nedelja
    FOR EACH ROW
    EXECUTE FUNCTION auto_assign_termin_to_slot_vozac();
