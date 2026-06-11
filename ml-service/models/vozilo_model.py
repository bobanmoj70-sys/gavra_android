"""
Vehicle ML Model - Random Forest
Uci iskljucivo iz Supabase v3_vozila podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.metrics import mean_squared_error, r2_score, mean_absolute_error
import joblib
import os
import config


class VoziloMLModel:
    def __init__(self):
        self.is_trained = False
        self.health_model = None
        self.scaler = None
        self.le_marka = None
        self.le_model = None
        self.model_dir = config.MODEL_DIR
        self.feature_columns = None
        os.makedirs(self.model_dir, exist_ok=True)

    def _extract_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generiše features iz vozilo podataka — sve iz baze, ništa hardkodovano"""
        features = pd.DataFrame()
        features['trenutna_km'] = pd.to_numeric(df['trenutna_km'], errors='coerce').fillna(0)
        features['godina_proizvodnje'] = pd.to_numeric(df['godina_proizvodnje'], errors='coerce').fillna(2015)
        features['starost_godina'] = 2026 - features['godina_proizvodnje']

        if self.le_marka is None:
            self.le_marka = LabelEncoder()
            features['marka_encoded'] = self.le_marka.fit_transform(df['marka'].fillna('nepoznato').astype(str))
        else:
            marka_vals = df['marka'].fillna('nepoznato').astype(str)
            known = set(self.le_marka.classes_)
            marka_vals = marka_vals.apply(lambda x: x if x in known else 'nepoznato')
            features['marka_encoded'] = self.le_marka.transform(marka_vals)

        if self.le_model is None:
            self.le_model = LabelEncoder()
            features['model_encoded'] = self.le_model.fit_transform(df['model'].fillna('nepoznato').astype(str))
        else:
            model_vals = df['model'].fillna('nepoznato').astype(str)
            known = set(self.le_model.classes_)
            model_vals = model_vals.apply(lambda x: x if x in known else 'nepoznato')
            features['model_encoded'] = self.le_model.transform(model_vals)

        servis_types = ['mali_servis', 'veliki_servis', 'alternator', 'akumulator',
                        'plocice_prednje', 'plocice_zadnje', 'trap',
                        'gume_prednje', 'gume_zadnje']
        for servis in servis_types:
            km_col = f'{servis}_km'
            if km_col in df.columns:
                features[f'km_od_{servis}'] = features['trenutna_km'] - pd.to_numeric(df[km_col], errors='coerce').fillna(0)
            else:
                features[f'km_od_{servis}'] = features['trenutna_km']

        servis_km_cols = [c for c in df.columns if c.endswith('_km') and c != 'trenutna_km']
        features['broj_zapisanih_servisa'] = df[servis_km_cols].notna().sum(axis=1)

        if 'registracija_vazi_do' in df.columns:
            features['dana_do_registracije'] = pd.to_datetime(
                df['registracija_vazi_do'], errors='coerce'
            ).apply(lambda x: (x - pd.Timestamp.now()).days if pd.notna(x) else -1)
        else:
            features['dana_do_registracije'] = -1

        features['prosecna_km_godisnje'] = features['trenutna_km'] / features['starost_godina'].clip(lower=1)
        return features

    def _compute_health_target(self, features: pd.DataFrame) -> np.ndarray:
        """
        Računa health risk score SAMO iz podataka — bez hardkodovanih intervala.
        Za svaki servis tip: km_od_servisa / max_fleet_km_od_tog_servisa
        Daje 0-1 score gde 1 = najkritičnije vozilo u floti.
        """
        servis_types = ['mali_servis', 'veliki_servis', 'alternator', 'akumulator',
                        'plocice_prednje', 'plocice_zadnje', 'trap',
                        'gume_prednje', 'gume_zadnje']
        scores = []
        for servis in servis_types:
            col = f'km_od_{servis}'
            if col in features.columns:
                vals = features[col].clip(lower=0)
                max_val = vals.max() if vals.max() > 0 else 1
                norm = (vals / max_val).values
                scores.append(norm)
        if len(scores) == 0:
            return np.zeros(len(features))
        avg_score = np.mean(scores, axis=0)
        age_max = features['starost_godina'].max()
        age_factor = features['starost_godina'].values / age_max if age_max > 0 else 0
        return np.clip(avg_score * (1 + 0.3 * age_factor), 0, 1)

    def train(self, df: pd.DataFrame):
        """Trenira model na vozilo podacima sa pravim train/test splitom i metrikama"""
        print("=" * 50)
        print("Training Vehicle ML Model from scratch")
        print("=" * 50)
        features = self._extract_features(df)
        y = self._compute_health_target(features)
        self.scaler = StandardScaler()
        X_scaled = self.scaler.fit_transform(features)
        self.feature_columns = features.columns.tolist()
        n_samples = len(df)
        eval_split = n_samples >= 10
        if eval_split:
            X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.25, random_state=42)
        else:
            X_train, X_test, y_train, y_test = X_scaled, X_scaled, y, y
            print(f"[WARN] Samo {n_samples} vozila — evaluacija na trening setu")
        self.health_model = RandomForestRegressor(n_estimators=200, random_state=42, max_depth=12)
        self.health_model.fit(X_train, y_train)
        y_pred_train = self.health_model.predict(X_train)
        train_r2 = r2_score(y_train, y_pred_train)
        train_mae = mean_absolute_error(y_train, y_pred_train)
        metrics = {'train_r2': float(train_r2), 'train_mae': float(train_mae),
                   'feature_count': len(self.feature_columns), 'samples': n_samples,
                   'eval_on_train': not eval_split}
        if eval_split:
            y_pred_test = self.health_model.predict(X_test)
            metrics['test_r2'] = float(r2_score(y_test, y_pred_test))
            metrics['test_mae'] = float(mean_absolute_error(y_test, y_pred_test))
            metrics['r2_score'] = metrics['test_r2']
            print(f"Test R²: {metrics['test_r2']:.3f} | Test MAE: {metrics['test_mae']:.4f}")
        else:
            metrics['r2_score'] = float(train_r2)
        print(f"Train R²: {train_r2:.3f} | Train MAE: {train_mae:.4f}")
        print(f"Samples: {n_samples} | Features: {len(self.feature_columns)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics
        return metrics

    def predict_health(self, df: pd.DataFrame) -> pd.DataFrame:
        """Predviđa health risk score za svako vozilo"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        features = self._extract_features(df)
        X = self.scaler.transform(features)
        pred = self.health_model.predict(X)
        df = df.copy()
        df['health_risk_score'] = pred
        return df

    def analyze_vehicle_health(self, df: pd.DataFrame) -> dict:
        """Analizira zdravlje vozila na osnovu naučenog modela"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        result = self.predict_health(df)
        # Nauči percentilne pragove iz podataka
        risk_vals = result['health_risk_score'].values
        p70 = np.percentile(risk_vals, 70) if len(risk_vals) > 1 else 0.7
        p40 = np.percentile(risk_vals, 40) if len(risk_vals) > 1 else 0.4
        results = []
        for _, row in result.iterrows():
            risk = row['health_risk_score']
            trenutna = row.get('trenutna_km', 0) or 0
            if risk > p70:
                status, color = 'hitno', 'red'
            elif risk > p40:
                status, color = 'uskoro', 'orange'
            else:
                status, color = 'ok', 'green'
            km_do = max(0, int((1 - risk) * 5000))
            results.append({
                'vozilo_id': str(row.get('id', '')),
                'registracija': str(row.get('registracija', 'Nepoznato')),
                'trenutna_km': int(trenutna),
                'health_risk': round(float(risk), 3),
                'km_do_servisa': km_do,
                'status': status,
                'status_color': color
            })
        return {
            'vehicles': results,
            'total': len(results),
            'hitno': sum(1 for r in results if r['status'] == 'hitno'),
            'uskoro': sum(1 for r in results if r['status'] == 'uskoro'),
            'ok': sum(1 for r in results if r['status'] == 'ok'),
            'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None)
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.health_model, f"{self.model_dir}/vozilo_health_model.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/vozilo_scaler.pkl")
        joblib.dump(self.le_marka, f"{self.model_dir}/vozilo_le_marka.pkl")
        joblib.dump(self.le_model, f"{self.model_dir}/vozilo_le_model.pkl")
        joblib.dump(self.feature_columns, f"{self.model_dir}/vozilo_features.pkl")
        print("[OK] Vehicle model saved")

    def load(self):
        try:
            self.health_model = joblib.load(f"{self.model_dir}/vozilo_health_model.pkl")
            self.scaler = joblib.load(f"{self.model_dir}/vozilo_scaler.pkl")
            self.le_marka = joblib.load(f"{self.model_dir}/vozilo_le_marka.pkl")
            self.le_model = joblib.load(f"{self.model_dir}/vozilo_le_model.pkl")
            self.feature_columns = joblib.load(f"{self.model_dir}/vozilo_features.pkl")
            self.is_trained = True
            print("[OK] Vehicle model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved vehicle model")
