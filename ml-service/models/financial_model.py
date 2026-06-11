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

class FinancialMLModel:
    def __init__(self):
        # Model za predikciju iznosa (regresija)
        self.amount_model = RandomForestRegressor(
            n_estimators=100,
            max_depth=10,
            random_state=42,
            n_jobs=-1
        )
        
        # Model za predikciju tipa (klasifikacija - prihod/rashod)
        self.type_model = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            random_state=42,
            n_jobs=-1
        )
        
        self.scaler = StandardScaler()
        self.feature_columns = None
        self.is_trained = False
    
    def prepare_training_data(self, df: pd.DataFrame):
        """
        Priprema podatke za treniranje
        Sve features se generišu iz Supabase podataka
        """
        features = prepare_ml_features(df)
        
        # Target za amount model
        if 'iznos' in df.columns:
            y_amount = df['iznos'].fillna(0)
        else:
            y_amount = pd.Series([0] * len(df))
        
        # Target za type model
        if 'tip' in df.columns:
            y_type = (df['tip'] == 'prihod').astype(int)  # 1 = prihod, 0 = rashod
        else:
            y_type = pd.Series([0] * len(df))
        
        return features, y_amount, y_type
    
    def train(self, df: pd.DataFrame):
        """
        Trenira model isključivo na Supabase podacima
        Model uči od nule bez spoljnih dataset-a
        """
        print("=" * 50)
        print("Training Financial ML Model from scratch")
        print("=" * 50)
        print(f"Training data: {len(df)} records from Supabase")
        
        # Priprema podataka
        features, y_amount, y_type = self.prepare_training_data(df)
        
        self.feature_columns = features.columns.tolist()
        print(f"Features: {len(self.feature_columns)}")
        
        # Split za amount model
        X_train, X_test, y_train_amount, y_test_amount = train_test_split(
            features, y_amount, test_size=0.2, random_state=42
        )
        
        # Split za type model
        _, _, y_train_type, y_test_type = train_test_split(
            features, y_type, test_size=0.2, random_state=42
        )
        
        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        # Treniraj amount model (regresija)
        print("\n[1/2] Training Amount Prediction Model...")
        self.amount_model.fit(X_train_scaled, y_train_amount)
        
        # Evaluacija amount model
        y_pred_amount = self.amount_model.predict(X_test_scaled)
        mse = mean_squared_error(y_test_amount, y_pred_amount)
        r2 = r2_score(y_test_amount, y_pred_amount)
        
        print(f"  MSE: {mse:.2f}")
        print(f"  R²: {r2:.3f}")
        print(f"  Avg Prediction Error: {np.sqrt(mse):.2f}")
        
        # Treniraj type model (klasifikacija)
        print("\n[2/2] Training Type Prediction Model...")
        self.type_model.fit(X_train_scaled, y_train_type)
        
        # Evaluacija type model
        y_pred_type = self.type_model.predict(X_test_scaled)
        print("\nClassification Report:")
        print(classification_report(y_test_type, y_pred_type, 
                                    target_names=['Rashod', 'Prihod']))
        
        # Feature importance
        importance = pd.DataFrame({
            'feature': self.feature_columns,
            'importance': self.amount_model.feature_importances_
        }).sort_values('importance', ascending=False)
        
        print("\nTop 10 Most Important Features:")
        print(importance.head(10))
        
        self.is_trained = True
        self._last_metrics = {
            'amount_mse': float(mse),
            'amount_r2': float(r2),
            'amount_rmse': float(np.sqrt(mse)),
            'feature_importance': importance.head(10).to_dict('records'),
            'samples': len(df),
            'features': len(self.feature_columns)
        }
        print("\n" + "=" * 50)
        print("Training Complete!")
        print("=" * 50)
        return self._last_metrics
    
    def predict_amount(self, df: pd.DataFrame) -> pd.DataFrame:
        """
        Predikcija iznosa za nove transakcije
        Model koristi naučeno znanje isključivo iz Supabase podataka
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before prediction")
        
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
        if not self.is_trained:
            raise ValueError("Model must be trained before prediction")
        
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
        top_anomalies = anom_df[anom_df['is_anomaly'] == 1].nlargest(5, 'iznos')[['naziv', 'iznos', 'tip', 'anomaly_score']].to_dict('records') if 'is_anomaly' in anom_df.columns else []
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
        print(f"\nModels saved to {config.MODEL_DIR}")
    
    def load(self):
        """Učitava model iz fajl sistema"""
        self.amount_model = joblib.load(f"{config.MODEL_DIR}/financial_amount_model.pkl")
        self.type_model = joblib.load(f"{config.MODEL_DIR}/financial_type_model.pkl")
        self.scaler = joblib.load(f"{config.MODEL_DIR}/financial_scaler.pkl")
        self.feature_columns = joblib.load(f"{config.MODEL_DIR}/financial_features.pkl")
        self.is_trained = True
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
