-- HERE WeGo install listing URLs (remote config only; not hardcoded in app binary).
ALTER TABLE public.v3_app_settings
  ADD COLUMN IF NOT EXISTS here_wego_install_url_android text,
  ADD COLUMN IF NOT EXISTS here_wego_install_url_ios text;

COMMENT ON COLUMN public.v3_app_settings.here_wego_install_url_android IS
  'Optional store listing URL for installing HERE WeGo on Android (served at runtime).';
COMMENT ON COLUMN public.v3_app_settings.here_wego_install_url_ios IS
  'Optional store listing URL for installing HERE WeGo on iOS (served at runtime).';

UPDATE public.v3_app_settings
SET
  here_wego_install_url_android = COALESCE(
    NULLIF(trim(here_wego_install_url_android), ''),
    'https://play.google.com/store/apps/details?id=com.here.app.maps'
  ),
  here_wego_install_url_ios = COALESCE(
    NULLIF(trim(here_wego_install_url_ios), ''),
    'https://apps.apple.com/app/id955837750'
  ),
  updated_at = now()
WHERE id = 'global';
