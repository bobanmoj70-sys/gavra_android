-- =============================================================
-- Push Bojanu kada stigne novi PIN zahtev
-- =============================================================

CREATE OR REPLACE FUNCTION public.send_push_to_bojan_on_new_pin_request()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  bojan_token text;
  putnik_ime text;
  v_title text;
  v_body text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.aktivno, true) = false THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.status, '') <> 'ceka' THEN
    RETURN NEW;
  END IF;

  SELECT p.ime_prezime
    INTO putnik_ime
  FROM public.v3_putnici p
  WHERE p.id = NEW.putnik_id
  LIMIT 1;

  SELECT v.push_token
    INTO bojan_token
  FROM public.v3_vozaci v
  WHERE v.aktivno = true
    AND v.ime_prezime = 'Bojan'
    AND v.push_token IS NOT NULL
    AND v.push_token <> ''
  ORDER BY v.updated_at DESC NULLS LAST
  LIMIT 1;

  IF bojan_token IS NULL THEN
    RETURN NEW;
  END IF;

  v_title := '🔐 Novi PIN zahtev';
  v_body := format('%s • %s',
    COALESCE(NULLIF(putnik_ime, ''), 'Putnik'),
    COALESCE(NULLIF(NEW.telefon, ''), '-')
  );

  PERFORM public.notify_push(
    jsonb_build_array(jsonb_build_object('token', bojan_token, 'provider', 'fcm')),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'v3_novi_pin_zahtev',
      'pin_zahtev_id', NEW.id,
      'putnik_id', NEW.putnik_id,
      'putnik_ime', COALESCE(putnik_ime, ''),
      'telefon', COALESCE(NEW.telefon, ''),
      'status', NEW.status,
      'screen', 'v3_pin_zahtevi'
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_v3_pin_zahtevi_push_bojan_new ON public.v3_pin_zahtevi;

CREATE TRIGGER tr_v3_pin_zahtevi_push_bojan_new
AFTER INSERT ON public.v3_pin_zahtevi
FOR EACH ROW
EXECUTE FUNCTION public.send_push_to_bojan_on_new_pin_request();
