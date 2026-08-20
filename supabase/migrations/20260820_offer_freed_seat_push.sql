-- Ponuda oslobođenog mesta putniku koji je odbijen jer nije bilo mesta.
-- Nema automatskog dodavanja: ostaje odbijeno dok putnik ne pritisne Prihvati.
-- Ako kaže Ne, više se ne nudi za taj zahtev.

ALTER TABLE public.v3_zahtevi
  ADD COLUMN IF NOT EXISTS mesto_ponuda boolean NOT NULL DEFAULT false;

ALTER TABLE public.v3_zahtevi
  ADD COLUMN IF NOT EXISTS mesto_ponuda_odbijena boolean NOT NULL DEFAULT false;

ALTER TABLE public.v3_zahtevi
  ADD COLUMN IF NOT EXISTS mesto_ponuda_at timestamptz;

COMMENT ON COLUMN public.v3_zahtevi.mesto_ponuda IS
  'True dok je putniku poslat push da se oslobodilo mesto (status ostaje odbijeno).';

COMMENT ON COLUMN public.v3_zahtevi.mesto_ponuda_odbijena IS
  'True ako je putnik odbio ponudu oslobođenog mesta — ne nudi se ponovo.';

COMMENT ON COLUMN public.v3_zahtevi.mesto_ponuda_at IS
  'Kad je ponuda oslobođenog mesta poslata. Posle 10 minuta ide sledećem.';

CREATE OR REPLACE FUNCTION public.v3_norm_hhmm(p_value text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT CASE
    WHEN p_value IS NULL OR btrim(p_value) = '' THEN ''
    WHEN btrim(p_value) ~ '^[0-9]{1,2}:[0-9]{2}' THEN
      lpad(split_part(btrim(p_value), ':', 1), 2, '0')
      || ':'
      || lpad(substr(split_part(btrim(p_value), ':', 2), 1, 2), 2, '0')
    ELSE btrim(p_value)
  END
$function$;

CREATE OR REPLACE FUNCTION public.fn_v3_offer_freed_seats(
  p_datum date,
  p_grad text,
  p_vreme text
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_grad text := upper(btrim(coalesce(p_grad, '')));
  v_vreme text := public.v3_norm_hhmm(p_vreme);
  v_now_bg timestamp;
  v_max integer := 0;
  v_occupied integer := 0;
  v_free integer := 0;
  v_offered integer := 0;
  r record;
  v_tokens jsonb;
  v_grad_label text;
  v_title text;
  v_body text;
  v_data jsonb;
BEGIN
  IF p_datum IS NULL OR v_grad = '' OR v_vreme = '' THEN
    RETURN 0;
  END IF;

  v_now_bg := timezone('Europe/Belgrade', now());
  IF v_now_bg::date > p_datum THEN
    RETURN 0;
  END IF;
  IF v_now_bg::date = p_datum AND to_char(v_now_bg, 'HH24:MI') >= v_vreme THEN
    RETURN 0;
  END IF;

  SELECT COALESCE(MAX(ks.max_mesta), 0)
  INTO v_max
  FROM public.v3_kapacitet_slots ks
  WHERE upper(btrim(ks.grad)) = v_grad
    AND ks.datum = p_datum
    AND public.v3_norm_hhmm(ks.vreme::text) = v_vreme;

  IF v_max <= 0 THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*)::int
  INTO v_occupied
  FROM public.v3_operativna_nedelja o
  LEFT JOIN public.v3_auth a ON a.id = o.created_by
  WHERE o.datum = p_datum
    AND upper(btrim(coalesce(o.grad, ''))) = v_grad
    AND public.v3_norm_hhmm(o.polazak_at::text) = v_vreme
    AND o.otkazano_at IS NULL
    AND lower(btrim(coalesce(a.tip, ''))) <> 'posiljka';

  v_free := v_max - v_occupied;
  IF v_free <= 0 THEN
    RETURN 0;
  END IF;

  v_grad_label := CASE
    WHEN v_grad = 'BC' THEN 'Bela Crkva'
    WHEN v_grad = 'VS' THEN 'Vrsac'
    ELSE v_grad
  END;

  FOR r IN
    SELECT z.id, z.created_by, z.updated_by, z.datum, z.grad, z.trazeni_polazak_at
    FROM public.v3_zahtevi z
    WHERE z.status = 'odbijeno'
      AND COALESCE(z.mesto_ponuda, false) = false
      AND COALESCE(z.mesto_ponuda_odbijena, false) = false
      AND z.datum = p_datum
      AND upper(btrim(coalesce(z.grad, ''))) = v_grad
      AND public.v3_norm_hhmm(z.trazeni_polazak_at::text) = v_vreme
      AND z.created_by IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_auth a
        WHERE a.id = z.created_by
          AND lower(btrim(coalesce(a.tip, ''))) = 'posiljka'
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_zahtevi z2
        WHERE z2.created_by = z.created_by
          AND z2.datum = z.datum
          AND upper(btrim(coalesce(z2.grad, ''))) = v_grad
          AND z2.id <> z.id
          AND z2.status IN ('obrada', 'odobreno', 'alternativa')
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_zahtevi z3
        WHERE z3.created_by = z.created_by
          AND z3.datum = z.datum
          AND upper(btrim(coalesce(z3.grad, ''))) = v_grad
          AND z3.status = 'otkazano'
          AND public.v3_norm_hhmm(coalesce(z3.polazak_at, z3.trazeni_polazak_at)::text) = v_vreme
      )
    ORDER BY z.created_at ASC NULLS LAST, z.id ASC
    LIMIT v_free
  LOOP
    UPDATE public.v3_zahtevi
    SET mesto_ponuda = true,
        mesto_ponuda_at = now(),
        updated_at = now()
    WHERE id = r.id
      AND status = 'odbijeno'
      AND COALESCE(mesto_ponuda, false) = false
      AND COALESCE(mesto_ponuda_odbijena, false) = false;

    IF NOT FOUND THEN
      CONTINUE;
    END IF;

    SELECT jsonb_agg(tkn)
    INTO v_tokens
    FROM (
      SELECT jsonb_build_object('token', a.push_token, 'provider', 'fcm') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token IS NOT NULL
        AND btrim(a.push_token) <> ''
      UNION
      SELECT jsonb_build_object('token', a.push_token_2, 'provider', 'fcm') AS tkn
      FROM public.v3_auth a
      WHERE a.id = r.created_by
        AND a.push_token_2 IS NOT NULL
        AND btrim(a.push_token_2) <> ''
    ) s;

    IF v_tokens IS NULL OR jsonb_array_length(v_tokens) = 0 THEN
      v_offered := v_offered + 1;
      CONTINUE;
    END IF;

    v_title := 'Oslobodilo se mesto';
    v_body := 'Oslobodilo se mesto u terminu ' || v_vreme || ' (' || v_grad_label || '). Prihvati ili odbij.';

    v_data := jsonb_build_object(
      'type', 'v3_alternativa',
      'offer_kind', 'mesto_oslobodjeno',
      'zahtev_id', r.id,
      'recipient_id', r.created_by,
      'alt_pre', v_vreme,
      'alt_posle', '',
      'datum', r.datum,
      'grad', r.grad,
      'status', 'odbijeno',
      'screen', 'v3_putnik_profil',
      'action_pre_label', 'Prihvati',
      'action_reject_label', 'Ne',
      'title_sr', v_title,
      'title_en', 'A seat opened up',
      'title_ru', 'Освободилось место',
      'title_de', 'Ein Platz ist frei geworden',
      'title_zh', '有空位了',
      'body_sr', v_body,
      'body_en', 'A seat opened up at ' || v_vreme || ' (' || v_grad_label || '). Accept or decline.',
      'body_ru', 'Освободилось место в ' || v_vreme || ' (' || v_grad_label || '). Примите или отклоните.',
      'body_de', 'Ein Platz ist um ' || v_vreme || ' (' || v_grad_label || ') frei geworden. Annehmen oder ablehnen.',
      'body_zh', v_vreme || '（' || v_grad_label || '）有空位了。请选择接受或拒绝。'
    );

    PERFORM public.notify_push(v_tokens, v_title, v_body, v_data);
    v_offered := v_offered + 1;
  END LOOP;

  RETURN v_offered;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_v3_on_operativna_otkazano_offer_seats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_vreme text;
BEGIN
  IF TG_OP = 'UPDATE'
     AND OLD.otkazano_at IS NULL
     AND NEW.otkazano_at IS NOT NULL THEN
    IF EXISTS (
      SELECT 1
      FROM public.v3_auth a
      WHERE a.id = NEW.created_by
        AND lower(btrim(coalesce(a.tip, ''))) = 'posiljka'
    ) THEN
      RETURN NEW;
    END IF;

    v_vreme := public.v3_norm_hhmm(COALESCE(NEW.polazak_at, OLD.polazak_at)::text);
    IF v_vreme = '' THEN
      RETURN NEW;
    END IF;

    -- otkazano = otkazana vožnja; odbijeno = odbijen zahtev. Nije isto.
    -- Ponudu šaljemo samo kad je mesto stvarno otkazano, ne kad je zahtev odbijen.
    IF NOT EXISTS (
      SELECT 1
      FROM public.v3_zahtevi z
      WHERE z.created_by = NEW.created_by
        AND z.datum = NEW.datum::date
        AND upper(btrim(coalesce(z.grad, ''))) = upper(btrim(coalesce(NEW.grad, '')))
        AND public.v3_norm_hhmm(coalesce(z.polazak_at, z.trazeni_polazak_at)::text) = v_vreme
        AND z.status IN ('otkazano', 'odobreno')
    ) THEN
      RETURN NEW;
    END IF;

    BEGIN
      PERFORM public.fn_v3_offer_freed_seats(
        NEW.datum::date,
        NEW.grad::text,
        v_vreme
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'fn_v3_offer_freed_seats: %', SQLERRM;
    END;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_v3_offer_freed_seats_on_otkazano ON public.v3_operativna_nedelja;
CREATE TRIGGER trg_v3_offer_freed_seats_on_otkazano
  AFTER UPDATE OF otkazano_at ON public.v3_operativna_nedelja
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_v3_on_operativna_otkazano_offer_seats();

GRANT EXECUTE ON FUNCTION public.v3_norm_hhmm(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_v3_offer_freed_seats(date, text, text) TO service_role;
