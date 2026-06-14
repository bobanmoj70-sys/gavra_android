"""
Putnik ML Model - Ensemble (Random Forest + XGBoost)
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
try:
    from xgboost import XGBRegressor, XGBClassifier
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False
    print("[WARN] XGBoost not available, using only Random Forest")


class PutnikMLModel:
    def __init__(self):
        self.is_trained = False
        self.payment_rf = None
        self.payment_xgb = None
        self.ltv_rf = None
        self.ltv_xgb = None
        self.scaler = StandardScaler()
        self.model_dir = config.MODEL_DIR
        os.makedirs(self.model_dir, exist_ok=True)
        self.memory = LearningMemory("putnik")
        self.discoverer = AutoFeatureDiscovery()
        self._last_data = {}
        from models.knowledge_graph import KnowledgeGraph
        self.knowledge_graph = KnowledgeGraph()

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

    def _add_cross_table_features(self, primary_df: pd.DataFrame, other_df: pd.DataFrame, table_name: str) -> pd.DataFrame:
        """Dodaje feature-e iz drugih tabela - automatski otkriva relevantne kolone"""
        if primary_df.empty or other_df.empty:
            return primary_df
        
        # Pronađi zajedničke ključeve
        join_keys = []
        for col in primary_df.columns:
            if any(k in col.lower() for k in ['id', 'putnik', 'user', 'auth']):
                for other_col in other_df.columns:
                    if col.lower() == other_col.lower() or col.lower() in other_col.lower():
                        join_keys.append((col, other_col))
        
        if not join_keys:
            return primary_df
        
        # Merge sa drugom tabelom
        result = primary_df.copy()
        for daily_key, other_key in join_keys[:1]:
            try:
                numeric_cols = other_df.select_dtypes(include=['number']).columns.tolist()
                
                if numeric_cols:
                    agg_dict = {col: 'sum' for col in numeric_cols}
                    stats = other_df.groupby(other_key).agg(agg_dict).reset_index()
                    
                    result = result.merge(
                        stats,
                        left_on=daily_key,
                        right_on=other_key,
                        how='left',
                        suffixes=('', f'_{table_name}')
                    )
                    
                    for col in result.columns:
                        if f'_{table_name}' in col:
                            result[col] = result[col].fillna(0)
                    
                    print(f"[CrossTable] Merged {table_name} on {daily_key} -> {len(numeric_cols)} numeric features")
            except Exception as e:
                print(f"[CrossTable] Merge failed for {table_name}: {e}")
        
        return result

    def train(self, data: dict):
        """Trenira model na SVIM tabelama - automatski otkriva šta je bitno"""
        print("=" * 50)
        print("Training Putnik ML Model from ALL tables")
        print("=" * 50)
        
        # Primary tables: users (putnici), finansije, zahtevi
        users_df = data.get('users', pd.DataFrame())
        fin_df = data.get('finansije', pd.DataFrame())
        zahtevi_df = data.get('zahtevi', pd.DataFrame())
        
        if users_df.empty:
            print("[WARN] No users data - cannot train")
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 0, 'samples': 0, 'warning': 'Nema podataka o putnicima'}
        
        print(f"Primary data: {len(users_df)} users, {len(fin_df)} finansije, {len(zahtevi_df)} zahtevi")
        print(f"Total tables: {len(data)}")
        
        # Izgradi knowledge graph za logičko povezivanje
        self.knowledge_graph.build_from_supabase(data)
        print(f"[KnowledgeGraph] {len(self.knowledge_graph.nodes)} entiteta, {sum(len(v) for v in self.knowledge_graph.edges.values())} relacija")
        
        # Koristi AutoFeatureDiscovery za automatsko otkrivanje bitnih feature-a
        print(f"[AutoFeature] Learning from {len(data)} tables...")
        discovered_features = self.discoverer.discover_features(data, target_table='users')
        print(f"[AutoFeature] Discovered {len(discovered_features)} potential features")
        
        # Ekstraktuj RFM feature-e
        rfm = self._extract_rfm_features(fin_df, zahtevi_df)
        y_churn, y_ltv = self._compute_targets(rfm)
        
        # Dodaj cross-table feature-e ako postoje relevantne tabele
        for table_name, table_df in data.items():
            if table_name in ['users', 'finansije', 'zahtevi'] or table_df.empty:
                continue
            try:
                enriched = self._add_cross_table_features(rfm, table_df, table_name)
                if not enriched.empty:
                    rfm = enriched
                    print(f"[CrossTable] Added features from {table_name}")
            except Exception as e:
                print(f"[CrossTable] Could not add features from {table_name}: {e}")
        
        # Re-compute targets after enrichment
        y_churn, y_ltv = self._compute_targets(rfm)
        
        X = rfm.select_dtypes(include=[np.number]).fillna(0)
        X_scaled = self.scaler.fit_transform(X)
        n_samples = len(rfm)
        eval_split = n_samples >= 10
        if eval_split:
            X_train, X_test, y_train_churn, y_test_churn = train_test_split(X_scaled, y_churn, test_size=0.25, random_state=42)
            _, _, y_train_ltv, y_test_ltv = train_test_split(X_scaled, y_ltv, test_size=0.25, random_state=42)
        else:
            X_train, X_test, y_train_churn, y_test_churn = X_scaled, X_scaled, y_churn, y_churn
            _, _, y_train_ltv, y_test_ltv = X_scaled, X_scaled, y_ltv, y_ltv
            print(f"[WARN] Samo {n_samples} putnika — evaluacija na trening setu")
        
        # Inicijalizuj ensemble modele
        self.payment_rf = RandomForestClassifier(n_estimators=200, random_state=42, max_depth=12)
        self.ltv_rf = RandomForestRegressor(n_estimators=200, random_state=42, max_depth=12)
        
        if XGBOOST_AVAILABLE:
            self.payment_xgb = XGBClassifier(n_estimators=200, max_depth=12, learning_rate=0.1, random_state=42)
            self.ltv_xgb = XGBRegressor(n_estimators=200, max_depth=12, learning_rate=0.1, random_state=42)
            print("[Ensemble] Using Random Forest + XGBoost")
        else:
            print("[Ensemble] Using Random Forest only (XGBoost not available)")
        
        # Churn model (ensemble)
        self.payment_rf.fit(X_train, y_train_churn)
        
        if XGBOOST_AVAILABLE:
            self.payment_xgb.fit(X_train, y_train_churn)
            # Ensemble predikcija - soft voting
            proba_rf = self.payment_rf.predict_proba(X_test)
            proba_xgb = self.payment_xgb.predict_proba(X_test)
            avg_proba = (proba_rf + proba_xgb) / 2
            y_pred_churn = np.argmax(avg_proba, axis=1)
        else:
            y_pred_churn = self.payment_rf.predict(X_test)
        
        churn_auc = roc_auc_score(y_test_churn, y_pred_churn) if eval_split else 0.0
        
        # LTV model (ensemble)
        self.ltv_rf.fit(X_train, y_train_ltv)
        
        if XGBOOST_AVAILABLE:
            self.ltv_xgb.fit(X_train, y_train_ltv)
            # Ensemble predikcija
            y_pred_rf = self.ltv_rf.predict(X_test)
            y_pred_xgb = self.ltv_xgb.predict(X_test)
            y_pred_ltv = (y_pred_rf + y_pred_xgb) / 2
        else:
            y_pred_ltv = self.ltv_rf.predict(X_test)
        
        ltv_r2 = r2_score(y_test_ltv, y_pred_ltv) if eval_split else 0.0
        
        metrics = {
            'churn_auc': self._safe_float(churn_auc),
            'ltv_r2': self._safe_float(ltv_r2),
            'feature_count': len(X.columns),
            'samples': n_samples,
            'eval_on_train': not eval_split,
            'tables_used': len(data)
        }
        
        print(f"Churn AUC: {churn_auc:.3f} | LTV R²: {ltv_r2:.3f}")
        print(f"Samples: {n_samples} | Features: {len(X.columns)} | Tables: {len(data)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics
        self._last_data = data

        # ZABORAVI stare tabele koje vise ne postoje
        self.memory.forget_old(list(data.keys()))

        # PAMTI sta je naucio iz SVIH tabela - kombinujemo feature importance
        if XGBOOST_AVAILABLE and self.payment_xgb is not None:
            rf_importance = self.payment_rf.feature_importances_
            xgb_importance = self.payment_xgb.feature_importances_
            combined_importance = (rf_importance + xgb_importance) / 2
        else:
            combined_importance = self.payment_rf.feature_importances_
        
        sources = {tbl: {"columns": list(df.columns), "rows": len(df)} for tbl, df in data.items()}
        feature_imp = dict(zip(X.columns, combined_importance)) if self.payment_rf else {}
        self.memory.record_training(sources, feature_imp, metrics)
        print("  [Memory] Putnik model zapamtio ucenje")

        return metrics

    def analyze_passengers(self, data: dict) -> dict:
        """Analizira putnike sa churn + LTV predikcijom (ensemble)"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        
        fin_df = data.get('finansije', pd.DataFrame())
        zahtevi_df = data.get('zahtevi', pd.DataFrame())
        
        rfm = self._extract_rfm_features(fin_df, zahtevi_df)
        if rfm.empty:
            return {'passengers': [], 'total': 0, 'lojalan': 0, 'rizican': 0, 'prosecan': 0, 'ukupan_prihod': 0}
        
        all_feature_cols = ['recency_dana', 'frekvenca', 'ukupno_platio', 'prosecan_iznos', 'std_iznos',
                              'broj_prihoda', 'ukupno_voznji', 'cancellation_rate', 'vrednost_po_voznji',
                              'broj_zahteva', 'zahtevi_otkazano', 'tenure_dana']
        feature_cols = [c for c in all_feature_cols if c in rfm.columns]
        X = rfm[feature_cols].fillna(0)
        X_scaled = self.scaler.transform(X)
        
        # Churn predikcija (ensemble)
        if XGBOOST_AVAILABLE and self.payment_xgb is not None:
            proba_rf = self.payment_rf.predict_proba(X_scaled)
            proba_xgb = self.payment_xgb.predict_proba(X_scaled)
            avg_proba = (proba_rf + proba_xgb) / 2
            churn_proba = avg_proba[:, 1] if avg_proba.shape[1] > 1 else np.zeros(len(avg_proba))
        else:
            proba = self.payment_rf.predict_proba(X_scaled)
            churn_proba = proba[:, 1] if proba.shape[1] > 1 else np.zeros(len(proba))
        
        rfm['churn_risk'] = churn_proba
        
        # LTV predikcija (ensemble)
        if XGBOOST_AVAILABLE and self.ltv_xgb is not None:
            ltv_rf = self.ltv_rf.predict(X_scaled)
            ltv_xgb = self.ltv_xgb.predict(X_scaled)
            ltv_pred = (ltv_rf + ltv_xgb) / 2
        else:
            ltv_pred = self.ltv_rf.predict(X_scaled)
        
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
            'model_r2': getattr(self, '_last_metrics', {}).get('ltv_r2', None),
            'churn_auc': getattr(self, '_last_metrics', {}).get('churn_auc', None)
        }

    def save(self):
        if not self.is_trained:
            return
        joblib.dump(self.payment_rf, f"{self.model_dir}/putnik_churn_rf.pkl")
        joblib.dump(self.ltv_rf, f"{self.model_dir}/putnik_ltv_rf.pkl")
        if XGBOOST_AVAILABLE and self.payment_xgb is not None:
            joblib.dump(self.payment_xgb, f"{self.model_dir}/putnik_churn_xgb.pkl")
        if XGBOOST_AVAILABLE and self.ltv_xgb is not None:
            joblib.dump(self.ltv_xgb, f"{self.model_dir}/putnik_ltv_xgb.pkl")
        joblib.dump(self.scaler, f"{self.model_dir}/putnik_scaler.pkl")
        print("[OK] Putnik ensemble model saved")

    def load(self):
        try:
            self.payment_rf = joblib.load(f"{self.model_dir}/putnik_churn_rf.pkl")
            self.ltv_rf = joblib.load(f"{self.model_dir}/putnik_ltv_rf.pkl")
            try:
                if XGBOOST_AVAILABLE:
                    self.payment_xgb = joblib.load(f"{self.model_dir}/putnik_churn_xgb.pkl")
                    self.ltv_xgb = joblib.load(f"{self.model_dir}/putnik_ltv_xgb.pkl")
            except FileNotFoundError:
                print("[WARN] XGBoost models not found, using only Random Forest")
                self.payment_xgb = None
                self.ltv_xgb = None
            self.scaler = joblib.load(f"{self.model_dir}/putnik_scaler.pkl")
            self.is_trained = True
            print("[OK] Putnik ensemble model loaded")
        except FileNotFoundError:
            print("[MISSING] No saved putnik model")
