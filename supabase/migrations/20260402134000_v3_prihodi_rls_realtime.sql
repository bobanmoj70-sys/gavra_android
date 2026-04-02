BEGIN;

ALTER TABLE public.v3_prihodi ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'v3_prihodi' AND policyname = 'anon_all'
  ) THEN
    CREATE POLICY anon_all ON public.v3_prihodi
      FOR ALL
      TO anon
      USING (true)
      WITH CHECK (true);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'v3_prihodi' AND policyname = 'Enable all for anon'
  ) THEN
    CREATE POLICY "Enable all for anon" ON public.v3_prihodi
      FOR ALL
      TO anon
      USING (true)
      WITH CHECK (true);
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'v3_prihodi'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.v3_prihodi;
  END IF;
END;
$$;

COMMIT;
