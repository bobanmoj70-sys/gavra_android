-- Uklanjanje zastarelog mehanizma koji je prepisivao max_mesta u v3_kapacitet_slots
-- pri svakom update-u v3_app_settings (VS 14:00 -> 18, BC 06:00 -> 14, BC 07:00 -> 20,
-- VS 16:30/19:00 -> 12 itd) preko ON CONFLICT DO UPDATE.
-- Trigger i funkcije ne postoje u migracijama repoa; zivele su samo u produkcionoj bazi.
-- Jedini izvor default kapaciteta ostaje seed_kapacitet_slots_for_active_week.
drop trigger if exists trg_v3_seed_bc_kapacitet_defaults_on_settings on public.v3_app_settings;
drop function if exists public.v3_seed_bc_kapacitet_defaults_from_settings();
drop function if exists public.v3_seed_bc_kapacitet_defaults_for_week(date);
