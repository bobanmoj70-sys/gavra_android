-- Popunjava nenaplacene_voznje_json za postojece neplacene redove na osnovu broja voznji i cene po tipu putnika.
-- Ova migracija se moze pokrenuti samo jednom. Ako se pokrene ponovo, doci ce do dupliranja stavki.

WITH neplaceni AS (
  SELECT 
    f.id,
    f.putnik_v3_auth_id,
    f.godina,
    f.mesec,
    f.broj_voznji,
    CASE 
      WHEN LOWER(a.tip) IN ('radnik', 'ucenik') THEN COALESCE(a.cena_po_danu, 0)
      ELSE COALESCE(a.cena_po_pokupljenju, 0)
    END as cena
  FROM public.v3_finansije f
  JOIN public.v3_auth a ON a.id = f.putnik_v3_auth_id
  WHERE f.tip = 'prihod'
    AND f.kategorija = 'operativna_naplata'
    AND f.iznos = 0
    AND f.broj_voznji > 0
),
generisane_stavke AS (
  SELECT 
    n.id,
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', 'migrated:' || n.id || ':' || gs.broj,
        'datum', make_date(n.godina, n.mesec, LEAST(gs.broj, 28))::text,
        'cena', n.cena
      )
    ) as nove_stavke
  FROM neplaceni n
  CROSS JOIN LATERAL generate_series(1, n.broj_voznji) AS gs(broj)
  WHERE n.cena > 0
  GROUP BY n.id
)
UPDATE public.v3_finansije f
SET nenaplacene_voznje_json = g.nove_stavke
FROM generisane_stavke g
WHERE f.id = g.id;
