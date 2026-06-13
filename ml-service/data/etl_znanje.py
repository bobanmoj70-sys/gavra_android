"""
ETL Pipeline - Extract ALL data for AI Knowledge Base
Agregira podatke iz svih tabela za AI asistenta
"""
import pandas as pd
from supabase import create_client
import config

_supabase = None

def _get_supabase():
    global _supabase
    if _supabase is None:
        _supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)
    return _supabase


_discovered_tables_cache = None


def _check_table_exists(table_name: str) -> bool:
    """Proverava da li tabela postoji u Supabase"""
    try:
        r = _get_supabase().table(table_name).select('*').limit(1).execute()
        return True
    except Exception:
        return False


def discover_all_tables() -> list:
    """Dinamicki otkriva SVE tabele u Supabase — proverava sve poznate sablone"""
    global _discovered_tables_cache
    if _discovered_tables_cache is not None:
        return _discovered_tables_cache

    # Svi poznati sabloni tabela (postojeci, sadasnji, buduci)
    candidates = [
        # V3 tabele
        'v3_auth', 'v3_zahtevi', 'v3_operativna_nedelja', 'v3_finansije',
        'v3_vozila', 'v3_gorivo', 'v3_trenutna_dodela', 'v3_trenutna_dodela_slot',
        'v3_eta_results', 'v3_vozac_lokacija', 'v3_eta_log', 'v3_vozac_status',
        # V2 tabele (istorijske)
        'v2_auth', 'v2_zahtevi', 'v2_operativna', 'v2_finansije',
        'v2_vozila', 'v2_gorivo',
        # AI tabele
        'ai_znanje', 'ai_embeddings', 'ai_conversations', 'ai_logs',
        # Dodatne tabele
        'adrese', 'lokacije', 'cenovnik', 'notifikacije', 'logs',
    ]

    existing = []
    for table_name in candidates:
        if _check_table_exists(table_name):
            existing.append(table_name)

    _discovered_tables_cache = existing
    print(f"[Discovery] Pronadjeno {len(existing)} tabela: {existing}")
    return existing


def get_table_columns(table_name: str) -> list:
    """Dynamically get columns for a table"""
    try:
        response = _get_supabase().table(table_name).select('*').limit(1).execute()
        if response.data:
            return list(response.data[0].keys())
    except Exception as e:
        print(f"[Znanje] Could not get columns for {table_name}: {e}")
    return []


# Mapiranje praviih imena tabela na alias-e koje modeli ocekuju
_TABLE_NAME_MAP = {
    'v3_auth': 'users',
    'v3_zahtevi': 'zahtevi',
    'v3_operativna_nedelja': 'operativna',
    'v3_finansije': 'finansije',
    'v3_vozila': 'vozila',
    'v3_gorivo': 'gorivo',
}


def extract_all_tables() -> dict:
    """Extract data from ALL discovered tables for AI context"""
    data = {}
    all_tables = discover_all_tables()

    for table_name in all_tables:
        try:
            # Get columns first to know what to select
            columns = get_table_columns(table_name)
            if not columns:
                continue

            # Build select string, limit to avoid overload
            select_cols = ', '.join(columns[:50])  # max 50 columns

            # Query with limit
            r = _get_supabase().table(table_name).select(select_cols).limit(200).execute()
            df = pd.DataFrame(r.data)

            # Map to alias for known tables, keep original for new ones
            alias = _TABLE_NAME_MAP.get(table_name, table_name)

            if not df.empty:
                data[alias] = df
                print(f"[Znanje] {table_name} -> {alias}: {len(df)} rows, {len(columns)} cols")
            else:
                print(f"[Znanje] {table_name} -> {alias}: empty")

        except Exception as e:
            print(f"[Znanje] {table_name} error: {e}")

    return data


def get_database_schema() -> dict:
    """Dynamically discover schema for ALL tables — sa alias mapiranjem"""
    schema = {}
    all_tables = discover_all_tables()

    for table_name in all_tables:
        try:
            columns = get_table_columns(table_name)
            if columns:
                alias = _TABLE_NAME_MAP.get(table_name, table_name)
                schema[alias] = columns
        except Exception as e:
            print(f"[Znanje] Schema error for {table_name}: {e}")

    return schema
