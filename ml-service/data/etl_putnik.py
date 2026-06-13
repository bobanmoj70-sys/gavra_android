"""
ETL Pipeline - Extract passenger data from Supabase
Model uci iz v3_finansije + v3_zahtevi + v3_auth + v3_operativna_nedelja
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


def extract_finansije() -> pd.DataFrame:
    """Extract financial data for passenger analysis"""
    response = _get_supabase().table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records")
    return df


def extract_zahtevi() -> pd.DataFrame:
    """Extract request data for passenger analysis"""
    response = _get_supabase().table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records")
    return df


def extract_users() -> pd.DataFrame:
    """Extract user profiles"""
    response = _get_supabase().table("v3_auth").select("id, ime, prezime, role, created_at").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} user profiles")
    return df


def extract_operativna() -> pd.DataFrame:
    """Extract travel history"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} travel records")
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
