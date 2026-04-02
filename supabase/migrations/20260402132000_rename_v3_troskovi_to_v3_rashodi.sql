BEGIN;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'v3_troskovi'
  ) AND NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'v3_rashodi'
  ) THEN
    ALTER TABLE public.v3_troskovi RENAME TO v3_rashodi;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'v3_rashodi' AND c.conname = 'v3_troskovi_pkey'
  ) THEN
    ALTER TABLE public.v3_rashodi RENAME CONSTRAINT v3_troskovi_pkey TO v3_rashodi_pkey;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'v3_rashodi' AND c.conname = 'v3_troskovi_vozac_id_fkey'
  ) THEN
    ALTER TABLE public.v3_rashodi RENAME CONSTRAINT v3_troskovi_vozac_id_fkey TO v3_rashodi_vozac_id_fkey;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'fn_v3_sync_troskovi' AND p.prokind = 'f'
  ) THEN
    ALTER FUNCTION public.fn_v3_sync_troskovi() RENAME TO fn_v3_sync_rashodi;
  END IF;
END;
$$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_trigger tg
    JOIN pg_class t ON t.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'v3_rashodi' AND tg.tgname = 'tr_v3_troskovi_sync' AND NOT tg.tgisinternal
  ) THEN
    ALTER TRIGGER tr_v3_troskovi_sync ON public.v3_rashodi RENAME TO tr_v3_rashodi_sync;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_trigger tg
    JOIN pg_class t ON t.oid = tg.tgrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'public' AND t.relname = 'v3_rashodi' AND tg.tgname = 'tr_v3_troskovi_updated_at' AND NOT tg.tgisinternal
  ) THEN
    ALTER TRIGGER tr_v3_troskovi_updated_at ON public.v3_rashodi RENAME TO tr_v3_rashodi_updated_at;
  END IF;
END;
$$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'v3_rashodi'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.v3_rashodi;
  END IF;
END;
$$;

COMMIT;
