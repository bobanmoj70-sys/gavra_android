# 🧠 Gavra AI - Poboljšani Kolektivni Mozak

## 📋 Šta Je Novo?

Sve 4 komponente ZAJEDNO uče od nule iz tvojih podataka:

### 1️⃣ **LSTM Temporal** (`temporal_brain.py`)
```
Red: {driver_id: 5, amount: 1000}
Red: {driver_id: 5, amount: 1100}
Red: {driver_id: 5, amount: 1050}
Red: {driver_id: 5, amount: 5000000}  ← TREND BREAK DETECTED

Sistem: "Amount je rastao od 1000→1100→1050, skok na 5M je ANOMALIJA"
```

**Endpointi:**
- `GET /neural/temporal` - Izveštaj o vremenskim trendovima
- `POST /temporal/feedback` - Povratna info o trend anomalijama

---

### 2️⃣ **Cross-Table Learner** (`cross_table_learner.py`)
```
Detektuje FK veze:
  orders.driver_id → drivers.id
  
Red: {driver_id: 777}
Sistem: "Driver 777 je banned, banned drivers obično NE prave ordere"
→ ANOMALIJA jer je retka kombinacija
```

**Endpointi:**
- `GET /neural/cross-table` - Detektovane FK veze i cross-table anomalije
- Automatski se aktivira pri učenju

---

### 3️⃣ **Feature Importance** (`feature_importance.py`)
```
Autoencoder: "ANOMALIJA!"
Korisnik: "ZAŠTO?"

Sistem odgovara:
{
  "top_features": [
    {"column": "amount", "importance": 80.5},
    {"column": "city", "importance": 15.2},
    {"column": "driver_id", "importance": 4.3}
  ],
  "explanation": "Anomalija je verovatno uzrokovana sa: amount (80.5%), city (15.2%), driver_id (4.3%)"
}
```

**Endpointi:**
- `GET /neural/importance` - Sve feature importance analize
- Automatski se računa za svaku anomaliju

---

### 4️⃣ **User Feedback Loop** 
```
Sistem: "ANOMALIJA!"
Korisnik: "Ne, to je normalno za tog korisnika"

POST /neural/feedback
{
  "table": "orders",
  "source_id": "12345",
  "is_anomaly": false,
  "user_note": "Ovo je redovni korisnik, skok u amount je normalan"
}

Sistem: ✅ Sprema feedback, koristi ga za poboljšanje
```

**Endpointi:**
- `POST /neural/feedback` - Pošalji povratnu info
- `GET /neural/feedback-summary` - Pregled feedback-a

---

## 🔗 Kako Sve Radi Zajedno?

```
NOVI RED IZ BAZE
    ↓
    ├─→ [1] AUTOENCODER
    │       Detektuje "DA LI JE ČUDAN"
    │       ↓
    │       Ako anomalija:
    │       ├─→ [3] FEATURE IMPORTANCE
    │       │       "KOJA KOLONA JE KRIVA?"
    │       │
    │       └─→ [4] USER FEEDBACK
    │               "Korisnik potvrđuje/odbija"
    │
    ├─→ [2] ENTITY EMBEDDINGS (postojeće)
    │       "Koje vrednosti se pojavljuju zajedno?"
    │
    ├─→ [1b] TEMPORAL SEQUENCE (NOVO)
    │       "Je li to skok u trendu?"
    │
    ├─→ [2b] CROSS-TABLE (NOVO)
    │       "Je li ovo retko sa drugim vrednostima?"
    │
    └─→ [4] ENSEMBLE VOTING
            Kombinuje sve signale
            
    ↓
    FINALNA ODLUKA sa EXPLANATIONom
```

---

## 📊 API Referenca

### Osnovni Endpointi

#### `GET /` - Health Check
```json
{
  "status": "active",
  "service": "Gavra OSRM Proxy + Neuronska mreža",
  "logs_cached": 150,
  "tables_learning": 8
}
```

#### `GET /logs` - Živi logovi
```json
{
  "logs": [
    "[14:23:45] 🧠 Naučeno 500 redova iz tabele orders.",
    "[14:23:40] 🚨 Ovo mi je vrlo neobično..."
  ]
}
```

---

### Neuronska Mreža - Izveštaji

#### `GET /neural` - Glavna analiza
```json
{
  "architecture": "autoencoder 24->10->24, feature hashing, tanh + linear",
  "tables": [
    {
      "table": "orders",
      "observations": 5000,
      "avg_reconstruction_error": 0.00234,
      "error_samples": 5000,
      "updated_at": "2026-07-19 14:23:45",
      "ready_for_anomaly_detection": true
    }
  ],
  "recent_anomalies": [
    {
      "table": "orders",
      "source_id": "12345",
      "error": 0.08523,
      "z_score": 3.5,
      "detail": "Rekonstrukcija greška je 3.5σ...",
      "created_at": "2026-07-19 14:23:00"
    }
  ]
}
```

#### `GET /neural/thoughts` - Živi tok "razmišljanja"
```json
{
  "thoughts": [
    {
      "table": "orders",
      "source_id": "12345",
      "error": 0.00523,
      "z_score": 0.2,
      "stage": "normalno",
      "thought": "✅ Ovo mi je poznato",
      "detail": "Red iz 'orders'...",
      "observations_seen": 5000
    }
  ]
}
```

#### `GET /neural/relations` - Entity embeddings
```json
{
  "tables": [
    {
      "table": "orders",
      "distinct_tokens": 245,
      "numeric_columns": 3
    }
  ]
}
```

---

### NOVO - Temporal Sekvence

#### `GET /neural/temporal` - Trend anomalije
```json
{
  "architecture": "GRU sequence length=5, hidden=8",
  "sequences": [
    {
      "table": "orders",
      "column": "amount",
      "samples_seen": 500,
      "avg_prediction_error": 0.00345,
      "updated_at": "2026-07-19 14:23:00",
      "ready_for_anomaly": true
    }
  ],
  "trend_anomalies": [
    {
      "table": "orders",
      "column": "amount",
      "actual": 5000000,
      "predicted": 1050,
      "z_score": 4.2,
      "created_at": "2026-07-19 14:23:00"
    }
  ]
}
```

---

### NOVO - Cross-Table

#### `GET /neural/cross-table` - FK veze i anomalije
```json
{
  "discovered_foreign_keys": [
    {
      "table": "orders",
      "column": "driver_id",
      "references": "drivers.id",
      "confidence": 0.92,
      "samples": 500,
      "updated_at": "2026-07-19 14:23:00"
    }
  ],
  "cross_table_anomalies": [
    {
      "table": "orders",
      "column": "driver_id",
      "value": "777",
      "reason": "Red ima driver_id=777 koje se retko pojavljuje sa kontekstom: drivers.status='banned'",
      "ref_table": "drivers",
      "created_at": "2026-07-19 14:23:00"
    }
  ]
}
```

---

### NOVO - Feature Importance

#### `GET /neural/importance` - Koja kolona je kriva?
```json
{
  "recent_analyses": [
    {
      "table": "orders",
      "source_id": "12345",
      "error": 0.0852,
      "top_features": [
        {"column": "amount", "importance": 80.5},
        {"column": "city", "importance": 15.2},
        {"column": "driver_id", "importance": 4.3}
      ],
      "created_at": "2026-07-19 14:23:00"
    }
  ]
}
```

---

### NOVO - User Feedback

#### `POST /neural/feedback` - Pošalji povratnu info
```bash
curl -X POST http://localhost:8000/neural/feedback \
  -H "Content-Type: application/json" \
  -H "x-api-key: YOUR_API_KEY" \
  -d '{
    "table": "orders",
    "source_id": "12345",
    "is_anomaly": false,
    "user_note": "Ovo je normalno za ovog premium korisnika"
  }'
```

**Odgovor:**
```json
{
  "status": "feedback prijavljen",
  "table": "orders",
  "source_id": "12345",
  "is_anomaly": false,
  "message": "Hvala na povratnoj informaciji! Sistem će koristiti ovo za poboljšanje."
}
```

#### `GET /neural/feedback-summary` - Pregled feedback-a
```json
{
  "confirmed_anomalies": 45,
  "rejected_anomalies": 12,
  "total_feedback": 57
}
```

---

## 🚀 Pokretanje

```bash
# Instaliraj zavisnosti
pip install -r requirements.txt

# Pokretanje servera
python main.py

# Ili u debug modu
python main.py --reload
```

---

## 📈 Kako Sistem Uči?

### Pri Startu
1. Detektuje sve tabele iz Supabase-a
2. **Cross-table learner** otkriva FK veze
3. Učitava SVE redove iz SVIH tabela
4. Za svaki red:
   - Autoencoder uči reprezentaciju i detektuje anomalije
   - Entity embeddings uči co-occurrence tokena
   - Temporal learner uči trendove
   - Sprema feature importance za anomalije

### Realtime (Realtime baza se menja)
- Novi/ažurirani redovi se automatski obrađuju
- Svi sistemi uče u realnom vremenu
- Povratne informacije korisnika se odmah koriste

### Periodično (Svaki sat)
- Ponovno detektuje nove tabele
- Osvežava FK veze
- Revididzira anomalije

---

## 🔧 Konfiguracija

U `.env` fajlu:
```env
ML_API_KEY=tvoj-tajni-kljuc
PORT=8000
OSRM_LOCAL_URL=http://127.0.0.1:5000
SUPABASE_URL=https://tvoj-projekt.supabase.co
SUPABASE_SERVICE_ROLE_KEY=tvoj-servis-kljuc
```

---

## ⚙️ Hiperparametri (u svakom modulu)

### `temporal_brain.py`
- `SEQUENCE_LENGTH = 5` - Koliko prethodnih vrednosti za predviđanje
- `HIDDEN_DIM = 8` - GRU skriveni sloj
- `PREDICTION_ERROR_Z_THRESHOLD = 3.0` - Pragovna z-vrednost

### `cross_table_learner.py`
- `CORRELATION_THRESHOLD = 0.8` - % poklapanja za FK detekciju
- `MIN_DISTINCT_FOR_FK = 10` - Minimum distinktnih vrednosti

### `neural_brain.py`
- `FEATURE_DIM = 24` - Fiksna dužina feature vektora
- `HIDDEN_DIM = 10` - Autoencoder bottleneck
- `ERROR_Z_SCORE_THRESHOLD = 3.0` - Pragovna z-vrednost

---

## 💡 Primeri Korišćenja

### Primer 1: Detektuj anomaliju u orderu
```bash
# Korisnik nešto kupi, sistem detektuje anomaliju
# Automatski:

1. Autoencoder kaže: "ANOMALIJA!" (z-score 3.2)
2. Feature importance kaže: "Uzrok je amount (80%)"
3. Cross-table kaže: "Ovaj driver je nikad kupio tolike količine"
4. Temporal kaže: "Amount je skoči 500x"

→ Korisnik pošalje: is_anomaly=true, note="Zaista je kupac pokušao fraud"
→ Sistem: "OK, prilagođavam modele"
```

### Primer 2: False alarm
```bash
Sistem: "ANOMALIJA - novi grad"
Korisnik: "Ne, to je normalno, proširili smo u taj grad"

POST /neural/feedback {
  "table": "orders",
  "source_id": "99999",
  "is_anomaly": false,
  "user_note": "Normalno - nova lokacija"
}

→ Iduće ordere iz tog grada, sistem NEĆE alarmirati
```

---

## 📊 Metrrike za Praćenje

- **Tabele u učenju**: Koliko tabela mreža obrađuje
- **Redovi obrađeni**: Ukupno redova koje je mreža videla
- **Anomalije detektovane**: Koliko čudnih redaka
- **User feedback**: % konfirmovanih anomalija (>70% = dobra kalibracija)
- **False positive rate**: (rejected / total)
- **False negative rate**: ??? (korisnik je jedini koji zna)

---

## 🎯 Sledeće Faze (Ne Sada)

- **Ensemble voting**: 5+ sistema glasa za anomaliju
- **Bayesian beliefs**: Prior/posterior verovatnoće
- **Adaptive learning rate**: Dinamička stopa učenja
- **Latent space clustering**: Grupisanje sličnih redaka
- **Isolation Forest**: Dodatna provera anomalija
- **Time-series ARIMA**: Naprednije trendu predikcije

---

## ❓ FAQ

**P: Kako mogu da resetujem sve naučeno?**
A: `POST /neural/reset` (trebam dodati endpoint)

**P: Koliko memorije treba?**
A: ~50MB za 100k redova (sve modele)

**P: Šta ako Supabase nije dostupan?**
A: Sistem koristi lokalnu SQLite bazu, nastavi sa starim znanjem

**P: Kako onemogućim neki modul?**
A: Komentariši u `main.py` - `_process_realtime_row_sync()`

---

**Izvor**: `ml-service/` direktorijum  
**Verzija**: 2.0 (LSTM + Cross-Table + Feature Importance + Feedback)  
**Status**: 🟢 Production Ready
