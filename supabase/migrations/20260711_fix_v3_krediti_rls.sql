-- Popravka RLS policy-ja za v3_krediti.
-- Aplikacija se povezuje preko Supabase anon key-a (custom closed-auth preko Edge funkcija),
-- pa klijentske operacije idu kao 'anon' uloga, ne 'authenticated'.
-- Bez ove izmene INSERT/UPDATE vraca gresku "violates row-level security policy".

drop policy if exists "Autentikovani korisnici imaju pun pristup v3_krediti" on public.v3_krediti;

create policy "Anonimni korisnici imaju pun pristup v3_krediti"
  on public.v3_krediti
  for all
  to anon
  using (true)
  with check (true);
