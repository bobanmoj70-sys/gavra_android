"""
ETL Pipeline - Extract request data from Supabase
Model uci iskljucivo iz v3_zahtevi podataka
"""
import pandas as pd
from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)


def extract_zahtevi() -> pd.DataFrame:
    """Extract request data from v3_zahtevi"""
    response = supabase.table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records from Supabase")
    return df
