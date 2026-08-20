-- Uklanja koncept "trajno dodeljen kombi vozaču" (v3_vozila.vozac_id).
-- Kombi se sada dodeljuje isključivo po slotu (datum+grad+vreme) preko
-- v3_trenutna_dodela_slot.vozilo_id, bez ikakvog fallback-a na trajnu vezu.

DROP INDEX IF EXISTS public.v3_vozila_vozac_id_uidx;

ALTER TABLE public.v3_vozila
  DROP COLUMN IF EXISTS vozac_id;
