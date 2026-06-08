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
        """Izgrađuje graf iz Supabase podataka"""
        
        # Korisnici
        if 'users' in data:
            for _, row in data['users'].iterrows():
                user_id = str(row['id'])
                self.add_node(user_id, 'user', row.to_dict())
        
        # Vozila
        if 'vozila' in data:
            for _, row in data['vozila'].iterrows():
                vozilo_id = str(row['id'])
                self.add_node(vozilo_id, 'vozilo', row.to_dict())
        
        # Zahtevi → povezuju korisnike i vozila
        if 'zahtevi' in data:
            for _, row in data['zahtevi'].iterrows():
                zahtev_id = str(row['id'])
                self.add_node(zahtev_id, 'zahtev', row.to_dict())
                
                # Putnik → Zahtev
                if 'created_by' in row and pd.notna(row['created_by']):
                    user_id = str(row['created_by'])
                    self.add_edge(user_id, zahtev_id, 'napravio_zahtev')
                    self.add_edge(zahtev_id, user_id, 'napravio_od')
        
        # Operativna → povezuje zahtevi i vozila
        if 'operativna' in data:
            for _, row in data['operativna'].iterrows():
                oper_id = str(row['id'])
                self.add_node(oper_id, 'operativna', row.to_dict())
                
                # Vozac → Operativna
                if 'created_by' in row and pd.notna(row['created_by']):
                    vozac_id = str(row['created_by'])
                    self.add_edge(vozac_id, oper_id, 'vozio')
                    self.add_edge(oper_id, vozac_id, 'vozeno_od')
        
        # Finansije → povezuju korisnike
        if 'finansije' in data:
            for _, row in data['finansije'].iterrows():
                fin_id = str(row['id'])
                self.add_node(fin_id, 'finansije', row.to_dict())
                
                # Putnik → Finansije
                if 'putnik_v3_auth_id' in row and pd.notna(row['putnik_v3_auth_id']):
                    user_id = str(row['putnik_v3_auth_id'])
                    self.add_edge(user_id, fin_id, 'ima_transakciju')
                    self.add_edge(fin_id, user_id, 'pripada')
        
        # Gorivo → povezuje vozila
        if 'gorivo' in data:
            for _, row in data['gorivo'].iterrows():
                gorivo_id = str(row['id'])
                self.add_node(gorivo_id, 'gorivo', row.to_dict())
                
                # Vozilo → Gorivo
                if 'vozilo_id' in row and pd.notna(row['vozilo_id']):
                    vozilo_id = str(row['vozilo_id'])
                    self.add_edge(vozilo_id, gorivo_id, 'ima_gorivo')
                    self.add_edge(gorivo_id, vozilo_id, 'za_vozilo')
    
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
