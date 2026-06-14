"""
ETL Pipeline - Extract financial data from Supabase
Model uči iz v3_finansije + povezanih tabela (v3_auth, v3_zahtevi, v3_operativna_nedelja)
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

def extract_finances() -> pd.DataFrame:
    """Extract financial data from v3_finansije"""
    response = _get_supabase().table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records from Supabase")
    return df

def extract_users() -> pd.DataFrame:
    """Extract user data from v3_auth"""
    response = _get_supabase().table("v3_auth").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} user records from Supabase")
    return df

def extract_requests() -> pd.DataFrame:
    """Extract request data from v3_zahtevi"""
    response = _get_supabase().table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records from Supabase")
    return df

def extract_operativna() -> pd.DataFrame:
    """Extract operational data from v3_operativna_nedelja"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records from Supabase")
    return df

def extract_all_supabase_tables() -> dict:
    """Dinamicki ucitaj SVE dostupne tabele iz Supabase"""
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

def extract_enriched_finances() -> dict:
    """Extract ALL tables for Financial AI to learn from"""
    from data.etl_znanje import extract_all_tables
    all_data = extract_all_tables()
    
    # Glavni fokus na finansijama, ali uključi sve tabele za kontekst
    finansije = all_data.get('finansije', pd.DataFrame())
    
    print(f"[ENRICHED] Extracted {len(all_data)} tables for Financial AI")
    print(f"[ENRICHED] Primary (finansije): {len(finansije)} rows")
    
    return all_data

if __name__ == "__main__":
    data = extract_enriched_finances()
    print("\nEnriched financial data sample:")
    print(data.get('finansije', pd.DataFrame()).head())
