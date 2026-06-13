"""
Learning Memory System
Pamti sta su modeli videli, naucili i odlucili da je bitno.
Kao beba koja pamti iskustva i sama odlucuje sta je vazno.
"""
import os
import json
import joblib
from datetime import datetime
from collections import defaultdict
import config


class LearningMemory:
    """
    Pametno pamcenje za ML modele.
    Pamti:
    - Koje tabele i kolone je model video
    - Koliko zapisa je bilo
    - Koje feature-e su bile bitne (feature importance)
    - Sta se promenilo od proslog puta
    """

    def __init__(self, model_name: str):
        self.model_name = model_name
        self.memory_dir = os.path.join(config.MODEL_DIR, "memory")
        os.makedirs(self.memory_dir, exist_ok=True)
        self.memory_path = os.path.join(self.memory_dir, f"{model_name}_memory.json")
        self.state_path = os.path.join(config.MODEL_DIR, f"{model_name}_state.pkl")
        self.memory = self._load_memory()

    def _load_memory(self) -> dict:
        """Ucitava prethodno pamcenje"""
        if os.path.exists(self.memory_path):
            try:
                with open(self.memory_path, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception:
                pass
        return {
            "first_seen": datetime.now().isoformat(),
            "training_sessions": [],
            "known_tables": {},
            "known_columns": {},
            "important_features": {},
            "feature_importance_history": [],
            "data_stats_history": [],
            "total_samples_seen": 0,
            "model_versions": []
        }

    def save_memory(self):
        """Cuva pamcenje"""
        self.memory["last_updated"] = datetime.now().isoformat()
        with open(self.memory_path, 'w', encoding='utf-8') as f:
            json.dump(self.memory, f, indent=2, ensure_ascii=False, default=str)

    def record_training(self, data_sources: dict, feature_importance: dict,
                       metrics: dict, model_params: dict = None):
        """
        Pamti sta se desilo tokom treniranja.
        data_sources: {table_name: {columns: [...], rows: N, sample_types: {...}}}
        """
        session = {
            "timestamp": datetime.now().isoformat(),
            "total_tables": len(data_sources),
            "total_samples": sum(s.get("rows", 0) for s in data_sources.values()),
            "metrics": metrics,
            "sources": {name: {
                "columns": info.get("columns", []),
                "rows": info.get("rows", 0)
            } for name, info in data_sources.items()}
        }

        # Pamti znacajnost feature-a
        if feature_importance:
            self.memory["feature_importance_history"].append({
                "timestamp": session["timestamp"],
                "features": feature_importance
            })
            # Cuvaj samo poslednjih 10
            self.memory["feature_importance_history"] = \
                self.memory["feature_importance_history"][-10:]

            # Azuriraj prosecnu znacajnost
            self._update_average_importance(feature_importance)

        # Pamti sta smo videli
        for table_name, info in data_sources.items():
            self.memory["known_tables"][table_name] = {
                "last_seen": session["timestamp"],
                "columns": info.get("columns", []),
                "total_rows_ever": self.memory["known_tables"].get(table_name, {}).get("total_rows_ever", 0) + info.get("rows", 0)
            }
            for col in info.get("columns", []):
                if col not in self.memory["known_columns"]:
                    self.memory["known_columns"][col] = {
                        "first_seen": session["timestamp"],
                        "tables": []
                    }
                if table_name not in self.memory["known_columns"][col]["tables"]:
                    self.memory["known_columns"][col]["tables"].append(table_name)

        self.memory["training_sessions"].append(session)
        self.memory["total_samples_seen"] += session["total_samples"]
        self.memory["model_versions"].append({
            "timestamp": session["timestamp"],
            "samples": session["total_samples"],
            "tables": list(data_sources.keys())
        })

        self.save_memory()

    def _update_average_importance(self, feature_importance: dict):
        """Azurira prosecnu znacajnost feature-a kroz vreme"""
        avg = self.memory.get("important_features", {})
        for feat, score in feature_importance.items():
            if feat in avg:
                # Eksponencijalno kretanje prosek
                avg[feat] = 0.7 * avg[feat] + 0.3 * score
            else:
                avg[feat] = score
        # Sortiraj po znacajnosti
        self.memory["important_features"] = dict(sorted(avg.items(), key=lambda x: x[1], reverse=True))

    def discover_changes(self, current_data: dict) -> dict:
        """
        Otkriva promene u odnosu na proslo pamcenje.
        Vraca: {new_tables, removed_tables, new_columns, removed_columns, changed_rows}
        """
        current_tables = set(current_data.keys())
        known_tables = set(self.memory["known_tables"].keys())

        new_tables = current_tables - known_tables
        removed_tables = known_tables - current_tables

        new_columns = {}
        removed_columns = {}
        changed_rows = {}

        for table_name, info in current_data.items():
            current_cols = set(info.get("columns", []))
            known_cols = set(self.memory["known_tables"].get(table_name, {}).get("columns", []))

            new_cols = current_cols - known_cols
            rem_cols = known_cols - current_cols

            if new_cols:
                new_columns[table_name] = list(new_cols)
            if rem_cols:
                removed_columns[table_name] = list(rem_cols)

            # Proveri da li se broj redova znacajno promenio
            old_rows = self.memory["known_tables"].get(table_name, {}).get("last_rows", 0)
            curr_rows = info.get("rows", 0)
            if old_rows > 0 and abs(curr_rows - old_rows) / old_rows > 0.2:
                changed_rows[table_name] = {"old": old_rows, "new": curr_rows}

        return {
            "new_tables": list(new_tables),
            "removed_tables": list(removed_tables),
            "new_columns": new_columns,
            "removed_columns": removed_columns,
            "changed_rows": changed_rows,
            "is_first_time": len(self.memory["training_sessions"]) == 0
        }

    def get_important_features(self, top_n: int = 20) -> list:
        """Vraca feature-e koje model smatra bitnim na osnovu istorije"""
        features = self.memory.get("important_features", {})
        return list(features.keys())[:top_n]

    def get_learning_summary(self) -> dict:
        """Vraca rezime svega sto je model naucio"""
        sessions = self.memory.get("training_sessions", [])
        if not sessions:
            return {"status": "nova_beba", "message": "Jos nista nisam ucio"}

        return {
            "status": "iskusan",
            "model_name": self.model_name,
            "training_sessions": len(sessions),
            "total_samples_seen": self.memory.get("total_samples_seen", 0),
            "tables_known": list(self.memory.get("known_tables", {}).keys()),
            "columns_known": list(self.memory.get("known_columns", {}).keys()),
            "top_features": self.get_important_features(10),
            "first_trained": self.memory.get("first_seen"),
            "last_trained": sessions[-1]["timestamp"] if sessions else None
        }

    def forget_old_tables(self, current_tables: list):
        """Zaboravi tabele koje vise ne postoje - kao da cisti pamcenje"""
        known = set(self.memory["known_tables"].keys())
        current = set(current_tables)
        removed = known - current
        for table in removed:
            del self.memory["known_tables"][table]
            print(f"[Memory] {self.model_name} zaboravlja tabelu '{table}' (vise ne postoji)")
        if removed:
            self.save_memory()

    def forget_old(self, current_tables: list):
        """Alias za forget_old_tables - kompatibilnost sa pozivima u modelima"""
        self.forget_old_tables(current_tables)

    def save_model_state(self, model_data: dict):
        """Cuva stanje modela (ne samo sklearn, vec i nas memory)"""
        state = {
            "model_data": model_data,
            "memory": self.memory,
            "saved_at": datetime.now().isoformat()
        }
        joblib.dump(state, self.state_path)

    def load_model_state(self) -> dict:
        """Ucitava stanje modela"""
        try:
            state = joblib.load(self.state_path)
            if isinstance(state, dict) and "memory" in state:
                self.memory = state["memory"]
                return state.get("model_data", {})
        except FileNotFoundError:
            pass
        return {}
