-- 1) Globalno: ukloni ghost stavke iz realizovane_voznje_json (bez pokupljen_at).
-- Operativna se briše nedeljno; jedini dokaz realizacije je pokupljen_at u arhivi.
UPDATE public.v3_finansije f
SET
  realizovane_voznje_json = sub.cleaned,
  updated_at = now()
FROM (
  SELECT
    id,
    COALESCE(
      (
        SELECT jsonb_agg(elem ORDER BY ord)
        FROM jsonb_array_elements(COALESCE(realizovane_voznje_json, '[]'::jsonb))
          WITH ORDINALITY AS t(elem, ord)
        WHERE NULLIF(btrim(elem->>'pokupljen_at'), '') IS NOT NULL
          AND lower(btrim(elem->>'pokupljen_at')) <> 'null'
      ),
      '[]'::jsonb
    ) AS cleaned
  FROM public.v3_finansije
  WHERE tip = 'prihod'
    AND kategorija IN ('operativna_naplata', 'operativna_realizacija')
    AND realizovane_voznje_json IS NOT NULL
    AND jsonb_typeof(realizovane_voznje_json) = 'array'
) sub
WHERE f.id = sub.id
  AND f.realizovane_voznje_json IS DISTINCT FROM sub.cleaned;

-- 2) Otkazane: ukloni tačne duplikate (isti operativna_id) globalno u otkazane_voznje_json.
UPDATE public.v3_finansije f
SET
  otkazane_voznje_json = sub.cleaned,
  updated_at = now()
FROM (
  SELECT
    id,
    COALESCE(
      (
        SELECT jsonb_agg(elem ORDER BY ord)
        FROM (
          SELECT DISTINCT ON (elem->>'operativna_id')
            elem,
            ord
          FROM jsonb_array_elements(COALESCE(otkazane_voznje_json, '[]'::jsonb))
            WITH ORDINALITY AS t(elem, ord)
          WHERE NULLIF(btrim(elem->>'operativna_id'), '') IS NOT NULL
          ORDER BY elem->>'operativna_id', ord
        ) d
      ),
      '[]'::jsonb
    ) AS cleaned
  FROM public.v3_finansije
  WHERE tip = 'prihod'
    AND otkazane_voznje_json IS NOT NULL
    AND jsonb_typeof(otkazane_voznje_json) = 'array'
) sub
WHERE f.id = sub.id
  AND f.otkazane_voznje_json IS DISTINCT FROM sub.cleaned;

-- 3) Ljilja Rakićević (radnik, 700/dan) — jul 2026:
--    Jul ima 23 radna dana; jedini potvrđeni odsustvo = 22.07 (otkaz) → 22 naplativa dana.
--    Arhiva je imala samo 13 dana sa pickup-om jer se operativna briše nedeljno.
--    Dopuna: backfill realizovane + nenaplaćene za sve radne dane osim 22.07.
--    uplate_json prazan → nema potrošenog duga.
WITH target AS (
  SELECT f.id, f.realizovane_voznje_json
  FROM public.v3_finansije f
  WHERE f.putnik_v3_auth_id = '4f698f6f-76bc-4bca-bcc2-a559f8fcb482'
    AND f.mesec = 7
    AND f.godina = 2026
    AND f.tip = 'prihod'
    AND f.kategorija IN ('operativna_naplata', 'operativna_realizacija')
  ORDER BY f.created_at DESC
  LIMIT 1
),
radni AS (
  SELECT d::date AS dan
  FROM generate_series(date '2026-07-01', date '2026-07-31', interval '1 day') d
  WHERE EXTRACT(ISODOW FROM d) BETWEEN 1 AND 5
    AND d::date <> date '2026-07-22'
),
existing_real AS (
  SELECT elem,
         left(elem->>'datum', 10)::date AS dan
  FROM target t,
       jsonb_array_elements(COALESCE(t.realizovane_voznje_json, '[]'::jsonb)) elem
  WHERE NULLIF(btrim(elem->>'pokupljen_at'), '') IS NOT NULL
    AND lower(btrim(elem->>'pokupljen_at')) <> 'null'
),
existing_dani AS (
  SELECT DISTINCT dan FROM existing_real
),
backfill AS (
  SELECT jsonb_build_object(
    'operativna_id', 'backfill:4f698f6f-76bc-4bca-bcc2-a559f8fcb482:' || to_char(r.dan, 'YYYY-MM-DD'),
    'datum', to_char(r.dan, 'YYYY-MM-DD'),
    'pokupljen_by', NULL,
    'pokupljen_at', to_char(
      (r.dan + time '12:00') AT TIME ZONE 'Europe/Belgrade' AT TIME ZONE 'UTC',
      'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
    ),
    'dodao_by', '4f698f6f-76bc-4bca-bcc2-a559f8fcb482',
    'azurirao_by', NULL,
    'grad', 'BC',
    'vreme', '06:00:00',
    'backfill', true,
    'napomena', 'Dopuna arhive: radni dan bez sačuvanog pickup-a (operativna obrisana)'
  ) AS elem,
  r.dan
  FROM radni r
  WHERE NOT EXISTS (SELECT 1 FROM existing_dani e WHERE e.dan = r.dan)
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
nena_days AS (
  SELECT DISTINCT ON (left(elem->>'datum', 10))
    left(elem->>'datum', 10) AS dan,
    elem->>'operativna_id' AS operativna_id
  FROM (
    SELECT jsonb_array_elements((SELECT j FROM merged_real)) AS elem
  ) s
  WHERE NULLIF(btrim(elem->>'pokupljen_at'), '') IS NOT NULL
  ORDER BY left(elem->>'datum', 10),
           CASE WHEN elem->>'backfill' = 'true' THEN 1 ELSE 0 END,
           elem->>'pokupljen_at'
),
new_nena AS (
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', n.operativna_id,
        'datum', n.dan,
        'cena', 700
      ) ORDER BY n.dan
    ),
    '[]'::jsonb
  ) AS j,
  COUNT(*)::int AS broj
  FROM nena_days n
)
UPDATE public.v3_finansije f
SET
  realizovane_voznje_json = m.j,
  nenaplacene_voznje_json = nn.j,
  broj_voznji = nn.broj,
  updated_at = now()
FROM target t
CROSS JOIN merged_real m
CROSS JOIN new_nena nn
WHERE f.id = t.id;
