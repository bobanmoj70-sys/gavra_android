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

    def _extract_features(self, df: pd.DataFrame) -> pd.DataFrame:
        """Generiše temporal + rolling + lag features iz zahteva - DINAMICKI"""
        # DINAMICKI otkriji kljucne kolone
        grad_col = self._find_col(df, 'grad', 'lokacija', 'mesto', 'city')
        date_col = self._find_col(df, 'created_at', 'datum', 'vreme', 'date')
        status_col = self._find_col(df, 'status', 'stanje')
        zavrseni_col = self._find_col(df, 'zavrsenih', 'putovanja', 'completed')
        prihod_col = self._find_col(df, 'prihod', 'ukupni', 'revenue', 'iznos')

        print(f"  [AutoDiscover] Zahtevi kolone: grad={grad_col}, date={date_col}, status={status_col}, zavrseni={zavrseni_col}, prihod={prihod_col}")

        if df.empty or not grad_col:
            return pd.DataFrame()
        df = df.copy()
        if date_col:
            df['created_at'] = pd.to_datetime(df[date_col], errors='coerce')
        else:
            df['created_at'] = pd.Timestamp.now()
        df = df.sort_values('created_at')
        
        # Agregacija po danu i gradu
        agg_dict = {'created_at': 'count'}  # broj_zahteva
        if zavrseni_col:
            agg_dict[zavrseni_col] = 'sum'
        if prihod_col:
            agg_dict[prihod_col] = 'sum'
        
        daily = df.groupby([df['created_at'].dt.date, grad_col]).agg(agg_dict).reset_index()
        daily.columns = ['datum', 'grad', 'broj_zahteva']
        if zavrseni_col:
            daily['zavrsenih_putovanja'] = daily[zavrseni_col]
            daily = daily.drop(columns=[zavrseni_col])
        else:
            daily['zavrsenih_putovanja'] = 0
        if prihod_col:
            daily['ukupni_prihod'] = daily[prihod_col]
            daily = daily.drop(columns=[prihod_col])
        else:
            daily['ukupni_prihod'] = 0
        
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
        
        # Enriched lag features
        if zavrseni_col:
            daily['zavrseni_lag_7d'] = daily.groupby('grad')['zavrsenih_putovanja'].shift(7)
        if prihod_col:
            daily['prihod_lag_7d'] = daily.groupby('grad')['ukupni_prihod'].shift(7)
        
        daily = daily.fillna(0)
        return daily

    def _add_cross_table_features(self, daily: pd.DataFrame, other_df: pd.DataFrame, table_name: str) -> pd.DataFrame:
        """Dodaje feature-e iz drugih tabela - automatski otkriva relevantne kolone"""
        if daily.empty or other_df.empty:
            return daily
        
        # Pronađi zajedničke ključeve (created_by, id, vozac_id, putnik_id, etc.)
        join_keys = []
        for col in daily.columns:
            if any(k in col.lower() for k in ['id', 'created_by', 'vozac', 'putnik', 'user', 'auth']):
                for other_col in other_df.columns:
                    if col.lower() == other_col.lower() or col.lower() in other_col.lower():
                        join_keys.append((col, other_col))
        
        if not join_keys:
            return daily
        
        # Merge sa drugom tabelom
        result = daily.copy()
        for daily_key, other_key in join_keys[:1]:  # Koristi samo prvi zajednički ključ
            try:
                # Agregiraj po ključu
                if 'datum' in other_df.columns:
                    other_df['datum'] = pd.to_datetime(other_df['datum'], errors='coerce')
                
                # Pronađi numeričke kolone za agregaciju
                numeric_cols = other_df.select_dtypes(include=['number']).columns.tolist()
                
                if numeric_cols:
                    agg_dict = {col: 'sum' for col in numeric_cols}
                    stats = other_df.groupby(other_key).agg(agg_dict).reset_index()
                    
                    # Merge
                    result = result.merge(
                        stats,
                        left_on=daily_key,
                        right_on=other_key,
                        how='left',
                        suffixes=('', f'_{table_name}')
                    )
                    
                    # Fill NaN
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
        print("Training Zahtevi ML Model from ALL tables")
        print("=" * 50)
        
        # Primary table: zahtevi
        zahtevi_df = data.get('zahtevi', pd.DataFrame())
        if zahtevi_df.empty:
            print("[WARN] No zahtevi data - cannot train")
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 0, 'samples': 0, 'warning': 'Nema podataka o zahtevima'}
        
        # Izgradi knowledge graph za logičko povezivanje
        self.knowledge_graph.build_from_supabase(data)
        print(f"[KnowledgeGraph] {len(self.knowledge_graph.nodes)} entiteta, {sum(len(v) for v in self.knowledge_graph.edges.values())} relacija")
        
        # Koristi AutoFeatureDiscovery za automatsko otkrivanje bitnih feature-a iz SVIH tabela
        print(f"[AutoFeature] Learning from {len(data)} tables...")
        discovered_features = self.discoverer.discover_features(data, target_table='zahtevi')
        print(f"[AutoFeature] Discovered {len(discovered_features)} potential features")
        
        # Ekstraktuj feature-e iz zahteva
        daily = self._extract_features(zahtevi_df)
        if len(daily) < 3:
            self.is_trained = True
            return {'r2_score': 0.0, 'feature_count': 0, 'samples': len(daily), 'warning': 'Premalo podataka'}
        
        # Dodaj cross-table feature-e ako postoje relevantne tabele
        for table_name, table_df in data.items():
            if table_name == 'zahtevi' or table_df.empty:
                continue
            try:
                enriched = self._add_cross_table_features(daily, table_df, table_name)
                if not enriched.empty:
                    daily = enriched
                    print(f"[CrossTable] Added features from {table_name}")
            except Exception as e:
                print(f"[CrossTable] Could not add features from {table_name}: {e}")
        
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
                   'feature_count': len(feature_cols), 'samples': n_samples, 'eval_on_train': not eval_split,
                   'tables_used': len(data)}
        if eval_split:
            y_pred_test = self.model.predict(X_test)
            metrics['test_r2'] = self._safe_float(r2_score(y_test, y_pred_test))
            metrics['test_mae'] = self._safe_float(mean_absolute_error(y_test, y_pred_test))
            metrics['r2_score'] = metrics['test_r2']
            print(f"Test R²: {metrics['test_r2']:.3f} | Test MAE: {metrics['test_mae']:.4f}")
        else:
            metrics['r2_score'] = self._safe_float(train_r2)
        print(f"Train R²: {train_r2:.3f} | Train MAE: {train_mae:.4f}")
        print(f"Samples: {n_samples} | Features: {len(feature_cols)} | Tables: {len(data)}")
        print("=" * 50)
        self.is_trained = True
        self._last_metrics = metrics
        self._last_data = data  # Čuvaj sve tabele za predikciju

        # ZABORAVI stare tabele koje vise ne postoje
        self.memory.forget_old(list(data.keys()))

        # PAMTI sta je naucio iz SVIH tabela
        sources = {tbl: {"columns": list(df.columns), "rows": len(df)} for tbl, df in data.items()}
        feature_imp = dict(zip(feature_cols, self.model.feature_importances_)) if self.model else {}
        self.memory.record_training(sources, feature_imp, metrics)
        print("  [Memory] Zahtevi model zapamtio ucenje iz svih tabela")

        return metrics

    def predict_next_week(self, data: dict) -> dict:
        """Predviđa zahteve za narednu nedelju po gradovima"""
        if not self.is_trained:
            raise ValueError("Model not trained")
        
        # Primary table: zahtevi
        zahtevi_df = data.get('zahtevi', pd.DataFrame())
        if zahtevi_df.empty:
            return {
                'next_week': [],
                'ukupno_nedelja': 0,
                'prosek_dnevno': 0,
                'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None),
                'error': 'Nema podataka o zahtevima'
            }
        
        # Prvo napravi feature-e iz istorijskih podataka
        daily = self._extract_features(zahtevi_df)
        if len(daily) == 0:
            return {
                'next_week': [],
                'ukupno_nedelja': 0,
                'prosek_dnevno': 0,
                'model_r2': getattr(self, '_last_metrics', {}).get('r2_score', None),
                'error': 'Nema dovoljno podataka za predikciju'
            }
        
        last_date = daily['datum'].max()
        next_week = pd.date_range(start=last_date + pd.Timedelta(days=1), periods=7, freq='D')
        grads = daily['grad'].unique()
        results = []
        total_pred = 0
        dani = ['Ponedeljak', 'Utorak', 'Sreda', 'Cetvrtak', 'Petak', 'Subota', 'Nedelja']
        
        feature_cols = [c for c in daily.columns if c not in ['datum', 'grad', 'broj_zahteva']]
        
        for grad in grads:
            grad_data = daily[daily['grad'] == grad].copy()
            grad_data = grad_data.sort_values('datum')
            
            for i, d in enumerate(next_week):
                # Napravi feature-e za ovaj dan
                row = {
                    'datum': d,
                    'grad': grad,
                    'dan_u_nedelji': d.dayofweek,
                    'mesec': d.month,
                    'dan_u_mesecu': d.day,
                    'je_vikend': 1 if d.dayofweek in [5, 6] else 0,
                    'grad_bc': 1 if grad == 'BC' else 0,
                }
                
                # Izračunaj lag feature-e na osnovu istorije
                for lag in [1, 2, 3, 7]:
                    target_date = d - pd.Timedelta(days=lag)
                    lag_data = grad_data[grad_data['datum'] == target_date]
                    if not lag_data.empty:
                        row[f'lag_{lag}d'] = lag_data['broj_zahteva'].values[0]
                    else:
                        row[f'lag_{lag}d'] = 0
                
                # Rolling mean
                recent_data = grad_data[grad_data['datum'] < d]
                if len(recent_data) >= 7:
                    row['rolling_7d'] = recent_data.tail(7)['broj_zahteva'].mean()
                else:
                    row['rolling_7d'] = recent_data['broj_zahteva'].mean() if len(recent_data) > 0 else 0
                
                if len(recent_data) >= 14:
                    row['rolling_14d'] = recent_data.tail(14)['broj_zahteva'].mean()
                else:
                    row['rolling_14d'] = row['rolling_7d']
                
                # Trend
                if len(recent_data) >= 7:
                    row['trend_7d'] = recent_data.tail(7)['broj_zahteva'].iloc[-1] - recent_data.tail(7)['broj_zahteva'].iloc[0]
                else:
                    row['trend_7d'] = 0
                
                # Enriched lag features
                if 'zavrsenih_putovanja' in grad_data.columns:
                    target_date = d - pd.Timedelta(days=7)
                    lag_data = grad_data[grad_data['datum'] == target_date]
                    row['zavrseni_lag_7d'] = lag_data['zavrsenih_putovanja'].values[0] if not lag_data.empty else 0
                else:
                    row['zavrseni_lag_7d'] = 0
                
                if 'ukupni_prihod' in grad_data.columns:
                    target_date = d - pd.Timedelta(days=7)
                    lag_data = grad_data[grad_data['datum'] == target_date]
                    row['prihod_lag_7d'] = lag_data['ukupni_prihod'].values[0] if not lag_data.empty else 0
                else:
                    row['prihod_lag_7d'] = 0
                
                # Predikcija
                X_pred = pd.DataFrame([row])
                X_pred = X_pred[feature_cols].fillna(0)
                X_pred_scaled = self.scaler.transform(X_pred)
                pred = self.model.predict(X_pred_scaled)[0]
                pred = max(0, pred)  # Ne može biti negativno
                
                total_pred += pred
                
                results.append({
                    'datum': d.strftime('%Y-%m-%d'),
                    'dan': dani[d.weekday()],
                    'grad': str(grad),
                    'procenjeni_zahtevi': round(float(pred), 1)
                })
        
        return {
            'next_week': results,
            'ukupno_nedelja': round(float(total_pred), 1),
            'prosek_dnevno': round(float(total_pred / len(results)), 1) if len(results) > 0 else 0.0,
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
