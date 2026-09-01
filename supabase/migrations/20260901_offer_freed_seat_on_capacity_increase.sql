-- Ponuda oslobođenog mesta i kada se poveća kapacitet slota (max_mesta),
-- ne samo kada neko otkaže vožnju. fn_v3_offer_freed_seats i dalje nudi
-- samo ako stvarno ima slobodnih mesta i ima odbijenih zahteva.

CREATE OR REPLACE FUNCTION public.fn_v3_on_kapacitet_increased_offer_seats()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_vreme text;
  v_old_max integer := 0;
  v_new_max integer := 0;
BEGIN
  v_new_max := COALESCE(NEW.max_mesta, 0);
  IF TG_OP = 'UPDATE' THEN
    v_old_max := COALESCE(OLD.max_mesta, 0);
    IF v_new_max <= v_old_max THEN
      RETURN NEW;
    END IF;
  ELSIF TG_OP = 'INSERT' THEN
    IF v_new_max <= 0 THEN
      RETURN NEW;
    END IF;
  ELSE
    RETURN NEW;
  END IF;

  v_vreme := public.v3_norm_hhmm(COALESCE(NEW.vreme, CASE WHEN TG_OP = 'UPDATE' THEN OLD.vreme ELSE NULL END)::text);
  IF v_vreme = '' OR NEW.datum IS NULL OR btrim(coalesce(NEW.grad, '')) = '' THEN
    RETURN NEW;
  END IF;

  BEGIN
    PERFORM public.fn_v3_offer_freed_seats(
      NEW.datum::date,
      NEW.grad::text,
      v_vreme
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'fn_v3_offer_freed_seats (kapacitet): %', SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

COMMENT ON FUNCTION public.fn_v3_on_kapacitet_increased_offer_seats() IS
  'Kad se max_mesta poveća (ili unese novi slot sa kapacitetom), nudi oslobođena mesta odbijenim putnicima.';

DROP TRIGGER IF EXISTS trg_v3_offer_freed_seats_on_kapacitet ON public.v3_kapacitet_slots;
CREATE TRIGGER trg_v3_offer_freed_seats_on_kapacitet
  AFTER INSERT OR UPDATE OF max_mesta ON public.v3_kapacitet_slots
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_v3_on_kapacitet_increased_offer_seats();
