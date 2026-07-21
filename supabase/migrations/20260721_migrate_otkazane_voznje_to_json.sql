-- Prebacuje postojece otkazane vožnje iz v3_operativna_nedelja
-- u arhivsku kolonu otkazane_voznje_json u v3_finansije.
-- Ova migracija se moze pokrenuti samo jednom. Trigger ce nastaviti
-- da održava kolonu u sinhronizaciji za sve nove promene.

WITH otkazivanja_po_finansiji AS (
  SELECT
    f.id AS finansije_id,
    jsonb_agg(
      jsonb_build_object(
        'operativna_id', o.id::text,
        'datum', o.datum::text,
        'otkazao_by', o.otkazano_by::text,
        'otkazano_at', o.otkazano_at::text,
        'tip_otkazivanja', CASE WHEN o.otkazano_by = o.created_by THEN 'putnik' ELSE 'vozac' END,
        'grad', o.grad,
        'vreme', o.polazak_at
      )
      ORDER BY o.otkazano_at
    ) AS nove_stavke
  FROM public.v3_finansije f
  JOIN public.v3_operativna_nedelja o
    ON o.created_by = f.putnik_v3_auth_id
    AND EXTRACT(YEAR FROM o.datum) = f.godina
    AND EXTRACT(MONTH FROM o.datum) = f.mesec
  WHERE f.tip = 'prihod'
    AND f.kategorija = 'operativna_naplata'
    AND o.otkazano_at IS NOT NULL
  GROUP BY f.id
)
UPDATE public.v3_finansije f
SET otkazane_voznje_json = COALESCE(f.otkazane_voznje_json, '[]'::jsonb) || v.nove_stavke,
    updated_at = now()
FROM otkazivanja_po_finansiji v
WHERE f.id = v.finansije_id;

