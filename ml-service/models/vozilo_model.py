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
from models.learning_memory import LearningMemory
from models.auto_features import AutoFeatureDiscovery


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
        self.memory = LearningMemory("vozilo")
        self.discoverer = AutoFeatureDiscovery()

    def _safe_float(self, val):
        return None if val != val else float(val)

    def _find_col(self, df: pd.DataFrame, *patterns: str) -> str:
        """Dinamicki pronalazi kolonu po sablonu - kao beba koja uci.
        Proverava da li su svi delovi sablona prisutni u imenu kolone, u istom redosledu."""
        for col in df.columns:
            col_parts = col.lower().split('_')
            for p in patterns:
                pat_parts = p.lower().split('_')
                idx = 0
                matched = 0
                for cp in col_parts:
                    if idx < len(pat_parts) and cp == pat_parts[idx]:
                        idx += 1
                        matched += 1
                if matched == len(pat_parts):
                    return col
        return None

    def _extract_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generiše features iz vozilo podataka — sve iz baze, ništa hardkodovano"""
        features = pd.DataFrame(index=df.index)

        # DINAMICKI otkriji kljucne kolone
        km_col = self._find_col(df, 'trenutna_km', 'kilometraza', 'km')
        godina_col = self._find_col(df, 'godina_proizvodnje', 'godina', 'proizvodnje')
        marka_col = self._find_col(df, 'marka')
        model_col = self._find_col(df, 'model')
        reg_col = self._find_col(df, 'registracija_vazi_do', 'registracija')

        print(f"  [AutoDiscover] Vozilo kolone: km={km_col}, godina={godina_col}, marka={marka_col}, model={model_col}, reg={reg_col}")

        features['trenutna_km'] = pd.to_numeric(df[km_col], errors='coerce').fillna(0) if km_col else pd.Series([0] * len(df), index=df.index)
        features['godina_proizvodnje'] = pd.to_numeric(df[godina_col], errors='coerce').fillna(2015) if godina_col else pd.Series([2015] * len(df), index=df.index)
        features['starost_godina'] = 2026 - features['godina_proizvodnje']

        marka_vals = df[marka_col].fillna('nepoznato').astype(str) if marka_col else pd.Series(['nepoznato'] * len(df), index=df.index)
        if self.le_marka is None:
            self.le_marka = LabelEncoder()
            all_vals = pd.concat([marka_vals, pd.Series(['nepoznato'])])
            self.le_marka.fit(all_vals)
            features['marka_encoded'] = self.le_marka.transform(marka_vals)
        else:
            known = set(self.le_marka.classes_)
            marka_vals = marka_vals.apply(lambda x: x if x in known else 'nepoznato')
            features['marka_encoded'] = self.le_marka.transform(marka_vals)

        model_vals = df[model_col].fillna('nepoznato').astype(str) if model_col else pd.Series(['nepoznato'] * len(df), index=df.index)
        if self.le_model is None:
            self.le_model = LabelEncoder()
            all_vals = pd.concat([model_vals, pd.Series(['nepoznato'])])
            self.le_model.fit(all_vals)
            features['model_encoded'] = self.le_model.transform(model_vals)
        else:
            known = set(self.le_model.classes_)
            model_vals = model_vals.apply(lambda x: x if x in known else 'nepoznato')
            features['model_encoded'] = self.le_model.transform(model_vals)

        # DINAMICKI otkriji SVE servis tipove iz podataka (sve kolone koje se zavrsavaju na _km osim trenutna_km)
        servis_km_cols = [c for c in df.columns if c.endswith('_km') and c != km_col]
        print(f"  [AutoDiscover] Servis kolone otkrivene: {servis_km_cols}")
        for km_col_name in servis_km_cols:
            servis_name = km_col_name[:-3]  # ukloni '_km'
            features[f'km_od_{servis_name}'] = features['trenutna_km'] - pd.to_numeric(df[km_col_name], errors='coerce').fillna(0)

        if servis_km_cols:
            features['broj_zapisanih_servisa'] = df[servis_km_cols].notna().sum(axis=1)
        else:
            features['broj_zapisanih_servisa'] = 0

        if reg_col:
            features['dana_do_registracije'] = pd.to_datetime(
                df[reg_col], errors='coerce'
            ).apply(lambda x: (x - pd.Timestamp.now()).days if pd.notna(x) else -1)
        else:
            features['dana_do_registracije'] = -1

        features['prosecna_km_godisnje'] = features['trenutna_km'] / features['starost_godina'].clip(lower=1)
        return features

    def _compute_health_target(self, features: pd.DataFrame) -> np.ndarray:
        """
        Računa health risk score SAMO iz podataka — bez hardkodovanih intervala.
        DINAMICKI otkriva servis tipove iz kolona koje pocinju sa 'km_od_'.
        Daje 0-1 score gde 1 = najkritičnije vozilo u floti.
        """
        servis_cols = [c for c in features.columns if c.startswith('km_od_')]
        print(f"  [AutoDiscover] Servis tipovi za health: {[c[6:] for c in servis_cols]}")
        scores = []
        for col in servis_cols:
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
        metrics = {'train_r2': self._safe_float(train_r2), 'train_mae': self._safe_float(train_mae),
                   'feature_count': len(self.feature_columns), 'samples': n_samples,
                   'eval_on_train': not eval_split}
        if eval_split:
            y_pred_test = self.health_model.predict(X_test)
            metrics['test_r2'] = self._safe_float(r2_score(y_test, y_pred_test))
            metrics['test_mae'] = self._safe_float(mean_absolute_error(y_test, y_pred_test))
            metrics['r2_score'] = metrics['test_r2']
            print(f"Test R²: {metrics['test_r2']:.3f} | Test MAE: {metrics['test_mae']:.4f}")
        else:
            metrics['r2_score'] = self._safe_float(train_r2)
        print(f"Train R²: {train_r2:.3f} | Train MAE: {train_mae:.4f}")
        print(f"Samples: {n_samples} | Features: {len(self.feature_columns)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics

        # ZABORAVI stare tabele koje vise ne postoje
        self.memory.forget_old(["vozilo"])

        # PAMTI sta je naucio
        sources = {"vozilo": {"columns": list(self.feature_columns), "rows": n_samples}}
        feature_imp = dict(zip(self.feature_columns, self.health_model.feature_importances_)) if self.health_model else {}
        self.memory.record_training(sources, feature_imp, metrics)
        print("  [Memory] Vozilo model zapamtio ucenje")

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
