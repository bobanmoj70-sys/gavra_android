"""
Google Gemini Flash Service
Lokalni fallback ako nema interneta, inace poziva Gemini API
"""
import config

GEMINI_AVAILABLE = False
try:
    import google.generativeai as genai
    GEMINI_AVAILABLE = True
except ImportError:
    pass


class GeminiService:
    """Wrapper oko Google Gemini Flash API-ja"""

    def __init__(self):
        self.model = None
        self.enabled = False
        self._init_model()

    def _init_model(self):
        if not GEMINI_AVAILABLE or not config.GEMINI_API_KEY:
            return
        try:
            genai.configure(api_key=config.GEMINI_API_KEY)
            self.model = genai.GenerativeModel('gemini-2.0-flash')
            self.enabled = True
            print("[Gemini] Service initialized")
        except Exception as e:
            print(f"[Gemini] Init error: {e}")

    def is_available(self) -> bool:
        return self.enabled and self.model is not None

    def ask(self, question: str, context: str = "") -> dict:
        """
        Salje pitanje ka Gemini-ju sa kontekstom iz baze.
        Vraca {'odgovor': str, 'tip': 'gemini'|'fallback'}.
        """
        if not self.is_available():
            return {
                'odgovor': 'Gemini AI nije dostupan (proveri API key ili internet).',
                'tip': 'fallback'
            }

        prompt = self._build_prompt(question, context)

        try:
            response = self.model.generate_content(
                prompt,
                generation_config=genai.types.GenerationConfig(
                    temperature=0.3,
                    max_output_tokens=256,
                )
            )
            return {
                'odgovor': response.text.strip(),
                'tip': 'gemini'
            }
        except Exception as e:
            return {
                'odgovor': f'Greška pri komunikaciji sa Gemini: {e}',
                'tip': 'fallback'
            }

    def _build_prompt(self, question: str, context: str) -> str:
        return f"""Ti si AI asistent za transportnu firmu. Koristi samo podatke ispod. Odgovori kratko i tačno na srpskom jeziku. Ako ne znaš odgovor, reci "Nemam dovoljno podataka".

PODACI IZ BAZE:
{context if context else 'Nema dostupnih podataka.'}

PITANJE KORISNIKA: {question}

ODGOVOR:"""
