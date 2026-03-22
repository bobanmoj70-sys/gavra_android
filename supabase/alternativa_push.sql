-- =============================================================
-- Push putniku kada zahtev pređe u status ALTERNATIVA
-- =============================================================

CREATE OR REPLACE FUNCTION public.send_push_on_zahtev_alternativa()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  putnik_token text;
  v_title text;
  v_body text;
BEGIN
  IF TG_OP <> 'UPDATE' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.aktivno, true) = false THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'alternativa' AND COALESCE(OLD.status, '') <> 'alternativa' THEN
    SELECT p.push_token
      INTO putnik_token
    FROM public.v3_putnici p
    WHERE p.id = NEW.putnik_id
      AND p.aktivno = true
      AND p.push_token IS NOT NULL
      AND p.push_token <> ''
    LIMIT 1;

    IF putnik_token IS NULL THEN
      RETURN NEW;
    END IF;

    v_title := '⚠️ Termin pun';
    v_body := 'Izaberi alternativni termin';

    PERFORM public.notify_push(
      jsonb_build_array(jsonb_build_object('token', putnik_token, 'provider', 'fcm')),
      v_title,
      v_body,
      jsonb_build_object(
        'type', 'v3_alternativa',
        'id', NEW.id,
        'alt_pre', NEW.alt_vreme_pre,
        'alt_posle', NEW.alt_vreme_posle,
        'title', v_title,
        'body', v_body,
        'status', NEW.status,
        'putnik_id', NEW.putnik_id,
        'grad', NEW.grad,
        'datum', NEW.datum,
        'screen', 'v3_putnik_profil'
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_v3_zahtevi_push_on_alternativa ON public.v3_zahtevi;

CREATE TRIGGER tr_v3_zahtevi_push_on_alternativa
AFTER UPDATE ON public.v3_zahtevi
FOR EACH ROW
EXECUTE FUNCTION public.send_push_on_zahtev_alternativa();
