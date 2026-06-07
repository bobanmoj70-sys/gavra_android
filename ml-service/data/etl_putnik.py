"""
ETL Pipeline - Extract passenger data from Supabase
Model uci iskljucivo iz v3_finansije i v3_zahtevi podataka
"""
import pandas as pd
from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)


def extract_finansije() -> pd.DataFrame:
    """Extract financial data for passenger analysis"""
    response = supabase.table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records")
    return df


def extract_zahtevi() -> pd.DataFrame:
    """Extract request data for passenger analysis"""
    response = supabase.table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records")
    return df
