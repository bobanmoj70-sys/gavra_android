-- Fix: prenesi koristi_sekundarnu i adresa_id_override iz v3_zahtevi u v3_operativna_nedelja
-- + backfill postojećih aktivnih redova

create or replace function public.transfer_to_operativna_nedelja()
 returns trigger
 language plpgsql
as $function$
declare
    target_time time;
    desired_status text;
    v_zeljeno_vreme time;
    v_slot_vozac_id uuid;
begin
    v_zeljeno_vreme := NULLIF(TRIM(NEW.zeljeno_vreme), '')::time;

    target_time := case
        when new.status = 'alternativa' then null
        else coalesce(new.dodeljeno_vreme, v_zeljeno_vreme)
    end;

    if target_time is not null then
        select case when count(distinct o.vozac_id) = 1 then (min(o.vozac_id::text))::uuid else null end
          into v_slot_vozac_id
        from public.v3_operativna_nedelja o
        where o.datum = new.datum
          and o.grad = new.grad
          and o.aktivno = true
          and o.status_final in ('odobreno','alternativa')
          and o.vozac_id is not null
          and coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) = target_time
          and o.putnik_id is distinct from new.putnik_id;
    else
        v_slot_vozac_id := null;
    end if;

    if new.status in ('obrada','odobreno','alternativa') then
        desired_status := case when new.status = 'alternativa' then 'alternativa' else new.status end;

        update v3_operativna_nedelja o
        set zeljeno_vreme = v_zeljeno_vreme,
            dodeljeno_vreme = target_time,
            status_final = desired_status,
            aktivno = true,
            broj_mesta = new.broj_mesta,
            koristi_sekundarnu = coalesce(new.koristi_sekundarnu, false),
            adresa_id_override = new.adresa_id_override,
            vozac_id = coalesce(o.vozac_id, v_slot_vozac_id),
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
                koristi_sekundarnu,
                adresa_id_override,
                vozac_id,
                aktivno,
                created_at,
                created_by,
                updated_at,
                updated_by
            ) values (
                new.putnik_id,
                new.datum,
                new.grad,
                v_zeljeno_vreme,
                target_time,
                desired_status,
                new.broj_mesta,
                coalesce(new.koristi_sekundarnu, false),
                new.adresa_id_override,
                v_slot_vozac_id,
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

update public.v3_operativna_nedelja o
set koristi_sekundarnu = coalesce(z.koristi_sekundarnu, false),
    adresa_id_override = z.adresa_id_override,
    updated_at = greatest(coalesce(o.updated_at, now()), coalesce(z.updated_at, now())),
    updated_by = coalesce(z.updated_by, 'sync_backfill_koristi_sekundarnu')
from public.v3_zahtevi z
where o.putnik_id = z.putnik_id
  and o.datum = z.datum
  and o.grad = z.grad
  and o.aktivno = true
  and z.aktivno = true
  and (
    o.koristi_sekundarnu is distinct from coalesce(z.koristi_sekundarnu, false)
    or o.adresa_id_override is distinct from z.adresa_id_override
  );
