"""
Financial ML Model - Ensemble (Random Forest + XGBoost)
Uči isključivo iz Supabase podataka (v3_finansije)
Bez pre-trained znanja, čisti learning od nule
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestRegressor, RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import mean_squared_error, r2_score, classification_report, mean_absolute_error
import joblib
import os
import config
from data.features import prepare_ml_features
from models.learning_memory import LearningMemory
from models.auto_features import AutoFeatureDiscovery
try:
    from xgboost import XGBRegressor, XGBClassifier
    XGBOOST_AVAILABLE = True
except ImportError:
    XGBOOST_AVAILABLE = False
    print("[WARN] XGBoost not available, using only Random Forest")

try:
    from prophet import Prophet
    PROPHET_AVAILABLE = True
except ImportError:
    PROPHET_AVAILABLE = False
    print("[WARN] Prophet not available, time series predictions disabled")

try:
    from river import linear_model, preprocessing, metrics, optim, loss
    RIVER_AVAILABLE = True
except ImportError:
    RIVER_AVAILABLE = False
    print("[WARN] River not available, online learning disabled")

try:
    from sklearn.feature_selection import RFE
    RFE_AVAILABLE = True
except ImportError:
    RFE_AVAILABLE = False
    print("[WARN] RFE not available, advanced feature selection disabled")


class FinancialMLModel:
    def __init__(self):
        # Pamcenje - model pamti sta je video i naucio
        self.memory = LearningMemory("financial")
        self.discoverer = AutoFeatureDiscovery()
        self._last_data = {}
        from models.knowledge_graph import KnowledgeGraph
        self.knowledge_graph = KnowledgeGraph()

        # Modeli - ensemble Random Forest + XGBoost
        self.amount_rf = None
        self.amount_xgb = None
        self.type_rf = None
        self.type_xgb = None
        self.scaler = StandardScaler()
        self.feature_columns = None
        self.is_amount_trained = False
        self.is_type_trained = False

        # Time series model (Prophet)
        self.prophet_model = None
        self.is_prophet_trained = False

        # Online learning model (River)
        self.online_model = None
        self.online_scaler = None
        self.is_online_trained = False

        # RFE selected features
        self.rfe_selected_features = None
        self.is_rfe_applied = False

        # Samootkrivene mete (target columns)
        self.amount_target_col = None
        self.type_target_col = None

    def _detect_targets(self, df: pd.DataFrame):
        """Sami otkrije koje kolone su potencijalne mete"""
        amount_keywords = ['iznos', 'cena', 'vrednost', 'amount', 'suma', 'total', 'price', 'cost', 'kolicina']
        type_keywords = ['tip', 'type', 'status', 'kategorija', 'kategorija', 'vrsta', 'kla']

        for col in df.columns:
            lower = col.lower()
            if any(k in lower for k in amount_keywords):
                if pd.to_numeric(df[col], errors='coerce').notna().sum() > 5:
                    self.amount_target_col = col
                    print(f"  [Auto] Amount target detected: '{col}'")
            if any(k in lower for k in type_keywords):
                if df[col].nunique() >= 2 and df[col].nunique() < 50:
                    self.type_target_col = col
                    print(f"  [Auto] Type target detected: '{col}'")

    def _prepare_features_auto(self, df: pd.DataFrame) -> pd.DataFrame:
        """Automatski pripremi feature-e bez hardkodiranja"""
        self.discoverer.discover_table(df, table_name="finansije")
        features = self.discoverer.extract_features(df, table_name="finansije")
        # Ukloni mete iz feature-a
        for col in [self.amount_target_col, self.type_target_col]:
            if col and col in features.columns:
                del features[col]
        # Ukloni ID kolone
        id_cols = [c for c in features.columns if c.endswith('_id') and c != 'id']
        features = features.drop(columns=id_cols, errors='ignore')
        return features.fillna(0)

    def _safe_float(self, val):
        return None if val != val else float(val)
    
    def prepare_training_data(self, df: pd.DataFrame):
        """
        Priprema podatke za treniranje - AUTOMATSKI, bez hardkodiranja.
        Sam otkriva sta je target, sta su feature-i.
        """
        # Otkrij mete
        self._detect_targets(df)

        # Pripremi feature-e automatski
        features = self._prepare_features_auto(df)

        # Target za amount model
        if self.amount_target_col and self.amount_target_col in df.columns:
            y_amount = pd.to_numeric(df[self.amount_target_col], errors='coerce').fillna(0)
        else:
            # Ako nema jasan target, probaj bilo koju numericku kolonu
            numeric_cols = df.select_dtypes(include=[np.number]).columns.tolist()
            if numeric_cols:
                self.amount_target_col = numeric_cols[0]
                y_amount = df[numeric_cols[0]].fillna(0)
                print(f"  [Auto] Fallback amount target: '{numeric_cols[0]}'")
            else:
                y_amount = pd.Series([0] * len(df))

        # Target za type model
        if self.type_target_col and self.type_target_col in df.columns:
            # Pretvori u numericki (0, 1, 2...)
            unique_vals = df[self.type_target_col].dropna().unique()
            if len(unique_vals) >= 2:
                type_map = {v: i for i, v in enumerate(unique_vals)}
                y_type = df[self.type_target_col].map(type_map).fillna(0)
            else:
                y_type = pd.Series([0] * len(df))
        else:
            y_type = pd.Series([0] * len(df))

        self.feature_columns = features.columns.tolist()
        return features, y_amount, y_type

    def _add_cross_table_features(self, primary_df: pd.DataFrame, other_df: pd.DataFrame, table_name: str) -> pd.DataFrame:
        """Dodaje feature-e iz drugih tabela - automatski otkriva relevantne kolone"""
        if primary_df.empty or other_df.empty:
            return primary_df
        
        # Pronađi zajedničke ključeve
        join_keys = []
        for col in primary_df.columns:
            if any(k in col.lower() for k in ['id', 'created_by', 'vozac', 'putnik', 'user', 'auth']):
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
        """
        Trenira model na SVIM tabelama - automatski otkriva šta je bitno.
        """
        print("=" * 50)
        print("Training Financial ML Model from ALL tables")
        print("=" * 50)
        
        # Primary table: finansije
        fin_df = data.get('finansije', pd.DataFrame())
        if fin_df.empty:
            print("[WARN] No finansije data - cannot train")
            return {"error": "no_finansije_data"}
        
        print(f"Primary data: {len(fin_df)} records")
        print(f"Total tables: {len(data)}")
        
        # Izgradi knowledge graph za logičko povezivanje
        self.knowledge_graph.build_from_supabase(data)
        print(f"[KnowledgeGraph] {len(self.knowledge_graph.nodes)} entiteta, {sum(len(v) for v in self.knowledge_graph.edges.values())} relacija")
        
        # Koristi AutoFeatureDiscovery za automatsko otkrivanje bitnih feature-a
        print(f"[AutoFeature] Learning from {len(data)} tables...")
        discovered_features = self.discoverer.discover_features(data, target_table='finansije')
        print(f"[AutoFeature] Discovered {len(discovered_features)} potential features")
        
        # Priprema podataka - SAMI otkrivamo sta je bitno
        features, y_amount, y_type = self.prepare_training_data(fin_df)
        print(f"Auto-discovered features: {len(self.feature_columns)}")
        print(f"Amount target: {self.amount_target_col}")
        print(f"Type target: {self.type_target_col}")

        if len(self.feature_columns) == 0:
            print("[WARN] Nema feature-a za treniranje!")
            return {"error": "no_features"}

        # Dodaj cross-table feature-e ako postoje relevantne tabele
        for table_name, table_df in data.items():
            if table_name == 'finansije' or table_df.empty:
                continue
            try:
                enriched = self._add_cross_table_features(fin_df, table_df, table_name)
                if not enriched.empty:
                    fin_df = enriched
                    print(f"[CrossTable] Added features from {table_name}")
            except Exception as e:
                print(f"[CrossTable] Could not add features from {table_name}: {e}")
        
        # Re-prepare features after cross-table enrichment
        features, y_amount, y_type = self.prepare_training_data(fin_df)

        # Split
        X_train, X_test, y_train_amount, y_test_amount = train_test_split(
            features, y_amount, test_size=0.2, random_state=42
        )
        _, _, y_train_type, y_test_type = train_test_split(
            features, y_type, test_size=0.2, random_state=42
        )

        # Scale
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)

        # Inicijalizuj ensemble modele (Random Forest + XGBoost)
        self.amount_rf = RandomForestRegressor(
            n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
        )
        self.type_rf = RandomForestClassifier(
            n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
        )

        if XGBOOST_AVAILABLE:
            self.amount_xgb = XGBRegressor(
                n_estimators=100, max_depth=10, learning_rate=0.1, random_state=42, n_jobs=-1
            )
            self.type_xgb = XGBClassifier(
                n_estimators=100, max_depth=10, learning_rate=0.1, random_state=42, n_jobs=-1
            )
            print("[Ensemble] Using Random Forest + XGBoost")
        else:
            print("[Ensemble] Using Random Forest only (XGBoost not available)")

        # Treniraj amount model (ensemble)
        print("\n[1/2] Training Amount Prediction Model (Ensemble)...")
        self.amount_rf.fit(X_train_scaled, y_train_amount)
        
        if XGBOOST_AVAILABLE:
            self.amount_xgb.fit(X_train_scaled, y_train_amount)
            # Ensemble predikcija - prosečna vrednost
            y_pred_rf = self.amount_rf.predict(X_test_scaled)
            y_pred_xgb = self.amount_xgb.predict(X_test_scaled)
            y_pred_amount = (y_pred_rf + y_pred_xgb) / 2
        else:
            y_pred_amount = self.amount_rf.predict(X_test_scaled)
        
        self.is_amount_trained = True

        mse = mean_squared_error(y_test_amount, y_pred_amount)
        r2 = r2_score(y_test_amount, y_pred_amount)

        print(f"  MSE: {mse:.2f}")
        print(f"  R²: {self._safe_float(r2)}")
        print(f"  Avg Prediction Error: {np.sqrt(mse):.2f}")

        # Feature importance - kombinujemo iz oba modela
        if XGBOOST_AVAILABLE:
            rf_importance = self.amount_rf.feature_importances_
            xgb_importance = self.amount_xgb.feature_importances_
            combined_importance = (rf_importance + xgb_importance) / 2
        else:
            combined_importance = self.amount_rf.feature_importances_

        importance = pd.DataFrame({
            'feature': self.feature_columns,
            'importance': combined_importance
        }).sort_values('importance', ascending=False)
        top_features = importance.head(10)
        print("\nTop 10 Most Important Features (auto-discovered):")
        print(top_features)

        # Pamti sta smo naucili
        feature_imp_dict = dict(zip(top_features['feature'], top_features['importance']))

        # Treniraj type model (ensemble)
        n_classes = y_train_type.nunique()
        if n_classes >= 2 and self.type_target_col:
            print("\n[2/2] Training Type Prediction Model (Ensemble)...")
            self.type_rf.fit(X_train_scaled, y_train_type)
            
            if XGBOOST_AVAILABLE:
                self.type_xgb.fit(X_train_scaled, y_train_type)
                # Ensemble predikcija - soft voting
                proba_rf = self.type_rf.predict_proba(X_test_scaled)
                proba_xgb = self.type_xgb.predict_proba(X_test_scaled)
                avg_proba = (proba_rf + proba_xgb) / 2
                y_pred_type = np.argmax(avg_proba, axis=1)
            else:
                y_pred_type = self.type_rf.predict(X_test_scaled)
            
            self.is_type_trained = True
            print("\nClassification Report:")
            print(classification_report(y_test_type, y_pred_type))
        else:
            print(f"\n[SKIP] Type model - {n_classes} class(es), need 2+ for classification")
            self.is_type_trained = False

        # PAMTI sve sto si video i naucio iz SVIH tabela
        self._last_data = data
        self.memory.forget_old(list(data.keys()))

        sources = {tbl: {"columns": list(df.columns), "rows": len(df)} for tbl, df in data.items()}
        metrics = {
            "amount_mse": self._safe_float(mse),
            "amount_r2": self._safe_float(r2),
            "amount_rmse": self._safe_float(np.sqrt(mse)),
            "features": len(self.feature_columns),
            "samples": len(fin_df),
            "tables_used": len(data),
            "type_model_trained": self.is_type_trained,
            "type_classes": int(n_classes)
        }
        self.memory.record_training(sources, feature_imp_dict, metrics)

        # Proveri promene u odnosu na proslo pamcenje
        changes = self.memory.discover_changes(sources)
        if changes["new_tables"]:
            print(f"  [Memory] Nove tabele otkrivene: {changes['new_tables']}")
        if changes["removed_tables"]:
            print(f"  [Memory] Uklonjene tabele: {changes['removed_tables']}")
        if changes["new_columns"]:
            print(f"  [Memory] Nove kolone: {changes['new_columns']}")
        if changes["is_first_time"]:
            print("  [Memory] Prvo ucenje - beba uci da hoda!")

        self._last_metrics = metrics
        print("\n" + "=" * 50)
        print("Training Complete! (pamcenje sacuvano)")
        print("=" * 50)
        return self._last_metrics
    
    def predict_amount(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Predikcija iznosa za nove transakcije (ensemble)
        Model koristi naučeno znanje isključivo iz Supabase podataka
        """
        if not self.is_amount_trained:
            raise ValueError("Amount model must be trained before prediction")
        
        features = prepare_ml_features(df)
        
        # Osiguramo iste kolone
        for col in self.feature_columns:
            if col not in features.columns:
                features[col] = 0
        
        features = features[self.feature_columns]
        
        # Scale i predict (ensemble)
        features_scaled = self.scaler.transform(features)
        
        if XGBOOST_AVAILABLE and self.amount_xgb is not None:
            pred_rf = self.amount_rf.predict(features_scaled)
            pred_xgb = self.amount_xgb.predict(features_scaled)
            predictions = (pred_rf + pred_xgb) / 2
        else:
            predictions = self.amount_rf.predict(features_scaled)
        
        results = df.copy()
        results['predicted_amount'] = predictions
        
        return results
    
    def predict_type(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Predikcija tipa (prihod/rashod) - ensemble
        """
        if not self.is_type_trained:
            raise ValueError("Type model must be trained before prediction — need both 'prihod' and 'rashod' data")
        
        features = prepare_ml_features(df)
        
        # Osiguramo iste kolone
        for col in self.feature_columns:
            if col not in features.columns:
                features[col] = 0
        
        features = features[self.feature_columns]
        
        # Scale i predict (ensemble)
        features_scaled = self.scaler.transform(features)
        
        if XGBOOST_AVAILABLE and self.type_xgb is not None:
            # Soft voting ensemble
            proba_rf = self.type_rf.predict_proba(features_scaled)
            proba_xgb = self.type_xgb.predict_proba(features_scaled)
            avg_proba = (proba_rf + proba_xgb) / 2
            predictions = np.argmax(avg_proba, axis=1)
            probabilities = avg_proba
        else:
            predictions = self.type_rf.predict(features_scaled)
            probabilities = self.type_rf.predict_proba(features_scaled)
        
        results = df.copy()
        results['predicted_type'] = ['prihod' if p == 1 else 'rashod' for p in predictions]
        results['confidence'] = probabilities.max(axis=1)
        
        return results
    
    def detect_anomalies(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Detektuje anomalije u transakcijama koristeći IQR + Z-score hibrid.
        Uči granice SAMO iz trening podataka (bez hardkodovanih pragova).
        """
        df = df.copy()
        df['iznos'] = pd.to_numeric(df['iznos'], errors='coerce').fillna(0)
        # Po tipu transakcije
        anomalies = []
        for tip in df['tip'].unique() if 'tip' in df.columns else ['all']:
            subset = df[df['tip'] == tip] if tip != 'all' else df
            if len(subset) < 5:
                continue
            vals = subset['iznos']
            # IQR
            q1, q3 = vals.quantile([0.25, 0.75])
            iqr = q3 - q1
            lower_iqr = q1 - 1.5 * iqr
            upper_iqr = q3 + 1.5 * iqr
            # Z-score (robust - median absolute deviation)
            med = vals.median()
            mad = np.median(np.abs(vals - med)) * 1.4826  # consistent with std
            if mad == 0:
                mad = vals.std() or 1
            z_scores = np.abs((vals - med) / mad)
            # Označi anomaliju ako je van IQR ILI |z| > 3
            is_anomaly = ((vals < lower_iqr) | (vals > upper_iqr)) | (z_scores > 3)
            subset = subset.copy()
            subset['is_anomaly'] = is_anomaly.astype(int)
            subset['anomaly_score'] = z_scores.clip(0, 10).round(2)
            subset['anomaly_reason'] = subset.apply(
                lambda r: 'visok_iznos' if r['iznos'] > upper_iqr else ('nizak_iznos' if r['iznos'] < lower_iqr else 'z_score'),
                axis=1
            )
            anomalies.append(subset)
        return pd.concat(anomalies) if anomalies else df

    def analyze_financial_trends(self, df: pd.DataFrame) -> dict:
        """
        Analizira finansijske trendove + anomalije iz podataka.
        """
        if 'created_at' not in df.columns:
            return {}
        df = df.copy()
        df['created_at'] = pd.to_datetime(df['created_at'], format='ISO8601', errors='coerce')
        df['month'] = df['created_at'].dt.to_period('M')
        monthly_stats = df.groupby(['month', 'tip'])['iznos'].agg(['sum', 'mean', 'count']).reset_index()
        revenue = monthly_stats[monthly_stats['tip'] == 'prihod']['sum'].sum() if 'tip' in monthly_stats.columns else 0
        expenses = monthly_stats[monthly_stats['tip'] == 'rashod']['sum'].sum() if 'tip' in monthly_stats.columns else 0
        # Anomalije
        anom_df = self.detect_anomalies(df)
        anomaly_count = int(anom_df['is_anomaly'].sum()) if 'is_anomaly' in anom_df.columns else 0
        anomaly_pct = round(anomaly_count / max(len(df), 1) * 100, 1)
        # Samo kolone koje postoje u DataFrame-u
        available_cols = [c for c in ['naziv', 'iznos', 'tip', 'anomaly_score'] if c in anom_df.columns]
        top_anomalies = anom_df[anom_df['is_anomaly'] == 1].nlargest(5, 'iznos')[available_cols].to_dict('records') if 'is_anomaly' in anom_df.columns and available_cols else []
        return {
            'total_revenue': float(revenue),
            'total_expenses': float(expenses),
            'net_profit': float(revenue - expenses),
            'monthly_breakdown': monthly_stats.to_dict('records'),
            'anomaly_count': anomaly_count,
            'anomaly_pct': anomaly_pct,
            'top_anomalies': top_anomalies,
            'model_r2': getattr(self, '_last_metrics', {}).get('amount_r2', None)
        }
    
    def save(self):
        """Čuva ensemble modele u fajl sistem"""
        os.makedirs(config.MODEL_DIR, exist_ok=True)
        joblib.dump(self.amount_rf, f"{config.MODEL_DIR}/financial_amount_rf.pkl")
        joblib.dump(self.type_rf, f"{config.MODEL_DIR}/financial_type_rf.pkl")
        if XGBOOST_AVAILABLE and self.amount_xgb is not None:
            joblib.dump(self.amount_xgb, f"{config.MODEL_DIR}/financial_amount_xgb.pkl")
        if XGBOOST_AVAILABLE and self.type_xgb is not None:
            joblib.dump(self.type_xgb, f"{config.MODEL_DIR}/financial_type_xgb.pkl")
        joblib.dump(self.scaler, f"{config.MODEL_DIR}/financial_scaler.pkl")
        joblib.dump(self.feature_columns, f"{config.MODEL_DIR}/financial_features.pkl")
        joblib.dump({'is_amount_trained': self.is_amount_trained, 'is_type_trained': self.is_type_trained},
                    f"{config.MODEL_DIR}/financial_flags.pkl")
        print(f"\nEnsemble models saved to {config.MODEL_DIR}")

    def load(self):
        """Učitava ensemble modele iz fajl sistema"""
        self.amount_rf = joblib.load(f"{config.MODEL_DIR}/financial_amount_rf.pkl")
        self.type_rf = joblib.load(f"{config.MODEL_DIR}/financial_type_rf.pkl")
        try:
            if XGBOOST_AVAILABLE:
                self.amount_xgb = joblib.load(f"{config.MODEL_DIR}/financial_amount_xgb.pkl")
                self.type_xgb = joblib.load(f"{config.MODEL_DIR}/financial_type_xgb.pkl")
        except FileNotFoundError:
            print("[WARN] XGBoost models not found, using only Random Forest")
            self.amount_xgb = None
            self.type_xgb = None
        self.scaler = joblib.load(f"{config.MODEL_DIR}/financial_scaler.pkl")
        self.feature_columns = joblib.load(f"{config.MODEL_DIR}/financial_features.pkl")
        try:
            flags = joblib.load(f"{config.MODEL_DIR}/financial_flags.pkl")
            self.is_amount_trained = flags.get('is_amount_trained', True)
            self.is_type_trained = flags.get('is_type_trained', True)
        except FileNotFoundError:
            self.is_amount_trained = True
            self.is_type_trained = True
        print(f"\nEnsemble models loaded from {config.MODEL_DIR}")

    def train_prophet(self, df: pd.DataFrame) -> dict:
        """Trenira Prophet time series model za finansijske trendove"""
        if not PROPHET_AVAILABLE:
            print("[WARN] Prophet not available, skipping time series training")
            return {'prophet_trained': False, 'error': 'Prophet not available'}
        
        print("=" * 50)
        print("Training Prophet Time Series Model")
        print("=" * 50)
        
        # Pripremi podatke za Prophet (ds, y format)
        if 'created_at' not in df.columns or 'iznos' not in df.columns:
            print("[WARN] Missing required columns for Prophet training")
            return {'prophet_trained': False, 'error': 'Missing required columns'}
        
        # Konvertuj datum
        df_ts = df.copy()
        df_ts['created_at'] = pd.to_datetime(df_ts['created_at'], errors='coerce')
        df_ts = df_ts.dropna(subset=['created_at', 'iznos'])
        
        if len(df_ts) < 10:
            print("[WARN] Not enough data for Prophet (need at least 10 records)")
            return {'prophet_trained': False, 'error': 'Not enough data'}
        
        # Agregiraj po danu
        df_ts['date'] = df_ts['created_at'].dt.date
        daily_data = df_ts.groupby('date')['iznos'].sum().reset_index()
        daily_data.columns = ['ds', 'y']
        daily_data['ds'] = pd.to_datetime(daily_data['ds'])
        
        print(f"Daily data points: {len(daily_data)}")
        
        # Treniraj Prophet model
        try:
            self.prophet_model = Prophet(
                yearly_seasonality=True,
                weekly_seasonality=True,
                daily_seasonality=False,
                seasonality_mode='multiplicative'
            )
            self.prophet_model.fit(daily_data)
            self.is_prophet_trained = True
            
            # Evaluiraj na trening setu
            forecast = self.prophet_model.predict(daily_data)
            mae = mean_absolute_error(daily_data['y'], forecast['yhat'])
            
            print(f"Prophet trained successfully. MAE: {mae:.2f}")
            print("=" * 50)
            
            return {
                'prophet_trained': True,
                'mae': float(mae),
                'data_points': len(daily_data)
            }
        except Exception as e:
            print(f"[ERROR] Prophet training failed: {e}")
            return {'prophet_trained': False, 'error': str(e)}

    def predict_trends(self, days_ahead: int = 30) -> dict:
        """Predviđa finansijske trendove za narednih N dana koristeći Prophet"""
        if not self.is_prophet_trained or self.prophet_model is None:
            return {'error': 'Prophet model not trained'}
        
        try:
            # Napravi future dataframe
            future = self.prophet_model.make_future_dataframe(periods=days_ahead)
            forecast = self.prophet_model.predict(future)
            
            # Uzmi samo predikcije za budućnost
            future_forecast = forecast.tail(days_ahead)
            
            results = []
            for _, row in future_forecast.iterrows():
                results.append({
                    'datum': row['ds'].strftime('%Y-%m-%d'),
                    'predvidjeni_iznos': round(float(row['yhat']), 2),
                    'donja_granica': round(float(row['yhat_lower']), 2),
                    'gornja_granica': round(float(row['yhat_upper']), 2),
                    'trend': round(float(row['trend']), 2)
                })
            
            return {
                'trend_predikcije': results,
                'ukupno_predvidjeno': round(float(future_forecast['yhat'].sum()), 2),
                'prosek_dnevno': round(float(future_forecast['yhat'].mean()), 2),
                'dana_predvidjeno': days_ahead
            }
        except Exception as e:
            return {'error': f'Prediction failed: {str(e)}'}

    def init_online_learning(self):
        """Inicijalizuje online learning model za real-time ažuriranje"""
        if not RIVER_AVAILABLE:
            print("[WARN] River not available, online learning disabled")
            return False
        
        try:
            # Koristimo Linear Regression za online learning
            self.online_model = linear_model.LinearRegression(
                optimizer=optim.SGD(lr=0.01),
                loss=losses.Squared()
            )
            self.online_scaler = preprocessing.StandardScaler()
            self.is_online_trained = True
            print("[Online] Online learning model initialized")
            return True
        except Exception as e:
            print(f"[ERROR] Online learning initialization failed: {e}")
            return False

    def update_online(self, features: dict, target: float) -> dict:
        """Ažurira model u real-time sa novim podacima"""
        if not self.is_online_trained or self.online_model is None:
            return {'error': 'Online learning not initialized'}
        
        try:
            # Konvertuj features u River format
            x = {k: float(v) for k, v in features.items()}
            y = float(target)
            
            # Ažuriraj model
            self.online_model.learn_one(x, y)
            
            return {
                'status': 'updated',
                'model_updated': True,
                'samples_seen': self.online_model.n_samples_seen if hasattr(self.online_model, 'n_samples_seen') else 0
            }
        except Exception as e:
            return {'error': f'Online update failed: {str(e)}'}

    def predict_online(self, features: dict) -> dict:
        """Predikcija koristeći online learning model"""
        if not self.is_online_trained or self.online_model is None:
            return {'error': 'Online learning not initialized'}
        
        try:
            x = {k: float(v) for k, v in features.items()}
            prediction = self.online_model.predict_one(x)
            
            return {
                'prediction': float(prediction) if prediction is not None else 0.0,
                'model_type': 'online_learning'
            }
        except Exception as e:
            return {'error': f'Online prediction failed: {str(e)}'}

    def apply_rfe(self, X, y, n_features_to_select: int = 10) -> dict:
        """Primenjuje Recursive Feature Elimination za selekciju najbitnijih feature-a"""
        if not RFE_AVAILABLE:
            print("[WARN] RFE not available, skipping feature selection")
            return {'rfe_applied': False, 'error': 'RFE not available'}
        
        print("=" * 50)
        print("Applying Recursive Feature Elimination (RFE)")
        print("=" * 50)
        
        try:
            # Koristimo Random Forest kao estimator za RFE
            estimator = RandomForestRegressor(n_estimators=100, random_state=42)
            
            # RFE
            rfe = RFE(estimator=estimator, n_features_to_select=n_features_to_select, step=1)
            rfe.fit(X, y)
            
            # Dobij selektovane feature-e
            selected_mask = rfe.support_
            selected_features = [X.columns[i] for i in range(len(X.columns)) if selected_mask[i]]
            
            self.rfe_selected_features = selected_features
            self.is_rfe_applied = True
            
            print(f"RFE selected {len(selected_features)} features out of {len(X.columns)}")
            print(f"Selected features: {selected_features}")
            print("=" * 50)
            
            return {
                'rfe_applied': True,
                'n_features_selected': len(selected_features),
                'n_features_original': len(X.columns),
                'selected_features': selected_features,
                'feature_ranking': dict(zip(X.columns, rfe.ranking_))
            }
        except Exception as e:
            print(f"[ERROR] RFE failed: {e}")
            return {'rfe_applied': False, 'error': str(e)}

    def save(self):
        """Čuva ensemble modele u fajl sistem"""
        os.makedirs(config.MODEL_DIR, exist_ok=True)
        joblib.dump(self.amount_rf, f"{config.MODEL_DIR}/financial_amount_rf.pkl")
        joblib.dump(self.type_rf, f"{config.MODEL_DIR}/financial_type_rf.pkl")
        if XGBOOST_AVAILABLE and self.amount_xgb is not None:
            joblib.dump(self.amount_xgb, f"{config.MODEL_DIR}/financial_amount_xgb.pkl")
        if XGBOOST_AVAILABLE and self.type_xgb is not None:
            joblib.dump(self.type_xgb, f"{config.MODEL_DIR}/financial_type_xgb.pkl")
        if PROPHET_AVAILABLE and self.prophet_model is not None:
            joblib.dump(self.prophet_model, f"{config.MODEL_DIR}/financial_prophet.pkl")
        if RIVER_AVAILABLE and self.online_model is not None:
            joblib.dump(self.online_model, f"{config.MODEL_DIR}/financial_online.pkl")
        if self.rfe_selected_features is not None:
            joblib.dump(self.rfe_selected_features, f"{config.MODEL_DIR}/financial_rfe_features.pkl")
        joblib.dump(self.scaler, f"{config.MODEL_DIR}/financial_scaler.pkl")
        joblib.dump(self.feature_columns, f"{config.MODEL_DIR}/financial_features.pkl")
        joblib.dump({'is_amount_trained': self.is_amount_trained, 'is_type_trained': self.is_type_trained, 'is_prophet_trained': self.is_prophet_trained, 'is_online_trained': self.is_online_trained, 'is_rfe_applied': self.is_rfe_applied},
                    f"{config.MODEL_DIR}/financial_flags.pkl")
        print(f"\nEnsemble models saved to {config.MODEL_DIR}")

    def load(self):
        """Učitava ensemble modele iz fajl sistema"""
        self.amount_rf = joblib.load(f"{config.MODEL_DIR}/financial_amount_rf.pkl")
        self.type_rf = joblib.load(f"{config.MODEL_DIR}/financial_type_rf.pkl")
        try:
            if XGBOOST_AVAILABLE:
                self.amount_xgb = joblib.load(f"{config.MODEL_DIR}/financial_amount_xgb.pkl")
                self.type_xgb = joblib.load(f"{config.MODEL_DIR}/financial_type_xgb.pkl")
        except FileNotFoundError:
            print("[WARN] XGBoost models not found, using only Random Forest")
            self.amount_xgb = None
            self.type_xgb = None
        try:
            if PROPHET_AVAILABLE:
                self.prophet_model = joblib.load(f"{config.MODEL_DIR}/financial_prophet.pkl")
        except FileNotFoundError:
            print("[WARN] Prophet model not found, time series predictions disabled")
            self.prophet_model = None
        try:
            if RIVER_AVAILABLE:
                self.online_model = joblib.load(f"{config.MODEL_DIR}/financial_online.pkl")
        except FileNotFoundError:
            print("[WARN] Online learning model not found")
            self.online_model = None
        try:
            self.rfe_selected_features = joblib.load(f"{config.MODEL_DIR}/financial_rfe_features.pkl")
        except FileNotFoundError:
            print("[WARN] RFE features not found")
            self.rfe_selected_features = None
        self.scaler = joblib.load(f"{config.MODEL_DIR}/financial_scaler.pkl")
        self.feature_columns = joblib.load(f"{config.MODEL_DIR}/financial_features.pkl")
        try:
            flags = joblib.load(f"{config.MODEL_DIR}/financial_flags.pkl")
            self.is_amount_trained = flags.get('is_amount_trained', True)
            self.is_type_trained = flags.get('is_type_trained', True)
            self.is_prophet_trained = flags.get('is_prophet_trained', False)
            self.is_online_trained = flags.get('is_online_trained', False)
            self.is_rfe_applied = flags.get('is_rfe_applied', False)
        except FileNotFoundError:
            self.is_amount_trained = True
            self.is_type_trained = True
            self.is_prophet_trained = False
            self.is_online_trained = False
            self.is_rfe_applied = False
        print(f"\nEnsemble models loaded from {config.MODEL_DIR}")

if __name__ == "__main__":
    # Test training
    from data.etl import extract_finances
    
    df = extract_finances()
    
    model = FinancialMLModel()
    metrics = model.train(df)
    model.save()
    
    # Test prediction
    test_df = df.head(5)
    predictions = model.predict_amount(test_df)
    print("\nSample Predictions:")
    print(predictions[['iznos', 'predicted_amount']])
