-- HOTFIX (incident): ensure new requests are visible in operativna-driven screens immediately
-- Reason: operativna became primary source, but trigger previously synced only AFTER UPDATE,
-- causing fresh INSERT rows (status=obrada) to be missing in operativna until later transitions.

create or replace function public.transfer_to_operativna_nedelja()
returns trigger
language plpgsql
security definer
as $function$
declare
    target_time time;
    desired_status text;
begin
    target_time := coalesce(new.dodeljeno_vreme, new.zeljeno_vreme);

    if new.status in ('obrada','odobreno','alternativa') then
        desired_status := case when new.status = 'alternativa' then 'alternativa' else new.status end;

        update v3_operativna_nedelja o
        set zeljeno_vreme = new.zeljeno_vreme,
            dodeljeno_vreme = target_time,
            status_final = desired_status,
            aktivno = true,
            broj_mesta = new.broj_mesta,
            updated_at = coalesce(new.updated_at, now()),
            updated_by = coalesce(new.updated_by, 'sync_od_zahteva')
        where o.putnik_id = new.putnik_id
          and o.datum = new.datum
          and o.grad = new.grad
          and o.aktivno = true;

        if not found then
            insert into v3_operativna_nedelja (
                putnik_id,
                datum,
                grad,
                zeljeno_vreme,
                dodeljeno_vreme,
                status_final,
                broj_mesta,
                aktivno,
                created_at,
                created_by,
                updated_at,
                updated_by
            ) values (
                new.putnik_id,
                new.datum,
                new.grad,
                new.zeljeno_vreme,
                target_time,
                desired_status,
                new.broj_mesta,
                true,
                coalesce(new.updated_at, now()),
                coalesce(new.updated_by, 'auto_transfer') || '_auto_transfer',
                coalesce(new.updated_at, now()),
                coalesce(new.updated_by, 'auto_transfer') || '_auto_transfer'
            );
        end if;

    elsif new.status in ('otkazano','odbijeno')
          and (tg_op = 'INSERT' or old.status is distinct from new.status) then
        update v3_operativna_nedelja o
        set status_final = new.status,
            aktivno = false,
            updated_at = coalesce(new.updated_at, now()),
            updated_by = coalesce(new.updated_by, 'sync_od_zahteva')
        where o.putnik_id = new.putnik_id
          and o.datum = new.datum
          and o.grad = new.grad
          and o.aktivno = true
          and o.status_final in ('obrada','odobreno','alternativa');
    end if;

    return new;
end;
$function$;

drop trigger if exists zahtev_to_operativna_trigger on public.v3_zahtevi;
create trigger zahtev_to_operativna_trigger
after insert or update on public.v3_zahtevi
for each row execute function public.transfer_to_operativna_nedelja();
