-- Uskladi JSON kolone na v3_finansije.
-- Izvor istine za naplative jedinice: elementi nenaplacene_voznje_json.
-- 1) normalizuj nena (datum YYYY-MM-DD, unique operativna_id)
-- 2) očisti realizovane (bez ghost, unique operativna_id, datum YYYY-MM-DD)
-- 3) backfill u realizovane samo stavke koje postoje u nena a fale u arhivi
-- 4) broj_voznji = max(postojeći, nena_count, real_count) — ne smanjuje se pri uplati
--
-- NE generiše fiktivne radne dane (za razliku od ad-hoc Ljilja migracije).

WITH base AS (
  SELECT
    f.id,
    f.putnik_v3_auth_id,
    COALESCE(f.broj_voznji, 0) AS broj_voznji,
    COALESCE(f.nenaplacene_voznje_json, '[]'::jsonb) AS nena,
    COALESCE(f.realizovane_voznje_json, '[]'::jsonb) AS real
  FROM public.v3_finansije f
  WHERE f.tip = 'prihod'
    AND f.kategorija IN ('operativna_naplata', 'operativna_realizacija')
    AND (
      f.nenaplacene_voznje_json IS NOT NULL
      OR f.realizovane_voznje_json IS NOT NULL
      OR COALESCE(f.broj_voznji, 0) > 0
    )
),
norm_nena AS (
  SELECT
    b.id,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'operativna_id', btrim(e->>'operativna_id'),
          'datum', left(e->>'datum', 10),
          'cena', COALESCE(NULLIF(e->>'cena', '')::numeric, 0)
        )
        ORDER BY left(e->>'datum', 10), ord
      )
      FROM (
        SELECT DISTINCT ON (btrim(e->>'operativna_id'))
          e, ord
        FROM jsonb_array_elements(b.nena) WITH ORDINALITY AS t(e, ord)
        WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
          AND NULLIF(btrim(left(e->>'datum', 10)), '') IS NOT NULL
          AND left(e->>'datum', 10) ~ '^\d{4}-\d{2}-\d{2}$'
        ORDER BY btrim(e->>'operativna_id'), ord
      ) d
    ), '[]'::jsonb) AS nena_clean
  FROM base b
),
clean_real AS (
  SELECT
    b.id,
    COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'operativna_id', btrim(e->>'operativna_id'),
          'datum', left(COALESCE(e->>'datum', ''), 10),
          'pokupljen_by', e->>'pokupljen_by',
          'pokupljen_at', e->>'pokupljen_at',
          'dodao_by', e->>'dodao_by',
          'azurirao_by', e->>'azurirao_by',
          'grad', e->>'grad',
          'vreme', e->>'vreme'
        ) || CASE
          WHEN e ? 'backfill' THEN jsonb_build_object('backfill', e->'backfill')
          ELSE '{}'::jsonb
        END || CASE
          WHEN e ? 'napomena' THEN jsonb_build_object('napomena', e->'napomena')
          ELSE '{}'::jsonb
        END
        ORDER BY left(COALESCE(e->>'datum', ''), 10), ord
      )
      FROM (
        SELECT DISTINCT ON (btrim(e->>'operativna_id'))
          e, ord
        FROM jsonb_array_elements(b.real) WITH ORDINALITY AS t(e, ord)
        WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
          AND NULLIF(btrim(e->>'pokupljen_at'), '') IS NOT NULL
          AND lower(btrim(e->>'pokupljen_at')) <> 'null'
          AND NULLIF(btrim(left(COALESCE(e->>'datum', ''), 10)), '') IS NOT NULL
          AND left(COALESCE(e->>'datum', ''), 10) ~ '^\d{4}-\d{2}-\d{2}$'
        ORDER BY btrim(e->>'operativna_id'), ord
      ) d
    ), '[]'::jsonb) AS real_clean
  FROM base b
),
merged AS (
  SELECT
    b.id,
    b.broj_voznji,
    nn.nena_clean,
    jsonb_array_length(nn.nena_clean) AS nena_len,
    COALESCE((
      SELECT jsonb_agg(x.elem ORDER BY x.dan, x.ord)
      FROM (
        SELECT
          cr.elem,
          left(cr.elem->>'datum', 10) AS dan,
          0 AS ord
        FROM jsonb_array_elements(cr.real_clean) AS cr(elem)
        UNION ALL
        SELECT
          jsonb_build_object(
            'operativna_id', btrim(n.elem->>'operativna_id'),
            'datum', left(n.elem->>'datum', 10),
            'pokupljen_by', NULL,
            'pokupljen_at', to_char(
              ((left(n.elem->>'datum', 10)::date) + time '12:00')
                AT TIME ZONE 'Europe/Belgrade' AT TIME ZONE 'UTC',
              'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
            ),
            'dodao_by', b.putnik_v3_auth_id::text,
            'azurirao_by', NULL,
            'grad', NULL,
            'vreme', NULL,
            'backfill', true,
            'napomena', 'Uskladjivanje: stavka iz nenaplacene_voznje_json bez arhive u realizovane'
          ) AS elem,
          left(n.elem->>'datum', 10) AS dan,
          1 AS ord
        FROM jsonb_array_elements(nn.nena_clean) AS n(elem)
        WHERE NOT EXISTS (
          SELECT 1
          FROM jsonb_array_elements(cr.real_clean) r(elem)
          WHERE btrim(r.elem->>'operativna_id') = btrim(n.elem->>'operativna_id')
        )
      ) x
    ), '[]'::jsonb) AS real_merged
  FROM base b
  JOIN norm_nena nn ON nn.id = b.id
  JOIN clean_real cr ON cr.id = b.id
),
final_rows AS (
  SELECT
    m.id,
    m.nena_clean,
    m.real_merged,
    GREATEST(
      m.broj_voznji,
      m.nena_len,
      jsonb_array_length(m.real_merged)
    ) AS broj_voznji_new
  FROM merged m
)
UPDATE public.v3_finansije f
SET
  nenaplacene_voznje_json = fr.nena_clean,
  realizovane_voznje_json = fr.real_merged,
  broj_voznji = fr.broj_voznji_new,
  updated_at = now()
FROM final_rows fr
WHERE f.id = fr.id
  AND (
    f.nenaplacene_voznje_json IS DISTINCT FROM fr.nena_clean
    OR f.realizovane_voznje_json IS DISTINCT FROM fr.real_merged
    OR COALESCE(f.broj_voznji, 0) IS DISTINCT FROM fr.broj_voznji_new
  );
