-- Force UTC ISO timestamp strings in archived JSON payloads produced by sync triggers.

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
BEGIN
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
    v_nova_stavka := jsonb_build_object(
      'operativna_id', v_operativna_id::text,
      'datum', v_datum::text,
      'pokupljen_by', v_pokupljen_by::text,
      'pokupljen_at', to_char(v_pokupljen_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
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
  'Održava v3_finansije.realizovane_voznje_json u sinhronizaciji sa v3_operativna_nedelja.pokupljen_at (UTC ISO timestamp u JSON).';

CREATE OR REPLACE FUNCTION public.v3_sync_otkazane_voznje_to_finansije()
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
  v_otkazano_at timestamptz;
  v_otkazano_by uuid;
  v_grad text;
  v_vreme text;
  v_existing_id uuid;
  v_trenutne jsonb;
  v_nova_stavka jsonb;
  v_filtrirane jsonb;
  v_vec_postoji boolean;
  v_i int;
  v_item jsonb;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.otkazano_at IS NOT DISTINCT FROM OLD.otkazano_at THEN
    RETURN NEW;
  END IF;

  v_putnik_id := NEW.created_by;
  v_datum := NEW.datum;
  v_mesec := EXTRACT(MONTH FROM v_datum)::int;
  v_godina := EXTRACT(YEAR FROM v_datum)::int;
  v_operativna_id := NEW.id;
  v_otkazano_at := NEW.otkazano_at;
  v_otkazano_by := NEW.otkazano_by;
  v_grad := NEW.grad;
  v_vreme := NEW.polazak_at;

  IF v_putnik_id IS NULL OR v_datum IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT id, COALESCE(otkazane_voznje_json, '[]'::jsonb)
  INTO v_existing_id, v_trenutne
  FROM public.v3_finansije
  WHERE tip = 'prihod'
    AND kategorija = 'operativna_naplata'
    AND putnik_v3_auth_id = v_putnik_id
    AND mesec = v_mesec
    AND godina = v_godina
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_otkazano_at IS NULL THEN
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
        SET otkazane_voznje_json = v_filtrirane,
            updated_at = now()
        WHERE id = v_existing_id;
      END IF;
    END IF;
  ELSE
    v_nova_stavka := jsonb_build_object(
      'operativna_id', v_operativna_id::text,
      'datum', v_datum::text,
      'otkazao_by', v_otkazano_by::text,
      'otkazano_at', to_char(v_otkazano_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
      'tip_otkazivanja', CASE WHEN v_otkazano_by = v_putnik_id THEN 'putnik' ELSE 'vozac' END,
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

      IF NOT v_vec_postoji THEN
        UPDATE public.v3_finansije
        SET otkazane_voznje_json = v_trenutne || jsonb_build_array(v_nova_stavka),
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
        otkazane_voznje_json,
        mesec,
        godina
      ) VALUES (
        'Evidencija otkazivanja ' || v_mesec || '/' || v_godina,
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

COMMENT ON FUNCTION public.v3_sync_otkazane_voznje_to_finansije IS
  'Održava v3_finansije.otkazane_voznje_json u sinhronizaciji sa v3_operativna_nedelja.otkazano_at (UTC ISO timestamp u JSON).';
