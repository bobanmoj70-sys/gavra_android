"""
ETL Pipeline - Extract financial data from Supabase
Model uči iz v3_finansije + povezanih tabela (v3_auth, v3_zahtevi, v3_operativna_nedelja)
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

def extract_operativna() -> pd.DataFrame:
    """Extract operational data from v3_operativna_nedelja"""
    response = supabase.table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records from Supabase")
    return df

def extract_enriched_finances() -> pd.DataFrame:
    """Extract finances joined with user profiles and request history"""
    fin = extract_finances()
    users = extract_users()
    reqs = extract_requests()
    oper = extract_operativna()

    if 'putnik_v3_auth_id' in fin.columns and not users.empty:
        user_cols = [c for c in ['id', 'ime', 'prezime', 'role', 'tip'] if c in users.columns]
        fin = fin.merge(users[user_cols].rename(columns={'id': 'putnik_v3_auth_id'}),
                        on='putnik_v3_auth_id', how='left')

    if 'putnik_v3_auth_id' in fin.columns and not reqs.empty and 'created_by' in reqs.columns:
        req_stats = reqs.groupby('created_by').size().reset_index(name='broj_zahteva')
        fin = fin.merge(req_stats.rename(columns={'created_by': 'putnik_v3_auth_id'}),
                        on='putnik_v3_auth_id', how='left')
        fin['broj_zahteva'] = fin['broj_zahteva'].fillna(0)

    if 'putnik_v3_auth_id' in fin.columns and not oper.empty and 'created_by' in oper.columns:
        op_stats = oper.groupby('created_by').size().reset_index(name='broj_putovanja')
        fin = fin.merge(op_stats.rename(columns={'created_by': 'putnik_v3_auth_id'}),
                        on='putnik_v3_auth_id', how='left')
        fin['broj_putovanja'] = fin['broj_putovanja'].fillna(0)

    print(f"[ENRICHED] Financial data: {len(fin)} rows with cross-table features")
    return fin

if __name__ == "__main__":
    df = extract_enriched_finances()
    print("\nEnriched financial data sample:")
    print(df.head())
