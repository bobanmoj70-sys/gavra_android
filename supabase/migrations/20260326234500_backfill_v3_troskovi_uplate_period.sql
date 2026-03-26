with parsed as (
  select
    id,
    regexp_match(naziv, '\((\d{1,2})/(\d{4})\)') as m
  from public.v3_troskovi
  where kategorija = 'voznja'
    and aktivno = true
    and naziv like 'Uplata:%'
)
update public.v3_troskovi t
set
  mesec = (p.m)[1]::int,
  godina = (p.m)[2]::int
from parsed p
where t.id = p.id
  and p.m is not null
  and (
    coalesce(t.mesec, 0) <> (p.m)[1]::int
    or coalesce(t.godina, 0) <> (p.m)[2]::int
  );
