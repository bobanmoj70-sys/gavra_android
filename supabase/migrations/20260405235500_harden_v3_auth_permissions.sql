begin;

-- Table grants: remove broad access for anon/authenticated.
revoke all on table public.v3_auth from anon;
revoke all on table public.v3_auth from authenticated;

grant select on table public.v3_auth to authenticated;

-- Function grants: remove default/public execution and grant only required roles.
revoke all on function public.v3_auth_link_current_user(text) from public;
revoke all on function public.v3_auth_phone_exists(text) from public;
revoke all on function public.v3_normalize_phone(text) from public;

revoke all on function public.v3_auth_link_current_user(text) from anon;
revoke all on function public.v3_normalize_phone(text) from anon;
revoke all on function public.v3_normalize_phone(text) from authenticated;

grant execute on function public.v3_auth_link_current_user(text) to authenticated;

grant execute on function public.v3_auth_phone_exists(text) to anon;
grant execute on function public.v3_auth_phone_exists(text) to authenticated;

commit;