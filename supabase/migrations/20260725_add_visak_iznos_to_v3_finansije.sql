-- Dodaje kolonu za praćenje "viška" (preplate/kredita) po mesečnom master redu
-- u v3_finansije. Kada putnik plati više nego što trenutno duguje (npr. plati
-- paušal unapred pre nego što su sve vožnje tog meseca evidentirane), razlika
-- se čuva ovde umesto da se izgubi — i koristi se da pokrije naredne vožnje
-- pre nego što se one uopšte upišu u nenaplacene_voznje_json.
alter table public.v3_finansije
  add column if not exists visak_iznos numeric not null default 0;

comment on column public.v3_finansije.visak_iznos is
  'Preplaćen iznos (kredit) za ovaj mesečni red, koji se prvo troši na naredne vožnje pre generisanja duga.';
