FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/ ./api/
COPY data/ ./data/
COPY models/ ./models/
COPY training/ ./training/
COPY services/ ./services/
COPY config.py .

RUN mkdir -p models/saved logs

ENV PORT=7860
ENV PYTHONUNBUFFERED=1

EXPOSE 7860

CMD uvicorn api.main:app --host 0.0.0.0 --port ${PORT}
