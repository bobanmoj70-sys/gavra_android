-- Jasmina Marinkovic (radnik) — jul 2026
-- Izvor istine: nenaplacene_voznje_json = 21 elemenata (potvrđeno).
-- Otkazane (3) ostaju netaknute.
-- Dopuna: realizovane_voznje_json za dane/stavke iz nena koji fale u arhivi
-- (operativna obrisana nedeljno); broj_voznji = 21.

WITH target AS (
  SELECT f.id,
         f.realizovane_voznje_json,
         f.nenaplacene_voznje_json
  FROM public.v3_finansije f
  WHERE f.id = '50187cd4-e59c-4668-971f-fcc3de116b22'
    AND f.putnik_v3_auth_id = '270e4e95-f179-4d0c-b47e-b43bdd6cea80'
    AND f.mesec = 7
    AND f.godina = 2026
),
nena AS (
  SELECT
    e->>'operativna_id' AS op_id,
    left(e->>'datum', 10)::date AS dan,
    COALESCE((e->>'cena')::numeric, 700) AS cena,
    ord
  FROM target t,
       jsonb_array_elements(COALESCE(t.nenaplacene_voznje_json, '[]'::jsonb))
         WITH ORDINALITY AS x(e, ord)
  WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
),
existing_real AS (
  SELECT
    elem,
    elem->>'operativna_id' AS op_id,
    left(elem->>'datum', 10)::date AS dan
  FROM target t,
       jsonb_array_elements(COALESCE(t.realizovane_voznje_json, '[]'::jsonb)) elem
  WHERE NULLIF(btrim(elem->>'pokupljen_at'), '') IS NOT NULL
    AND lower(btrim(elem->>'pokupljen_at')) <> 'null'
),
existing_op AS (
  SELECT DISTINCT op_id FROM existing_real WHERE NULLIF(op_id, '') IS NOT NULL
),
backfill AS (
  SELECT jsonb_build_object(
    'operativna_id', n.op_id,
    'datum', to_char(n.dan, 'YYYY-MM-DD'),
    'pokupljen_by', NULL,
    'pokupljen_at', to_char(
      (n.dan + time '12:00') AT TIME ZONE 'Europe/Belgrade' AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'dodao_by', '270e4e95-f179-4d0c-b47e-b43bdd6cea80',
    'azurirao_by', NULL,
    'grad', 'BC',
    'vreme', '06:00:00',
    'backfill', true,
    'napomena', 'Dopuna arhive Jasmina Marinkovic jul 2026: stavka iz nenaplacene bez sačuvanog pickup-a'
  ) AS elem,
  n.dan,
  n.op_id
  FROM nena n
  WHERE NOT EXISTS (SELECT 1 FROM existing_op e WHERE e.op_id = n.op_id)
),
merged_real AS (
  SELECT COALESCE(
    (
      SELECT jsonb_agg(x.elem ORDER BY x.dan, x.ord)
      FROM (
        SELECT elem, dan, 0 AS ord FROM existing_real
        UNION ALL
        SELECT elem, dan, 1 AS ord FROM backfill
      ) x
    ),
    '[]'::jsonb
  ) AS j
),
normalized_nena AS (
  SELECT COALESCE(
    (
      SELECT jsonb_agg(
        jsonb_build_object(
          'operativna_id', n.op_id,
          'datum', to_char(n.dan, 'YYYY-MM-DD'),
          'cena', n.cena
        )
        ORDER BY n.dan, n.ord
      )
      FROM nena n
    ),
    '[]'::jsonb
  ) AS j,
  (SELECT COUNT(*)::int FROM nena) AS broj
)
UPDATE public.v3_finansije f
SET
  realizovane_voznje_json = m.j,
  nenaplacene_voznje_json = nn.j,
  broj_voznji = nn.broj,
  updated_at = now()
FROM target t
CROSS JOIN merged_real m
CROSS JOIN normalized_nena nn
WHERE f.id = t.id;
