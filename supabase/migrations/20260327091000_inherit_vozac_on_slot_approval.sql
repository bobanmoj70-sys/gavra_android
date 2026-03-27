-- Hotfix: nasleđivanje vozaca pri odobrenju novog putnika u već postojećem slotu
-- Datum: 2026-03-25
-- Cilj:
-- 1) Pri transferu odobrenog zahteva u operativnu tabelu, automatski nasledi `vozac_id`
--    iz istog slota (datum+grad+vreme) samo ako je vozač jednoznačan.
-- 2) Bezbedan backfill za postojeće redove sa `vozac_id IS NULL` bez konflikata.

CREATE OR REPLACE FUNCTION public.transfer_to_operativna_nedelja()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
declare
    target_time time;
    desired_status text;
    v_zeljeno_vreme time;
    v_slot_vozac_id uuid;
begin
    -- zeljeno_vreme u v3_zahtevi je text, kastujemo u time
    v_zeljeno_vreme := NULLIF(TRIM(NEW.zeljeno_vreme), '')::time;

    target_time := case
        when new.status = 'alternativa' then null
        else coalesce(new.dodeljeno_vreme, v_zeljeno_vreme)
    end;

    -- Nasledi vozaca iz istog slota samo ako je jednoznacan (nema konflikta)
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

-- Backfill: popuni vozac_id za postojece aktivne odobrene/alternativa redove
-- samo kada je vozac u slotu jednoznacan.
WITH slot_inherited AS (
  SELECT
    o.datum,
    o.grad,
    coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) AS slot_time,
    CASE
      WHEN count(DISTINCT o.vozac_id) = 1 THEN (min(o.vozac_id::text))::uuid
      ELSE NULL
    END AS inherited_vozac_id
  FROM public.v3_operativna_nedelja o
  WHERE o.aktivno = true
    AND o.status_final IN ('odobreno','alternativa')
    AND o.vozac_id IS NOT NULL
  GROUP BY o.datum, o.grad, coalesce(o.dodeljeno_vreme, o.zeljeno_vreme)
)
UPDATE public.v3_operativna_nedelja o
SET vozac_id = s.inherited_vozac_id,
    updated_at = now(),
    updated_by = coalesce(o.updated_by, 'hotfix_inherit_vozac')
FROM slot_inherited s
WHERE o.vozac_id IS NULL
  AND o.aktivno = true
  AND o.status_final IN ('odobreno','alternativa')
  AND coalesce(o.dodeljeno_vreme, o.zeljeno_vreme) = s.slot_time
  AND o.datum = s.datum
  AND o.grad = s.grad
  AND s.inherited_vozac_id IS NOT NULL;
