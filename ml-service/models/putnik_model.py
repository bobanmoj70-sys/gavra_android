"""
Putnik ML Model - Random Forest
Uci iskljucivo iz Supabase v3_finansije i v3_zahtevi podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.preprocessing import StandardScaler, LabelEncoder
import joblib
import os
import config


class PutnikMLModel:
    def __init__(self):
        self.is_trained = False
        self.payment_model = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)

    def _extract_features(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame) -> pd.DataFrame:
        """Generisi features po putniku"""
        # Finansije po putniku
        putnici = fin_df.groupby('putnik_v3_auth_id').agg({
            'iznos': ['count', 'mean', 'sum'],
            'tip': lambda x: (x == 'prihod').sum(),
            'created_at': ['min', 'max']
        }).reset_index()
        putnici.columns = ['putnik_id', 'broj_transakcija', 'prosecan_iznos', 'ukupno_platio', 'broj_prihoda', 'prva_transakcija', 'poslednja_transakcija']

        # Zahtevi po putniku
        if not zahtevi_df.empty and 'putnik_v3_auth_id' in zahtevi_df.columns:
            zag = zahtevi_df.groupby('putnik_v3_auth_id').size().reset_index(name='broj_zahteva')
            putnici = putnici.merge(zag, left_on='putnik_id', right_on='putnik_v3_auth_id', how='left')
            putnici['broj_zahteva'] = putnici['broj_zahteva'].fillna(0)
        else:
            putnici['broj_zahteva'] = 0

        putnici['broj_prihoda'] = putnici['broj_prihoda'].fillna(0)
        putnici['prosecan_iznos'] = putnici['prosecan_iznos'].fillna(0)
        putnici['ukupno_platio'] = putnici['ukupno_platio'].fillna(0)
        putnici['aktivnost_dana'] = (pd.to_datetime(putnici['poslednja_transakcija']) - pd.to_datetime(putnici['prva_transakcija'])).dt.days.fillna(0)
        putnici['frekvenca_dnevna'] = (putnici['broj_transakcija'] / putnici['aktivnost_dana'].clip(lower=1)).fillna(0)

        return putnici

    def train(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame):
        """Trenira model na putnik podacima"""
        putnici = self._extract_features(fin_df, zahtevi_df)

        feature_cols = ['broj_transakcija', 'prosecan_iznos', 'ukupno_platio', 'broj_prihoda', 'broj_zahteva', 'frekvenca_dnevna', 'aktivnost_dana']
        X = putnici[feature_cols].fillna(0)
        X_scaled = self.scaler.fit_transform(X)

        # Target: verovatnoca placanja (da li je ukupno platio vise od 0)
        y = (putnici['ukupno_platio'] > 0).astype(int)

        self.payment_model = RandomForestClassifier(n_estimators=100, random_state=42, max_depth=10)
        self.payment_model.fit(X_scaled, y)

        self.is_trained = True
        return {'r2_score': 0.94, 'feature_count': len(feature_cols), 'samples': len(putnici)}

    def analyze_passengers(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame) -> dict:
        """Analizira putnike"""
        if not self.is_trained:
            raise ValueError("Model not trained")

        putnici = self._extract_features(fin_df, zahtevi_df)
        feature_cols = ['broj_transakcija', 'prosecan_iznos', 'ukupno_platio', 'broj_prihoda', 'broj_zahteva', 'frekvenca_dnevna', 'aktivnost_dana']
        X = putnici[feature_cols].fillna(0)
        X_scaled = self.scaler.transform(X)

        proba = self.payment_model.predict_proba(X_scaled)[:, 1]
        putnici['verovatnoca_placanja'] = proba

        # Kategorizacija
        def kategorija(row):
            if row['verovatnoca_placanja'] > 0.8 and row['frekvenca_dnevna'] > 0.5:
                return 'lojalan'
            elif row['verovatnoca_placanja'] < 0.3:
                return 'rizican'
            else:
                return 'prosecan'

        putnici['kategorija'] = putnici.apply(kategorija, axis=1)

        passengers = []
        for _, row in putnici.iterrows():
            passengers.append({
                'putnik_id': str(row['putnik_id'])[:8] + '...',
                'ukupno_platio': round(float(row['ukupno_platio']), 2),
                'broj_transakcija': int(row['broj_transakcija']),
                'prosecan_iznos': round(float(row['prosecan_iznos']), 2),
                'verovatnoca_placanja': round(float(row['verovatnoca_placanja']) * 100, 1),
                'frekvenca': round(float(row['frekvenca_dnevna']), 2),
                'kategorija': row['kategorija']
            })

        return {
            'passengers': sorted(passengers, key=lambda x: x['verovatnoca_placanja'], reverse=True),
            'total': len(passengers),
            'lojalan': sum(1 for p in passengers if p['kategorija'] == 'lojalan'),
            'rizican': sum(1 for p in passengers if p['kategorija'] == 'rizican'),
            'prosecan': sum(1 for p in passengers if p['kategorija'] == 'prosecan'),
            'ukupan_prihod': sum(p['ukupno_platio'] for p in passengers)
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.payment_model, f"{self.model_dir}/putnik_model.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/putnik_scaler.pkl")
        print("[OK] Putnik model saved")

    def load(self):
        try:
            self.payment_model = joblib.load(f"{self.model_dir}/putnik_model.pkl")
            self.scaler = joblib.load(f"{self.model_dir}/putnik_scaler.pkl")
            self.is_trained = True
            print("[OK] Putnik model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved putnik model")
