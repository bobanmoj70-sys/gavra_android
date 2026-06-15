"""
AUTO TRAIN - Automatski trenira sve ML modele na dostupnim Supabase podacima
Sistem sam otkriva tabele, podatke i trenira modele bez ručnog podesavanja
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

import pandas as pd
from supabase import create_client
import config
from models.financial_model import FinancialMLModel
from models.gorivo_model import GorivoMLModel
from models.putnik_model import PutnikMLModel
from models.vozilo_model import VoziloMLModel
from models.zahtevi_model import ZahteviMLModel
from models.znanje_model import ZnanjeAIModel

_supabase = None

def _get_supabase():
    global _supabase
    if _supabase is None:
        _supabase = create_client(config.SUPABASE_URL, config.SUPABASE_KEY)
    return _supabase

def discover_tables():
    """Dinamicki otkrije SVE tabele u Supabase - bez hardcoded liste"""
    from data.etl_znanje import discover_all_tables
    try:
        tables = discover_all_tables()
        print(f"[AutoTrain] Dynamically discovered {len(tables)} tables")
        return tables
    except Exception as e:
        print(f"[AutoTrain] ERROR discovering tables: {e}")
        return []

def extract_table(table_name: str) -> pd.DataFrame:
    """Izvuci podatke iz tabele"""
    try:
        r = _get_supabase().table(table_name).select('*').execute()
        df = pd.DataFrame(r.data)
        print(f"[AutoTrain] Extracted {len(df)} rows from {table_name}")
        return df
    except Exception as e:
        print(f"[AutoTrain] ERROR extracting {table_name}: {e}")
        return pd.DataFrame()

def train_financial():
    """Trenira finansijski model ako ima podataka"""
    df = extract_table('v3_finansije')
    if df.empty:
        print("[AutoTrain] SKIP: No financial data")
        return None
    
    model = FinancialMLModel()
    metrics = model.train(df)
    model.save()
    r2 = metrics.get('r2_score')
    if r2 is None or pd.isna(r2):
        r2 = 0.0
    print(f"[AutoTrain] Financial model trained: R²={r2:.3f}")
    return metrics

def train_gorivo():
    """Trenira gorivo model ako ima podataka"""
    df = extract_table('v3_gorivo')
    if df.empty:
        print("[AutoTrain] SKIP: No fuel data")
        return None
    
    model = GorivoMLModel()
    metrics = model.train(df)
    model.save()
    r2 = metrics.get('r2_score')
    if r2 is None or pd.isna(r2):
        r2 = 0.0
    print(f"[AutoTrain] Gorivo model trained: R²={r2:.3f}")
    return metrics

def train_vozilo():
    """Trenira vozilo model ako ima podataka"""
    df = extract_table('v3_vozila')
    if df.empty:
        print("[AutoTrain] SKIP: No vehicle data")
        return None
    
    model = VoziloMLModel()
    metrics = model.train(df)
    model.save()
    r2 = metrics.get('r2_score')
    if r2 is None or pd.isna(r2):
        r2 = 0.0
    print(f"[AutoTrain] Vozilo model trained: R²={r2:.3f}")
    return metrics

def train_zahtevi():
    """Trenira zahtevi model ako ima podataka"""
    df = extract_table('v3_zahtevi')
    if df.empty:
        print("[AutoTrain] SKIP: No request data")
        return None
    
    model = ZahteviMLModel()
    metrics = model.train(df)
    model.save()
    r2 = metrics.get('r2_score')
    if r2 is None or pd.isna(r2):
        r2 = 0.0
    print(f"[AutoTrain] Zahtevi model trained: R²={r2:.3f}")
    return metrics

def train_putnik():
    """Trenira putnik model ako ima podataka"""
    fin_df = extract_table('v3_finansije')
    zahtevi_df = extract_table('v3_zahtevi')
    
    if fin_df.empty:
        print("[AutoTrain] SKIP: No financial data for passenger model")
        return None
    
    model = PutnikMLModel()
    data = {'finansije': fin_df, 'zahtevi': zahtevi_df}
    metrics = model.train(data)
    model.save()
    r2 = metrics.get('r2_score')
    if r2 is None or pd.isna(r2):
        r2 = 0.0
    print(f"[AutoTrain] Putnik model trained: R²={r2:.3f}")
    return metrics

def train_znanje():
    """Trenira znanje model ako ima podataka"""
    tables = discover_tables()
    if not tables:
        print("[AutoTrain] SKIP: No tables for knowledge model")
        return None
    
    data = {}
    for table in tables:
        df = extract_table(table)
        if not df.empty:
            data[table] = df
    
    if not data:
        print("[AutoTrain] SKIP: No data for knowledge model")
        return None
    
    model = ZnanjeAIModel()
    schema = {table: list(df.columns) for table, df in data.items()}
    metrics = model.train(data, schema)
    model.save()
    print(f"[AutoTrain] Znanje model trained: {metrics.get('tables_loaded', 0)} tables")
    return metrics

def auto_train_all():
    """Automatski trenira sve modele na dostupnim podacima"""
    print("=" * 60)
    print("AUTO TRAIN - Automatski ML Training Pipeline")
    print("=" * 60)
    print("Sistem sam otkriva podatke i trenira modele")
    print("=" * 60)
    
    results = {}
    
    # Treniraj sve modele
    results['financial'] = train_financial()
    results['gorivo'] = train_gorivo()
    results['vozilo'] = train_vozilo()
    results['zahtevi'] = train_zahtevi()
    results['putnik'] = train_putnik()
    results['znanje'] = train_znanje()
    
    # Summary
    print("\n" + "=" * 60)
    print("AUTO TRAIN COMPLETE - SUMMARY")
    print("=" * 60)
    
    trained = [k for k, v in results.items() if v is not None]
    skipped = [k for k, v in results.items() if v is None]
    
    print(f"Trained: {len(trained)} models - {', '.join(trained)}")
    print(f"Skipped: {len(skipped)} models - {', '.join(skipped)}")
    
    for model_name, metrics in results.items():
        if metrics:
            print(f"  {model_name}: {metrics}")
    
    print("=" * 60)
    return results

if __name__ == "__main__":
    auto_train_all()
