"""
Embeddings Service za semantičku pretragu
Pokušava da koristi sentence-transformers, inače koristi TF-IDF
"""
import numpy as np
from typing import List, Optional
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.metrics.pairwise import cosine_similarity

class EmbeddingsService:
    def __init__(self):
        self.model = None
        self.use_sentence_transformers = False
        self.tfidf_vectorizer = None
        self.tfidf_matrix = None
        self.documents = []
        
        # Pokušaj da učitaš sentence-transformers
        try:
            from sentence_transformers import SentenceTransformer
            print("[Embeddings] Loading sentence-transformers model...")
            self.model = SentenceTransformer('all-MiniLM-L6-v2')
            self.use_sentence_transformers = True
            print("[Embeddings] sentence-transformers loaded successfully")
        except Exception as e:
            print(f"[Embeddings] Could not load sentence-transformers: {e}")
            print("[Embeddings] Falling back to TF-IDF")
            self.tfidf_vectorizer = TfidfVectorizer()
    
    def encode_documents(self, documents: List[str]) -> np.ndarray:
        """Kodira dokumente u vektore"""
        self.documents = documents
        
        if self.use_sentence_transformers and self.model:
            embeddings = self.model.encode(documents)
            return embeddings
        else:
            # TF-IDF fallback
            self.tfidf_matrix = self.tfidf_vectorizer.fit_transform(documents)
            return self.tfidf_matrix.toarray()
    
    def encode_query(self, query: str) -> np.ndarray:
        """Kodira upit u vektor"""
        if self.use_sentence_transformers and self.model:
            return self.model.encode([query])[0]
        else:
            # TF-IDF fallback
            query_vec = self.tfidf_vectorizer.transform([query])
            return query_vec.toarray()[0]
    
    def find_similar(self, query: str, top_k: int = 5) -> List[tuple]:
        """Nalazi najviše sličnih dokumenata za upit"""
        if not self.documents:
            return []
        
        query_vec = self.encode_query(query)
        
        if self.use_sentence_transformers:
            # Cosine similarity za sentence-transformers
            doc_vecs = self.model.encode(self.documents)
            similarities = cosine_similarity([query_vec], doc_vecs)[0]
        else:
            # Cosine similarity za TF-IDF
            similarities = cosine_similarity([query_vec], self.tfidf_matrix)[0]
        
        # Sortiraj po sličnosti
        top_indices = np.argsort(similarities)[::-1][:top_k]
        
        results = []
        for idx in top_indices:
            results.append((self.documents[idx], similarities[idx]))
        
        return results
    
    def is_available(self) -> bool:
        """Da li je embeddings service dostupan"""
        return self.use_sentence_transformers or self.tfidf_vectorizer is not None

if __name__ == "__main__":
    # Test
    service = EmbeddingsService()
    
    docs = [
        "Imamo li goriva u rezervoaru?",
        "Koliko novca imamo na računu?",
        "Koja vozila su dostupna?",
        "Status finansija",
        "Vozila i servis"
    ]
    
    service.encode_documents(docs)
    
    query = "Imam li benzina?"
    results = service.find_similar(query, top_k=3)
    
    print(f"Query: {query}")
    print("Similar documents:")
    for doc, score in results:
        print(f"  {score:.3f}: {doc}")
