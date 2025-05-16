# app/main.py
import asyncio
from typing import Any, Dict

from fastapi import FastAPI, HTTPException, Body, status
from pydantic import BaseModel

# camadas internas (criadas nos passos anteriores)
from .storage import backend          # ↔ Cockroach ou outro backend
from .cache import get as cache_get   # ↔ Redis
from .cache import set as cache_set
from .cache import delete as cache_del
from .mq import mq                    # ↔ RabbitMQ producer

CACHE_TTL_SECONDS = 300               # 5 min de cache

app = FastAPI(title="Distributed KV-Store")

class KVPair(BaseModel):
    data: Dict[str, Any]


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
    value = await backend.get(key)
    if value is None:
        raise HTTPException(status_code=404, detail="Key not found")

    # 3. grava em cache de forma assíncrona (não bloqueia resposta)
    asyncio.create_task(cache_set(key, value, CACHE_TTL_SECONDS))
    return {"data": {"value": value}}


@app.put("/kv", status_code=status.HTTP_202_ACCEPTED)
async def put_value(body: KVPair = Body(...)):
    """
    PUT /kv  body: {"data":{"key":<foo>,"value":<bar>}}
    Produz mensagem na fila “add_key” (processada pelo consumer).
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
    Envia para fila “del_key” e remove da cache.
    """
    await mq.send("del_key", {"key": key})
    asyncio.create_task(cache_del(key))
    return {"detail": "queued"}


@app.get("/health")
async def healthcheck():
    """
    Verificação simples do backend.
    (Podes expandir com checks a Redis e RabbitMQ se quiseres.)
    """
    try:
        await backend.put("_probe", "_ok")
        await backend.delete("_probe")
        return {"status": "ok"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"backend error: {exc}")
