-- Enforce allowed kategorija values per tip in v3_finansije.

alter table public.v3_finansije
drop constraint if exists v3_finansije_tip_kategorija_check;

alter table public.v3_finansije
add constraint v3_finansije_tip_kategorija_check
check (
  (
    tip = 'prihod'
    and kategorija in ('operativna_naplata')
  )
  or
  (
    tip = 'rashod'
    and kategorija in (
      'plate',
      'kredit',
      'gorivo',
      'registracija',
      'yu_auto',
      'majstori',
      'porez',
      'alimentacija',
      'racuni',
      'ostalo'
    )
  )
);
