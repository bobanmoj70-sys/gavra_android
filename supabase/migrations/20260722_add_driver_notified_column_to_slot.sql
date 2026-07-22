-- Razdvaja flag za notifikaciju vozača od flaga za notifikaciju putnika.
-- Ranije je oba koristila isti auto_notified_at, pa ako bi RPC za putnike
-- (v3_notify_passengers_driver_started) bacio grešku PRE upisa auto_notified_at,
-- sledeći cron ciklus bi ponovo slao push vozaču da pokrene tracking (duplikat).
ALTER TABLE public.v3_trenutna_dodela_slot
  ADD COLUMN IF NOT EXISTS auto_driver_notified_at timestamptz;

COMMENT ON COLUMN public.v3_trenutna_dodela_slot.auto_driver_notified_at IS 'Kada je vozacu automatski poslat push da pokrene tracking (odvojeno od auto_notified_at koji prati notifikaciju putnika)';
