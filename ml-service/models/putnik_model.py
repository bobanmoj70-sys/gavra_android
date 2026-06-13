"""
Putnik ML Model - Random Forest
Uci iskljucivo iz Supabase v3_finansije i v3_zahtevi podataka
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score, classification_report, mean_squared_error, r2_score, mean_absolute_error
import joblib
import os
import config
from models.learning_memory import LearningMemory
from models.auto_features import AutoFeatureDiscovery


class PutnikMLModel:
    def __init__(self):
        self.is_trained = False
        self.payment_model = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)
        self.memory = LearningMemory("putnik")
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

    def _extract_rfm_features(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame) -> pd.DataFrame:
        """Generiše RFM (Recency, Frequency, Monetary) + dodatne feature po putniku - DINAMICKI"""
        # DINAMICKI otkriji kljucne kolone
        putnik_id_col = self._find_col(fin_df, 'putnik_v3_auth_id', 'putnik_id', 'user_id', 'auth_id')
        iznos_col = self._find_col(fin_df, 'iznos', 'amount', 'vrednost')
        tip_col = self._find_col(fin_df, 'tip', 'type', 'vrsta')
        created_col = self._find_col(fin_df, 'created_at', 'datum', 'vreme')
        voznje_col = self._find_col(fin_df, 'broj_voznji', 'voznji')
        otkaz_col = self._find_col(fin_df, 'broj_otkazivanja', 'otkazivanja', 'cancelled')

        print(f"  [AutoDiscover] Putnik kolone: putnik_id={putnik_id_col}, iznos={iznos_col}, tip={tip_col}, created={created_col}")

        if fin_df.empty or not putnik_id_col:
            return pd.DataFrame()
        fin_df = fin_df.copy()
        fin_df['created_at'] = pd.to_datetime(fin_df.get(created_col, pd.Timestamp.now()) if created_col else pd.Timestamp.now(), errors='coerce')
        # Ukloni timezone ako postoji da izbegnemo tz-naive vs tz-aware grešku
        if fin_df['created_at'].dt.tz is not None:
            fin_df['created_at'] = fin_df['created_at'].dt.tz_localize(None)
        fin_df['iznos'] = pd.to_numeric(fin_df[iznos_col], errors='coerce').fillna(0) if iznos_col else pd.Series([0] * len(fin_df), index=fin_df.index)
        now = pd.Timestamp.now()
        # RFM iz finansija — dinamicki agg_dict
        agg_dict = {
            'created_at': ['max', 'min', 'count'],
            'iznos': ['sum', 'mean', 'std'],
        }
        if tip_col:
            agg_dict[tip_col] = lambda x: (x == 'prihod').sum()
        if voznje_col:
            agg_dict[voznje_col] = 'sum'
        if otkaz_col:
            agg_dict[otkaz_col] = 'sum'
        rfm = fin_df.groupby(putnik_id_col).agg(agg_dict).reset_index()
        base_cols = ['putnik_id', 'poslednja_transakcija', 'prva_transakcija', 'frekvenca',
                     'ukupno_platio', 'prosecan_iznos', 'std_iznos']
        if tip_col:
            base_cols.append('broj_prihoda')
        if voznje_col:
            base_cols.append('ukupno_voznji')
        if otkaz_col:
            base_cols.append('ukupno_otkazivanja')
        rfm.columns = base_cols
        # Ukloni timezone pre oduzimanja
        poslednja = pd.to_datetime(rfm['poslednja_transakcija'], errors='coerce')
        prva = pd.to_datetime(rfm['prva_transakcija'], errors='coerce')
        if poslednja.dt.tz is not None:
            poslednja = poslednja.dt.tz_localize(None)
        if prva.dt.tz is not None:
            prva = prva.dt.tz_localize(None)
        rfm['recency_dana'] = (now - poslednja).dt.days.fillna(999)
        rfm['tenure_dana'] = (now - prva).dt.days.fillna(0)
        if 'ukupno_otkazivanja' not in rfm.columns:
            rfm['ukupno_otkazivanja'] = 0
        if 'ukupno_voznji' not in rfm.columns:
            rfm['ukupno_voznji'] = 0
        rfm['cancellation_rate'] = (rfm['ukupno_otkazivanja'] / rfm['frekvenca'].clip(lower=1)).fillna(0)
        rfm['vrednost_po_voznji'] = (rfm['ukupno_platio'] / rfm['ukupno_voznji'].clip(lower=1)).fillna(0)
        rfm['std_iznos'] = rfm['std_iznos'].fillna(0)
        # Zahtevi feature - DINAMICKI otkrij kolone
        zah_user_col = self._find_col(zahtevi_df, 'created_by', 'putnik_id', 'user_id', 'auth_id') if not zahtevi_df.empty else None
        zah_id_col = self._find_col(zahtevi_df, 'id') if not zahtevi_df.empty else None
        zah_status_col = self._find_col(zahtevi_df, 'status', 'stanje') if not zahtevi_df.empty else None

        if zah_user_col and zah_id_col:
            agg = {zah_id_col: 'count'}
            if zah_status_col:
                agg[zah_status_col] = lambda x: (x == 'otkazano').sum()
            zah = zahtevi_df.groupby(zah_user_col).agg(agg).reset_index()
            cols = ['putnik_id', 'broj_zahteva']
            if zah_status_col:
                cols.append('zahtevi_otkazano')
            zah.columns = cols
            rfm = rfm.merge(zah, on='putnik_id', how='left')
            rfm['broj_zahteva'] = rfm['broj_zahteva'].fillna(0)
            if zah_status_col:
                rfm['zahtevi_otkazano'] = rfm['zahtevi_otkazano'].fillna(0)
        else:
            rfm['broj_zahteva'] = 0
            rfm['zahtevi_otkazano'] = 0
        rfm = rfm.fillna(0)
        return rfm

    def _compute_targets(self, rfm: pd.DataFrame):
        """
        Dva targeta:
        1. churn_30d: da li putnik NEMA transakciju u poslednjih 30 dana (1 = churned)
        2. lifetime_value: procenjena buduća vrednost = ukupno_platio * (frekvenca / tenure) * 365
        """
        # Churn: recency > 30 dana
        y_churn = (rfm['recency_dana'] > 30).astype(int)
        # LTV: annualized value
        rfm['ltv'] = rfm['ukupno_platio'] * (rfm['frekvenca'] / rfm['tenure_dana'].clip(lower=1)) * 365
        y_ltv = rfm['ltv'].fillna(0).values
        return y_churn, y_ltv

    def train(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame):
        """Trenira model na putnik podacima sa churn + LTV predikcijom"""
        print("=" * 50)
        print("Training Putnik ML Model from scratch")
        print("=" * 50)
        rfm = self._extract_rfm_features(fin_df, zahtevi_df)
        if rfm.empty:
            print("[WARN] Nema dovoljno podataka za treniranje")
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 0, 'samples': 0, 'warning': 'Nema podataka'}
        all_feature_cols = ['recency_dana', 'frekvenca', 'ukupno_platio', 'prosecan_iznos', 'std_iznos',
                              'broj_prihoda', 'ukupno_voznji', 'cancellation_rate', 'vrednost_po_voznji',
                              'broj_zahteva', 'zahtevi_otkazano', 'tenure_dana']
        feature_cols = [c for c in all_feature_cols if c in rfm.columns]
        X = rfm[feature_cols].fillna(0)
        self.scaler = StandardScaler()
        X_scaled = self.scaler.fit_transform(X)
        y_churn, y_ltv = self._compute_targets(rfm)
        n_samples = len(rfm)
        eval_split = n_samples >= 10
        if eval_split:
            Xc_train, Xc_test, yc_train, yc_test = train_test_split(X_scaled, y_churn, test_size=0.25, random_state=42)
            Xl_train, Xl_test, yl_train, yl_test = train_test_split(X_scaled, y_ltv, test_size=0.25, random_state=42)
        else:
            Xc_train, Xc_test, yc_train, yc_test = X_scaled, X_scaled, y_churn, y_churn
            Xl_train, Xl_test, yl_train, yl_test = X_scaled, X_scaled, y_ltv, y_ltv
            print(f"[WARN] Samo {n_samples} putnika — evaluacija na trening setu")
        # Churn classifier
        self.churn_model = RandomForestClassifier(n_estimators=200, random_state=42, max_depth=12)
        self.churn_model.fit(Xc_train, yc_train)
        yc_pred_train = self.churn_model.predict(Xc_train)
        try:
            churn_auc_train = roc_auc_score(yc_train, self.churn_model.predict_proba(Xc_train)[:, 1])
        except (ValueError, IndexError):
            churn_auc_train = 0.5  # jedna klasa, nema smisla racunati AUC
        # LTV regressor
        self.value_model = RandomForestRegressor(n_estimators=200, random_state=42, max_depth=12)
        self.value_model.fit(Xl_train, yl_train)
        yl_pred_train = self.value_model.predict(Xl_train)
        ltv_r2_train = r2_score(yl_train, yl_pred_train)
        ltv_mae_train = mean_absolute_error(yl_train, yl_pred_train)
        metrics = {'churn_auc_train': self._safe_float(churn_auc_train), 'ltv_r2_train': self._safe_float(ltv_r2_train),
                   'ltv_mae_train': self._safe_float(ltv_mae_train), 'feature_count': len(feature_cols),
                   'samples': n_samples, 'eval_on_train': not eval_split}
        if eval_split:
            yc_pred_test = self.churn_model.predict(Xc_test)
            try:
                churn_auc_test = roc_auc_score(yc_test, self.churn_model.predict_proba(Xc_test)[:, 1])
            except (ValueError, IndexError):
                churn_auc_test = 0.5
            yl_pred_test = self.value_model.predict(Xl_test)
            ltv_r2_test = r2_score(yl_test, yl_pred_test)
            ltv_mae_test = mean_absolute_error(yl_test, yl_pred_test)
            metrics['churn_auc_test'] = self._safe_float(churn_auc_test)
            metrics['ltv_r2_test'] = self._safe_float(ltv_r2_test)
            metrics['ltv_mae_test'] = self._safe_float(ltv_mae_test)
            metrics['r2_score'] = self._safe_float(ltv_r2_test)
            print(f"Churn AUC: {churn_auc_test:.3f} | LTV R²: {ltv_r2_test:.3f} | LTV MAE: {ltv_mae_test:.2f}")
        else:
            metrics['r2_score'] = self._safe_float(ltv_r2_train)
        print(f"Churn AUC (train): {churn_auc_train:.3f} | LTV R² (train): {ltv_r2_train:.3f}")
        print(f"Samples: {n_samples} | Features: {len(feature_cols)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics

        # ZABORAVI stare tabele koje vise ne postoje
        self.memory.forget_old(["putnik"])

        # PAMTI sta je naucio
        sources = {"putnik": {"columns": list(feature_cols), "rows": n_samples}}
        feature_imp = dict(zip(feature_cols, self.value_model.feature_importances_)) if self.value_model else {}
        self.memory.record_training(sources, feature_imp, metrics)
        print("  [Memory] Putnik model zapamtio ucenje")

        return metrics

    def analyze_passengers(self, fin_df: pd.DataFrame, zahtevi_df: pd.DataFrame) -> dict:
        """Analizira putnike sa churn + LTV predikcijom"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        rfm = self._extract_rfm_features(fin_df, zahtevi_df)
        if rfm.empty:
            return {'passengers': [], 'total': 0, 'lojalan': 0, 'rizican': 0, 'prosecan': 0, 'ukupan_prihod': 0}
        all_feature_cols = ['recency_dana', 'frekvenca', 'ukupno_platio', 'prosecan_iznos', 'std_iznos',
                              'broj_prihoda', 'ukupno_voznji', 'cancellation_rate', 'vrednost_po_voznji',
                              'broj_zahteva', 'zahtevi_otkazano', 'tenure_dana']
        feature_cols = [c for c in all_feature_cols if c in rfm.columns]
        X = rfm[feature_cols].fillna(0)
        X_scaled = self.scaler.transform(X)
        # Churn predikcija
        proba = self.churn_model.predict_proba(X_scaled)
        churn_proba = proba[:, 1] if proba.shape[1] > 1 else np.zeros(len(proba))
        rfm['churn_risk'] = churn_proba
        # LTV predikcija
        ltv_pred = self.value_model.predict(X_scaled)
        rfm['predicted_ltv'] = ltv_pred
        # Kategorizacija na osnovu churn risk + LTV
        def kategorija(row):
            if row['churn_risk'] < 0.3 and row['predicted_ltv'] > rfm['predicted_ltv'].median():
                return 'lojalan'
            elif row['churn_risk'] > 0.7:
                return 'rizican'
            else:
                return 'prosecan'
        rfm['kategorija'] = rfm.apply(kategorija, axis=1)
        passengers = []
        for _, row in rfm.iterrows():
            passengers.append({
                'putnik_id': str(row['putnik_id'])[:8] + '...',
                'ukupno_platio': round(float(row['ukupno_platio']), 2),
                'broj_transakcija': int(row['frekvenca']),
                'prosecan_iznos': round(float(row['prosecan_iznos']), 2),
                'churn_risk': round(float(row['churn_risk']) * 100, 1),
                'predicted_ltv': round(float(row['predicted_ltv']), 2),
                'recency_dana': int(row['recency_dana']),
                'kategorija': row['kategorija']
            })
        return {
            'passengers': sorted(passengers, key=lambda x: x['predicted_ltv'], reverse=True),
            'total': len(passengers),
            'lojalan': sum(1 for p in passengers if p['kategorija'] == 'lojalan'),
            'rizican': sum(1 for p in passengers if p['kategorija'] == 'rizican'),
            'prosecan': sum(1 for p in passengers if p['kategorija'] == 'prosecan'),
            'ukupan_prihod': sum(p['ukupno_platio'] for p in passengers),
            'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None),
            'churn_auc': getattr(self, '_last_metrics', {}).get('churn_auc_test',
                                 getattr(self, '_last_metrics', {}).get('churn_auc_train', None))
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.churn_model, f"{self.model_dir}/putnik_churn_model.pkl")
        joblib.dump(self.value_model, f"{self.model_dir}/putnik_ltv_model.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/putnik_scaler.pkl")
        print("[OK] Putnik model saved")

    def load(self):
        try:
            self.churn_model = joblib.load(f"{self.model_dir}/putnik_churn_model.pkl")
            self.value_model = joblib.load(f"{self.model_dir}/putnik_ltv_model.pkl")
            self.scaler = joblib.load(f"{self.model_dir}/putnik_scaler.pkl")
            self.is_trained = True
            print("[OK] Putnik model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved putnik model")
