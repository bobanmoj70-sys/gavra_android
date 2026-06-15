---
title: Gavra ML API
emoji: 🧠
colorFrom: blue
colorTo: purple
sdk: docker
pinned: false
---

# Gavra ML Service - 6 AI Modela

Python ML service sa 6 specijalizovanih AI modela. Svi modeli uče isključivo iz Supabase podataka bez pre-trained znanja.

## 6 AI Modela:

| Model | Tabele | Funkcije |
|-------|--------|----------|
| **💰 Finansije** | v3_finansije | Predikcija iznosa, tipa, analiza trendova, anomalije |
| **🚗 Vozila** | v3_vozila | Predikcija zdravlja vozila, održavanje |
| **⛽ Gorivo** | v3_gorivo | Potrošnja goriva, efikasnost |
| **👥 Putnici** | v3_finansije, v3_zahtevi | Churn prediction, LTV, segmentacija |
| **📋 Zahtevi** | v3_zahtevi | Predikcija broja zahteva, optmizacija |
| **🧠 Znanje** | Sve tabele | AI asistent za bazu podataka (Gemini + lokalno)

## Setup:

1. Instaliraj dependecies:
```bash
cd ml-service
pip install -r requirements.txt
```

2. Podesi environment:
```bash
cp .env.example .env
# Dodaj svoj SUPABASE_KEY u .env
```

3. Treniraj model:
```bash
python training/train.py
```

4. Pokreni API:
```bash
python api/main.py
```

API će biti dostupan na http://localhost:8000

## API Endpointi po Modelima:

### 💰 Finansije (`/financial/*`)
- `GET /health` - Status modela
- `POST /predict/amount` - Predikcija iznosa
- `POST /predict/type` - Predikcija tipa (prihod/rashod)
- `GET /analyze/trends` - Analiza trendova
- `GET /detect/anomalies` - Detekcija anomalija
- `GET /predict/trends?days_ahead=7` - Time series predikcija
- `POST /train` - Retrain modela

### 🚗 Vozila (`/vozilo/*`)
- `GET /health` - Status modela
- `GET /predict/all` - Sve predikcije za vozila
- `POST /train` - Retrain modela

### ⛽ Gorivo (`/gorivo/*`)
- `GET /health` - Status modela
- `GET /predict` - Predikcija potrošnje
- `POST /train` - Retrain modela

### 👥 Putnici (`/putnik/*`)
- `GET /health` - Status modela
- `GET /predict/all` - Churn, LTV, segmentacija
- `POST /train` - Retrain modela

### 📋 Zahtevi (`/zahtevi/*`)
- `GET /health` - Status modela
- `GET /predict/next-week` - Predikcija za narednu nedelju
- `POST /train` - Retrain modela

### 🧠 Znanje (`/znanje/*`)
- `GET /health` - Status i broj učitanih tabela
- `POST /ask` - Postavi pitanje o bazi podataka
- `GET /search` - Pretraga znanja

### Globalni Endpointi
- `GET /` - Root info
- `GET /health` - Glavni health check (finansije)
- `GET /models/status` - Status svih 6 modela
- `POST /auto-train` - Automatski trenira SVE modele
- `POST /retrain-all` - Ponovo trenira sve od nule

## Kako model uči:

Svi modeli uče **isključivo** iz Supabase podataka - bez pre-trained znanja:

| Model | Tabele | Zapisi | Algoritam |
|-------|--------|--------|-----------|
| 💰 Finansije | v3_finansije | ~319 | Random Forest + XGBoost Ensemble |
| 🚗 Vozila | v3_vozila | Auto | Random Forest |
| ⛽ Gorivo | v3_gorivo | Auto | Random Forest |
| 👥 Putnici | v3_finansije + v3_zahtevi | ~319 + zahtevi | Random Forest (Churn, LTV, Segments) |
| 📋 Zahtevi | v3_zahtevi | Auto | Random Forest |
| 🧠 Znanje | Sve v3_* tabele | Dinamički | Gemini API + lokalna pretraga |

**Features:**
- Generišu se automatski (vreme, korisnik, trendovi, sezone)
- Bez hardkodiranih postavki
- Auto-discovery kolona i tipova
- Pamćenje prethodnih treninga (LearningMemory)

**Čuvanje modela:**
- `models/saved/*.pkl` - Serializovani modeli
- `models/saved/memory/` - JSON istorija učenja

## Integracija sa Flutter:

```dart
// Predikcija iznosa
final response = await http.post(
  Uri.parse('http://localhost:8000/predict/amount'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({'month': 6, 'year': 2026}),
);

final data = jsonDecode(response.body);
print('Predicted amount: ${data['avg_predicted_amount']}');
```

## Struktura projekta:

```
ml-service/
├── api/
│   ├── main.py                 # FastAPI glavni fajl + ruteri
│   ├── financial_routes.py     # 💰 Finansije endpointi
│   ├── vozilo_routes.py        # 🚗 Vozila endpointi
│   ├── gorivo_routes.py        # ⛽ Gorivo endpointi
│   ├── putnik_routes.py        # 👥 Putnici endpointi
│   ├── zahtevi_routes.py       # 📋 Zahtevi endpointi
│   ├── znanje_routes.py        # 🧠 Znanje endpointi
│   └── realtime_listener.py    # Real-time Supabase listener
├── data/
│   ├── etl.py                  # Finansije ETL
│   ├── etl_vozilo.py           # Vozila ETL
│   ├── etl_gorivo.py           # Gorivo ETL
│   ├── etl_putnik.py           # Putnici ETL
│   ├── etl_zahtevi.py          # Zahtevi ETL
│   ├── etl_znanje.py           # Znanje ETL (sve tabele)
│   └── features.py             # Feature engineering
├── models/
│   ├── base_model.py           # Bazna klasa za sve modele
│   ├── financial_model.py      # 💰 Finansije ML model
│   ├── vozilo_model.py         # 🚗 Vozila ML model
│   ├── gorivo_model.py         # ⛽ Gorivo ML model
│   ├── putnik_model.py         # 👥 Putnici ML model
│   ├── zahtevi_model.py        # 📋 Zahtevi ML model
│   ├── znanje_model.py         # 🧠 Znanje AI model
│   ├── learning_memory.py      # Pamćenje za sve modele
│   ├── auto_features.py        # Auto-discovery feature-a
│   ├── knowledge_graph.py      # Knowledge graph za Znanje
│   └── saved/                  # Sačuvani modeli (.pkl)
├── training/
│   ├── auto_train.py           # Automatski trening svih modela
│   ├── train.py                # Manualni trening
│   └── train_vozilo.py         # Trening vozila
├── config.py                   # Konfiguracija (Supabase, API)
├── requirements.txt            # Python dependecies
├── Dockerfile                  # Docker build
└── README.md                   # Ovaj fajl
```

## Dependencies:

| Paket | Verzija | Namena |
|-------|---------|--------|
| fastapi | 0.103.1 | REST API framework |
| uvicorn | 0.23.2 | ASGI server |
| scikit-learn | 1.4.2 | ML algoritmi (Random Forest) |
| xgboost | 2.0.3 | Gradient boosting |
| prophet | 1.1.4 | Time series predikcija |
| pandas | 2.2.2 | Data manipulation |
| numpy | 1.26.4 | Numeričke operacije |
| supabase | 2.9.1 | Supabase client |
| google-generativeai | 0.8.0 | Gemini AI za Znanje |
| joblib | 1.3.2 | Model serialization |
| python-dotenv | 1.0.0 | Environment varijable |

## Model uči od nule:

- ❌ Nema pre-trained znanja
- ❌ Nema transfer learning
- ✅ Samo vaši Supabase podaci
- ✅ Full kontrola nad učenjem

## Deploy:

### Lokalno (Development)
```bash
cd ml-service
python -m venv venv
venv\Scripts\activate  # Windows
pip install -r requirements.txt
python api/main.py
# API: http://localhost:8000
```

### Ngrok (Javni tunnel za test)
```bash
ngrok http 8000
# Kopiraj URL u: lib/config/ml_config.dart
```

### Docker
```bash
docker build -t gavra-ml .
docker run -p 8000:8000 --env-file .env gavra-ml
```

### Production (Render/Railway/Heroku)
- Build command: `pip install -r requirements.txt`
- Start command: `python api/main.py`
- Port: `8000`
- Environment: `SUPABASE_URL`, `SUPABASE_KEY`, `GEMINI_API_KEY`

## Flutter Konfiguracija:

U `@c:\Users\Bojan\gavra_android\lib\config\ml_config.dart`:

```dart
class MlConfig {
  // Lokalno
  // static const baseUrl = 'http://localhost:8000';
  
  // Ngrok (za test na telefonu)
  static const baseUrl = 'https://your-ngrok-url.ngrok-free.dev';
  
  static const headers = {
    'ngrok-skip-browser-warning': 'true',
    'Content-Type': 'application/json',
  };
}
```
