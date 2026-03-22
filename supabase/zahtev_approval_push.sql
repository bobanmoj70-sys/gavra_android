-- =============================================================
-- Instant push notifikacija putniku kada zahtev postane ODOBRENO
-- =============================================================

-- Funkcija: šalje push samo kada status pređe u 'odobreno'
CREATE OR REPLACE FUNCTION public.send_push_on_zahtev_approved()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  putnik_token text;
  efektivno_vreme text;
  v_title text;
  v_body text;
BEGIN
  -- Reaguj samo na update statusa -> odobreno
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'odobreno' AND COALESCE(OLD.status, '') <> 'odobreno' THEN
    SELECT p.push_token
      INTO putnik_token
    FROM public.v3_putnici p
    WHERE p.id = NEW.putnik_id
      AND p.aktivno = true
      AND p.push_token IS NOT NULL
      AND p.push_token <> ''
    LIMIT 1;

    IF putnik_token IS NOT NULL THEN
      efektivno_vreme := COALESCE(NULLIF(NEW.dodeljeno_vreme, ''), NULLIF(NEW.zeljeno_vreme, ''), '');

      v_title := '✅ Zahtev odobren';
      v_body := CASE
        WHEN efektivno_vreme <> ''
          THEN format('Vaš termin za %s u %s je odobren.', NEW.grad, efektivno_vreme)
        ELSE format('Vaš termin za %s je odobren.', NEW.grad)
      END;

      PERFORM public.notify_push(
        jsonb_build_array(jsonb_build_object('token', putnik_token, 'provider', 'fcm')),
        v_title,
        v_body,
        jsonb_build_object(
          'type', 'v3_zahtev_odobren',
          'zahtev_id', NEW.id,
          'putnik_id', NEW.putnik_id,
          'datum', NEW.datum,
          'grad', NEW.grad,
          'vreme', efektivno_vreme,
          'status', NEW.status,
          'screen', 'v3_putnik_profil'
        )
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_v3_zahtevi_push_on_approved ON public.v3_zahtevi;

CREATE TRIGGER tr_v3_zahtevi_push_on_approved
AFTER UPDATE ON public.v3_zahtevi
FOR EACH ROW
EXECUTE FUNCTION public.send_push_on_zahtev_approved();
