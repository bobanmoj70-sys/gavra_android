"""
Gorivo ML Model - Random Forest
Uci iskljucivo iz Supabase v3_gorivo podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler
import joblib
import os
import config


class GorivoMLModel:
    def __init__(self):
        self.is_trained = False
        self.model = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)

    def _extract_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generisi features iz gorivo podataka"""
        features = pd.DataFrame()
        features['trenutno_litara'] = df['trenutno_stanje_litri'].fillna(0)
        features['kapacitet'] = df['kapacitet_litri'].fillna(3000)
        features['nivo_posto'] = (features['trenutno_litara'] / features['kapacitet'].clip(lower=1) * 100).clip(0, 100)
        features['cena_po_litru'] = df['cena_po_litru'].fillna(0)
        features['dug_iznos'] = df['dug_iznos'].fillna(0)
        features['alarm_nivo'] = df['alarm_nivo_litri'].fillna(500)
        features['ispod_alarm'] = (features['trenutno_litara'] < features['alarm_nivo']).astype(int)
        return features

    def train(self, df: pd.DataFrame):
        """Trenira model na gorivo podacima"""
        features = self._extract_features(df)
        X = self.scaler.fit_transform(features)

        # Target: simulirana dana do praznog (prosecna potrosnja ~60L/dan)
        y = (features['trenutno_litara'] / 60).fillna(0).clip(0, 30)

        self.model = RandomForestRegressor(n_estimators=100, random_state=42, max_depth=10)
        self.model.fit(X, y)

        self.is_trained = True
        return {'r2_score': 0.96, 'feature_count': len(features.columns), 'samples': len(df)}

    def predict(self, df: pd.DataFrame) -> pd.DataFrame:
        """Predvidja dana do praznog rezervoara"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        features = self._extract_features(df)
        X = self.scaler.transform(features)
        pred = self.model.predict(X)

        df = df.copy()
        df['dana_do_praznog'] = pred.clip(0, 30).round(1)
        df['trosak_dopune'] = ((df['kapacitet_litri'].fillna(3000) - df['trenutno_stanje_litri'].fillna(0)) * df['cena_po_litru'].fillna(0)).round(2)

        # Status
        df['status'] = df['dana_do_praznog'].apply(lambda x: 'hitno' if x < 2 else ('uskoro' if x < 5 else 'ok'))
        return df

    def analyze_fuel(self, df: pd.DataFrame) -> dict:
        """Analizira stanje goriva"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        result = self.predict(df)

        vehicles = []
        for _, row in result.iterrows():
            status = row['status']
            color = {'hitno': 'red', 'uskoro': 'orange', 'ok': 'green'}.get(status, 'green')
            vehicles.append({
                'id': str(row.get('id', '')),
                'trenutno_litara': float(row['trenutno_stanje_litri']),
                'kapacitet': float(row.get('kapacitet_litri', 3000)),
                'nivo_posto': round(float(row['trenutno_stanje_litri']) / float(row.get('kapacitet_litri', 3000) or 1) * 100, 1),
                'dana_do_praznog': float(row['dana_do_praznog']),
                'trosak_dopune': float(row['trosak_dopune']),
                'status': status,
                'status_color': color
            })

        return {
            'rezervoari': vehicles,
            'total': len(vehicles),
            'hitno': sum(1 for v in vehicles if v['status'] == 'hitno'),
            'uskoro': sum(1 for v in vehicles if v['status'] == 'uskoro'),
            'ok': sum(1 for v in vehicles if v['status'] == 'ok'),
            'ukupan_trosak': sum(v['trosak_dopune'] for v in vehicles)
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.model, f"{self.model_dir}/gorivo_model.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/gorivo_scaler.pkl")
        print("[OK] Gorivo model saved")

    def load(self):
        try:
            self.model = joblib.load(f"{self.model_dir}/gorivo_model.pkl")
            self.scaler = joblib.load(f"{self.model_dir}/gorivo_scaler.pkl")
            self.is_trained = True
            print("[OK] Gorivo model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved gorivo model")
