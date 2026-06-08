"""
ETL Pipeline - Extract request data from Supabase
Model uci iz v3_zahtevi + v3_operativna_nedelja + v3_finansije
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


def extract_operativna() -> pd.DataFrame:
    """Extract completed trips"""
    response = supabase.table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records")
    return df


def extract_finansije() -> pd.DataFrame:
    """Extract financial correlation"""
    response = supabase.table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records")
    return df


def extract_enriched_zahtevi() -> pd.DataFrame:
    """Extract requests joined with completed trips and revenue"""
    zahtevi = extract_zahtevi()
    oper = extract_operativna()
    fin = extract_finansije()

    if not oper.empty and 'created_by' in oper.columns and 'created_by' in zahtevi.columns:
        op_stats = oper.groupby('created_by').size().reset_index(name='zavrsenih_putovanja')
        zahtevi = zahtevi.merge(op_stats, on='created_by', how='left')
        zahtevi['zavrsenih_putovanja'] = zahtevi['zavrsenih_putovanja'].fillna(0)

    if not fin.empty and 'putnik_v3_auth_id' in fin.columns and 'created_by' in zahtevi.columns:
        fin_stats = fin.groupby('putnik_v3_auth_id')['iznos'].sum().reset_index(name='ukupni_prihod')
        zahtevi = zahtevi.merge(fin_stats, left_on='created_by', right_on='putnik_v3_auth_id', how='left')
        zahtevi['ukupni_prihod'] = zahtevi['ukupni_prihod'].fillna(0)

    print(f"[ENRICHED] Request data: {len(zahtevi)} rows with completion & revenue features")
    return zahtevi
