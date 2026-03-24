-- Hotfix: deduplikacija putnik push-a i ispravan status payload
-- Datum: 2026-03-24
-- Cilj:
-- 1) Sprečiti dupli `v3_alternativa` push (specifični trigger već postoji)
-- 2) Sprečiti pogrešan `v3_alternativa` payload kada je status `odbijeno`
-- 3) Zadržati samo generičke poruke koje nemaju poseban dedicated trigger

CREATE OR REPLACE FUNCTION public.fn_v3_notify_putnik_on_zahtev_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_tokens jsonb;
  v_title  text;
  v_body   text;
  v_data   jsonb;
  v_grad   text;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  v_grad := CASE
    WHEN NEW.grad = 'BC' THEN 'Bela Crkva'
    WHEN NEW.grad = 'VS' THEN 'Vršac'
    ELSE NEW.grad
  END;

  SELECT jsonb_build_array(jsonb_build_object('token', push_token, 'provider', 'fcm'))
  INTO v_tokens
  FROM public.v3_putnici
  WHERE id = NEW.putnik_id
    AND push_token IS NOT NULL
    AND push_token <> ''
  LIMIT 1;

  IF v_tokens IS NULL THEN
    RETURN NEW;
  END IF;

  -- DEDUP: `odobreno` i `alternativa/ponuda` imaju dedicated triggere
  IF NEW.status IN ('odobreno', 'alternativa', 'ponuda') THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'odbijeno' THEN
    v_title := '❌ Termin popunjen';
    v_body  := 'Nažalost, u terminu ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
      || ' nema slobodnih mesta (' || v_grad || ').';
    v_data  := jsonb_build_object(
      'type', 'v3_zahtev_odbijen',
      'id', NEW.id,
      'grad', NEW.grad,
      'status', NEW.status
    );
  ELSIF NEW.status = 'otkazano' THEN
    v_title := '🚫 Prevoz otkazan';
    v_body  := 'Vaš prevoz za ' || to_char(NEW.zeljeno_vreme, 'HH24:MI')
      || ' (' || v_grad || ') je otkazan.';
    v_data  := jsonb_build_object(
      'type', 'v3_otkazano',
      'id', NEW.id,
      'grad', NEW.grad,
      'status', NEW.status
    );
  END IF;

  IF v_title IS NOT NULL THEN
    PERFORM notify_push(v_tokens, v_title, v_body, v_data);
  END IF;

  RETURN NEW;
END;
$function$;
