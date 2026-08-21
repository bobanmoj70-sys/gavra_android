-- Jedna istina: svi zahtevi čekaju 10 minuta pre obrade.
-- Validacija datuma za dnevne putnike ostaje (pre 16:00 = danas, posle 16:00 = sutra).

CREATE OR REPLACE FUNCTION public.set_zahtev_scheduled_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
declare
    putnik_tip text;
    prijava_vreme time;
    prijava_datum date;
begin
    if new.status is distinct from 'obrada' then
        return new;
    end if;

    if new.scheduled_at is not null then
        return new;
    end if;

    select tip into putnik_tip
    from public.v3_auth
    where id = new.created_by;

    prijava_vreme := (coalesce(new.created_at, now()) at time zone 'Europe/Belgrade')::time;
    prijava_datum := (coalesce(new.created_at, now()) at time zone 'Europe/Belgrade')::date;

    if putnik_tip = 'dnevni' then
        if prijava_vreme < '16:00'::time then
            if new.datum::date <> prijava_datum then
                raise exception 'Dnevni zahtev pre 16:00 mora biti za tekući datum.';
            end if;
        else
            if new.datum::date <> (prijava_datum + interval '1 day')::date then
                raise exception 'Dnevni zahtev od 16:00 mora biti za sutrašnji datum.';
            end if;
        end if;
    end if;

    new.scheduled_at := coalesce(new.created_at, now()) + interval '10 minutes';
    return new;
end;
$function$;
