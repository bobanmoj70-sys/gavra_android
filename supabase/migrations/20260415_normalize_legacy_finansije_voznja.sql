-- Normalize legacy income entries for consistent naziv/kategorija values.
-- Scope: old manual rows that used kategorija='voznja' with naziv 'Uplata: ...'.

update public.v3_finansije
set
  naziv = 'Naplata prevoza',
  kategorija = 'operativna_naplata',
  updated_at = now()
where tip = 'prihod'
  and operativna_id is null
  and kategorija = 'voznja'
  and naziv like 'Uplata:%';
