"""
ETL Pipeline - Extract vehicle data from Supabase
Model uci iz v3_vozila + v3_gorivo + v3_operativna_nedelja (frekvenca koriscenja)
"""
import pandas as pd
from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)


def extract_vozila() -> pd.DataFrame:
    """Extract vehicle data from v3_vozila"""
    response = supabase.table("v3_vozila").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} vehicle records from Supabase")
    return df


def extract_gorivo() -> pd.DataFrame:
    """Extract fuel data from v3_gorivo"""
    response = supabase.table("v3_gorivo").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} fuel records from Supabase")
    return df


def extract_operativna_for_vozila() -> pd.DataFrame:
    """Extract operational trips per vehicle"""
    response = supabase.table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records for vehicle usage")
    return df


def extract_enriched_vozila() -> pd.DataFrame:
    """Extract vehicles joined with fuel and trip frequency"""
    vozila = extract_vozila()
    gorivo = extract_gorivo()
    oper = extract_operativna_for_vozila()

    if not gorivo.empty and 'vozilo_id' in gorivo.columns and 'id' in vozila.columns:
        gor_stats = gorivo.groupby('vozilo_id').agg({
            'trenutno_stanje_litri': 'last',
            'kapacitet_litri': 'last',
            'cena_po_litru': 'mean'
        }).reset_index()
        vozila = vozila.merge(gor_stats, left_on='id', right_on='vozilo_id', how='left')

    if not oper.empty and 'vozilo_id' in oper.columns and 'id' in vozila.columns:
        trip_stats = oper.groupby('vozilo_id').size().reset_index(name='broj_voznji_30dana')
        vozila = vozila.merge(trip_stats, left_on='id', right_on='vozilo_id', how='left')
        vozila['broj_voznji_30dana'] = vozila['broj_voznji_30dana'].fillna(0)

    print(f"[ENRICHED] Vehicle data: {len(vozila)} rows with fuel & trip features")
    return vozila


if __name__ == "__main__":
    df = extract_enriched_vozila()
    print("\nEnriched vehicle data sample:")
    print(df.head())
