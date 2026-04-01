create or replace function public.fn_v3_gorivo_promene_apply()
returns trigger
language plpgsql
as $$
declare
  delta_old numeric(12,2);
  delta_new numeric(12,2);
begin
  if tg_op = 'INSERT' then
    delta_new := case
      when new.tip_promene = 'dopuna' then new.kolicina_litri
      when new.tip_promene = 'tocenje' then -new.kolicina_litri
      when new.tip_promene = 'korekcija' then new.kolicina_litri
      else 0
    end;

    update public.v3_gorivo
    set
      trenutno_stanje_litri = greatest(0, coalesce(trenutno_stanje_litri, 0) + delta_new),
      brojac_pistolj_litri = coalesce(new.brojac_posle_litri, brojac_pistolj_litri),
      cena_po_litru = coalesce(new.cena_po_litru, cena_po_litru),
      dug_iznos = coalesce(dug_iznos, 0) + coalesce(new.dug_promena, 0),
      updated_at = now()
    where id = new.gorivo_id;

    return new;
  end if;

  if tg_op = 'DELETE' then
    delta_old := case
      when old.tip_promene = 'dopuna' then old.kolicina_litri
      when old.tip_promene = 'tocenje' then -old.kolicina_litri
      when old.tip_promene = 'korekcija' then old.kolicina_litri
      else 0
    end;

    update public.v3_gorivo
    set
      trenutno_stanje_litri = greatest(0, coalesce(trenutno_stanje_litri, 0) - delta_old),
      dug_iznos = coalesce(dug_iznos, 0) - coalesce(old.dug_promena, 0),
      updated_at = now()
    where id = old.gorivo_id;

    return old;
  end if;

  if tg_op = 'UPDATE' then
    delta_old := case
      when old.tip_promene = 'dopuna' then old.kolicina_litri
      when old.tip_promene = 'tocenje' then -old.kolicina_litri
      when old.tip_promene = 'korekcija' then old.kolicina_litri
      else 0
    end;

    delta_new := case
      when new.tip_promene = 'dopuna' then new.kolicina_litri
      when new.tip_promene = 'tocenje' then -new.kolicina_litri
      when new.tip_promene = 'korekcija' then new.kolicina_litri
      else 0
    end;

    update public.v3_gorivo
    set
      trenutno_stanje_litri = greatest(0, coalesce(trenutno_stanje_litri, 0) - delta_old),
      dug_iznos = coalesce(dug_iznos, 0) - coalesce(old.dug_promena, 0),
      updated_at = now()
    where id = old.gorivo_id;

    update public.v3_gorivo
    set
      trenutno_stanje_litri = greatest(0, coalesce(trenutno_stanje_litri, 0) + delta_new),
      brojac_pistolj_litri = coalesce(new.brojac_posle_litri, brojac_pistolj_litri),
      cena_po_litru = coalesce(new.cena_po_litru, cena_po_litru),
      dug_iznos = coalesce(dug_iznos, 0) + coalesce(new.dug_promena, 0),
      updated_at = now()
    where id = new.gorivo_id;

    return new;
  end if;

  return null;
end;
$$;

drop trigger if exists trg_v3_gorivo_promene_apply on public.v3_gorivo_promene;

create trigger trg_v3_gorivo_promene_apply
after insert or update or delete on public.v3_gorivo_promene
for each row
execute function public.fn_v3_gorivo_promene_apply();
