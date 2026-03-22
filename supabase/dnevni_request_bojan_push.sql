-- =============================================================
-- Push Bojanu kada stigne novi dnevni zahtev
-- =============================================================

CREATE OR REPLACE FUNCTION public.send_push_to_bojan_on_new_dnevni_request()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  bojan_token text;
  putnik_ime text;
  tip_putnika text;
  v_title text;
  v_body text;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.aktivno, true) = false THEN
    RETURN NEW;
  END IF;

  SELECT p.ime_prezime,
         p.tip_putnika
    INTO putnik_ime,
      tip_putnika
  FROM public.v3_putnici p
  WHERE p.id = NEW.putnik_id
  LIMIT 1;

    IF COALESCE(tip_putnika, '') <> 'dnevni' THEN
    RETURN NEW;
  END IF;

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

  v_title := '🔔 Novi dnevni zahtev';
  v_body := format('%s • %s • %s (%s mesta)',
    COALESCE(NULLIF(putnik_ime, ''), 'Putnik'),
    COALESCE(NULLIF(NEW.grad, ''), '-'),
    COALESCE(NULLIF(NEW.zeljeno_vreme, ''), '-'),
    COALESCE(NEW.broj_mesta, 1)
  );

  PERFORM public.notify_push(
    jsonb_build_array(jsonb_build_object('token', bojan_token, 'provider', 'fcm')),
    v_title,
    v_body,
    jsonb_build_object(
      'type', 'v3_novi_dnevni_zahtev',
      'zahtev_id', NEW.id,
      'putnik_id', NEW.putnik_id,
      'putnik_ime', COALESCE(putnik_ime, ''),
      'datum', NEW.datum,
      'grad', NEW.grad,
      'zeljeno_vreme', NEW.zeljeno_vreme,
      'broj_mesta', COALESCE(NEW.broj_mesta, 1),
      'status', NEW.status,
      'screen', 'v3_admin_raspored'
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_v3_zahtevi_push_bojan_new_dnevni ON public.v3_zahtevi;

CREATE TRIGGER tr_v3_zahtevi_push_bojan_new_dnevni
AFTER INSERT ON public.v3_zahtevi
FOR EACH ROW
EXECUTE FUNCTION public.send_push_to_bojan_on_new_dnevni_request();
