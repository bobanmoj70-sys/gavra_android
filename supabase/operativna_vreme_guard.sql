-- Sanacija postojećih redova: vreme iz rasporeda
with to_fix as (
  select o.id, r.vreme as vreme_from_raspored
  from v3_operativna_nedelja o
  join v3_gps_raspored r
    on r.putnik_id = o.putnik_id
   and r.datum = o.datum
   and upper(r.grad) = upper(o.grad)
   and r.aktivno is not false
  where o.vreme is null
)
update v3_operativna_nedelja o
set vreme = t.vreme_from_raspored,
    updated_at = now(),
    updated_by = coalesce(o.updated_by, 'system_fix_null_vreme')
from to_fix t
where o.id = t.id;

-- Sanacija preostalih redova: fallback na dodeljeno/željeno vreme
update v3_operativna_nedelja
set vreme = coalesce(dodeljeno_vreme, zeljeno_vreme),
    updated_at = now(),
    updated_by = coalesce(updated_by, 'system_fix_null_vreme_from_assigned')
where aktivno = true
  and vreme is null
  and coalesce(dodeljeno_vreme, zeljeno_vreme) is not null;

-- Guard: za aktivne redove vreme ne sme ostati NULL
create or replace function public.fn_v3_operativna_ensure_vreme()
returns trigger
language plpgsql
as $$
begin
  if new.vreme is null then
    new.vreme := coalesce(new.dodeljeno_vreme, new.zeljeno_vreme);
  end if;

  if coalesce(new.aktivno, false) = true and new.vreme is null then
    raise exception 'v3_operativna_nedelja.vreme ne sme biti NULL za aktivne redove (putnik_id=% datum=% grad=%)',
      new.putnik_id, new.datum, new.grad;
  end if;

  return new;
end;
$$;

drop trigger if exists tr_v3_operativna_ensure_vreme on public.v3_operativna_nedelja;

create trigger tr_v3_operativna_ensure_vreme
before insert or update of vreme, dodeljeno_vreme, zeljeno_vreme, aktivno
on public.v3_operativna_nedelja
for each row
execute function public.fn_v3_operativna_ensure_vreme();