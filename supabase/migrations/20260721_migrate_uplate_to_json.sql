-- Popunjava uplate_json za postojeće prihodne redove iz v3_finansije
-- koji imaju uplatu u skalarnim kolonama (iznos > 0) ali prazan uplate_json.
-- Ova migracija se moze pokrenuti samo jednom. Ako se pokrene ponovo,
-- zastita preko uplata_id sprecice dupliranje.

WITH redovi_sa_uplatom AS (
  SELECT
    f.id,
    f.putnik_v3_auth_id,
    f.iznos,
    f.naplaceno_by,
    f.updated_at,
    COALESCE(f.uplate_json, '[]'::jsonb) AS postojece_uplate
  FROM public.v3_finansije f
  WHERE f.tip = 'prihod'
    AND f.kategorija = 'operativna_naplata'
    AND f.iznos > 0
)
UPDATE public.v3_finansije f
SET uplate_json = CASE
  WHEN r.postojece_uplate = '[]'::jsonb THEN
    jsonb_build_array(
      jsonb_build_object(
        'uplata_id', 'migrated:' || r.id,
        'datum', COALESCE(r.updated_at, now())::text,
        'iznos', r.iznos,
        'naplatio_by', r.naplaceno_by::text
      )
    )
  ELSE
    r.postojece_uplate
END,
updated_at = now()
FROM redovi_sa_uplatom r
WHERE f.id = r.id;

