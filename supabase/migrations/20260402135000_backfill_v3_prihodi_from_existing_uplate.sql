BEGIN;

INSERT INTO public.v3_prihodi (
  datum,
  iznos,
  kategorija,
  opis,
  nacin_naplate,
  izvor,
  putnik_id,
  putnik_ime_prezime,
  vozac_id,
  za_mesec,
  za_godinu,
  aktivno,
  created_at,
  updated_at,
  created_by,
  updated_by,
  source_table,
  source_id
)
SELECT
  COALESCE(
    CASE
      WHEN r.godina IS NOT NULL AND r.mesec IS NOT NULL AND r.mesec BETWEEN 1 AND 12
      THEN make_date(r.godina, r.mesec, 1)
      ELSE NULL
    END,
    (r.created_at)::date,
    CURRENT_DATE
  ) AS datum,
  COALESCE(r.iznos, 0) AS iznos,
  COALESCE(NULLIF(r.kategorija, ''), 'voznja') AS kategorija,
  r.naziv AS opis,
  'gotovina' AS nacin_naplate,
  'v3_finansije_uplata_migracija' AS izvor,
  NULL::uuid AS putnik_id,
  NULL::text AS putnik_ime_prezime,
  r.vozac_id,
  r.mesec,
  r.godina,
  COALESCE(r.aktivno, true) AS aktivno,
  COALESCE(r.created_at, now()) AS created_at,
  COALESCE(r.updated_at, now()) AS updated_at,
  r.created_by,
  r.updated_by,
  'v3_finansije' AS source_table,
  r.id AS source_id
FROM public.v3_finansije r
WHERE r.naziv ILIKE 'Uplata:%'
ON CONFLICT (source_table, source_id) DO NOTHING;

INSERT INTO public.v3_prihodi (
  datum,
  iznos,
  kategorija,
  opis,
  nacin_naplate,
  izvor,
  putnik_id,
  putnik_ime_prezime,
  vozac_id,
  za_mesec,
  za_godinu,
  aktivno,
  created_at,
  updated_at,
  created_by,
  updated_by,
  source_table,
  source_id
)
SELECT
  COALESCE(
    (a.created_at)::date,
    CASE
      WHEN a.za_godinu IS NOT NULL AND a.za_mesec IS NOT NULL AND a.za_mesec BETWEEN 1 AND 12
      THEN make_date(a.za_godinu, a.za_mesec, 1)
      ELSE NULL
    END,
    CURRENT_DATE
  ) AS datum,
  COALESCE(a.iznos, 0) AS iznos,
  CASE
    WHEN a.tip_akcije = 'uplata_mesecna' THEN 'mesecna'
    WHEN a.tip_akcije = 'uplata_voznja' THEN 'voznja'
    ELSE 'ostalo'
  END AS kategorija,
  CONCAT(
    'Uplata arhiva: ',
    COALESCE(a.putnik_ime_prezime, 'Nepoznat putnik'),
    ' (',
    COALESCE(a.za_mesec::text, '?'),
    '/',
    COALESCE(a.za_godinu::text, '?'),
    ')'
  ) AS opis,
  'gotovina' AS nacin_naplate,
  'v3_putnici_arhiva_migracija' AS izvor,
  a.putnik_id,
  a.putnik_ime_prezime,
  a.vozac_id,
  a.za_mesec,
  a.za_godinu,
  COALESCE(a.aktivno, true) AS aktivno,
  COALESCE(a.created_at, now()) AS created_at,
  COALESCE(a.updated_at, now()) AS updated_at,
  a.created_by,
  a.updated_by,
  'v3_putnici_arhiva' AS source_table,
  a.id AS source_id
FROM public.v3_putnici_arhiva a
WHERE a.tip_akcije IN ('uplata_mesecna', 'uplata_voznja')
ON CONFLICT (source_table, source_id) DO NOTHING;

COMMIT;
