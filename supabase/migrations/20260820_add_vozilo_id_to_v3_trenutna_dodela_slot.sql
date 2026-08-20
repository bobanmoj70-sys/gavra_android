-- Dodela kombija po slotu (datum + grad + vreme), isto kao dodela vozača.
-- Ranije je kombi bio vezan trajno za vozača (v3_vozila.vozac_id), globalno za sve dane.
-- Sada admin može po potrebi izabrati DRUGI kombi za konkretan slot/termin,
-- bez menjanja trajne dodele vozač↔kombi.

ALTER TABLE public.v3_trenutna_dodela_slot
  ADD COLUMN IF NOT EXISTS vozilo_id uuid REFERENCES public.v3_vozila(id) ON DELETE SET NULL;

COMMENT ON COLUMN public.v3_trenutna_dodela_slot.vozilo_id IS
  'Kombi dodeljen ovom konkretnom slotu (datum+grad+vreme). Ako je NULL, koristi se trajna dodela vozača (v3_vozila.vozac_id).';

CREATE INDEX IF NOT EXISTS v3_trenutna_dodela_slot_vozilo_id_idx
  ON public.v3_trenutna_dodela_slot (vozilo_id)
  WHERE vozilo_id IS NOT NULL;
