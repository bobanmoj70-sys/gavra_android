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
  putnik_ime_prezime text;
  efektivno_vreme text;
  termin_opis text;
  v_title text;
  v_body text;
BEGIN
  -- Reaguj samo na update statusa -> odobreno
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'odobreno' AND COALESCE(OLD.status, '') <> 'odobreno' THEN
    SELECT p.push_token, COALESCE(NULLIF(BTRIM(p.ime_prezime), ''), 'putniče')
      INTO putnik_token, putnik_ime_prezime
    FROM public.v3_putnici p
    WHERE p.id = NEW.putnik_id
      AND p.aktivno = true
      AND p.push_token IS NOT NULL
      AND p.push_token <> ''
    LIMIT 1;

    IF putnik_token IS NOT NULL THEN
      efektivno_vreme := COALESCE(
        to_char(NEW.dodeljeno_vreme, 'HH24:MI'),
        to_char(NEW.zeljeno_vreme, 'HH24:MI'),
        ''
      );
      termin_opis := CASE
        WHEN efektivno_vreme <> ''
          THEN format('%s %s u %s', to_char(NEW.datum::date, 'DD.MM.YYYY.'), NEW.grad, efektivno_vreme)
        ELSE format('%s %s', to_char(NEW.datum::date, 'DD.MM.YYYY.'), NEW.grad)
      END;

      v_title := '✅ Zahtev odobren';
      v_body := format('Poštovani %s, Vaš zahtev za termin %s je odobren. Srećan put 😊', putnik_ime_prezime, termin_opis);

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
