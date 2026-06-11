"""
Gorivo ML Model - Random Forest
Uci iskljucivo iz Supabase v3_gorivo podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error
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
        """Generiše features iz gorivo + operativnih podataka"""
        features = pd.DataFrame()
        features['trenutno_litara'] = pd.to_numeric(df['trenutno_stanje_litri'], errors='coerce').fillna(0)
        features['kapacitet'] = pd.to_numeric(df['kapacitet_litri'], errors='coerce').fillna(3000)
        features['nivo_posto'] = (features['trenutno_litara'] / features['kapacitet'].clip(lower=1) * 100).clip(0, 100)
        features['cena_po_litru'] = pd.to_numeric(df['cena_po_litru'], errors='coerce').fillna(0)
        features['dug_iznos'] = pd.to_numeric(df['dug_iznos'], errors='coerce').fillna(0)
        features['alarm_nivo'] = pd.to_numeric(df['alarm_nivo_litri'], errors='coerce').fillna(500)
        features['ispod_alarm'] = (features['trenutno_litara'] < features['alarm_nivo']).astype(int)
        # Operational intensity — broj voznji iz operativne (ako postoji)
        features['broj_voznji'] = pd.to_numeric(df.get('broj_voznji'), errors='coerce').fillna(0)
        # Vehicle specs (ako su join-ovani)
        features['godina_proizvodnje'] = pd.to_numeric(df.get('godina_proizvodnje'), errors='coerce').fillna(2015)
        features['starost_godina'] = 2026 - features['godina_proizvodnje']
        features['trenutna_km'] = pd.to_numeric(df.get('trenutna_km'), errors='coerce').fillna(0)
        # Data-driven features
        used_liters = features['kapacitet'] - features['trenutno_litara']
        features['procenjena_potrosnja_po_voznji'] = (used_liters / features['broj_voznji'].clip(lower=1)).fillna(0)
        features['cena_po_km'] = (features['cena_po_litru'] * features['procenjena_potrosnja_po_voznji'] / features['trenutna_km'].clip(lower=1)).fillna(0)
        return features

    def _compute_target(self, features: pd.DataFrame) -> np.ndarray:
        """
        Target: fuel_urgency_score = koliko je hitno dopuniti gorivo.
        Računa se iz podataka: niski nivo + visoka aktivnost = visoka hitnost.
        """
        nivo_norm = 1 - (features['nivo_posto'] / 100)
        trips = features['broj_voznji']
        trip_max = trips.max() if trips.max() > 0 else 1
        activity_norm = trips / trip_max
        urgency = nivo_norm * (1 + 2 * activity_norm)
        below_alarm = features['ispod_alarm'].values
        urgency = urgency * (1 + below_alarm)
        return urgency.clip(0, 3).values

    def train(self, df: pd.DataFrame):
        """Trenira model na gorivo podacima sa pravim evaluacijom"""
        print("=" * 50)
        print("Training Gorivo ML Model from scratch")
        print("=" * 50)
        features = self._extract_features(df)
        y = self._compute_target(features)
        X = features.select_dtypes(include=[np.number]).fillna(0)
        X_scaled = self.scaler.fit_transform(X)
        n_samples = len(df)
        eval_split = n_samples >= 10
        if eval_split:
            X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.25, random_state=42)
        else:
            X_train, X_test, y_train, y_test = X_scaled, X_scaled, y, y
            print(f"[WARN] Samo {n_samples} zapisa — evaluacija na trening setu")
        self.model = RandomForestRegressor(n_estimators=200, random_state=42, max_depth=12)
        self.model.fit(X_train, y_train)
        y_pred_train = self.model.predict(X_train)
        train_r2 = r2_score(y_train, y_pred_train)
        train_mae = mean_absolute_error(y_train, y_pred_train)
        metrics = {'train_r2': float(train_r2), 'train_mae': float(train_mae),
                   'feature_count': len(X.columns), 'samples': n_samples, 'eval_on_train': not eval_split}
        if eval_split:
            y_pred_test = self.model.predict(X_test)
            metrics['test_r2'] = float(r2_score(y_test, y_pred_test))
            metrics['test_mae'] = float(mean_absolute_error(y_test, y_pred_test))
            metrics['r2_score'] = metrics['test_r2']
            print(f"Test R²: {metrics['test_r2']:.3f} | Test MAE: {metrics['test_mae']:.4f}")
        else:
            metrics['r2_score'] = float(train_r2)
        print(f"Train R²: {train_r2:.3f} | Train MAE: {train_mae:.4f}")
        print(f"Samples: {n_samples} | Features: {len(X.columns)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics
        return metrics

    def predict(self, df: pd.DataFrame) -> pd.DataFrame:
        """Predviđa urgency score i dana do praznog rezervoara"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        features = self._extract_features(df)
        X = features.select_dtypes(include=[np.number]).fillna(0)
        X_scaled = self.scaler.transform(X)
        pred = self.model.predict(X_scaled)
        df = df.copy()
        df['urgency_score'] = pred.clip(0, 3).round(3)
        # Dana do praznog — uči iz podataka (median potrošnje flote)
        potrosnja_po_voznji = features['procenjena_potrosnja_po_voznji'].replace(0, np.nan)
        median_potrosnja = potrosnja_po_voznji.median()
        if pd.isna(median_potrosnja) or median_potrosnja == 0:
            median_potrosnja = 5.0
        dnevna_potrosnja = median_potrosnja * 3
        df['dana_do_praznog'] = (features['trenutno_litara'] / max(1, dnevna_potrosnja)).clip(0, 30).round(1)
        df['trosak_dopune'] = ((features['kapacitet'] - features['trenutno_litara']) * features['cena_po_litru']).round(2)
        # Status na osnovu naučenog urgency score-a (percentili flote)
        urg_vals = df['urgency_score'].values
        p70 = np.percentile(urg_vals, 70) if len(urg_vals) > 1 else 1.5
        p40 = np.percentile(urg_vals, 40) if len(urg_vals) > 1 else 0.7
        df['status'] = df['urgency_score'].apply(lambda x: 'hitno' if x > p70 else ('uskoro' if x > p40 else 'ok'))
        return df

    def analyze_fuel(self, df: pd.DataFrame) -> dict:
        """Analizira stanje goriva sa naučenim modelom"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        result = self.predict(df)
        vehicles = []
        for _, row in result.iterrows():
            status = row['status']
            color = {'hitno': 'red', 'uskoro': 'orange', 'ok': 'green'}.get(status, 'green')
            vehicles.append({
                'id': str(row.get('id', '')),
                'vozilo_id': str(row.get('vozilo_id', row.get('id', ''))),
                'trenutno_litara': float(row.get('trenutno_stanje_litri', 0)),
                'kapacitet': float(row.get('kapacitet_litri', 3000)),
                'nivo_posto': round(float(row.get('trenutno_stanje_litri', 0)) / float(row.get('kapacitet_litri', 3000) or 1) * 100, 1),
                'urgency_score': float(row['urgency_score']),
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
            'ukupan_trosak': sum(v['trosak_dopune'] for v in vehicles),
            'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None)
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
