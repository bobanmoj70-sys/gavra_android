"""
ETL Pipeline - Extract request data from Supabase
Model uci iz v3_zahtevi + v3_operativna_nedelja + v3_finansije
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


def extract_zahtevi() -> pd.DataFrame:
    """Extract request data from v3_zahtevi"""
    response = _get_supabase().table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records from Supabase")
    return df


def extract_operativna() -> pd.DataFrame:
    """Extract completed trips"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records")
    return df


def extract_finansije() -> pd.DataFrame:
    """Extract financial correlation"""
    response = _get_supabase().table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records")
    return df


def extract_all_supabase_tables() -> dict:
    """Dinamicki ucitaj SVE dostupne tabele"""
    from data.etl_znanje import discover_all_tables
    tables = {}
    for table_name in discover_all_tables():
        try:
            r = _get_supabase().table(table_name).select('*').limit(200).execute()
            df = pd.DataFrame(r.data)
            if not df.empty:
                tables[table_name] = df
        except Exception:
            pass
    return tables


def extract_enriched_zahtevi() -> dict:
    """Extract ALL tables for AI to learn from - dinamički otkrije šta je bitno"""
    from data.etl_znanje import extract_all_tables
    all_data = extract_all_tables()
    
    # Glavni fokus na zahtevima, ali uključi sve tabele za kontekst
    zahtevi = all_data.get('zahtevi', pd.DataFrame())
    
    print(f"[ENRICHED] Extracted {len(all_data)} tables for AI learning")
    print(f"[ENRICHED] Primary (zahtevi): {len(zahtevi)} rows")
    
    return all_data
