-- Generiše placeholder stavke u realizovane_voznje_json za redove gde je
-- skalarni broj_voznji > 0 a realizovane_voznje_json je prazan.
-- Ovim se osigurava da aplikacija (koja broji vožnje isključivo iz JSON kolone)
-- prikazuje isti broj vožnji kao postojeći broj_voznji.
-- Ova migracija se moze pokrenuti samo jednom.

WITH redovi_za_migraciju AS (
  SELECT
    f.id,
    f.putnik_v3_auth_id,
    f.godina,
    f.mesec,
    f.broj_voznji,
    f.created_at
  FROM public.v3_finansije f
  WHERE f.tip = 'prihod'
    AND f.kategorija = 'operativna_naplata'
    AND f.broj_voznji > 0
    AND COALESCE(f.realizovane_voznje_json, '[]'::jsonb) = '[]'::jsonb
),
generisane_voznje AS (
  SELECT
    r.id,
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', 'migrated:' || r.id || ':' || gs.broj,
        'datum', make_date(r.godina, r.mesec, LEAST(gs.broj, 28))::text,
        'pokupljen_by', NULL,
        'pokupljen_at', NULL,
        'dodao_by', r.putnik_v3_auth_id::text,
        'azurirao_by', NULL,
        'grad', NULL,
        'vreme', NULL
      )
      ORDER BY gs.broj
    ) AS nove_stavke
  FROM redovi_za_migraciju r
  CROSS JOIN LATERAL generate_series(1, r.broj_voznji) AS gs(broj)
  GROUP BY r.id
)
UPDATE public.v3_finansije f
SET realizovane_voznje_json = g.nove_stavke,
    updated_at = now()
FROM generisane_voznje g
WHERE f.id = g.id;

