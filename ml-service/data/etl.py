"""
ETL Pipeline - Extract financial data from Supabase
Model uči iz v3_finansije + povezanih tabela (v3_auth, v3_zahtevi, v3_operativna_nedelja)
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

def extract_finances() -> pd.DataFrame:
    """Extract financial data from v3_finansije"""
    response = _get_supabase().table("v3_finansije").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} financial records from Supabase")
    return df

def extract_users() -> pd.DataFrame:
    """Extract user data from v3_auth"""
    response = _get_supabase().table("v3_auth").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} user records from Supabase")
    return df

def extract_requests() -> pd.DataFrame:
    """Extract request data from v3_zahtevi"""
    response = _get_supabase().table("v3_zahtevi").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} request records from Supabase")
    return df

def extract_operativna() -> pd.DataFrame:
    """Extract operational data from v3_operativna_nedelja"""
    response = _get_supabase().table("v3_operativna_nedelja").select("*").execute()
    df = pd.DataFrame(response.data)
    print(f"Extracted {len(df)} operational records from Supabase")
    return df

def extract_all_supabase_tables() -> dict:
    """Dinamicki ucitaj SVE dostupne tabele iz Supabase"""
    from data.etl_znanje import discover_all_tables
    tables = {}
    for table_name in discover_all_tables():
        try:
            r = _get_supabase().table(table_name).select('*').limit(200).execute()
            df = pd.DataFrame(r.data)
            if not df.empty:
                tables[table_name] = df
        except Exception as e:
            print(f"[ETL] Skip {table_name}: {e}")
    return tables


def extract_enriched_finances() -> pd.DataFrame:
    """Extract finances joined with ALL available Supabase tables"""
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

    # Dinamicki: merge sa SVIM tabelama koje imaju putnik_v3_auth_id ili slicne kolone
    all_tables = extract_all_supabase_tables()
    for table_name, df in all_tables.items():
        if table_name == 'v3_finansije' or df.empty:
            continue
        # Ako tabela ima putnik_v3_auth_id
        if 'putnik_v3_auth_id' in df.columns and 'putnik_v3_auth_id' in fin.columns:
            # Izracunaj agregate po putniku
            numeric_cols = df.select_dtypes(include=['number']).columns.tolist()
            if numeric_cols:
                agg = {c: 'mean' for c in numeric_cols[:3]}
                stats = df.groupby('putnik_v3_auth_id').agg(agg).reset_index()
                # Dodaj prefiks da izbegnes konflikte
                stats.columns = ['putnik_v3_auth_id'] + [f'{table_name}_{c}' for c in stats.columns[1:]]
                fin = fin.merge(stats, on='putnik_v3_auth_id', how='left')
        # Ako tabela ima created_by
        if 'created_by' in df.columns and 'putnik_v3_auth_id' in fin.columns:
            stats = df.groupby('created_by').size().reset_index(name=f'{table_name}_count')
            fin = fin.merge(stats.rename(columns={'created_by': 'putnik_v3_auth_id'}),
                            on='putnik_v3_auth_id', how='left')
            fin[f'{table_name}_count'] = fin[f'{table_name}_count'].fillna(0)

    print(f"[ENRICHED] Financial data: {len(fin)} rows with cross-table features from {len(all_tables)} tables")
    return fin

if __name__ == "__main__":
    df = extract_enriched_finances()
    print("\nEnriched financial data sample:")
    print(df.head())
