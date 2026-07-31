-- Jasmina Marinkovic — jun 2026
-- 20 naplativih dana × 700 = 14000, uplata Bilevski, JSON arhiva usklađena.
-- Jun ima 22 radna dana; uzimamo prvih 20 (bez 29. i 30.06) jer nema liste odsustva.

WITH target AS (
  SELECT f.id
  FROM public.v3_finansije f
  WHERE f.id = '29edecbe-0718-4adb-a9f3-0bdb57aea46e'
    AND f.putnik_v3_auth_id = '270e4e95-f179-4d0c-b47e-b43bdd6cea80'
    AND f.mesec = 6
    AND f.godina = 2026
),
radni AS (
  SELECT d::date AS dan
  FROM generate_series(date '2026-06-01', date '2026-06-30', interval '1 day') d
  WHERE EXTRACT(ISODOW FROM d) BETWEEN 1 AND 5
    AND d::date NOT IN (date '2026-06-29', date '2026-06-30')
  ORDER BY 1
),
real_json AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', 'backfill:270e4e95-f179-4d0c-b47e-b43bdd6cea80:' || to_char(r.dan, 'YYYY-MM-DD'),
        'datum', to_char(r.dan, 'YYYY-MM-DD'),
        'pokupljen_by', '7c32a5db-98f8-4aa2-b365-5cc83533ec41',
        'pokupljen_at', to_char(
          (r.dan + time '06:00') AT TIME ZONE 'Europe/Belgrade' AT TIME ZONE 'UTC',
          'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
        ),
        'dodao_by', '270e4e95-f179-4d0c-b47e-b43bdd6cea80',
        'azurirao_by', NULL,
        'grad', 'BC',
        'vreme', '06:00:00',
        'backfill', true,
        'napomena', 'Dopuna arhive Jasmina Marinkovic jun 2026: 20 dana, skalar-only red'
      )
      ORDER BY r.dan
    ),
    '[]'::jsonb
  ) AS j,
  COUNT(*)::int AS broj
  FROM radni r
),
uplata_json AS (
  SELECT jsonb_build_array(
    jsonb_build_object(
      'uplata_id', 'upl:backfill-jasmina-jun-2026',
      'datum', '2026-06-30T12:00:00.000Z',
      'iznos', 14000,
      'naplatio_by', '7c32a5db-98f8-4aa2-b365-5cc83533ec41',
      'naplatio_at', '2026-06-30T12:00:00.000Z'
    )
  ) AS j
)
UPDATE public.v3_finansije f
SET
  broj_voznji = r.broj,
  iznos = 14000,
  poslednja_dopuna = 14000,
  naplaceno_by = '7c32a5db-98f8-4aa2-b365-5cc83533ec41',
  naplatio_ime = 'Bilevski',
  realizovane_voznje_json = r.j,
  nenaplacene_voznje_json = '[]'::jsonb,
  otkazane_voznje_json = '[]'::jsonb,
  uplate_json = u.j,
  visak_iznos = 0,
  updated_at = now()
FROM target t
CROSS JOIN real_json r
CROSS JOIN uplata_json u
WHERE f.id = t.id;
