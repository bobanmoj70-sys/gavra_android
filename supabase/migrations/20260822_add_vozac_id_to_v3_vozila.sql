-- Trenutna dodela kombija vozaču.
-- Jedan vozač vozi najviše jedan kombi; kombi može biti i bez vozača.

ALTER TABLE public.v3_vozila
  ADD COLUMN IF NOT EXISTS vozac_id uuid REFERENCES public.v3_auth(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS v3_vozila_vozac_id_uidx
  ON public.v3_vozila (vozac_id)
  WHERE vozac_id IS NOT NULL;

COMMENT ON COLUMN public.v3_vozila.vozac_id IS
  'Vozač kome je kombi trenutno dodeljen. Jedan vozač = jedan kombi.';
