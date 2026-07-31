-- Spoji duple master redove v3_finansije (isti putnik+godina+mesec+kategorija).
-- Uzrok: race app INSERT vs trigger INSERT pri pokupljanju/naplati.
--
-- Pravila:
-- 1) keeper = red sa novijim created_at (ili veći id ako isto)
-- 2) JSON nizovi: union elemenata, unique po operativna_id (real/nena/otk) / uplata_id (uplate)
-- 3) iznos = suma uplate_json.iznos
-- 4) visak_iznos = max(visak sa oba reda)
-- 5) broj_voznji = max(postojeći, unique real, unique nena)
-- 6) obriši loser red
--
-- Primljeno live 2026-07-31 ~11:06 (4 para → 4 keepers).
-- Keepers:
--   Mitar Jankov     3d3066b9-d95c-493f-a367-afbe74715178  (obrisan a83e1b31-...)
--   Bilja kusic      3e3491b5-a247-4dd1-9497-a7696799fd12  (obrisan 6b3832b6-...)
--   Sofija Irović    11d493f3-2a1f-42bb-a3d7-48e52be15b0c  (obrisan bff79188-...)
--   Jana Nikolajev   c367c9f7-2a71-4eec-a2a8-deee860c9468  (obrisan ef034c13-...)

WITH dups AS (
  SELECT putnik_v3_auth_id, godina, mesec, kategorija
  FROM public.v3_finansije
  WHERE tip = 'prihod'
    AND kategorija IN ('operativna_naplata', 'operativna_realizacija')
    AND putnik_v3_auth_id IS NOT NULL
  GROUP BY 1, 2, 3, 4
  HAVING COUNT(*) > 1
),
ranked AS (
  SELECT
    f.*,
    ROW_NUMBER() OVER (
      PARTITION BY f.putnik_v3_auth_id, f.godina, f.mesec, f.kategorija
      ORDER BY f.created_at DESC NULLS LAST, f.id DESC
    ) AS rn
  FROM public.v3_finansije f
  JOIN dups d
    ON d.putnik_v3_auth_id = f.putnik_v3_auth_id
   AND d.godina = f.godina
   AND d.mesec = f.mesec
   AND d.kategorija = f.kategorija
  WHERE f.tip = 'prihod'
),
keepers AS (
  SELECT * FROM ranked WHERE rn = 1
),
losers AS (
  SELECT * FROM ranked WHERE rn > 1
),
merged AS (
  SELECT
    k.id AS keeper_id,
    -- realizovane: unique operativna_id
    COALESCE((
      SELECT jsonb_agg(elem ORDER BY left(COALESCE(elem->>'datum',''), 10), elem->>'operativna_id')
      FROM (
        SELECT DISTINCT ON (btrim(e->>'operativna_id')) e AS elem
        FROM (
          SELECT jsonb_array_elements(COALESCE(k.realizovane_voznje_json, '[]'::jsonb)) AS e
          UNION ALL
          SELECT jsonb_array_elements(COALESCE(l.realizovane_voznje_json, '[]'::jsonb)) AS e
          FROM losers l
          WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
            AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        ) all_r
        WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
        ORDER BY btrim(e->>'operativna_id'),
                 NULLIF(btrim(e->>'pokupljen_at'), '') NULLS LAST
      ) u
    ), '[]'::jsonb) AS real_merged,
    -- nenaplacene: unique operativna_id
    COALESCE((
      SELECT jsonb_agg(elem ORDER BY left(COALESCE(elem->>'datum',''), 10), elem->>'operativna_id')
      FROM (
        SELECT DISTINCT ON (btrim(e->>'operativna_id')) e AS elem
        FROM (
          SELECT jsonb_array_elements(COALESCE(k.nenaplacene_voznje_json, '[]'::jsonb)) AS e
          UNION ALL
          SELECT jsonb_array_elements(COALESCE(l.nenaplacene_voznje_json, '[]'::jsonb)) AS e
          FROM losers l
          WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
            AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        ) all_n
        WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
        ORDER BY btrim(e->>'operativna_id')
      ) u
    ), '[]'::jsonb) AS nena_merged,
    -- otkazane: unique operativna_id
    COALESCE((
      SELECT jsonb_agg(elem ORDER BY left(COALESCE(elem->>'datum',''), 10), elem->>'operativna_id')
      FROM (
        SELECT DISTINCT ON (btrim(e->>'operativna_id')) e AS elem
        FROM (
          SELECT jsonb_array_elements(COALESCE(k.otkazane_voznje_json, '[]'::jsonb)) AS e
          UNION ALL
          SELECT jsonb_array_elements(COALESCE(l.otkazane_voznje_json, '[]'::jsonb)) AS e
          FROM losers l
          WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
            AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        ) all_o
        WHERE NULLIF(btrim(e->>'operativna_id'), '') IS NOT NULL
        ORDER BY btrim(e->>'operativna_id')
      ) u
    ), '[]'::jsonb) AS otk_merged,
    -- uplate: unique uplata_id (fallback whole object text)
    COALESCE((
      SELECT jsonb_agg(elem ORDER BY COALESCE(elem->>'naplatio_at', elem->>'datum'), elem->>'uplata_id')
      FROM (
        SELECT DISTINCT ON (
          COALESCE(NULLIF(btrim(e->>'uplata_id'), ''), md5(e::text))
        ) e AS elem
        FROM (
          SELECT jsonb_array_elements(COALESCE(k.uplate_json, '[]'::jsonb)) AS e
          UNION ALL
          SELECT jsonb_array_elements(COALESCE(l.uplate_json, '[]'::jsonb)) AS e
          FROM losers l
          WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
            AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        ) all_u
        ORDER BY COALESCE(NULLIF(btrim(e->>'uplata_id'), ''), md5(e::text))
      ) u
    ), '[]'::jsonb) AS uplate_merged,
    GREATEST(
      COALESCE(k.visak_iznos, 0),
      COALESCE((
        SELECT MAX(COALESCE(l.visak_iznos, 0))
        FROM losers l
        WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
          AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
      ), 0)
    ) AS visak_merged,
    GREATEST(
      COALESCE(k.broj_voznji, 0),
      COALESCE((
        SELECT MAX(COALESCE(l.broj_voznji, 0))
        FROM losers l
        WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
          AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
      ), 0)
    ) AS broj_scalar_max,
    -- prefer non-null payment meta from any row
    COALESCE(k.naplaceno_by, (
      SELECT l.naplaceno_by FROM losers l
      WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
        AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        AND l.naplaceno_by IS NOT NULL
      ORDER BY l.updated_at DESC NULLS LAST
      LIMIT 1
    )) AS naplaceno_by_merged,
    COALESCE(NULLIF(k.naplatio_ime, ''), (
      SELECT NULLIF(l.naplatio_ime, '') FROM losers l
      WHERE l.putnik_v3_auth_id = k.putnik_v3_auth_id
        AND l.godina = k.godina AND l.mesec = k.mesec AND l.kategorija = k.kategorija
        AND NULLIF(l.naplatio_ime, '') IS NOT NULL
      ORDER BY l.updated_at DESC NULLS LAST
      LIMIT 1
    )) AS naplatio_ime_merged
  FROM keepers k
),
final_vals AS (
  SELECT
    m.keeper_id,
    m.real_merged,
    m.nena_merged,
    m.otk_merged,
    m.uplate_merged,
    m.visak_merged,
    m.naplaceno_by_merged,
    m.naplatio_ime_merged,
    COALESCE((
      SELECT SUM(COALESCE(NULLIF(e->>'iznos', '')::numeric, 0))
      FROM jsonb_array_elements(m.uplate_merged) e
    ), 0) AS iznos_merged,
    COALESCE((
      SELECT (e->>'iznos')::numeric
      FROM jsonb_array_elements(m.uplate_merged) e
      ORDER BY COALESCE(e->>'naplatio_at', e->>'datum') DESC NULLS LAST
      LIMIT 1
    ), 0) AS poslednja_dopuna_merged,
    GREATEST(
      m.broj_scalar_max,
      COALESCE(jsonb_array_length(m.real_merged), 0),
      COALESCE(jsonb_array_length(m.nena_merged), 0)
    ) AS broj_merged
  FROM merged m
),
upd AS (
  UPDATE public.v3_finansije f
  SET
    realizovane_voznje_json = fv.real_merged,
    nenaplacene_voznje_json = fv.nena_merged,
    otkazane_voznje_json = fv.otk_merged,
    uplate_json = fv.uplate_merged,
    iznos = fv.iznos_merged,
    visak_iznos = fv.visak_merged,
    broj_voznji = fv.broj_merged,
    poslednja_dopuna = fv.poslednja_dopuna_merged,
    naplaceno_by = fv.naplaceno_by_merged,
    naplatio_ime = fv.naplatio_ime_merged,
    updated_at = now()
  FROM final_vals fv
  WHERE f.id = fv.keeper_id
  RETURNING f.id
)
DELETE FROM public.v3_finansije f
USING losers l
WHERE f.id = l.id;
