"""
Auto Feature Discovery
Modeli sami otkrivaju kolone i odlucuju kako da ih koriste.
Nema hardkodiranih postavki - sve se uci iz podataka.
"""
import pandas as pd
import numpy as np
from typing import Dict, List, Tuple
import re


class AutoFeatureDiscovery:
    """
    Automatsko otkrivanje i izdvajanje feature-a iz BILO KAKVIH podataka.
    Kao beba koja gleda svet i sama shvata sta je bitno.
    """

    # Tipovi kolona koje prepoznajemo
    TYPE_TIMESTAMP = 'timestamp'
    TYPE_DATETIME = 'datetime'
    TYPE_NUMERIC = 'numeric'
    TYPE_CATEGORICAL = 'categorical'
    TYPE_ID = 'id'
    TYPE_TEXT = 'text'
    TYPE_BOOLEAN = 'boolean'
    TYPE_UNKNOWN = 'unknown'

    def __init__(self):
        self.discovered_schema = {}  # table -> {col: type}
        self.feature_stats = {}      # table -> {col: stats}

    def discover_table(self, df: pd.DataFrame, table_name: str = "unknown") -> Dict:
        """
        Otkriva sve kolone u tabeli i njihove tipove.
        Vraca mapiranje kolona na tipove.
        """
        schema = {}
        stats = {}

        for col in df.columns:
            col_type = self._detect_column_type(df, col)
            schema[col] = col_type
            stats[col] = self._compute_column_stats(df, col, col_type)

        self.discovered_schema[table_name] = schema
        self.feature_stats[table_name] = stats
        return schema

    def _detect_column_type(self, df: pd.DataFrame, col: str) -> str:
        """Sami detektuje tip kolone bez hardkodiranja"""
        series = df[col]

        # Proveri da li je ID (sadrzi uuid, svi unikatni, string)
        if col.endswith('_id') or col == 'id':
            return self.TYPE_ID

        # Proveri boolean
        if series.dropna().isin([True, False, 0, 1, 'true', 'false', 'yes', 'no']).all():
            return self.TYPE_BOOLEAN

        # Proveri timestamp/datetime
        sample = series.dropna().head(10)
        timestamp_patterns = [
            r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}',
            r'^\d{4}-\d{2}-\d{2}$',
        ]
        if sample.dtype == 'object':
            for val in sample:
                if isinstance(val, str):
                    for pattern in timestamp_patterns:
                        if re.match(pattern, str(val)):
                            return self.TYPE_TIMESTAMP

        # Pokusaj konvertovati u datetime
        try:
            pd.to_datetime(series, errors='raise')
            if sample.dtype == 'object':
                return self.TYPE_TIMESTAMP
        except (ValueError, TypeError):
            pass

        # Proveri numericki
        try:
            numeric = pd.to_numeric(series, errors='coerce')
            if numeric.notna().sum() / len(series) > 0.5:
                return self.TYPE_NUMERIC
        except:
            pass

        # Kategorijski ako ima malo unikatnih vrednosti
        n_unique = series.nunique()
        n_total = len(series)
        if n_unique <= 20 or (n_unique / n_total < 0.1 and n_unique < 100):
            return self.TYPE_CATEGORICAL

        return self.TYPE_TEXT

    def _compute_column_stats(self, df: pd.DataFrame, col: str, col_type: str) -> dict:
        """Racuna statistike za kolonu"""
        series = df[col]
        stats = {
            "total": len(series),
            "missing": int(series.isna().sum()),
            "unique": int(series.nunique()),
            "type": col_type
        }

        if col_type == self.TYPE_NUMERIC:
            numeric = pd.to_numeric(series, errors='coerce')
            stats["mean"] = float(numeric.mean()) if numeric.notna().any() else None
            stats["std"] = float(numeric.std()) if numeric.notna().any() else None
            stats["min"] = float(numeric.min()) if numeric.notna().any() else None
            stats["max"] = float(numeric.max()) if numeric.notna().any() else None

        elif col_type in (self.TYPE_CATEGORICAL, self.TYPE_BOOLEAN):
            top_vals = series.value_counts().head(5).to_dict()
            stats["top_values"] = {str(k): int(v) for k, v in top_vals.items()}

        return stats

    def extract_features(self, df: pd.DataFrame, table_name: str = "unknown",
                         target_col: str = None) -> pd.DataFrame:
        """
        Automatski izvlaci feature-e iz DataFrame-a.
        Nema hardkodiranja - sve se otkriva iz podataka.
        """
        schema = self.discover_table(df, table_name)
        features = pd.DataFrame(index=df.index)

        for col, col_type in schema.items():
            # Preskoci ID kolone kao direktne feature-e (koristi ih samo za povezivanje)
            if col_type == self.TYPE_ID and col not in ['id', 'uuid']:
                continue

            if col == target_col:
                continue

            if col_type == self.TYPE_NUMERIC:
                features[f"{col}"] = pd.to_numeric(df[col], errors='coerce').fillna(0)

            elif col_type == self.TYPE_TIMESTAMP:
                dt = pd.to_datetime(df[col], errors='coerce')
                # Izvlaci vremenske feature-e
                features[f"{col}_hour"] = dt.dt.hour.fillna(0)
                features[f"{col}_dayofweek"] = dt.dt.dayofweek.fillna(0)
                features[f"{col}_dayofmonth"] = dt.dt.day.fillna(0)
                features[f"{col}_month"] = dt.dt.month.fillna(0)
                features[f"{col}_year"] = dt.dt.year.fillna(0)
                features[f"{col}_is_weekend"] = (dt.dt.dayofweek >= 5).astype(int).fillna(0)

            elif col_type == self.TYPE_CATEGORICAL:
                # One-hot encoding za top kategorije
                top_vals = df[col].value_counts().head(10).index.tolist()
                for val in top_vals:
                    features[f"{col}_{val}"] = (df[col] == val).astype(int)
                features[f"{col}_other"] = (~df[col].isin(top_vals)).astype(int)

            elif col_type == self.TYPE_BOOLEAN:
                features[f"{col}"] = df[col].astype(int)

            elif col_type == self.TYPE_TEXT:
                # Jednostavne tekstualne feature-e
                features[f"{col}_len"] = df[col].astype(str).str.len()
                features[f"{col}_has_value"] = df[col].notna().astype(int)

        return features

    def find_relationships(self, tables: Dict[str, pd.DataFrame]) -> List[Tuple[str, str, str, str]]:
        """
        Otkriva veze izmedju tabela na osnovu zajednickih kolona.
        Vraca listu: (table1, col1, table2, col2)
        """
        relationships = []
        table_names = list(tables.keys())

        for i, t1 in enumerate(table_names):
            for t2 in table_names[i+1:]:
                df1 = tables[t1]
                df2 = tables[t2]

                # Nadji kolone koje se poklapaju
                common_cols = set(df1.columns) & set(df2.columns)
                for col in common_cols:
                    # Ignorisati genericki nazivi
                    if col in ['id', 'created_at', 'updated_at']:
                        continue
                    relationships.append((t1, col, t2, col))

        return relationships

    def auto_select_important_features(self, X: pd.DataFrame, y: pd.Series,
                                      model, top_n: int = 20) -> List[str]:
        """
        Sam izaberi najbitnije feature-e na osnovu modela.
        """
        if hasattr(model, 'feature_importances_'):
            importance = pd.DataFrame({
                'feature': X.columns,
                'importance': model.feature_importances_
            }).sort_values('importance', ascending=False)
            return importance.head(top_n)['feature'].tolist()
        return list(X.columns)[:top_n]

    def get_feature_report(self, table_name: str = None) -> dict:
        """Generise izvestaj o otkrivenim feature-ima"""
        if table_name:
            return {
                "table": table_name,
                "schema": self.discovered_schema.get(table_name, {}),
                "stats": self.feature_stats.get(table_name, {})
            }
        return {
            "tables": list(self.discovered_schema.keys()),
            "total_columns": sum(len(s) for s in self.discovered_schema.values()),
            "schemas": self.discovered_schema
        }
