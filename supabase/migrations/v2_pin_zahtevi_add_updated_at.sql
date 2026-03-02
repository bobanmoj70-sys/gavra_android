-- Dodaje updated_at kolonu na v2_pin_zahtevi tabelu
-- Potrebno za praćenje kada je admin odobrio/odbio zahtev

ALTER TABLE public.v2_pin_zahtevi
  ADD COLUMN IF NOT EXISTS updated_at timestamptz;

COMMENT ON COLUMN public.v2_pin_zahtevi.updated_at IS 'Timestamp kada je admin odobrio ili odbio zahtev';
