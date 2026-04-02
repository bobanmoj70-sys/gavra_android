-- Move payment history from v3_putnici_arhiva into v3_finansije and drop legacy table

-- 1) Add metadata columns needed by putnik statistics/history logic
ALTER TABLE public.v3_finansije
  ADD COLUMN IF NOT EXISTS putnik_id text,
  ADD COLUMN IF NOT EXISTS putnik_ime_prezime text,
  ADD COLUMN IF NOT EXISTS tip_akcije text,
  ADD COLUMN IF NOT EXISTS vozac_ime_prezime text;

-- 2) Backfill metadata onto existing matching prihod rows
DO $$
BEGIN
  IF to_regclass('public.v3_putnici_arhiva') IS NOT NULL THEN
    WITH src AS (
      SELECT
        a.id,
        a.putnik_id::text AS putnik_id,
        a.putnik_ime_prezime,
        a.tip_akcije,
        a.za_mesec,
        a.za_godinu,
        COALESCE(a.iznos, 0) AS iznos,
        a.vozac_id,
        a.vozac_ime_prezime,
        a.created_at,
        a.updated_at,
        a.created_by,
        a.updated_by,
        COALESCE(a.aktivno, true) AS aktivno,
        'Uplata: ' || COALESCE(a.putnik_ime_prezime, 'Nepoznat putnik') || ' (' || a.za_mesec::text || '/' || a.za_godinu::text || ')' AS naziv
      FROM public.v3_putnici_arhiva a
      WHERE a.aktivno IS DISTINCT FROM false
        AND a.tip_akcije IN ('uplata', 'uplata_mesecna', 'uplata_voznja')
        AND a.za_mesec BETWEEN 1 AND 12
        AND a.za_godinu IS NOT NULL
    )
    UPDATE public.v3_finansije f
    SET
      putnik_id = COALESCE(f.putnik_id, s.putnik_id),
      putnik_ime_prezime = COALESCE(f.putnik_ime_prezime, s.putnik_ime_prezime),
      tip_akcije = COALESCE(f.tip_akcije, s.tip_akcije),
      vozac_ime_prezime = COALESCE(f.vozac_ime_prezime, s.vozac_ime_prezime),
      isplata_iz = COALESCE(NULLIF(f.isplata_iz, ''), 'putnici_arhiva')
    FROM src s
    WHERE f.tip = 'prihod'
      AND f.naziv = s.naziv
      AND COALESCE(f.iznos, 0) = s.iznos
      AND f.mesec = s.za_mesec
      AND f.godina = s.za_godinu;

    -- 3) Insert only those payment rows that still don't exist semantically
    WITH src AS (
      SELECT
        a.id,
        a.putnik_id::text AS putnik_id,
        a.putnik_ime_prezime,
        a.tip_akcije,
        a.za_mesec,
        a.za_godinu,
        COALESCE(a.iznos, 0) AS iznos,
        a.vozac_id,
        a.vozac_ime_prezime,
        a.created_at,
        a.updated_at,
        a.created_by,
        a.updated_by,
        COALESCE(a.aktivno, true) AS aktivno,
        'Uplata: ' || COALESCE(a.putnik_ime_prezime, 'Nepoznat putnik') || ' (' || a.za_mesec::text || '/' || a.za_godinu::text || ')' AS naziv
      FROM public.v3_putnici_arhiva a
      WHERE a.aktivno IS DISTINCT FROM false
        AND a.tip_akcije IN ('uplata', 'uplata_mesecna', 'uplata_voznja')
        AND a.za_mesec BETWEEN 1 AND 12
        AND a.za_godinu IS NOT NULL
    )
    INSERT INTO public.v3_finansije (
      id,
      naziv,
      kategorija,
      iznos,
      isplata_iz,
      ponavljaj_mesecno,
      mesec,
      godina,
      vozac_id,
      vozac_ime_prezime,
      putnik_id,
      putnik_ime_prezime,
      tip_akcije,
      aktivno,
      created_at,
      updated_at,
      created_by,
      updated_by,
      tip
    )
    SELECT
      s.id,
      s.naziv,
      'voznja' AS kategorija,
      s.iznos,
      'putnici_arhiva' AS isplata_iz,
      false AS ponavljaj_mesecno,
      s.za_mesec,
      s.za_godinu,
      CASE
        WHEN s.vozac_id IS NULL THEN NULL
        WHEN EXISTS (SELECT 1 FROM public.v3_vozaci v WHERE v.id = s.vozac_id) THEN s.vozac_id
        ELSE NULL
      END AS vozac_id,
      s.vozac_ime_prezime,
      s.putnik_id,
      s.putnik_ime_prezime,
      s.tip_akcije,
      s.aktivno,
      COALESCE(s.created_at, now()) AS created_at,
      COALESCE(s.updated_at, s.created_at, now()) AS updated_at,
      s.created_by,
      s.updated_by,
      'prihod' AS tip
    FROM src s
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.v3_finansije f_id
      WHERE f_id.id = s.id
    )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_finansije f
        WHERE f.tip = 'prihod'
          AND f.naziv = s.naziv
          AND COALESCE(f.iznos, 0) = s.iznos
          AND f.mesec = s.za_mesec
          AND f.godina = s.za_godinu
      );

    -- 4) Drop legacy table
    DROP TABLE IF EXISTS public.v3_putnici_arhiva;
  END IF;
END $$;
