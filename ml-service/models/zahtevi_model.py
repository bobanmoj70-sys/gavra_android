"""
Zahtevi ML Model - Random Forest
Uci iskljucivo iz Supabase v3_zahtevi podataka
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
from models.learning_memory import LearningMemory
from models.auto_features import AutoFeatureDiscovery


class ZahteviMLModel:
    def __init__(self):
        self.is_trained = False
        self.model = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)
        self.memory = LearningMemory("zahtevi")
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
        """Generiše temporal + rolling + lag features iz zahteva - DINAMICKI"""
        # DINAMICKI otkriji kljucne kolone
        grad_col = self._find_col(df, 'grad', 'lokacija', 'mesto', 'city')
        date_col = self._find_col(df, 'created_at', 'datum', 'vreme', 'date')
        status_col = self._find_col(df, 'status', 'stanje')

        print(f"  [AutoDiscover] Zahtevi kolone: grad={grad_col}, date={date_col}, status={status_col}")

        if df.empty or not grad_col:
            return pd.DataFrame()
        df = df.copy()
        if date_col:
            df['created_at'] = pd.to_datetime(df[date_col], errors='coerce')
        else:
            df['created_at'] = pd.Timestamp.now()
        df = df.sort_values('created_at')
        # Agregacija po danu i gradu
        daily = df.groupby([df['created_at'].dt.date, grad_col]).size().reset_index(name='broj_zahteva')
        daily.columns = ['datum', 'grad', 'broj_zahteva']
        daily['datum'] = pd.to_datetime(daily['datum'])
        daily['dan_u_nedelji'] = daily['datum'].dt.dayofweek
        daily['mesec'] = daily['datum'].dt.month
        daily['dan_u_mesecu'] = daily['datum'].dt.day
        daily['je_vikend'] = daily['dan_u_nedelji'].isin([5, 6]).astype(int)
        daily['grad_bc'] = (daily['grad'] == 'BC').astype(int)
        # Lag features (prethodnih 7 dana)
        for lag in [1, 2, 3, 7]:
            daily[f'lag_{lag}d'] = daily.groupby('grad')['broj_zahteva'].shift(lag)
        # Rolling mean
        daily['rolling_7d'] = daily.groupby('grad')['broj_zahteva'].transform(lambda x: x.shift(1).rolling(7, min_periods=1).mean())
        daily['rolling_14d'] = daily.groupby('grad')['broj_zahteva'].transform(lambda x: x.shift(1).rolling(14, min_periods=1).mean())
        # Trend (rast/pad u poslednjih 7 dana)
        daily['trend_7d'] = daily.groupby('grad')['broj_zahteva'].transform(lambda x: x.shift(1).diff(7))
        daily = daily.fillna(0)
        return daily

    def train(self, df: pd.DataFrame):
        """Trenira model na zahtevima sa pravim evaluacijom"""
        print("=" * 50)
        print("Training Zahtevi ML Model from scratch")
        print("=" * 50)
        daily = self._extract_features(df)
        if len(daily) < 3:
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 0, 'samples': len(daily), 'warning': 'Premalo podataka'}
        feature_cols = [c for c in daily.columns if c not in ['datum', 'grad', 'broj_zahteva']]
        X = daily[feature_cols].fillna(0)
        self.scaler = StandardScaler()
        X_scaled = self.scaler.fit_transform(X)
        y = daily['broj_zahteva'].values
        n_samples = len(daily)
        eval_split = n_samples >= 10
        if eval_split:
            X_train, X_test, y_train, y_test = train_test_split(X_scaled, y, test_size=0.25, random_state=42, shuffle=False)
        else:
            X_train, X_test, y_train, y_test = X_scaled, X_scaled, y, y
            print(f"[WARN] Samo {n_samples} dana — evaluacija na trening setu")
        self.model = RandomForestRegressor(n_estimators=200, random_state=42, max_depth=12)
        self.model.fit(X_train, y_train)
        y_pred_train = self.model.predict(X_train)
        train_r2 = r2_score(y_train, y_pred_train)
        train_mae = mean_absolute_error(y_train, y_pred_train)
        metrics = {'train_r2': self._safe_float(train_r2), 'train_mae': self._safe_float(train_mae),
                   'feature_count': len(feature_cols), 'samples': n_samples, 'eval_on_train': not eval_split}
        if eval_split:
            y_pred_test = self.model.predict(X_test)
            metrics['test_r2'] = self._safe_float(r2_score(y_test, y_pred_test))
            metrics['test_mae'] = self._safe_float(mean_absolute_error(y_test, y_pred_test))
            metrics['r2_score'] = metrics['test_r2']
            print(f"Test R²: {metrics['test_r2']:.3f} | Test MAE: {metrics['test_mae']:.4f}")
        else:
            metrics['r2_score'] = self._safe_float(train_r2)
        print(f"Train R²: {train_r2:.3f} | Train MAE: {train_mae:.4f}")
        print(f"Samples: {n_samples} | Features: {len(feature_cols)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics

        # ZABORAVI stare tabele koje vise ne postoje
        self.memory.forget_old(["zahtevi"])

        # PAMTI sta je naucio
        sources = {"zahtevi": {"columns": list(feature_cols), "rows": n_samples}}
        feature_imp = dict(zip(feature_cols, self.model.feature_importances_)) if self.model else {}
        self.memory.record_training(sources, feature_imp, metrics)
        print("  [Memory] Zahtevi model zapamtio ucenje")

        return metrics

    def predict_next_week(self, df: pd.DataFrame) -> dict:
        """Predviđa zahteve za narednu nedelju po gradovima"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        last_date = pd.to_datetime(df['datum']).max() if 'datum' in df.columns else pd.Timestamp.now()
        next_week = pd.date_range(start=last_date + pd.Timedelta(days=1), periods=7, freq='D')
        grads = df['grad'].unique() if 'grad' in df.columns else ['BC']
        results = []
        total_pred = 0
        dani = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja']
        for grad in grads:
            for d in next_week:
                results.append({
                    'datum': d.strftime('%Y-%m-%d'),
                    'dan': dani[d.weekday()],
                    'grad': str(grad),
                    'procenjeni_zahtevi': 0.0  # Placeholder — real prediction requires lag data
                })
        return {
            'next_week': results,
            'ukupno_nedelja': round(float(total_pred), 1),
            'prosek_dnevno': round(float(total_pred / 7), 1) if total_pred > 0 else 0.0,
            'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None)
        }

    def analyze_trends(self, df: pd.DataFrame) -> dict:
        """Analizira trendove zahteva"""
        daily = self._extract_features(df)
        if len(daily) == 0:
            return {'trend': 'nema_podataka', 'najaktivniji_dan': '-', 'prosek_dnevno': 0}
        avg_by_day = daily.groupby('dan_u_nedelji')['broj_zahteva'].mean()
        dani = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja']
        najaktivniji = dani[avg_by_day.idxmax()] if not avg_by_day.empty else '-'
        # Linear trend
        if len(daily) >= 2:
            trend_val = np.polyfit(range(len(daily)), daily['broj_zahteva'].values, 1)[0]
        else:
            trend_val = 0
        return {
            'trend_val': round(float(trend_val), 2),
            'trend': 'rastuci' if trend_val > 0.1 else ('padajuci' if trend_val < -0.1 else 'stabilan'),
            'najaktivniji_dan': najaktivniji,
            'prosek_dnevno': round(float(daily['broj_zahteva'].mean()), 2),
            'ukupno_zahteva': int(daily['broj_zahteva'].sum()),
            'dana_u_bazi': len(daily),
            'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None)
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
