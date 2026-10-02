-- Praćenje prenosa viška (kredita) između mesečnih master redova.
-- Ulaz: koliko je viška ušlo u ovaj mesec iz prethodnog.
-- Izlaz: koliko je viška otišlo iz ovog meseca u naredni.
-- Potrebno da formula obaveze ostane tačna i POSLE permanentnog prenosa
-- (kada se visak_iznos na izvornom mesecu postavi na 0).
alter table public.v3_finansije
  add column if not exists preneti_visak_ulaz numeric not null default 0;

alter table public.v3_finansije
  add column if not exists preneti_visak_izlaz numeric not null default 0;

comment on column public.v3_finansije.preneti_visak_ulaz is
  'Ukupan višak prenet U ovaj mesečni red iz ranijeg meseca (kumulativno).';

comment on column public.v3_finansije.preneti_visak_izlaz is
  'Ukupan višak prenet IZ ovog mesečnog reda u kasniji mesec (kumulativno).';
