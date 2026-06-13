import os
from dotenv import load_dotenv

# Ucitaj .env iz istog direktorijuma kao i ovaj fajl
_env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.env')
load_dotenv(dotenv_path=_env_path)

SUPABASE_URL = os.getenv("SUPABASE_URL", "https://gjtabtwudbrmfeyjiicu.supabase.co")
SUPABASE_KEY = os.getenv("SUPABASEKEY", os.getenv("SUPABASE_KEY", ""))

API_HOST = os.getenv("API_HOST", "0.0.0.0")
API_PORT = int(os.getenv("PORT", os.getenv("API_PORT", "8000")))

GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
MODEL_DIR = "models/saved"
