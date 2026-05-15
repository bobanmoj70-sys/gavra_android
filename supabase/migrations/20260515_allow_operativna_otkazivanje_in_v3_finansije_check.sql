alter table public.v3_finansije
  drop constraint if exists v3_finansije_tip_kategorija_check;

alter table public.v3_finansije
  add constraint v3_finansije_tip_kategorija_check
  check (
    (
      tip = 'prihod'
      and kategorija = any (
        array[
          'operativna_naplata',
          'operativna_realizacija',
          'dnevna_predaja',
          'operativna_otkazivanje'
        ]
      )
    )
    or
    (
      tip = 'rashod'
      and kategorija = any (
        array[
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
        ]
      )
    )
  );
