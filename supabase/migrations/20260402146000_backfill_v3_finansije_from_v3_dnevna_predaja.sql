-- Transfer legacy daily handover records into v3_finansije (idempotent)
DO $$
BEGIN
  IF to_regclass('public.v3_dnevna_predaja') IS NOT NULL THEN
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
      d.id,
      'Dnevna predaja' AS naziv,
      'dnevna_predaja' AS kategorija,
      COALESCE(d.predao_iznos, d.ukupno_naplaceno, 0) AS iznos,
      'predaja' AS isplata_iz,
      false AS ponavljaj_mesecno,
      EXTRACT(MONTH FROM d.datum)::int AS mesec,
      EXTRACT(YEAR FROM d.datum)::int AS godina,
      d.vozac_id,
      COALESCE(d.aktivno, true) AS aktivno,
      COALESCE(d.created_at, d.datum::timestamptz, now()) AS created_at,
      COALESCE(d.updated_at, d.created_at, d.datum::timestamptz, now()) AS updated_at,
      d.created_by,
      d.updated_by,
      'prihod' AS tip
    FROM public.v3_dnevna_predaja d
    WHERE d.aktivno IS DISTINCT FROM false
      AND NOT EXISTS (
        SELECT 1
        FROM public.v3_finansije f
        WHERE f.id = d.id
      );
  END IF;
END $$;
