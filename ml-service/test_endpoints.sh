#!/usr/bin/env bash
# Test svi endpointi - Copy/paste u terminal

BASE_URL="http://localhost:8000"
API_KEY="your-api-key-here"

echo "=== GAVRA AI - ENDPOINT TEST SUITE ==="
echo ""

echo "1️⃣  Health Check"
curl -X GET "$BASE_URL/" | jq .

echo ""
echo "2️⃣  Živi logovi"
curl -X GET "$BASE_URL/logs" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "3️⃣  Autoencoder - Osnovna anomalija detektuje"
curl -X GET "$BASE_URL/neural" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "4️⃣  Živi tok razmišljanja mreže"
curl -X GET "$BASE_URL/neural/thoughts" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "5️⃣  Entity Embeddings - Naučene veze"
curl -X GET "$BASE_URL/neural/relations" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "6️⃣  🆕 TEMPORAL - Trend anomalije"
curl -X GET "$BASE_URL/neural/temporal" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "7️⃣  🆕 CROSS-TABLE - FK veze i kontekst anomalije"
curl -X GET "$BASE_URL/neural/cross-table" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "8️⃣  🆕 FEATURE IMPORTANCE - Koja kolona je kriva?"
curl -X GET "$BASE_URL/neural/importance" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "9️⃣  🆕 USER FEEDBACK - Pošalji povratnu info"
curl -X POST "$BASE_URL/neural/feedback" \
  -H "x-api-key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "table": "orders",
    "source_id": "12345",
    "is_anomaly": false,
    "user_note": "Normalno za tog korisnika"
  }' | jq .

echo ""
echo "🔟 FEEDBACK SUMMARY - Pregled korisnikove povratne info"
curl -X GET "$BASE_URL/neural/feedback-summary" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "🔄 RESYNC - Ručno osvežavanje učenja"
curl -X POST "$BASE_URL/resync" \
  -H "x-api-key: $API_KEY" | jq .

echo ""
echo "✅ Svi testovi završeni!"
