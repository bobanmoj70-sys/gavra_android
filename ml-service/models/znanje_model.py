"""
AI Knowledge Assistant Model
Razume prirodni jezik, izvrsava upite, generise odgovore
"""
import re
import pandas as pd
from typing import Dict, List, Any
import json
import os
import joblib
import config
from models.knowledge_graph import KnowledgeGraph
from services.embeddings_service import EmbeddingsService


class ZnanjeAIModel:
    """AI asistent koji razume podatke iz baze i odgovara na pitanja"""

    def __init__(self):
        self.data_cache = {}
        self.schema = {}
        self.knowledge_graph = KnowledgeGraph()
        self.embeddings_service = EmbeddingsService()
        self.is_ready = False
        self.model_dir = config.MODEL_DIR
        self.state_path = f"{self.model_dir}/znanje_state.pkl"
        os.makedirs(self.model_dir, exist_ok=True)

    def load_data(self, data: Dict[str, pd.DataFrame], schema: Dict):
        """Ucitava podatke iz ETL-a i gradi knowledge graph"""
        self.data_cache = {k: v.copy() for k, v in data.items() if not v.empty}
        self.schema = schema
        
        # Izgradi knowledge graph za logičko povezivanje
        self.knowledge_graph.build_from_supabase(self.data_cache)
        print(f"[ZnanjeAI] Knowledge graph: {len(self.knowledge_graph.nodes)} cvorova, {sum(len(v) for v in self.knowledge_graph.edges.values())} grana")
        
        # Pripremi dokumente za embeddings
        documents = self._prepare_documents_for_embeddings()
        if documents and self.embeddings_service.is_available():
            self.embeddings_service.encode_documents(documents)
            print(f"[ZnanjeAI] Embeddings: {len(documents)} dokumenata indeksirano")
        
        self.is_ready = True
        print(f"[ZnanjeAI] Ucitano {len(self.data_cache)} tabela")

    def _prepare_documents_for_embeddings(self) -> List[str]:
        """Priprema dokumente iz baze za embeddings indeksiranje"""
        documents = []
        
        # Dodaj podatke iz svake tabele kao dokumente
        for table_name, df in self.data_cache.items():
            if df.empty:
                continue
            
            for _, row in df.iterrows():
                # Kreiraj tekstualni reprezentaciju reda
                text_parts = []
                for col in df.columns:
                    val = row[col]
                    if pd.notna(val):
                        text_parts.append(f"{col}: {val}")
                
                doc_text = f"[{table_name}] " + ", ".join(text_parts)
                documents.append(doc_text)
        
        return documents
    
    def _format_embeddings_response(self, similar_docs: List[tuple]) -> Dict:
        """Formatira odgovor iz embeddings pretrage"""
        response_parts = ["Pronasao sam relevantne informacije:"]
        
        for doc, score in similar_docs:
            response_parts.append(f"\n- {doc} (sličnost: {score:.2f})")
        
        return {
            'odgovor': "\n".join(response_parts),
            'tip': 'embeddings',
            'sličnost': [score for _, score in similar_docs]
        }
    
    def _extract_keywords(self, question: str) -> List[str]:
        """Izvlaci kljucne reci iz pitanja sa stemming-like redukcijom"""
        q = question.lower().strip()
        q = re.sub(r'[^\w\s]', ' ', q)
        words = q.split()
        stop = {'da', 'li', 'je', 'u', 'za', 'na', 'se', 'koji', 'koliko', 'sta', 'kako', 'mi', 'nam',
                'the', 'is', 'are', 'what', 'how', 'many', 'show', 'me', 'a', 'an', 'in', 'of', 'i', 'ili',
                'ko', 'ga', 'mu', 'joj', 'ima', 'nema', 'svi', 'sve', 'ti', 'vi'}
        keywords = []
        for w in words:
            if w not in stop and len(w) > 2:
                # Remove common serbian suffixes for matching
                for suffix in ['ova', 'ove', 'ovi', 'a', 'e', 'i', 'u', 'om', 'ima', 'ima', 'ovanje', 'anje', 'eni']:
                    if w.endswith(suffix) and len(w) - len(suffix) > 2:
                        w = w[:-len(suffix)]
                        break
                keywords.append(w)
        return keywords

    def _detect_intent(self, question: str) -> str:
        """Prepoznaje nameru pitanja sa fuzzy matchingom"""
        q = question.lower()
        # Brojanje
        if re.search(r'(koliko|broj|count|ukupno)', q):
            if re.search(r'(zahtev|termin|request)', q): return 'count_zahtevi'
            if re.search(r'(korisnik|putnik|vozac|user)', q): return 'count_users'
            if re.search(r'(vozil|auto|registrac)', q): return 'count_vozila'
            if re.search(r'(transakci|finans|novac|prihod|rashod|dug|iznos)', q): return 'count_finansije'
            if re.search(r'(gorivo|rezervoar|benzin|lit)', q): return 'count_gorivo'
            return 'count_general'
        # Status / stanje
        if re.search(r'(status|stanje|kako je|sta je sa)', q):
            if re.search(r'(zahtev|request)', q): return 'status_zahtevi'
            if re.search(r'(vozil|auto|registrac|servis)', q): return 'vehicle_status'
            if re.search(r'(gorivo|rezervoar|benzin)', q): return 'status_gorivo'
            return 'status_general'
        # Lista / prikaz
        if re.search(r'(lista|prikazi|pokazi|show|koje|koja|koji)', q):
            if re.search(r'(zahtev|request|termin)', q): return 'list_zahtevi'
            if re.search(r'(korisnik|putnik|vozac)', q): return 'list_users'
            if re.search(r'(transakci|finans|dug)', q): return 'list_finansije'
            if re.search(r'(vozil|auto)', q): return 'list_vozila'
            return 'list_general'
        # Top / naj
        if re.search(r'(top|najbolj|najcesc|najvise|najmanje|naj|sortiraj)', q):
            if re.search(r'(vozac|putnik|korisnik)', q): return 'top_users'
            if re.search(r'(vozil)', q): return 'top_vozila'
            return 'top_general'
        # Aktivnost
        if re.search(r'(danas|today|sada)', q): return 'today'
        if re.search(r'(skoro|nedavno|recent|poslednj|zadnj|u zadnj|ove nedelj)', q): return 'recent_activity'
        # Pojedinačne entitete
        if re.search(r'(vozil|auto|servis|registrac|gorivo)', q): return 'vehicle_status'
        if re.search(r'(putnik|vozac|korisnik|ime)', q): return 'user_info'
        return 'general'

    def _get_table_for_question(self, keywords: List[str]) -> str:
        """Određuje koja tabela je relevantna sa fuzzy skorovima — dinamicki iz svih ucitanih tabela"""
        # Build mapping from actual loaded tables + common aliases
        mapping = {}
        for tbl in self.data_cache.keys():
            mapping[tbl] = [tbl.lower().replace('v3_', '')]
            # Add common aliases
            if 'zahtev' in tbl.lower():
                mapping[tbl].extend(['zahtev', 'request', 'termin', 'putnik', 'grad', 'vreme', 'polazak'])
            if 'auth' in tbl.lower() or 'user' in tbl.lower():
                mapping[tbl].extend(['korisnik', 'user', 'putnik', 'vozac', 'ime', 'email', 'osob'])
            if 'operativ' in tbl.lower():
                mapping[tbl].extend(['operativna', 'nedelja', 'putovanje', 'voznja', 'dodela'])
            if 'finans' in tbl.lower():
                mapping[tbl].extend(['finans', 'transakc', 'novac', 'iznos', 'prihod', 'rashod', 'plata', 'dug'])
            if 'vozil' in tbl.lower():
                mapping[tbl].extend(['vozil', 'auto', 'registrac', 'marka', 'model', 'servis', 'km'])
            if 'gorivo' in tbl.lower():
                mapping[tbl].extend(['gorivo', 'rezervoar', 'benzin', 'dizel', 'litra', 'dopuna', 'tankanje'])
            if 'dodela' in tbl.lower() and 'slot' in tbl.lower():
                mapping[tbl].extend(['slot', 'raspored', 'smena', 'voznja', 'termin'])
            if 'dodela' in tbl.lower() and 'slot' not in tbl.lower():
                mapping[tbl].extend(['dodela', 'dodeljen', 'vozac', 'putnik', 'termin'])
            if 'eta' in tbl.lower():
                mapping[tbl].extend(['eta', 'vreme', 'dolazak', 'stizanje', 'predikcija'])

        scores = {k: 0.0 for k in mapping}
        for kw in keywords:
            for table, terms in mapping.items():
                for term in terms:
                    if kw == term:
                        scores[table] += 2.0
                    elif kw.startswith(term) or term.startswith(kw):
                        scores[table] += 1.0
                    elif len(kw) > 3 and len(term) > 3:
                        if term in kw or kw in term:
                            scores[table] += 0.5
        if scores and max(scores.values()) > 0:
            best = max(scores, key=scores.get)
            return best
        return list(self.data_cache.keys())[0] if self.data_cache else 'general'

    def _find_entity_by_name(self, question: str, table: str, name_col: str = 'ime', id_col: str = 'id') -> Any:
        """Fuzzy traženje entiteta po imenu u pitanju"""
        df = self.data_cache.get(table, pd.DataFrame())
        if df.empty or name_col not in df.columns:
            return None
        q_lower = question.lower()
        # Izdvuci potencijalna imena iz pitanja (reči duže od 3 karaktera koje nisu stop reči)
        candidates = re.findall(r'[a-zA-ZčćđšžČĆĐŠŽ]{3,}', q_lower)
        stop = {'koliko', 'broj', 'koji', 'sta', 'kako', 'danas', 'ima', 'nema', 'putnik', 'vozac', 'korisnik', 'user'}
        candidates = [c for c in candidates if c not in stop]
        if not candidates:
            return None
        best_match = None
        best_score = 0.0
        for _, row in df.iterrows():
            name = str(row.get(name_col, '')).lower()
            if not name or name in ('nepoznato', 'nan', 'none', ''):
                continue
            for cand in candidates:
                if cand in name or name in cand:
                    score = len(cand) / max(len(name), 1)
                    if score > best_score:
                        best_score = score
                        best_match = row
        return best_match

    def ask(self, question: str) -> Dict[str, Any]:
        """Glavna metoda: prihvata pitanje, vraca odgovor sa embeddings + fuzzy matching"""
        if not self.is_ready:
            return {'odgovor': 'AI asistent nije spreman. Nema podataka.', 'tip': 'greska'}
        # Prvo probaj semantičku pretragu sa embeddings
        if self.embeddings_service.is_available():
            similar_docs = self.embeddings_service.find_similar(question, top_k=3)
            if similar_docs and similar_docs[0][1] > 0.25:
                print(f"[ZnanjeAI] Embeddings pronašao relevantne dokumente")
                return self._format_embeddings_response(similar_docs)
        keywords = self._extract_keywords(question)
        intent = self._detect_intent(question)
        table = self._get_table_for_question(keywords)
        # RUTA 1: Brojanje
        if intent.startswith('count_'):
            return self._handle_count(intent, keywords, question)
        # RUTA 2: Liste
        if intent.startswith('list_'):
            return self._handle_list(intent, keywords, limit=10, question=question)
        # RUTA 3: Status
        if intent in ('status_zahtevi', 'status_gorivo', 'status_general'):
            return self._handle_status(intent)
        # RUTA 4: Vozila
        if intent == 'vehicle_status':
            return self._handle_vehicle_status()
        # RUTA 5: Danasnja aktivnost
        if intent == 'today':
            return self._handle_today()
        # RUTA 6: Top/Najbolji
        if intent.startswith('top_'):
            return self._handle_top(intent, keywords, question)
        # RUTA 7: Skora aktivnost
        if intent == 'recent_activity':
            return self._handle_recent()
        # RUTA 8: User info (specifican putnik/vozac)
        if intent == 'user_info':
            return self._handle_user_info(question)
        # DEFAULT
        return self._handle_general(table)

    def build_context_for_llm(self, question: str, max_rows: int = 10) -> str:
        """Izgrađuje tekstualni kontekst iz baze za slanje LLM-u"""
        if not self.is_ready:
            return "Nema podataka."
        keywords = self._extract_keywords(question)
        table = self._get_table_for_question(keywords)
        df = self.data_cache.get(table, pd.DataFrame())
        if df.empty:
            # Ako primarna tabela nema podataka, probaj sve
            parts = []
            for tbl_name, tbl_df in self.data_cache.items():
                if not tbl_df.empty:
                    sample = tbl_df.head(min(max_rows, len(tbl_df))).fillna('-').to_string(index=False)
                    parts.append(f"[{tbl_name}]\n{sample}\n")
            return "\n".join(parts) if parts else "Nema podataka u bazi."
        sample = df.head(min(max_rows, len(df))).fillna('-').to_string(index=False)
        return f"[tabela: {table}]\n{sample}\n\nUkupno redova: {len(df)}"

    # === HANDLERI ===

    def _handle_count(self, intent: str, keywords: List[str], question: str = '') -> Dict:
        # Try to find matching table from all loaded tables
        tbl = self._get_table_for_question(keywords)
        df = self.data_cache.get(tbl, pd.DataFrame())
        if not df.empty:
            total = len(df)
            # Try to extract smart stats if columns exist
            extras = []
            if 'status' in df.columns:
                active = len(df[df['status'] != 'otkazano'])
                extras.append(f"aktivnih: {active}")
            if 'tip' in df.columns and 'iznos' in df.columns:
                prihod = df[df['tip'] == 'prihod']['iznos'].sum()
                rashod = df[df['tip'] == 'rashod']['iznos'].sum()
                extras.append(f"prihod: {prihod:.2f}, rashod: {rashod:.2f}")
            if 'tip' in df.columns:
                counts = df['tip'].value_counts().to_dict()
                for t, c in list(counts.items())[:3]:
                    extras.append(f"{t}: {c}")
            extra_str = f" ({', '.join(extras)})" if extras else ""
            return {'odgovor': f'Ukupno u {tbl}: {total}{extra_str}.', 'tip': 'count', 'podaci': {'ukupno': total, 'tabela': tbl}}

        # Fallback for general count
        all_counts = {tbl: len(df) for tbl, df in self.data_cache.items() if not df.empty}
        if all_counts:
            lines = [f"{k}: {v}" for k, v in all_counts.items()]
            return {'odgovor': f'Ukupno zapisa po tabelama:\n' + '\n'.join(lines), 'tip': 'count', 'podaci': all_counts}
        return {'odgovor': 'Nisam razumeo šta želiš da prebrojim.', 'tip': 'unknown'}

    def _handle_list(self, intent: str, keywords: List[str], limit: int = 10, question: str = '') -> Dict:
        tbl = self._get_table_for_question(keywords)
        df = self.data_cache.get(tbl, pd.DataFrame())
        if df.empty:
            return {'odgovor': f'Nema podataka u tabeli {tbl}.', 'tip': 'prazno'}
        # Filtriraj po statusu ako je pomenut
        for status in ['aktivan', 'otkazano', 'zavrseno', 'obrada', 'odbijeno', 'odobreno']:
            if status in question.lower() and 'status' in df.columns:
                mask = df['status'].str.contains(status, case=False, na=False)
                if mask.any():
                    df = df[mask]
                    break
        # Sortiraj po datumu ako postoji
        date_col = None
        for col in ['created_at', 'datum', 'updated_at']:
            if col in df.columns:
                date_col = col
                break
        if date_col:
            df = df.sort_values(date_col, ascending=False)
        records = df.head(limit).fillna('-').to_dict('records')
        return {'odgovor': f'Prikazujem {len(records)} najskorijih zapisa iz {tbl}:', 'tip': 'lista', 'podaci': records}

    def _handle_status_zahtevi(self) -> Dict:
        df = self.data_cache.get('zahtevi', pd.DataFrame())
        if df.empty or 'status' not in df.columns:
            return {'odgovor': 'Nema podataka o zahtevima.', 'tip': 'prazno'}

        statusi = df['status'].value_counts().to_dict()
        lines = [f'{k}: {v}' for k, v in statusi.items()]
        return {
            'odgovor': 'Statusi zahteva:\n' + '\n'.join(lines),
            'tip': 'status',
            'podaci': statusi
        }

    def _handle_status(self, intent: str) -> Dict:
        if intent == 'status_gorivo':
            gorivo = self.data_cache.get('gorivo', pd.DataFrame())
            if gorivo.empty:
                return {'odgovor': 'Nema podataka o gorivu.', 'tip': 'prazno'}
            if 'trenutno_stanje_litri' in gorivo.columns and 'kapacitet_litri' in gorivo.columns:
                gorivo['nivo'] = gorivo['trenutno_stanje_litri'] / gorivo['kapacitet_litri'] * 100
                nisko = len(gorivo[gorivo['nivo'] < 20])
                alarm = len(gorivo[gorivo['alarm_nivo_litri'] > gorivo['trenutno_stanje_litri']]) if 'alarm_nivo_litri' in gorivo.columns else 0
                return {'odgovor': f'Rezervoara: {len(gorivo)}. Niski nivo (<20%): {nisko}. Alarm: {alarm}.', 'tip': 'status', 'podaci': {'nisko': nisko, 'alarm': alarm}}
        if intent == 'status_zahtevi':
            return self._handle_status_zahtevi()
        return self._handle_vehicle_status()

    def _handle_user_info(self, question: str) -> Dict:
        """Odgovara na pitanja o specifičnim korisnicima"""
        entity = self._find_entity_by_name(question, 'users', name_col='ime')
        if entity is not None:
            info_parts = []
            for k, v in entity.items():
                if pd.notna(v) and str(v) not in ('None', 'nan', ''):
                    info_parts.append(f'{k}: {v}')
            return {'odgovor': 'Pronađen korisnik:\n' + '\n'.join(info_parts[:10]), 'tip': 'user_info', 'podaci': dict(entity)}
        return {'odgovor': 'Nisam pronašao korisnika sa tim imenom.', 'tip': 'not_found'}

    def _handle_vehicle_status(self) -> Dict:
        vozila = self.data_cache.get('vozila', pd.DataFrame())
        gorivo = self.data_cache.get('gorivo', pd.DataFrame())
        if vozila.empty:
            return {'odgovor': 'Nema podataka o vozilima.', 'tip': 'prazno'}
        total = len(vozila)
        info = f'Ukupno vozila: {total}. '
        if 'trenutna_km' in vozila.columns:
            prosek_km = vozila['trenutna_km'].mean()
            info += f'Prosek KM: {prosek_km:.0f}. '
        if not gorivo.empty and 'trenutno_stanje_litri' in gorivo.columns and 'kapacitet_litri' in gorivo.columns:
            gorivo['nivo'] = gorivo['trenutno_stanje_litri'] / gorivo['kapacitet_litri'] * 100
            nisko = len(gorivo[gorivo['nivo'] < 20])
            info += f'Vozila sa niskim gorivom (<20%): {nisko}.'
        return {'odgovor': info, 'tip': 'vozila', 'podaci': {'ukupno': total}}

    def _handle_today(self) -> Dict:
        from datetime import date
        today = date.today().isoformat()

        df = self.data_cache.get('operativna', pd.DataFrame())
        if not df.empty and 'datum' in df.columns:
            today_df = df[df['datum'].astype(str) == today]
            if len(today_df) > 0:
                aktivni = len(today_df[today_df.get('otkazano_at', pd.NaT).isna()])
                return {
                    'odgovor': f'Danas ({today}): {len(today_df)} zakazanih termina, {aktivni} aktivnih.',
                    'tip': 'danas',
                    'podaci': {'ukupno': len(today_df), 'aktivni': aktivni}
                }

        df2 = self.data_cache.get('zahtevi', pd.DataFrame())
        if not df2.empty and 'datum' in df2.columns:
            today_df2 = df2[df2['datum'].astype(str) == today]
            return {
                'odgovor': f'Danas ({today}): {len(today_df2)} zahteva.',
                'tip': 'danas',
                'podaci': {'ukupno': len(today_df2)}
            }

        return {'odgovor': f'Danas ({today}) nema aktivnosti u sistemu.', 'tip': 'danas'}

    def _handle_top(self, intent: str, keywords: List[str], question: str = '') -> Dict:
        tbl = self._get_table_for_question(keywords)
        df = self.data_cache.get(tbl, pd.DataFrame())
        if not df.empty:
            # Try numeric columns for top
            numeric_cols = df.select_dtypes(include=['number']).columns.tolist()
            if numeric_cols:
                top = df.nlargest(5, numeric_cols[0])
                return {'odgovor': f'Top 5 iz {tbl} po {numeric_cols[0]}:', 'tip': 'top', 'podaci': top.head(5).fillna('-').to_dict('records')}
            # Try value counts
            if 'created_by' in df.columns:
                top = df['created_by'].value_counts().head(5)
                return {'odgovor': f'Top {len(top)} najaktivnijih u {tbl}:', 'tip': 'top', 'podaci': top.to_dict()}
            # Just return first 5
            return {'odgovor': f'Prvih 5 zapisa iz {tbl}:', 'tip': 'top', 'podaci': df.head(5).fillna('-').to_dict('records')}
        return {'odgovor': 'Nema dovoljno podataka za top listu.', 'tip': 'prazno'}

    def _handle_recent(self) -> Dict:
        combined = []
        podaci = {}

        for tbl_name in self.data_cache.keys():
            df = self.data_cache.get(tbl_name, pd.DataFrame())
            if not df.empty:
                combined.append(f'{tbl_name}: {len(df)} zapisa')
                podaci[tbl_name] = len(df)

        if not combined:
            return {'odgovor': 'Nema skorijih podataka.', 'tip': 'prazno'}

        return {
            'odgovor': 'Skoriji podaci u sistemu:\n' + '\n'.join(combined),
            'tip': 'recent',
            'podaci': podaci
        }

    def _handle_general(self, table: str) -> Dict:
        info = []
        for tbl_name in self.data_cache.keys():
            df = self.data_cache.get(tbl_name, pd.DataFrame())
            if not df.empty:
                info.append(f'{tbl_name}: {len(df)} redova')

        # Dodaj info o knowledge graph
        graph_info = f'\n\nKnowledge Graph: {len(self.knowledge_graph.nodes)} entiteta, {sum(len(v) for v in self.knowledge_graph.edges.values())} relacija'

        return {
            'odgovor': 'Trenutno u bazi imam podatke iz sledecih tabela:\n' + '\n'.join(info) +
                      graph_info +
                      '\n\nPitaj me npr: "Koliko zahteva ima Bojan?", "Prikazi finansije", "Status vozila", "Sta je danas?"',
            'tip': 'help',
            'podaci': {tbl: len(self.data_cache.get(tbl, pd.DataFrame())) for tbl in self.data_cache}
        }

    def train(self, data: Dict[str, pd.DataFrame], schema: Dict) -> Dict:
        """Ucitava i indeksira podatke"""
        self.load_data(data, schema)
        return {
            'status': 'ready',
            'tables_loaded': len(self.data_cache),
            'total_rows': sum(len(df) for df in self.data_cache.values())
        }

    def save(self):
        if not self.is_ready or not self.data_cache:
            return

        state = {
            'schema': self.schema,
            'data_cache': self.data_cache,
        }
        joblib.dump(state, self.state_path)
        print("[OK] Znanje model state saved")

    def load(self):
        try:
            state = joblib.load(self.state_path)
            cached_data = state.get('data_cache', {}) if isinstance(state, dict) else {}
            schema = state.get('schema', {}) if isinstance(state, dict) else {}

            normalized_data = {}
            for table_name, table_data in cached_data.items():
                if isinstance(table_data, pd.DataFrame):
                    normalized_data[table_name] = table_data
                else:
                    normalized_data[table_name] = pd.DataFrame(table_data)

            self.load_data(normalized_data, schema)
            print("[OK] Znanje model state loaded")
        except FileNotFoundError:
            print("[MISSING] No saved znanje model state")
