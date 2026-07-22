-- Veži postojeću logiku za gorivo na tabelu v3_gorivo.
--
-- Funkcija v3_gorivo_set_trenutno_from_brojac() je definisana u prethodnoj
-- migraciji, ali bez okidača ne može da primeni delta-logiku za potrošnju.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_trigger
    WHERE tgname = 'trg_v3_gorivo_set_trenutno_from_brojac'
      AND tgrelid = 'public.v3_gorivo'::regclass
  ) THEN
    CREATE TRIGGER trg_v3_gorivo_set_trenutno_from_brojac
    BEFORE INSERT OR UPDATE OF brojac_pistolj_litri ON public.v3_gorivo
    FOR EACH ROW
    EXECUTE FUNCTION public.v3_gorivo_set_trenutno_from_brojac();
  END IF;
END;
$$;
