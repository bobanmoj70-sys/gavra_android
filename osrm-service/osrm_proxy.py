"""Gavra OSRM reverse proxy — ČIST servis, BEZ ikakve AI/ML/neuronske logike.

Namena: jedini posao ovog procesa je da prosledi HTTP zahteve sa javnog
Tailscale Funnel URL-a (/osrm/*) ka lokalnom OSRM Docker kontejneru
(http://127.0.0.1:5000), uz proveru X-API-Key headera.

Ovo je namerno odvojeno od bilo kakvog AI/ML servisa (koji je uklonjen iz
repozitorijuma) da bi dostupnost rutiranja (ETA/optimizacija redosleda) za
vozače bila nezavisna od bilo kakvog eksperimentalnog/AI koda.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response
from fastapi.security import APIKeyHeader

load_dotenv()

ML_API_KEY = os.environ.get("ML_API_KEY")
PORT = int(os.environ.get("PORT", "8000"))
OSRM_LOCAL_URL = os.environ.get("OSRM_LOCAL_URL", "http://127.0.0.1:5000")

if not ML_API_KEY:
    raise RuntimeError("ML_API_KEY mora biti definisan (environment varijabla) radi zaštite OSRM proxy-ja")

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("gavra_osrm_proxy")

osrm_client: httpx.AsyncClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Inicijalizuje/zatvara HTTP klijent ka lokalnom OSRM kontejneru."""
    global osrm_client
    osrm_client = httpx.AsyncClient(base_url=OSRM_LOCAL_URL, timeout=30.0)
    logger.info("OSRM reverse proxy klijent inicijalizovan za %s.", OSRM_LOCAL_URL)
    yield
    if osrm_client:
        await osrm_client.aclose()
        osrm_client = None
        logger.info("OSRM reverse proxy klijent zatvoren.")


app = FastAPI(title="Gavra OSRM Proxy", lifespan=lifespan)

api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)


async def verify_api_key(request: Request, api_key: str = Depends(api_key_header)) -> bool:
    # Root health-check je dozvoljen bez ključa (koristi ga Tailscale funnel health-check).
    if request.url.path == "/":
        return True
    if api_key != ML_API_KEY:
        raise HTTPException(status_code=401, detail="Nevažeći API ključ")
    return True


app.router.dependencies.append(Depends(verify_api_key))


@app.get("/")
def read_root():
    return {"status": "active", "service": "Gavra OSRM Proxy"}


@app.api_route("/osrm/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "OPTIONS", "HEAD"])
async def osrm_proxy(request: Request, path: str):
    """Reverse proxy: Tailscale Funnel /osrm -> /osrm/* -> lokalni OSRM:5000/*"""
    if not osrm_client:
        raise HTTPException(status_code=503, detail="OSRM reverse proxy nije inicijalizovan")

    try:
        url = httpx.URL(path=f"/{path}", query=request.url.query.encode("utf-8"))
        body = await request.body()
        headers = {
            k: v
            for k, v in request.headers.items()
            if k.lower() not in ("host", "content-length", "x-api-key")
        }

        rp_resp = await osrm_client.request(
            method=request.method,
            url=url,
            headers=headers,
            content=body,
        )
        return Response(
            content=rp_resp.content,
            status_code=rp_resp.status_code,
            media_type=rp_resp.headers.get("content-type"),
        )
    except httpx.RequestError as e:
        logger.error("OSRM proxy greška: %s", e)
        raise HTTPException(status_code=502, detail=f"OSRM nije dostupan: {e}") from e
    except Exception as e:  # noqa: BLE001
        logger.error("Neočekivana OSRM proxy greška: %s", e)
        raise HTTPException(status_code=500, detail=f"OSRM proxy greška: {e}") from e


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=PORT)
