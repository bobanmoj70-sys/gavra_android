-- Usklađivanje kategorija rashoda sa dogovorenim setom
-- plata -> plate
-- amortizacija -> majstori

UPDATE public.v3_finansije
SET kategorija = 'plate'
WHERE tip = 'rashod'
  AND kategorija = 'plata';

UPDATE public.v3_finansije
SET kategorija = 'majstori'
WHERE tip = 'rashod'
  AND kategorija = 'amortizacija';
