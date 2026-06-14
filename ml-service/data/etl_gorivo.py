"""
ETL Pipeline - Extract fuel data from Supabase
Model uci iz v3_gorivo + v3_vozila + v3_operativna_nedelja (prava potrosnja)
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


def extract_gorivo() -> pd.DataFrame:
    """Extract fuel data from v3_gorivo"""
    response = _get_supabase().table("v3_gorivo").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} fuel records from Supabase")
    return df


def extract_vozila() -> pd.DataFrame:
    """Extract vehicle specs"""
    response = _get_supabase().table("v3_vozila").select("id, marka, model, godina_proizvodnje, trenutna_km").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} vehicle specs")
    return df


def extract_operativna() -> pd.DataFrame:
    """Extract trips for real consumption"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} trips for fuel analysis")
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


def extract_enriched_gorivo() -> dict:
    """Extract ALL tables for Fuel AI to learn from"""
    from data.etl_znanje import extract_all_tables
    all_data = extract_all_tables()
    
    # Glavni fokus na gorivu, ali uključi sve tabele za kontekst
    gorivo = all_data.get('gorivo', pd.DataFrame())
    
    print(f"[ENRICHED] Extracted {len(all_data)} tables for Fuel AI")
    print(f"[ENRICHED] Primary (gorivo): {len(gorivo)} rows")
    
    return all_data


if __name__ == "__main__":
    data = extract_enriched_gorivo()
    print("\nEnriched fuel data sample:")
    print(data.get('gorivo', pd.DataFrame()).head())
