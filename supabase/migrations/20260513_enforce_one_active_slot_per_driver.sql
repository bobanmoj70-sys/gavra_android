-- Enforce: najviše jedan aktivan slot po vozaču.
-- 1) Sanacija postojećih duplikata: zadrži najnoviji (datum/vreme), ostale prebaci u neaktivan.
WITH ranked_active AS (
  SELECT
    ctid,
    vozac_v3_auth_id,
    ROW_NUMBER() OVER (
      PARTITION BY vozac_v3_auth_id
      ORDER BY datum DESC, vreme DESC, ctid DESC
    ) AS rn
  FROM public.v3_trenutna_dodela_slot
  WHERE status = 'aktivan'
    AND vozac_v3_auth_id IS NOT NULL
)
UPDATE public.v3_trenutna_dodela_slot AS s
SET status = 'neaktivan'
FROM ranked_active AS r
WHERE s.ctid = r.ctid
  AND r.rn > 1;

-- 2) Pravilo: jedan aktivan slot po vozaču.
CREATE UNIQUE INDEX IF NOT EXISTS ux_v3_trenutna_dodela_slot_one_active_per_vozac
ON public.v3_trenutna_dodela_slot (vozac_v3_auth_id)
WHERE status = 'aktivan'
  AND vozac_v3_auth_id IS NOT NULL;
