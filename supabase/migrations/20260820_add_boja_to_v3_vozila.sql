-- Sopstvena boja kombija (nezavisna od boje vozača).
-- Koristi se za vizuelnu identifikaciju kombija (npr. emoji/registracija u AppBar-u
-- vozača) po slotu, bez obzira koji je vozač trenutno ulogovan.

ALTER TABLE public.v3_vozila
  ADD COLUMN IF NOT EXISTS boja text;

COMMENT ON COLUMN public.v3_vozila.boja IS
  'Hex boja kombija (npr. #E53935) za vizuelnu identifikaciju u UI-u, nezavisno od boje vozača.';
