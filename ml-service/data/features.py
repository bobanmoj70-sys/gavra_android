"""
Feature Engineering for Financial ML Model
Sve features se generišu isključivo iz Supabase podataka
"""
import pandas as pd
import numpy as np
from datetime import datetime

def extract_financial_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Generiše features za finansijski model SAMO iz v3_finansije podataka
    Model uči od nule bez spoljnih podataka
    """
    features = df.copy()
    
    # Vremenski features
    if 'created_at' in features.columns:
        features['created_at'] = pd.to_datetime(features['created_at'], format='ISO8601')
        features['day_of_week'] = features['created_at'].dt.dayofweek
        features['day_of_month'] = features['created_at'].dt.day
        features['month'] = features['created_at'].dt.month
        features['hour'] = features['created_at'].dt.hour
        features['is_weekend'] = features['day_of_week'].isin([5, 6]).astype(int)
    
    # Binary features za tip
    if 'tip' in features.columns:
        features['is_prihod'] = (features['tip'] == 'prihod').astype(int)
        features['is_rashod'] = (features['tip'] == 'rashod').astype(int)
    
    # Features za kategoriju
    if 'kategorija' in features.columns:
        kategorija_dummies = pd.get_dummies(features['kategorija'], prefix='kategorija')
        features = pd.concat([features, kategorija_dummies], axis=1)
    
    # Features za isplata
    if 'isplata_iz' in features.columns:
        isplata_dummies = pd.get_dummies(features['isplata_iz'], prefix='isplata')
        features = pd.concat([features, isplata_dummies], axis=1)
    
    # Numerički features
    numeric_cols = ['iznos', 'broj_voznji', 'broj_otkazivanja', 'poslednja_dopuna']
    for col in numeric_cols:
        if col in features.columns:
            features[col] = pd.to_numeric(features[col], errors='coerce').fillna(0)
    
    return features

def create_user_aggregates(df: pd.DataFrame) -> pd.DataFrame:
    """
    Kreira agregate po korisniku iz finansijskih podataka
    Ovo pomaže modelu da uči ponašanje pojedinačnih korisnika
    """
    if 'putnik_v3_auth_id' not in df.columns:
        return df
    
    # Agregati po korisniku — samo kolone koje postoje
    agg_dict = {'iznos': ['sum', 'mean', 'std', 'count']}
    if 'broj_voznji' in df.columns:
        agg_dict['broj_voznji'] = 'sum'
    if 'broj_otkazivanja' in df.columns:
        agg_dict['broj_otkazivanja'] = 'sum'

    user_stats = df.groupby('putnik_v3_auth_id').agg(agg_dict).reset_index()

    base_cols = ['user_id', 'total_amount', 'avg_amount', 'std_amount', 'transaction_count']
    if 'broj_voznji' in df.columns:
        base_cols.append('total_rides')
    if 'broj_otkazivanja' in df.columns:
        base_cols.append('total_cancellations')
    user_stats.columns = base_cols

    # Dodatni features
    if 'total_cancellations' in user_stats.columns and 'total_rides' in user_stats.columns:
        user_stats['cancellation_rate'] = user_stats['total_cancellations'] / (user_stats['transaction_count'] + 1)
        user_stats['rides_per_transaction'] = user_stats['total_rides'] / (user_stats['transaction_count'] + 1)
    elif 'total_rides' in user_stats.columns:
        user_stats['rides_per_transaction'] = user_stats['total_rides'] / (user_stats['transaction_count'] + 1)
    
    return user_stats

def create_time_series_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Kreira time series features iz finansijskih podataka
    Pomaže modelu da uči vremenske paternje
    """
    if 'created_at' not in df.columns:
        return df
    
    df = df.copy()
    df['created_at'] = pd.to_datetime(df['created_at'], format='ISO8601')
    df = df.sort_values('created_at')
    
    # Rolling averages
    if 'iznos' in df.columns:
        df['iznos_rolling_7'] = df['iznos'].rolling(window=7, min_periods=1).mean()
        df['iznos_rolling_30'] = df['iznos'].rolling(window=30, min_periods=1).mean()
    
    # Lag features
    df['iznos_lag_1'] = df['iznos'].shift(1)
    df['iznos_lag_7'] = df['iznos'].shift(7)
    
    # Trend
    df['iznos_trend'] = df['iznos'].diff()
    
    return df

def add_cross_table_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Dodaje features iz povezanih tabela
    """
    features = df.copy()

    # Putnik behavior features (ako postoje iz enriched ETL)
    if 'broj_zahteva' in features.columns:
        features['zahtevi_po_transakciji'] = features['broj_zahteva'] / (features.get('broj_voznji', 1) + 1)
    if 'broj_putovanja' in features.columns:
        features['putovanja_po_transakciji'] = features['broj_putovanja'] / (features.get('broj_voznji', 1) + 1)
        features['loyalty_score'] = features['broj_putovanja'].clip(0, 50) / 50

    # Vehicle features (ako postoje)
    if 'broj_voznji_30dana' in features.columns:
        features['intenzitet_koriscenja'] = features['broj_voznji_30dana'].clip(0, 100) / 100

    # Fuel features (ako postoje)
    if 'trenutno_litara' in features.columns and 'kapacitet' in features.columns:
        features['nivo_goriva_posto'] = (features['trenutno_litara'] / features['kapacitet'].clip(lower=1) * 100).clip(0, 100)

    return features


def prepare_ml_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Priprema sve features za ML model
    Sve se generiše iz Supabase podataka + povezanih tabela
    """
    # Osnovni features
    features = extract_financial_features(df)

    # User agregati
    user_aggregates = create_user_aggregates(df)

    # Time series features
    time_features = create_time_series_features(df)

    # Cross-table features
    cross_features = add_cross_table_features(df)

    # Spajamo sve features
    if 'putnik_v3_auth_id' in features.columns:
        features = features.merge(user_aggregates, left_on='putnik_v3_auth_id',
                                   right_on='user_id', how='left')

    # Dodajemo time series features
    for col in time_features.columns:
        if col not in features.columns:
            features[col] = time_features[col]

    # Dodajemo cross-table features
    for col in cross_features.columns:
        if col not in features.columns and col in ['zahtevi_po_transakciji', 'putovanja_po_transakciji',
                                                     'loyalty_score', 'intenzitet_koriscenja',
                                                     'nivo_goriva_posto', 'broj_zahteva', 'broj_putovanja',
                                                     'broj_voznji_30dana']:
            features[col] = cross_features[col]

    # Uklanjamo non-numeric kolone za ML
    numeric_cols = features.select_dtypes(include=[np.number]).columns.tolist()
    features = features[numeric_cols]

    # Popunjavamo missing values
    features = features.fillna(0)

    return features

if __name__ == "__main__":
    # Test feature engineering
    from data.etl import extract_finances
    
    df = extract_finances()
    features = prepare_ml_features(df)
    
    print(f"\nGenerated {len(features.columns)} features")
    print(f"Feature names: {features.columns.tolist()}")
    print(f"\nSample features:")
    print(features.head())
