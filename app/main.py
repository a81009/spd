# app/main.py
import asyncio
import signal
from typing import Any, Dict

from fastapi import FastAPI, HTTPException, Body, status, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from prometheus_client import make_asgi_app

# camadas internas (criadas nos passos anteriores)
from .storage import backend          # ↔ Cockroach ou outro backend
from .cache import get as cache_get   # ↔ Redis
from .cache import set as cache_set
from .cache import delete as cache_del
from .mq import mq                    # ↔ RabbitMQ producer
from .metrics import MetricsMiddleware, CACHE_HIT, CACHE_MISS, DB_OPERATION_LATENCY
from .health_check import full_health_check, quick_health_check

CACHE_TTL_SECONDS = 300               # 5 min de cache

app = FastAPI(title="Distributed KV-Store")

# Configurar CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Adicionar middleware de métricas
app.add_middleware(MetricsMiddleware)

# Expor métricas para Prometheus
metrics_app = make_asgi_app()
app.mount("/metrics", metrics_app)

class KVPair(BaseModel):
    data: Dict[str, Any]

# Configurar fechamento adequado da conexão RabbitMQ quando a aplicação for encerrada
@app.on_event("shutdown")
async def shutdown_event():
    await mq.close()
    print("RabbitMQ connection closed")

# ---------- ROTAS ----------
@app.get("/kv", status_code=status.HTTP_200_OK)
async def get_value(key: str):
    """
    GET /kv?key=<foo> → {"data":{"value":<bar>}}
    1. Tenta cache Redis
    2. Vai ao backend se falhar ou não existir
    3. (lazy write-back) grava em cache
    """
    # 1. cache
    try:
        cached = await cache_get(key)
        if cached is not None:
            return {"data": {"value": cached}}
    except Exception:
        pass  # Redis indisponível – continua

    # 2. backend
    start_time = asyncio.get_event_loop().time()
    value = await backend.get(key)
    db_latency = asyncio.get_event_loop().time() - start_time
    DB_OPERATION_LATENCY.labels(operation="get").observe(db_latency)
    
    if value is None:
        raise HTTPException(status_code=404, detail="Key not found")

    # 3. grava em cache de forma assíncrona (não bloqueia resposta)
    asyncio.create_task(cache_set(key, value, CACHE_TTL_SECONDS))
    return {"data": {"value": value}}


@app.put("/kv", status_code=status.HTTP_202_ACCEPTED)
async def put_value(body: KVPair = Body(...)):
    """
    PUT /kv  body: {"data":{"key":<foo>,"value":<bar>}}
    Produz mensagem na fila "add_key" (processada pelo consumer).
    """
    key = body.data.get("key")
    value = body.data.get("value")
    if key is None or value is None:
        raise HTTPException(status_code=400, detail="key & value required")

    await mq.send("add_key", {"key": key, "value": value})
    # invalida cache localmente para coerência rápida
    asyncio.create_task(cache_del(key))
    return {"detail": "queued"}


@app.delete("/kv", status_code=status.HTTP_202_ACCEPTED)
async def delete_value(key: str):
    """
    DELETE /kv?key=<foo>
    Envia para fila "del_key" e remove da cache.
    """
    await mq.send("del_key", {"key": key})
    asyncio.create_task(cache_del(key))
    return {"detail": "queued"}


@app.get("/health")
async def healthcheck():
    """
    Verificação completa de saúde do sistema.
    Verifica backend, cache e sistema de mensageria.
    """
    return await full_health_check()


@app.get("/health/live", status_code=status.HTTP_200_OK)
async def liveness_check():
    """
    Verificação rápida para Kubernetes liveness probe.
    Apenas verifica se o sistema está respondendo.
    """
    is_alive = await quick_health_check()
    if not is_alive:
        raise HTTPException(status_code=503, detail="Service unavailable")
    return {"status": "alive"}


@app.get("/health/ready", status_code=status.HTTP_200_OK)
async def readiness_check():
    """
    Verificação de prontidão para Kubernetes readiness probe.
    Verifica se todos os componentes estão prontos para receber tráfego.
    """
    health_result = await full_health_check()
    if health_result["status"] != "healthy":
        raise HTTPException(
            status_code=503, 
            detail="Service not ready", 
            headers={"Retry-After": "10"}
        )
    return {"status": "ready"}
