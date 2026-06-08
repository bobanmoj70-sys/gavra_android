"""
AI Knowledge Assistant Model
Razume prirodni jezik, izvrsava upite, generise odgovore
"""
import re
import pandas as pd
from typing import Dict, List, Any
import json
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
        """Izvlaci kljucne reci iz pitanja"""
        q = question.lower().strip()
        # Ukloni znake interpunkcije
        q = re.sub(r'[^\w\s]', ' ', q)
        words = q.split()
        # Ukloni ceste stop reci
        stop = {'da', 'li', 'je', 'u', 'za', 'na', 'se', 'koji', 'koliko', 'sta', 'kako', 'mi',
                'the', 'is', 'are', 'what', 'how', 'many', 'show', 'me', 'a', 'an', 'in', 'of'}
        return [w for w in words if w not in stop and len(w) > 2]

    def _detect_intent(self, question: str) -> str:
        """Prepoznaje nameru pitanja"""
        q = question.lower()

        patterns = {
            'count_zahtevi': r'(koliko|broj|count).*(zahtev|request)',
            'count_users': r'(koliko|broj).*(korisnik|user|putnik|vozac|vozac)',
            'count_finansije': r'(koliko|broj|iznos|sum).*(transakci|finans|novac|prihod|rashod)',
            'list_zahtevi': r'(lista|prikazi|show).*(zahtev|request)',
            'list_users': r'(lista|prikazi|show).*(korisnik|user|putnik|vozac)',
            'list_finansije': r'(lista|prikazi|show).*(transakci|finans)',
            'status_zahtevi': r'(status|stanje).*(zahtev|request)',
            'vehicle_status': r'(vozil|auto|servis|registrac|gorivo)',
            'recent_activity': r'(skoro|nedavno|recent|poslednj|zadnj)',
            'top_users': r'(top|najbolj|najcesc|najvise)',
            'today': r'(danas|today)',
        }

        for intent, pattern in patterns.items():
            if re.search(pattern, q):
                return intent

        return 'general'

    def _get_table_for_question(self, keywords: List[str]) -> str:
        """Odredjuje koja tabela je relevantna"""
        mapping = {
            'zahtevi': ['zahtev', 'request', 'termin', 'putnik', 'grad', 'vreme', 'polazak'],
            'users': ['korisnik', 'user', 'putnik', 'vozac', 'ime', 'prezime', 'email'],
            'operativna': ['operativna', 'nedelja', 'putovanje', 'voznja', 'dodela'],
            'finansije': ['finans', 'transakc', 'novac', 'iznos', 'prihod', 'rashod', 'plata'],
            'vozila': ['vozil', 'auto', 'registrac', 'marka', 'model', 'servis', 'km'],
            'gorivo': ['gorivo', 'rezervoar', 'benzin', 'dizel', 'litra', 'dopuna'],
        }

        scores = {k: 0 for k in mapping}
        for kw in keywords:
            for table, terms in mapping.items():
                if any(term in kw for term in terms):
                    scores[table] += 1

        best = max(scores, key=scores.get)
        return best if scores[best] > 0 else 'general'

    def ask(self, question: str) -> Dict[str, Any]:
        """
        Glavna metoda: prihvata pitanje, vraca odgovor
        """
        if not self.is_ready:
            return {'odgovor': 'AI asistent nije spreman. Nema podataka.', 'tip': 'greska'}

        # Prvo probaj semantičku pretragu sa embeddings
        if self.embeddings_service.is_available():
            similar_docs = self.embeddings_service.find_similar(question, top_k=3)
            if similar_docs and similar_docs[0][1] > 0.3:  # Threshold za sličnost
                print(f"[ZnanjeAI] Embeddings pronasao relevantne dokumente")
                return self._format_embeddings_response(similar_docs)

        keywords = self._extract_keywords(question)
        intent = self._detect_intent(question)
        table = self._get_table_for_question(keywords)

        # RUTA 1: Brojanje (koliko...)
        if intent.startswith('count_'):
            return self._handle_count(intent, keywords)

        # RUTA 2: Liste (prikazi...)
        if intent.startswith('list_'):
            return self._handle_list(intent, keywords, limit=10)

        # RUTA 3: Status
        if intent == 'status_zahtevi':
            return self._handle_status_zahtevi()

        # RUTA 4: Vozila
        if intent == 'vehicle_status':
            return self._handle_vehicle_status()

        # RUTA 5: Danasnja aktivnost
        if intent == 'today':
            return self._handle_today()

        # RUTA 6: Top/Najbolji
        if intent == 'top_users':
            return self._handle_top(keywords)

        # RUTA 7: Skora aktivnost
        if intent == 'recent_activity':
            return self._handle_recent()

        # DEFAULT: General info
        return self._handle_general(table)

    # === HANDLERI ===

    def _handle_count(self, intent: str, keywords: List[str]) -> Dict:
        if 'zahtev' in intent:
            df = self.data_cache.get('zahtevi', pd.DataFrame())
            total = len(df)
            active = len(df[df.get('status', '') != 'otkazano']) if 'status' in df.columns else total
            return {
                'odgovor': f'Ukupno zahteva: {total}. Aktivnih: {active}.',
                'tip': 'count',
                'podaci': {'ukupno': total, 'aktivni': active}
            }

        if 'user' in intent or 'putnik' in intent or 'vozac' in intent:
            df = self.data_cache.get('users', pd.DataFrame())
            total = len(df)
            vozaci = len(df[df.get('role', '') == 'vozac']) if 'role' in df.columns else 0
            putnici = len(df[df.get('role', '') == 'putnik']) if 'role' in df.columns else 0
            return {
                'odgovor': f'Ukupno korisnika: {total} ({vozaci} vozaca, {putnici} putnika).',
                'tip': 'count',
                'podaci': {'ukupno': total, 'vozaci': vozaci, 'putnici': putnici}
            }

        if 'finans' in intent:
            df = self.data_cache.get('finansije', pd.DataFrame())
            total = len(df)
            prihod = df[df.get('tip', '') == 'prihod']['iznos'].sum() if 'tip' in df.columns and 'iznos' in df.columns else 0
            rashod = df[df.get('tip', '') == 'rashod']['iznos'].sum() if 'tip' in df.columns and 'iznos' in df.columns else 0
            return {
                'odgovor': f'Ukupno transakcija: {total}. Prihod: {prihod:.2f}, Rashod: {rashod:.2f}.',
                'tip': 'count',
                'podaci': {'ukupno': total, 'prihod': prihod, 'rashod': rashod}
            }

        return {'odgovor': 'Nisam razumeo sta zelis da prebrojim.', 'tip': 'unknown'}

    def _handle_list(self, intent: str, keywords: List[str], limit: int = 10) -> Dict:
        table_map = {
            'list_zahtevi': 'zahtevi',
            'list_users': 'users',
            'list_finansije': 'finansije'
        }
        tbl = table_map.get(intent, 'zahtevi')
        df = self.data_cache.get(tbl, pd.DataFrame())

        if df.empty:
            return {'odgovor': f'Nema podataka u tabeli {tbl}.', 'tip': 'prazno'}

        # Filtriraj po statusu ako je pomenut
        if 'status' in str(keywords).lower():
            for status in ['aktivan', 'otkazano', 'zavrseno', 'obrada', 'odbijen']:
                if 'status' in df.columns:
                    mask = df['status'].str.contains(status, case=False, na=False)
                    if mask.any():
                        df = df[mask]
                        break

        recent = df.head(limit)
        records = recent.fillna('-').to_dict('records')

        return {
            'odgovor': f'Prikazujem {len(records)} najskorijih zapisa iz {tbl}:',
            'tip': 'lista',
            'podaci': records
        }

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

    def _handle_top(self, keywords: List[str]) -> Dict:
        fin = self.data_cache.get('finansije', pd.DataFrame())
        if not fin.empty and 'putnik_v3_auth_id' in fin.columns and 'iznos' in fin.columns:
            top = fin.groupby('putnik_v3_auth_id')['iznos'].sum().nlargest(5)
            return {
                'odgovor': f'Top {len(top)} putnika po prihodu:',
                'tip': 'top',
                'podaci': top.to_dict()
            }

        zah = self.data_cache.get('zahtevi', pd.DataFrame())
        if not zah.empty and 'created_by' in zah.columns:
            top = zah['created_by'].value_counts().head(5)
            return {
                'odgovor': f'Top {len(top)} najaktivnijih putnika po zahtevima:',
                'tip': 'top',
                'podaci': top.to_dict()
            }

        return {'odgovor': 'Nema dovoljno podataka za top listu.', 'tip': 'prazno'}

    def _handle_recent(self) -> Dict:
        combined = []

        for tbl in ['zahtevi', 'operativna', 'finansije']:
            df = self.data_cache.get(tbl, pd.DataFrame())
            if not df.empty:
                combined.append(f'{tbl}: {len(df)} zapisa')

        if not combined:
            return {'odgovor': 'Nema skorijih podataka.', 'tip': 'prazno'}

        return {
            'odgovor': 'Skoriji podaci u sistemu:\n' + '\n'.join(combined),
            'tip': 'recent',
            'podaci': {tbl: len(self.data_cache.get(tbl, pd.DataFrame())) for tbl in ['zahtevi', 'operativna', 'finansije']}
        }

    def _handle_general(self, table: str) -> Dict:
        info = []
        for tbl_name in ['zahtevi', 'users', 'operativna', 'finansije', 'vozila', 'gorivo']:
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
        pass

    def load(self):
        pass
