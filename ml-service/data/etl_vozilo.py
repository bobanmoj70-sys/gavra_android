"""
ETL Pipeline - Extract vehicle data from Supabase
Model uci iz v3_vozila + v3_gorivo + v3_operativna_nedelja (frekvenca koriscenja)
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


def extract_vozila() -> pd.DataFrame:
    """Extract vehicle data from v3_vozila"""
    response = _get_supabase().table("v3_vozila").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} vehicle records from Supabase")
    return df


def extract_gorivo() -> pd.DataFrame:
    """Extract fuel data from v3_gorivo"""
    response = _get_supabase().table("v3_gorivo").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} fuel records from Supabase")
    return df


def extract_operativna_for_vozila() -> pd.DataFrame:
    """Extract operational trips per vehicle"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records for vehicle usage")
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


def extract_enriched_vozila() -> dict:
    """Extract ALL tables for Vehicle AI to learn from"""
    from data.etl_znanje import extract_all_tables
    all_data = extract_all_tables()
    
    # Glavni fokus na vozilima, ali uključi sve tabele za kontekst
    vozila = all_data.get('vozila', pd.DataFrame())
    
    print(f"[ENRICHED] Extracted {len(all_data)} tables for Vehicle AI")
    print(f"[ENRICHED] Primary (vozila): {len(vozila)} rows")
    
    return all_data


if __name__ == "__main__":
    data = extract_enriched_vozila()
    print("\nEnriched vehicle data sample:")
    print(data.get('vozila', pd.DataFrame()).head())
