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


def extract_enriched_gorivo() -> pd.DataFrame:
    """Extract fuel joined with vehicle specs and trip frequency"""
    gorivo = extract_gorivo()
    vozila = extract_vozila()
    oper = extract_operativna()

    if not vozila.empty and 'vozilo_id' in gorivo.columns:
        gorivo = gorivo.merge(vozila.rename(columns={'id': 'vozilo_id'}),
                              on='vozilo_id', how='left')

    if not oper.empty and 'vozilo_id' in oper.columns and 'vozilo_id' in gorivo.columns:
        trip_stats = oper.groupby('vozilo_id').size().reset_index(name='broj_voznji')
        gorivo = gorivo.merge(trip_stats, on='vozilo_id', how='left')
        gorivo['broj_voznji'] = gorivo['broj_voznji'].fillna(0)

    print(f"[ENRICHED] Fuel data: {len(gorivo)} rows with vehicle & trip features")
    return gorivo


if __name__ == "__main__":
    df = extract_enriched_gorivo()
    print("\nEnriched fuel data sample:")
    print(df.head())
