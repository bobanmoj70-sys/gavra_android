"""
ETL Pipeline - Extract passenger data from Supabase
Model uci iz v3_finansije + v3_zahtevi + v3_auth + v3_operativna_nedelja
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


def extract_users() -> pd.DataFrame:
    """Extract user profiles"""
    response = supabase.table("v3_auth").select("id, ime, prezime, role, created_at").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} user profiles")
    return df


def extract_operativna() -> pd.DataFrame:
    """Extract travel history"""
    response = supabase.table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} travel records")
    return df
