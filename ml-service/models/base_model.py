"""
Base ML Model sa pamcenjem i auto-discovery.
Svi modeli nasledjuju ovu klasu - kao beba koja uci od nule.
"""
import pandas as pd
import numpy as np
from sklearn.preprocessing import StandardScaler
import os
import config
from models.learning_memory import LearningMemory
from models.auto_features import AutoFeatureDiscovery


class BaseMLModel:
    """
    Bazna klasa za sve ML modele.
    Svaki model:
    - Pamti sta je video i naucio
    - Sam otkriva tabele i kolone
    - Sam odlucuje sta je bitno
    - Nema hardkodiranih postavki
    """

    def __init__(self, model_name: str):
        self.model_name = model_name
        self.memory = LearningMemory(model_name)
        self.discoverer = AutoFeatureDiscovery()
        self.scaler = StandardScaler()
        self.feature_columns = None
        self.is_trained = False
        self.model = None
        self._last_metrics = {}

    def _safe_float(self, val):
        return None if val != val else float(val)

    def _detect_target(self, df: pd.DataFrame, keywords: list) -> str:
        """Sami otkrije target kolonu na osnovu kljucnih reci"""
        for col in df.columns:
            lower = col.lower()
            if any(k in lower for k in keywords):
                if pd.to_numeric(df[col], errors='coerce').notna().sum() > 5:
                    return col
        # Fallback - prva numericka kolona
        numeric = df.select_dtypes(include=[np.number]).columns.tolist()
        return numeric[0] if numeric else None

    def _prepare_features(self, df: pd.DataFrame, table_name: str,
                          exclude_cols: list = None) -> pd.DataFrame:
        """Automatski pripremi feature-e"""
        self.discoverer.discover_table(df, table_name)
        features = self.discoverer.extract_features(df, table_name)

        # Ukloni specificne kolone
        if exclude_cols:
            for col in exclude_cols:
                if col and col in features.columns:
                    del features[col]

        # Ukloni ID kolone
        id_cols = [c for c in features.columns if c.endswith('_id') and c != 'id']
        features = features.drop(columns=id_cols, errors='ignore')
        return features.fillna(0)

    def _record_training(self, data_sources: dict, feature_importance: dict,
                         metrics: dict):
        """Pamti treniranje"""
        self.memory.record_training(data_sources, feature_importance, metrics)
        self._last_metrics = metrics

    def get_learning_summary(self) -> dict:
        """Vrata sta je model naucio"""
        return self.memory.get_learning_summary()

    def forget_old(self, current_tables: list):
        """Zaboravi stare tabele"""
        self.memory.forget_old_tables(current_tables)

    def save(self, model_path: str = None):
        """Cuva model + pamcenje"""
        if model_path is None:
            model_path = os.path.join(config.MODEL_DIR, f"{self.model_name}_state.pkl")
        os.makedirs(config.MODEL_DIR, exist_ok=True)
        state = {
            "model": self.model,
            "scaler": self.scaler,
            "feature_columns": self.feature_columns,
            "is_trained": self.is_trained,
            "last_metrics": self._last_metrics,
            "model_name": self.model_name
        }
        import joblib
        joblib.dump(state, model_path)
        self.memory.save_model_state(state)
        print(f"[Save] {self.model_name} model + memory saved")

    def load(self, model_path: str = None):
        """Ucitava model + pamcenje"""
        import joblib
        if model_path is None:
            model_path = os.path.join(config.MODEL_DIR, f"{self.model_name}_state.pkl")
        try:
            state = joblib.load(model_path)
            self.model = state.get("model")
            self.scaler = state.get("scaler", StandardScaler())
            self.feature_columns = state.get("feature_columns")
            self.is_trained = state.get("is_trained", False)
            self._last_metrics = state.get("last_metrics", {})
            # Ucitaj i pamcenje
            self.memory.load_model_state()
            print(f"[Load] {self.model_name} model + memory loaded")
            return True
        except FileNotFoundError:
            return False
