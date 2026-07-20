-- Trigger funkcija koja održava sinhronizaciju između
-- v3_operativna_nedelja.pokupljen_at (jedini izvor istine za operativno stanje)
-- i v3_finansije.realizovane_voznje_json (arhivska kolona za statistiku i obračun).
CREATE OR REPLACE FUNCTION public.v3_sync_realizovane_voznje_to_finansije()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_putnik_id uuid;
  v_datum date;
  v_mesec int;
  v_godina int;
  v_operativna_id uuid;
  v_pokupljen_at timestamptz;
  v_pokupljen_by uuid;
  v_dodao_by uuid;
  v_azurirao_by uuid;
  v_grad text;
  v_vreme text;
  v_existing_id uuid;
  v_trenutne jsonb;
  v_nova_stavka jsonb;
  v_filtrirane jsonb;
  v_vec_postoji boolean;
  v_i int;
  v_item jsonb;
  v_stavka_key text;
BEGIN
  -- Samo ako se pokupljen_at promenio
  IF TG_OP = 'UPDATE' AND NEW.pokupljen_at IS NOT DISTINCT FROM OLD.pokupljen_at THEN
    RETURN NEW;
  END IF;

  v_putnik_id := NEW.created_by;
  v_datum := NEW.datum;
  v_mesec := EXTRACT(MONTH FROM v_datum)::int;
  v_godina := EXTRACT(YEAR FROM v_datum)::int;
  v_operativna_id := NEW.id;
  v_pokupljen_at := NEW.pokupljen_at;
  v_pokupljen_by := NEW.pokupljen_by;
  v_dodao_by := NEW.created_by;
  v_azurirao_by := NEW.updated_by;
  v_grad := NEW.grad;
  v_vreme := NEW.polazak_at::text;

  IF v_putnik_id IS NULL OR v_datum IS NULL THEN
    RETURN NEW;
  END IF;

  -- Pronađi postojeći master red u v3_finansije za ovog putnika/mesec
  SELECT id, COALESCE(realizovane_voznje_json, '[]'::jsonb)
  INTO v_existing_id, v_trenutne
  FROM public.v3_finansije
  WHERE tip = 'prihod'
    AND kategorija = 'operativna_naplata'
    AND putnik_v3_auth_id = v_putnik_id
    AND mesec = v_mesec
    AND godina = v_godina
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_pokupljen_at IS NULL THEN
    -- Ukloni stavku iz arhive (poništavanje pokupljanja)
    IF v_existing_id IS NOT NULL THEN
      v_filtrirane := '[]'::jsonb;
      FOR v_i IN 0 .. jsonb_array_length(v_trenutne) - 1 LOOP
        v_item := v_trenutne -> v_i;
        IF (v_item ->> 'operativna_id') IS DISTINCT FROM v_operativna_id::text THEN
          v_filtrirane := v_filtrirane || jsonb_build_array(v_item);
        END IF;
      END LOOP;

      IF v_filtrirane IS DISTINCT FROM v_trenutne THEN
        UPDATE public.v3_finansije
        SET realizovane_voznje_json = v_filtrirane,
            updated_at = now()
        WHERE id = v_existing_id;
      END IF;
    END IF;
  ELSE
    -- Dodaj ili ažuriraj stavku u arhivi
    v_nova_stavka := jsonb_build_object(
      'operativna_id', v_operativna_id::text,
      'datum', v_datum::text,
      'pokupljen_by', v_pokupljen_by::text,
      'pokupljen_at', v_pokupljen_at::text,
      'dodao_by', v_dodao_by::text,
      'azurirao_by', v_azurirao_by::text,
      'grad', v_grad,
      'vreme', v_vreme
    );

    IF v_existing_id IS NOT NULL THEN
      v_vec_postoji := false;
      FOR v_i IN 0 .. jsonb_array_length(v_trenutne) - 1 LOOP
        IF (v_trenutne -> v_i ->> 'operativna_id') = v_operativna_id::text THEN
          v_vec_postoji := true;
          EXIT;
        END IF;
      END LOOP;

      IF v_vec_postoji THEN
        UPDATE public.v3_finansije
        SET realizovane_voznje_json = (
            SELECT jsonb_agg(
              CASE
                WHEN (value ->> 'operativna_id') = v_operativna_id::text THEN v_nova_stavka
                ELSE value
              END
            )
            FROM jsonb_array_elements(v_trenutne)
          ),
          updated_at = now()
        WHERE id = v_existing_id;
      ELSE
        UPDATE public.v3_finansije
        SET realizovane_voznje_json = v_trenutne || jsonb_build_array(v_nova_stavka),
            updated_at = now()
        WHERE id = v_existing_id;
      END IF;
    ELSE
      INSERT INTO public.v3_finansije (
        naziv,
        kategorija,
        tip,
        iznos,
        putnik_v3_auth_id,
        broj_voznji,
        realizovane_voznje_json,
        mesec,
        godina
      ) VALUES (
        'Evidencija realizacije ' || v_mesec || '/' || v_godina,
        'operativna_naplata',
        'prihod',
        0,
        v_putnik_id,
        0,
        jsonb_build_array(v_nova_stavka),
        v_mesec,
        v_godina
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.v3_sync_realizovane_voznje_to_finansije IS
  'Održava v3_finansije.realizovane_voznje_json u sinhronizaciji sa v3_operativna_nedelja.pokupljen_at.';

-- Kreiraj trigger ako već ne postoji
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_sync_realizovane_voznje_to_finansije'
      AND tgrelid = 'public.v3_operativna_nedelja'::regclass
  ) THEN
    CREATE TRIGGER trg_sync_realizovane_voznje_to_finansije
    AFTER INSERT OR UPDATE OF pokupljen_at ON public.v3_operativna_nedelja
    FOR EACH ROW
    EXECUTE FUNCTION public.v3_sync_realizovane_voznje_to_finansije();
  END IF;
END;
$$;

-- Funkcija za proveru konzistentnosti (koristi se ručno ili kroz cron)
CREATE OR REPLACE FUNCTION public.v3_check_realizovane_voznje_consistency(
  p_godina int,
  p_mesec int
)
RETURNS TABLE (
  putnik_v3_auth_id uuid,
  operativna_count bigint,
  finansije_count bigint,
  inconsistent boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  WITH operativna_counts AS (
    SELECT
      o.created_by AS putnik_id,
      count(*) AS cnt
    FROM public.v3_operativna_nedelja o
    WHERE o.pokupljen_at IS NOT NULL
      AND EXTRACT(YEAR FROM o.datum)::int = p_godina
      AND EXTRACT(MONTH FROM o.datum)::int = p_mesec
    GROUP BY o.created_by
  ),
  finansije_counts AS (
    SELECT
      f.putnik_v3_auth_id AS putnik_id,
      COALESCE(sum(jsonb_array_length(COALESCE(f.realizovane_voznje_json, '[]'::jsonb))), 0) AS cnt
    FROM public.v3_finansije f
    WHERE f.tip = 'prihod'
      AND f.kategorija = 'operativna_naplata'
      AND f.godina = p_godina
      AND f.mesec = p_mesec
    GROUP BY f.putnik_v3_auth_id
  )
  SELECT
    COALESCE(o.putnik_id, f.putnik_id) AS putnik_v3_auth_id,
    COALESCE(o.cnt, 0) AS operativna_count,
    COALESCE(f.cnt, 0) AS finansije_count,
    COALESCE(o.cnt, 0) != COALESCE(f.cnt, 0) AS inconsistent
  FROM operativna_counts o
  FULL OUTER JOIN finansije_counts f ON o.putnik_id = f.putnik_id
  WHERE COALESCE(o.cnt, 0) != COALESCE(f.cnt, 0);
$$;

COMMENT ON FUNCTION public.v3_check_realizovane_voznje_consistency IS
  'Vraća putnike kod kojih se broj realizovanih vožnji u operativnoj tabeli i finansijama ne poklapa.';
