-- Prebacuje postojece vožnje iz v3_operativna_nedelja u arhivsku kolonu realizovane_voznje_json u v3_finansije.
-- Ova migracija se moze pokrenuti samo jednom. Ako se pokrene ponovo, moze doci do dupliranja stavki.

WITH voznje_po_finansiji AS (
  SELECT 
    f.id as finansije_id,
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', o.id,
        'datum', o.datum,
        'pokupljen_by', o.pokupljen_by,
        'pokupljen_at', o.pokupljen_at,
        'dodao_by', o.created_by,
        'azurirao_by', o.updated_by,
        'grad', o.grad,
        'vreme', o.polazak_at
      )
    ) as nove_voznje
  FROM public.v3_finansije f
  JOIN public.v3_operativna_nedelja o 
    ON o.created_by = f.putnik_v3_auth_id
    AND EXTRACT(YEAR FROM o.datum) = f.godina
    AND EXTRACT(MONTH FROM o.datum) = f.mesec
  WHERE f.tip = 'prihod'
    AND f.kategorija = 'operativna_naplata'
  GROUP BY f.id
)
UPDATE public.v3_finansije f
SET realizovane_voznje_json = COALESCE(f.realizovane_voznje_json, '[]'::jsonb) || v.nove_voznje
FROM voznje_po_finansiji v
WHERE f.id = v.finansije_id;
