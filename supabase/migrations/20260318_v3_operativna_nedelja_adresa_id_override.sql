-- Dodaje adresa_id_override kolonu u v3_operativna_nedelja
-- Čuva ID konkretne adrese kada vozač/dispečer bira adresu koja nije ni
-- primarna (adresa_bc_id / adresa_vs_id) ni sekundarna (adresa_bc_id_2 / adresa_vs_id_2) putnika.
-- Ima prednost nad koristiSekundarnu flagom.

ALTER TABLE v3_operativna_nedelja
  ADD COLUMN IF NOT EXISTS adresa_id_override UUID REFERENCES v3_adrese(id) ON DELETE SET NULL;

COMMENT ON COLUMN v3_operativna_nedelja.adresa_id_override IS
  'Override adresa za ovaj unos. Ako je setovano, koristi se ova adresa umesto putnikove primarne/sekundarne.';
