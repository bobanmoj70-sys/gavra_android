-- Root fix: ensure operativna naplata always syncs to v3_finansije

drop trigger if exists tr_v3_sync_operativna_to_finansije on public.v3_operativna_nedelja;

create trigger tr_v3_sync_operativna_to_finansije
after insert or update on public.v3_operativna_nedelja
for each row
execute function public.fn_v3_sync_operativna_to_finansije();

-- Backfill: re-fire sync only for paid operativna rows missing prihod entry.
update public.v3_operativna_nedelja o
set updated_at = coalesce(o.updated_at, now())
where o.naplacen_at is not null
  and coalesce(o.naplacen_iznos, 0) > 0
  and not exists (
    select 1
    from public.v3_finansije f
    where f.operativna_id = o.id
      and f.tip = 'prihod'
  );
