-- Backfill only missing payment rows from v3_putnici_arhiva into v3_finansije
-- Avoid duplicates by ID and by semantic match (naziv+iznos+mesec+godina for prihod rows)
DO $$
BEGIN
  IF to_regclass('public.v3_putnici_arhiva') IS NOT NULL THEN
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
      aktivno,
      created_at,
      updated_at,
      created_by,
      updated_by,
      tip
    )
    SELECT
      a.id,
      'Uplata: ' || COALESCE(a.putnik_ime_prezime, 'Nepoznat putnik') || ' (' || a.za_mesec::text || '/' || a.za_godinu::text || ')' AS naziv,
      'voznja' AS kategorija,
      COALESCE(a.iznos, 0) AS iznos,
      'putnici_arhiva' AS isplata_iz,
      false AS ponavljaj_mesecno,
      a.za_mesec,
      a.za_godinu,
      CASE
        WHEN a.vozac_id IS NULL THEN NULL
        WHEN EXISTS (SELECT 1 FROM public.v3_vozaci v WHERE v.id = a.vozac_id) THEN a.vozac_id
        ELSE NULL
      END AS vozac_id,
      COALESCE(a.aktivno, true) AS aktivno,
      COALESCE(a.created_at, now()) AS created_at,
      COALESCE(a.updated_at, a.created_at, now()) AS updated_at,
      a.created_by,
      a.updated_by,
      'prihod' AS tip
    FROM public.v3_putnici_arhiva a
    WHERE a.aktivno IS DISTINCT FROM false
      AND a.tip_akcije IN ('uplata_mesecna', 'uplata_voznja')
      AND a.za_mesec BETWEEN 1 AND 12
      AND a.za_godinu IS NOT NULL
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_finansije f_id
        WHERE f_id.id = a.id
      )
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_finansije f
        WHERE f.tip = 'prihod'
          AND f.naziv = 'Uplata: ' || COALESCE(a.putnik_ime_prezime, 'Nepoznat putnik') || ' (' || a.za_mesec::text || '/' || a.za_godinu::text || ')'
          AND COALESCE(f.iznos, 0) = COALESCE(a.iznos, 0)
          AND f.mesec = a.za_mesec
          AND f.godina = a.za_godinu
      );
  END IF;
END $$;
