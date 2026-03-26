create table if not exists public.v3_putnici_arhiva (
  id uuid not null default gen_random_uuid (),
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null default now(),
  putnik_id uuid not null,
  putnik_ime_prezime text not null,
  iznos numeric null default 0,
  tip_akcije text not null,
  za_mesec integer null default 0,
  za_godinu integer null default 0,
  vozac_id uuid not null,
  vozac_ime_prezime text not null,
  aktivno boolean null default true,
  updated_by text null,
  created_by text null,
  constraint v3_arhiva_putnika_pkey primary key (id)
) TABLESPACE pg_default;

do $$
begin
  if not exists (
    select 1
    from pg_trigger
    where tgname = 'tr_v3_arhiva_putnika_updated_at'
      and tgrelid = 'public.v3_putnici_arhiva'::regclass
  ) then
    create trigger tr_v3_arhiva_putnika_updated_at before
    update on public.v3_putnici_arhiva for each row
    execute function set_updated_at();
  end if;
end
$$;
