"""
Knowledge Graph za logičko povezivanje podataka
Kreira relacije između entiteta iz baze
"""
import pandas as pd
from typing import Dict, List, Set
from collections import defaultdict

class KnowledgeGraph:
    def __init__(self):
        self.nodes = {}  # id -> {type, data}
        self.edges = defaultdict(set)  # from_id -> {to_id: relation_type}
        self.reverse_edges = defaultdict(set)  # to_id -> {from_id: relation_type}
    
    def add_node(self, node_id: str, node_type: str, data: dict):
        """Dodaje čvor u graf"""
        self.nodes[node_id] = {
            'type': node_type,
            'data': data
        }
    
    def add_edge(self, from_id: str, to_id: str, relation: str):
        """Dodaje granu (relaciju) između čvorova"""
        self.edges[from_id].add((to_id, relation))
        self.reverse_edges[to_id].add((from_id, relation))
    
    def build_from_supabase(self, data: Dict[str, pd.DataFrame]):
        """Izgrađuje graf iz Supabase podataka — dinamicki za sve tabele"""

        # Prvo: dodaj sve cvorove iz svih tabela
        for table_name, df in data.items():
            if df.empty or 'id' not in df.columns:
                continue
            for _, row in df.iterrows():
                node_id = str(row['id'])
                self.add_node(node_id, table_name, row.to_dict())

        # Zatim: povezi entitete na osnovu zajednickih kolona
        # Korisnici → Zahtevi (created_by)
        if 'zahtevi' in data and 'users' in data:
            for _, row in data['zahtevi'].iterrows():
                if 'created_by' in row and pd.notna(row['created_by']):
                    user_id = str(row['created_by'])
                    zahtev_id = str(row['id'])
                    self.add_edge(user_id, zahtev_id, 'napravio_zahtev')
                    self.add_edge(zahtev_id, user_id, 'napravio_od')

        # Vozac → Operativna (created_by)
        if 'operativna' in data:
            for _, row in data['operativna'].iterrows():
                if 'created_by' in row and pd.notna(row['created_by']):
                    vozac_id = str(row['created_by'])
                    oper_id = str(row['id'])
                    self.add_edge(vozac_id, oper_id, 'vozio')
                    self.add_edge(oper_id, vozac_id, 'vozeno_od')

        # Putnik → Finansije (putnik_v3_auth_id)
        if 'finansije' in data:
            for _, row in data['finansije'].iterrows():
                if 'putnik_v3_auth_id' in row and pd.notna(row['putnik_v3_auth_id']):
                    user_id = str(row['putnik_v3_auth_id'])
                    fin_id = str(row['id'])
                    self.add_edge(user_id, fin_id, 'ima_transakciju')
                    self.add_edge(fin_id, user_id, 'pripada')

        # Vozilo → Gorivo (vozilo_id)
        if 'gorivo' in data:
            for _, row in data['gorivo'].iterrows():
                if 'vozilo_id' in row and pd.notna(row['vozilo_id']):
                    vozilo_id = str(row['vozilo_id'])
                    gorivo_id = str(row['id'])
                    self.add_edge(vozilo_id, gorivo_id, 'ima_gorivo')
                    self.add_edge(gorivo_id, vozilo_id, 'za_vozilo')

        # Dinamicki: povezi sve tabele koje imaju _id kolone
        for table_name, df in data.items():
            if df.empty or 'id' not in df.columns:
                continue
            for col in df.columns:
                if col.endswith('_id') and col != 'id':
                    # Npr. 'vozilo_id', 'putnik_v3_auth_id', 'termin_id'
                    for _, row in df.iterrows():
                        if pd.notna(row[col]) and pd.notna(row.get('id')):
                            from_id = str(row[col])
                            to_id = str(row['id'])
                            relation = f'povezan_preko_{col}'
                            self.add_edge(from_id, to_id, relation)
    
    def get_related_entities(self, entity_id: str, max_depth: int = 2) -> Dict[str, List]:
        """Nalazi sve povezane entitete do određene dubine"""
        visited = set()
        result = defaultdict(list)
        
        def dfs(node_id: str, depth: int):
            if depth > max_depth or node_id in visited:
                return
            
            visited.add(node_id)
            
            # Napredne grane
            for neighbor, relation in self.edges[node_id]:
                if neighbor not in visited:
                    result[relation].append(neighbor)
                    dfs(neighbor, depth + 1)
            
            # Obrnute grane
            for neighbor, relation in self.reverse_edges[node_id]:
                if neighbor not in visited:
                    result[f'{relation}_reverse'].append(neighbor)
                    dfs(neighbor, depth + 1)
        
        dfs(entity_id, 0)
        return dict(result)
    
    def get_entity_context(self, entity_id: str) -> dict:
        """Vraća kontekst entiteta sa svim povezanim podacima"""
        if entity_id not in self.nodes:
            return {}
        
        related = self.get_related_entities(entity_id, max_depth=2)
        
        context = {
            'entity': self.nodes[entity_id],
            'relations': related,
            'total_connections': sum(len(v) for v in related.values())
        }
        
        return context
    
    def find_patterns(self) -> List[dict]:
        """Nalazi patern u grafu (npr. korisnici sa mnogo zahteva)"""
        patterns = []
        
        # Korisnici sa mnogo zahteva
        for node_id, node in self.nodes.items():
            if node['type'] == 'user':
                zahtevi = [n for n, r in self.edges[node_id] if r == 'napravio_zahtev']
                if len(zahtevi) > 5:
                    patterns.append({
                        'type': 'active_user',
                        'user_id': node_id,
                        'request_count': len(zahtevi)
                    })
        
        # Vozila sa niskim gorivom
        for node_id, node in self.nodes.items():
            if node['type'] == 'vozilo':
                gorivo = [n for n, r in self.edges[node_id] if r == 'ima_gorivo']
                if gorivo:
                    # Proveri nivo goriva
                    pass
        
        return patterns

if __name__ == "__main__":
    # Test
    from data.etl_znanje import extract_all_tables
    
    data = extract_all_tables()
    graph = KnowledgeGraph()
    graph.build_from_supabase(data)
    
    print(f"Nodes: {len(graph.nodes)}")
    print(f"Edges: {sum(len(v) for v in graph.edges.values())}")
    
    # Test konteksta
    if graph.nodes:
        first_id = list(graph.nodes.keys())[0]
        context = graph.get_entity_context(first_id)
        print(f"Context for {first_id}: {context}")
