import 'dotenv/config';
import postgres from 'postgres';

const db = process.env.DATABASE_URL;
if (!db) {
    console.log(JSON.stringify({ ok: false, error: 'DATABASE_URL missing in supabase-mcp/.env' }, null, 2));
    process.exit(0);
}

const sql = postgres(db, { ssl: 'require' });

async function run() {
    const out = {};

    out.tables = await sql.unsafe(`
    select table_name
    from information_schema.tables
    where table_schema='public'
      and table_name in ('v3_vozac_lokacije','v3_operativna_nedelja')
    order by table_name;
  `);

    out.columns_v3_vozac_lokacije = await sql.unsafe(`
    select column_name, data_type, is_nullable, column_default
    from information_schema.columns
    where table_schema='public' and table_name='v3_vozac_lokacije'
    order by ordinal_position;
  `);

    out.constraints_v3_vozac_lokacije = await sql.unsafe(`
    select con.conname as constraint_name,
           con.contype as constraint_type,
           pg_get_constraintdef(con.oid) as definition
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname='public' and rel.relname='v3_vozac_lokacije'
    order by con.conname;
  `);

    out.indexes_v3_vozac_lokacije = await sql.unsafe(`
    select indexname, indexdef
    from pg_indexes
    where schemaname='public' and tablename='v3_vozac_lokacije'
    order by indexname;
  `);

    out.fn_route_optimize = await sql.unsafe(`
    select n.nspname as schema,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as returns
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public'
      and p.proname in ('fn_v3_optimize_pickup_route')
    order by p.proname;
  `);

    out.functions_like_route_optimize = await sql.unsafe(`
    select n.nspname as schema,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as returns
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname='public'
      and (
        p.proname ilike '%optimiz%route%'
        or p.proname ilike '%optimize%pickup%'
        or p.proname ilike '%route%pickup%'
      )
    order by p.proname;
  `);

    out.functions_like_v3_optimize_any_schema = await sql.unsafe(`
    select n.nspname as schema,
           p.proname as function_name,
           pg_get_function_identity_arguments(p.oid) as args,
           pg_get_function_result(p.oid) as returns
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where (
      p.proname ilike '%v3%optimiz%'
      or p.proname ilike '%optimize%'
      or p.proname ilike '%route%'
    )
    order by n.nspname, p.proname;
  `);

    out.columns_v3_operativna_route_related = await sql.unsafe(`
    select column_name, data_type, is_nullable, column_default
    from information_schema.columns
    where table_schema='public' and table_name='v3_operativna_nedelja'
      and column_name in ('pickup_lat','pickup_lng','pickup_naziv','route_order','vreme','datum','grad','vozac_id','aktivno')
    order by ordinal_position;
  `);

    out.counts = await sql.unsafe(`
    select
      (select count(*) from public.v3_vozac_lokacije) as vozac_lokacije_total,
      (select count(*) from public.v3_vozac_lokacije where aktivno = true) as vozac_lokacije_aktivno,
      (select count(*) from public.v3_operativna_nedelja) as operativna_total,
      (select count(*) from public.v3_operativna_nedelja where route_order is not null) as operativna_with_route_order;
  `);

    out.triggers_v3_vozac_lokacije = await sql.unsafe(`
    select trigger_name, event_manipulation, action_timing, action_statement
    from information_schema.triggers
    where event_object_schema='public'
      and event_object_table='v3_vozac_lokacije'
    order by trigger_name, event_manipulation;
  `);

    out.sample_v3_vozac_lokacije = await sql.unsafe(`
    select vozac_id, lat, lng, bearing, brzina, grad, vreme_polaska, smer, aktivno, updated_at
    from public.v3_vozac_lokacije
    order by updated_at desc nulls last
    limit 3;
  `);

    console.log(JSON.stringify({ ok: true, ...out }, null, 2));
}

run()
    .catch((error) => {
        console.log(JSON.stringify({ ok: false, error: String(error) }, null, 2));
        process.exitCode = 1;
    })
    .finally(async () => {
        await sql.end({ timeout: 5 });
    });
