-- PROBLEM: v3-auto-prepare-termins (cron, svakog minuta) je slepo slao
-- "Vozač je krenuo" push putnicima tačno na T-10min pre polaska, bez obzira
-- da li je vozač STVARNO pokrenuo tracking (V3VozacLocationTrackingService
-- radi isključivo foreground-only — ako je app u pozadini, tracking se ne
-- pokreće dok vozač ne otvori app). Rezultat: putnici dobiju poruku da je
-- vozač krenuo i mogu da prate ETA uživo, a GPS/ETA podaci realno ne postoje
-- jer tracking nije aktivan.
--
-- FIX: putnici se sada obaveštavaju TEK kada je tracking stvarno aktiviran
-- — tj. kada `v3_trenutna_dodela_slot.vozac_v3_auth_id` bude (prvi put)
-- upisan/ažuriran od strane `activateSlotWithRetry` (poziva se ISKLJUČIVO
-- iz `V3VozacLocationTrackingService.start()`, i to samo dok je
-- V3VozacScreen otvoren u foreground-u — ručno ili auto-start). Kolona
-- `tracking_started_at` se upisuje SAMO tim putem, nikad iz crona, pa je
-- pouzdan signal da je GPS tracking zaista živ.
--
-- Vozač i dalje dobija auto-start push na T-10min (nepromenjeno) kao nudge
-- da otvori app — ta logika ostaje u v3-auto-prepare-termins edge funkciji.

ALTER TABLE public.v3_trenutna_dodela_slot
  ADD COLUMN IF NOT EXISTS tracking_started_at timestamptz;

COMMENT ON COLUMN public.v3_trenutna_dodela_slot.tracking_started_at IS
  'Kada je vozac STVARNO pokrenuo tracking (foreground, rucno ili auto-start). Upisuje ga iskljucivo activateSlotWithRetry iz V3VozacLocationTrackingService.start(). Koristi se kao okidac za obavestavanje putnika, umesto slepog T-10min crona.';

CREATE OR REPLACE FUNCTION public.v3_notify_passengers_on_tracking_start()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Okini se SAMO kada tracking_started_at prelazi iz null u ne-null
  -- (prvi put kada je tracking stvarno pokrenut za ovaj slot), i samo ako
  -- putnici za taj termin još nisu obavesteni (auto_notified_at prazan).
  IF NEW.tracking_started_at IS NOT NULL
     AND (TG_OP = 'INSERT' OR OLD.tracking_started_at IS NULL)
     AND NEW.auto_notified_at IS NULL
     AND NEW.vozac_v3_auth_id IS NOT NULL
  THEN
    BEGIN
      PERFORM public.v3_notify_passengers_driver_started(
        NEW.vozac_v3_auth_id,
        NEW.datum,
        NEW.grad,
        NEW.vreme
      );

      UPDATE public.v3_trenutna_dodela_slot
      SET auto_notified_at = now()
      WHERE id = NEW.id
        AND auto_notified_at IS NULL;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'v3_notify_passengers_on_tracking_start: notify greska za slot %: %', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.v3_notify_passengers_on_tracking_start IS
  'Trigger: obavestava putnike da je vozac krenuo TEK kada je tracking_started_at stvarno upisan (real tracking start), umesto slepog T-10min crona.';

DROP TRIGGER IF EXISTS trg_v3_notify_passengers_on_tracking_start ON public.v3_trenutna_dodela_slot;

CREATE TRIGGER trg_v3_notify_passengers_on_tracking_start
  AFTER INSERT OR UPDATE OF tracking_started_at ON public.v3_trenutna_dodela_slot
  FOR EACH ROW
  EXECUTE FUNCTION public.v3_notify_passengers_on_tracking_start();
