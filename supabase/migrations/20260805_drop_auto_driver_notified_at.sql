-- Kolona više nije u upotrebi: driver nudge push je uklonjen iz
-- v3-auto-prepare-termins; tracking se pokreće samo iz foregrounda
-- (V3VozacScreen auto-start T-15). auto_notified_at ostaje za putnike.
ALTER TABLE public.v3_trenutna_dodela_slot
  DROP COLUMN IF EXISTS auto_driver_notified_at;
