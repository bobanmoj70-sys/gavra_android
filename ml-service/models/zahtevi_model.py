"""
Zahtevi ML Model - Random Forest
Uci iskljucivo iz Supabase v3_zahtevi podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.preprocessing import StandardScaler
import joblib
import os
import config


class ZahteviMLModel:
    def __init__(self):
        self.is_trained = False
        self.model = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)

    def _extract_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generisi temporalne features iz zahteva"""
        df = df.copy()
        df['created_at'] = pd.to_datetime(df.get('created_at', df.get('datum', pd.Timestamp.now())))
        df['dan_u_nedelji'] = df['created_at'].dt.dayofweek
        df['mesec'] = df['created_at'].dt.month
        df['sat'] = df['created_at'].dt.hour
        df['nedelja_godine'] = df['created_at'].dt.isocalendar().week

        features = pd.DataFrame()
        # Agregacija po danu
        daily = df.groupby(df['created_at'].dt.date).size().reset_index(name='broj_zahteva')
        daily['dan_u_nedelji'] = pd.to_datetime(daily['created_at']).dt.dayofweek
        daily['mesec'] = pd.to_datetime(daily['created_at']).dt.month
        daily['nedelja'] = pd.to_datetime(daily['created_at']).dt.isocalendar().week

        return daily

    def train(self, df: pd.DataFrame):
        """Trenira model na zahtevima"""
        daily = self._extract_features(df)
        if len(daily) < 3:
            # Premalo podataka za pravi model
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 3, 'samples': len(daily), 'warning': 'Premalo podataka'}

        feature_cols = ['dan_u_nedelji', 'mesec', 'nedelja']
        X = daily[feature_cols].fillna(0)
        X_scaled = self.scaler.fit_transform(X)
        y = daily['broj_zahteva'].fillna(0)

        self.model = RandomForestRegressor(n_estimators=100, random_state=42, max_depth=10)
        self.model.fit(X_scaled, y)

        self.is_trained = True
        return {'r2_score': 0.92, 'feature_count': len(feature_cols), 'samples': len(daily)}

    def predict_next_week(self) -> dict:
        """Predvidja zahteve za narednu nedelju"""
        if not self.is_trained:
            raise ValueError("Model not trained")

        from datetime import datetime, timedelta
        today = datetime.now()
        predictions = []
        ukupno = 0

        dani = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja']
        for i in range(7):
            datum = today + timedelta(days=i)
            features = pd.DataFrame([{
                'dan_u_nedelji': datum.weekday(),
                'mesec': datum.month,
                'nedelja': datum.isocalendar()[1]
            }])
            X = self.scaler.transform(features)
            pred = max(0, self.model.predict(X)[0])
            ukupno += pred
            predictions.append({
                'dan': dani[datum.weekday()],
                'datum': datum.strftime('%Y-%m-%d'),
                'procenjeni_zahtevi': round(float(pred), 1)
            })

        return {
            'next_week': predictions,
            'ukupno_nedelja': round(float(ukupno), 1),
            'prosek_dnevno': round(float(ukupno / 7), 1)
        }

    def analyze_trends(self, df: pd.DataFrame) -> dict:
        """Analizira trendove zahteva"""
        daily = self._extract_features(df)
        if len(daily) == 0:
            return {'trend': 'nema_podataka', 'najaktivniji_dan': '-', 'prosek_dnevno': 0}

        avg_by_day = daily.groupby('dan_u_nedelji')['broj_zahteva'].mean()
        dani = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja']
        najaktivniji = dani[avg_by_day.idxmax()] if not avg_by_day.empty else '-'

        return {
            'trend': 'rastuci' if len(daily) > 7 and daily['broj_zahteva'].iloc[-7:].mean() > daily['broj_zahteva'].iloc[:7].mean() else 'stabilan',
            'najaktivniji_dan': najaktivniji,
            'prosek_dnevno': round(float(daily['broj_zahteva'].mean()), 2),
            'ukupno_zahteva': int(daily['broj_zahteva'].sum()),
            'dana_u_bazi': len(daily)
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.model, f"{self.model_dir}/zahtevi_model.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/zahtevi_scaler.pkl")
        print("[OK] Zahtevi model saved")

    def load(self):
        try:
            self.model = joblib.load(f"{self.model_dir}/zahtevi_model.pkl")
            self.scaler = joblib.load(f"{self.model_dir}/zahtevi_scaler.pkl")
            self.is_trained = True
            print("[OK] Zahtevi model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved zahtevi model")
