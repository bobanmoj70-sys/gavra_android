"""
Financial ML Model - Random Forest
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


class FinancialMLModel:
    def __init__(self):
        # Pamcenje - model pamti sta je video i naucio
        self.memory = LearningMemory("financial")
        self.discoverer = AutoFeatureDiscovery()

        # Modeli - prazne glave, sve se uci iz podataka
        self.amount_model = None
        self.type_model = None
        self.scaler = StandardScaler()
        self.feature_columns = None
        self.is_amount_trained = False
        self.is_type_trained = False

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

    def train(self, df: pd.DataFrame):
        """
        Trenira model iskljucivo na podacima - kao beba koja uci od nule.
        Sam otkriva sta je bitno i pamti to.
        """
        print("=" * 50)
        print("Training Financial ML Model from scratch")
        print("  (Kao beba - ne znam nista, ucim iz podataka)")
        print("=" * 50)
        print(f"Training data: {len(df)} records")

        # Priprema podataka - SAMI otkrivamo sta je bitno
        features, y_amount, y_type = self.prepare_training_data(df)
        print(f"Auto-discovered features: {len(self.feature_columns)}")
        print(f"Amount target: {self.amount_target_col}")
        print(f"Type target: {self.type_target_col}")

        if len(self.feature_columns) == 0:
            print("[WARN] Nema feature-a za treniranje!")
            return {"error": "no_features"}

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

        # Inicijalizuj modele (prazne glave)
        self.amount_model = RandomForestRegressor(
            n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
        )
        self.type_model = RandomForestClassifier(
            n_estimators=100, max_depth=10, random_state=42, n_jobs=-1
        )

        # Treniraj amount model
        print("\n[1/2] Training Amount Prediction Model...")
        self.amount_model.fit(X_train_scaled, y_train_amount)
        self.is_amount_trained = True

        y_pred_amount = self.amount_model.predict(X_test_scaled)
        mse = mean_squared_error(y_test_amount, y_pred_amount)
        r2 = r2_score(y_test_amount, y_pred_amount)

        print(f"  MSE: {mse:.2f}")
        print(f"  R²: {self._safe_float(r2)}")
        print(f"  Avg Prediction Error: {np.sqrt(mse):.2f}")

        # Feature importance - SAMI otkrivamo sta je bitno
        importance = pd.DataFrame({
            'feature': self.feature_columns,
            'importance': self.amount_model.feature_importances_
        }).sort_values('importance', ascending=False)
        top_features = importance.head(10)
        print("\nTop 10 Most Important Features (auto-discovered):")
        print(top_features)

        # Pamti sta smo naucili
        feature_imp_dict = dict(zip(top_features['feature'], top_features['importance']))

        # Treniraj type model
        n_classes = y_train_type.nunique()
        if n_classes >= 2 and self.type_target_col:
            print("\n[2/2] Training Type Prediction Model...")
            self.type_model.fit(X_train_scaled, y_train_type)
            self.is_type_trained = True
            y_pred_type = self.type_model.predict(X_test_scaled)
            print("\nClassification Report:")
            print(classification_report(y_test_type, y_pred_type))
        else:
            print(f"\n[SKIP] Type model - {n_classes} class(es), need 2+ for classification")
            self.is_type_trained = False

        # PAMTI sve sto si video i naucio
        # Prvo otkrij koje tabele trenutno postoje u podacima
        current_tables = []
        for col in df.columns:
            if '_id' in col:
                # Izvedi ime tabele iz kolone (npr putnik_v3_auth_id -> v3_auth)
                parts = col.replace('_id', '').split('_')
                if len(parts) >= 2:
                    current_tables.append('_'.join(parts))
        # Uvek dodaj osnovnu tabelu
        current_tables.append("finansije")
        current_tables = list(set(current_tables))

        # ZABORAVI tabele koje vise ne postoje
        self.memory.forget_old(current_tables)

        sources = {
            "finansije": {
                "columns": list(df.columns),
                "rows": len(df)
            }
        }
        metrics = {
            "amount_mse": self._safe_float(mse),
            "amount_r2": self._safe_float(r2),
            "amount_rmse": self._safe_float(np.sqrt(mse)),
            "features": len(self.feature_columns),
            "samples": len(df),
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
        Predikcija iznosa za nove transakcije
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
        
        # Scale i predict
        features_scaled = self.scaler.transform(features)
        predictions = self.amount_model.predict(features_scaled)
        
        results = df.copy()
        results['predicted_amount'] = predictions
        
        return results
    
    def predict_type(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Predikcija tipa (prihod/rashod)
        """
        if not self.is_type_trained:
            raise ValueError("Type model must be trained before prediction — need both 'prihod' and 'rashod' data")
        
        features = prepare_ml_features(df)
        
        # Osiguramo iste kolone
        for col in self.feature_columns:
            if col not in features.columns:
                features[col] = 0
        
        features = features[self.feature_columns]
        
        # Scale i predict
        features_scaled = self.scaler.transform(features)
        predictions = self.type_model.predict(features_scaled)
        probabilities = self.type_model.predict_proba(features_scaled)
        
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
        """Čuva model u fajl sistem"""
        os.makedirs(config.MODEL_DIR, exist_ok=True)
        joblib.dump(self.amount_model, f"{config.MODEL_DIR}/financial_amount_model.pkl")
        joblib.dump(self.type_model, f"{config.MODEL_DIR}/financial_type_model.pkl")
        joblib.dump(self.scaler, f"{config.MODEL_DIR}/financial_scaler.pkl")
        joblib.dump(self.feature_columns, f"{config.MODEL_DIR}/financial_features.pkl")
        joblib.dump({'is_amount_trained': self.is_amount_trained, 'is_type_trained': self.is_type_trained},
                    f"{config.MODEL_DIR}/financial_flags.pkl")
        print(f"\nModels saved to {config.MODEL_DIR}")

    def load(self):
        """Učitava model iz fajl sistema"""
        self.amount_model = joblib.load(f"{config.MODEL_DIR}/financial_amount_model.pkl")
        self.type_model = joblib.load(f"{config.MODEL_DIR}/financial_type_model.pkl")
        self.scaler = joblib.load(f"{config.MODEL_DIR}/financial_scaler.pkl")
        self.feature_columns = joblib.load(f"{config.MODEL_DIR}/financial_features.pkl")
        try:
            flags = joblib.load(f"{config.MODEL_DIR}/financial_flags.pkl")
            self.is_amount_trained = flags.get('is_amount_trained', True)
            self.is_type_trained = flags.get('is_type_trained', True)
        except FileNotFoundError:
            self.is_amount_trained = True
            self.is_type_trained = True
        print(f"\nModels loaded from {config.MODEL_DIR}")

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
