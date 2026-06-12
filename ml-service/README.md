---
title: Gavra ML API
emoji: 🧠
colorFrom: blue
colorTo: purple
sdk: docker
pinned: false
---

# Gavra Financial ML Service

Python ML service za finansijsku analizu. Model uči isključivo iz Supabase podataka (v3_finansije) bez pre-trained znanja.

## Šta model radi:

- **Predikcija iznosa** - koliko će biti prihod/rashod
- **Predikcija tipa** - da li će biti prihod ili rashod
- **Analiza trendova** - mesečna analiza finansija

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

## API Endpointi:

### Health Check
- `GET /health` - Proveri da li je model treniran

### Predikcija
- `POST /predict/amount` - Predikcija iznosa
- `POST /predict/type` - Predikcija tipa (prihod/rashod)

### Analiza
- `POST /analyze/trends` - Analiza finansijskih trendova

### Training
- `POST /train` - Retrain model sa najnovijim podacima

## Kako model uči:

Model uči **isključivo** iz Supabase tabele `v3_finansije`:
- 319 zapisa trenutno
- Generiše features automatski (vreme, korisnik, trendovi)
- Random Forest algoritam
- Čuva naučeno znanje u `models/saved/`

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
├── data/
│   ├── etl.py              # Povlačenje podataka iz Supabase
│   └── features.py          # Feature engineering
├── models/
│   └── financial_model.py   # ML model (Random Forest)
├── training/
│   └── train.py             # Training pipeline
├── api/
│   └── main.py              # FastAPI endpointi
├── config.py                # Konfiguracija
├── requirements.txt         # Python dependecies
└── README.md               # Ovaj fajl
```

## Model uči od nule:

- ❌ Nema pre-trained znanja
- ❌ Nema transfer learning
- ✅ Samo vaši Supabase podaci
- ✅ Full kontrola nad učenjem
