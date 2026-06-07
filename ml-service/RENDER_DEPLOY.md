# Deploy na Render.com

## Preduslovi

1. GitHub nalog
2. Render.com nalog (besplatno)

## Koraci za deploy

### 1. Push na GitHub

```bash
cd ml-service
git init
git add .
git commit -m "Initial ML service"
git remote add origin https://github.com/TVOJ_USERNAME/gavra-ml-service.git
git push -u origin main
```

### 2. Kreiraj Web Service na Render

1. Idi na https://dashboard.render.com
2. Klikni "New +" → "Web Service"
3. Poveži sa GitHub repo (gavra-ml-service)
4. Podesi:
   - **Name**: gavra-ml-service
   - **Environment**: Python 3
   - **Build Command**: `pip install -r requirements.txt && python training/train.py`
   - **Start Command**: `uvicorn api.main:app --host 0.0.0.0 --port $PORT`
   - **Plan**: Free

5. Klikni "Advanced" → dodaj Environment Variables:
   ```
   SUPABASE_URL=https://gjtabtwudbrmfeyjiicu.supabase.co
   SUPABASE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdqdGFidHd1ZGJybWZleWppaWN1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc0NzQzNjI5MiwiZXhwIjoyMDYzMDEyMjkyfQ.BrwnYQ6TWGB1BrmwaE0YnhMC5wMlBRdZUs1xv2dY5r4
   ```

6. Klikni "Create Web Service"

### 3. Čekaj deploy

- Render će automatski:
  1. Instalirati dependencije
  2. Trenirati ML model (python training/train.py)
  3. Pokrenuti API server

- Status možeš pratiti na Render dashboard-u

### 4. Testiraj API

Kada je deploy završen, dobićeš URL:
```
https://gavra-ml-service.onrender.com
```

Testiraj:
```bash
curl https://gavra-ml-service.onrender.com/health
```

Odgovor:
```json
{
  "status": "healthy",
  "model_trained": true,
  "timestamp": "..."
}
```

### 5. Poveži sa Flutter aplikacijom

U Flutter kodu, promeni URL:
```dart
const String ML_API_URL = 'https://gavra-ml-service.onrender.com';
```

## Ograničenja besplatnog plana

- **Spavanje**: Posle 15 min neaktivnosti, service "zaspava"
- **Cold start**: Prvi poziv posle spavanja traje 30-60 sekundi
- **Disk**: Nema persistent storage (model se trenira prilikom svakog deploy-a)

## Retraining

Da re-treniraš model:
1. Pushuj nove izmene na GitHub
2. Render će automatski re-deploy
3. Model će se ponovo trenirati

ILI manualno:
1. Idi na Render dashboard
2. Klikni "Manual Deploy" → "Deploy latest commit"
