"""
ETL Pipeline - Extract financial data from Supabase
Model uči isključivo iz ovih podataka
"""
import pandas as pd
from supabase import create_client
import config

supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)

def extract_finances() -> pd.DataFrame:
    """Extract financial data from v3_finansije"""
    response = supabase.table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records from Supabase")
    return df

def extract_users() -> pd.DataFrame:
    """Extract user data from v3_auth"""
    response = supabase.table("v3_auth").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} user records from Supabase")
    return df

def extract_requests() -> pd.DataFrame:
    """Extract request data from v3_zahtevi"""
    response = supabase.table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records from Supabase")
    return df

if __name__ == "__main__":
    # Test extraction
    finances = extract_finances()
    users = extract_users()
    requests = extract_requests()
    
    print("\nFinancial data sample:")
    print(finances.head())
