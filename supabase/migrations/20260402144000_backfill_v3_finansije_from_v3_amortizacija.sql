-- Ensure transfer of legacy rows from v3_amortizacija into v3_finansije (idempotent)
DO $$
BEGIN
  IF to_regclass('public.v3_amortizacija') IS NOT NULL THEN
    WITH src AS (
      SELECT
        a.id,
        CASE
          WHEN a.tip_troska IN ('plata', 'plate') THEN 'plate'
          WHEN a.tip_troska IN ('amortizacija', 'majstori') THEN 'majstori'
          WHEN a.tip_troska IN ('kredit', 'gorivo', 'registracija', 'yu_auto', 'porez', 'alimentacija', 'racuni', 'ostalo') THEN a.tip_troska
          ELSE 'ostalo'
        END AS mapped_kategorija,
        COALESCE(a.iznos, 0) AS iznos,
        a.izvor_novca,
        EXTRACT(MONTH FROM COALESCE(a.datum, a.created_at, NOW()))::int AS mesec,
        EXTRACT(YEAR FROM COALESCE(a.datum, a.created_at, NOW()))::int AS godina,
        a.vozac_id,
        COALESCE(a.aktivno, true) AS aktivno,
        COALESCE(a.created_at, a.datum, NOW()) AS created_at,
        COALESCE(a.updated_at, a.created_at, a.datum, NOW()) AS updated_at,
        a.created_by,
        a.updated_by
      FROM public.v3_amortizacija a
      WHERE a.aktivno IS DISTINCT FROM false
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
      aktivno,
      created_at,
      updated_at,
      created_by,
      updated_by,
      tip
    )
    SELECT
      s.id,
      CASE s.mapped_kategorija
        WHEN 'plate' THEN 'Plate'
        WHEN 'kredit' THEN 'Kredit'
        WHEN 'gorivo' THEN 'Gorivo'
        WHEN 'registracija' THEN 'Registracija'
        WHEN 'yu_auto' THEN 'YU auto'
        WHEN 'majstori' THEN 'Majstori'
        WHEN 'porez' THEN 'Porez'
        WHEN 'alimentacija' THEN 'Alimentacija'
        WHEN 'racuni' THEN 'Računi'
        ELSE 'Ostalo'
      END AS naziv,
      s.mapped_kategorija,
      s.iznos,
      s.izvor_novca,
      false,
      s.mesec,
      s.godina,
      s.vozac_id,
      s.aktivno,
      s.created_at,
      s.updated_at,
      s.created_by,
      s.updated_by,
      'rashod'
    FROM src s
    WHERE NOT EXISTS (
      SELECT 1
      FROM public.v3_finansije f
      WHERE f.id = s.id
    );
  END IF;
END $$;
