"""
ETL Pipeline - Extract vehicle data from Supabase
Model uci iskljucivo iz v3_vozila podataka
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


if __name__ == "__main__":
    vozila = extract_vozila()
    gorivo = extract_gorivo()
    print("\nVehicle data sample:")
    print(vozila.head())
    print("\nFuel data sample:")
    print(gorivo.head())
