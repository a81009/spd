# app/main.py
import asyncio
import signal
import os
from typing import Any, Dict

from fastapi import FastAPI, HTTPException, Body, status, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from prometheus_client import make_asgi_app

# camadas internas (criadas nos passos anteriores)
from .storage import backend          # ↔ Cockroach ou outro backend
from .cache import get as cache_get   # ↔ Redis
from .cache import set as cache_set
from .cache import delete as cache_del
from .cache import get_cache_stats    # ↔ Estatísticas do Redis
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

# Interface web HTML para a API
@app.get("/", response_class=HTMLResponse)
async def root():
    # Buscar o arquivo index.html na raiz do projeto
    try:
        # Tentar primeiro um caminho relativo à execução
        if os.path.exists("./index.html"):
            with open("./index.html", "r", encoding="utf-8") as f:
                return f.read()
        # Tentar um caminho relativo ao diretório do projeto
        elif os.path.exists("/app/index.html"):
            with open("/app/index.html", "r", encoding="utf-8") as f:
                return f.read()
        # Se não encontrar, usar o HTML hardcoded como fallback
        else:
            print("WARNING: index.html not found, using fallback HTML")
            return """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Key-Value Store API Interface</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        h1 {
            color: #333;
            text-align: center;
        }
        .card {
            background-color: white;
            padding: 20px;
            margin: 15px 0;
            border-radius: 8px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
        }
        .operation-title {
            color: #444;
            margin-top: 0;
        }
        .form-group {
            margin-bottom: 15px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            font-weight: bold;
        }
        input[type="text"] {
            width: 100%;
            padding: 8px;
            border: 1px solid #ddd;
            border-radius: 4px;
            box-sizing: border-box;
        }
        button {
            background-color: #4CAF50;
            color: white;
            border: none;
            padding: 10px 15px;
            border-radius: 4px;
            cursor: pointer;
            font-weight: bold;
        }
        button:hover {
            background-color: #45a049;
        }
        .response {
            min-height: 50px;
            border: 1px solid #ddd;
            border-radius: 4px;
            padding: 10px;
            background-color: #f9f9f9;
            white-space: pre-wrap;
            margin-top: 10px;
        }
        .put-button { background-color: #2196F3; }
        .put-button:hover { background-color: #0b7dda; }
        .get-button { background-color: #4CAF50; }
        .get-button:hover { background-color: #45a049; }
        .delete-button { background-color: #f44336; }
        .delete-button:hover { background-color: #d32f2f; }
    </style>
</head>
<body>
    <h1>Key-Value Store API Interface</h1>
    
    <!-- PUT Operation -->
    <div class="card">
        <h2 class="operation-title">Add or Update Key-Value</h2>
        <div class="form-group">
            <label for="putKey">Key:</label>
            <input type="text" id="putKey" placeholder="Enter key">
        </div>
        <div class="form-group">
            <label for="putValue">Value:</label>
            <input type="text" id="putValue" placeholder="Enter value">
        </div>
        <button class="put-button" onclick="putKeyValue()">PUT</button>
        <div class="response" id="putResponse">Response will appear here...</div>
    </div>
    
    <!-- GET Operation -->
    <div class="card">
        <h2 class="operation-title">Get Value by Key</h2>
        <div class="form-group">
            <label for="getKey">Key:</label>
            <input type="text" id="getKey" placeholder="Enter key">
        </div>
        <button class="get-button" onclick="getKeyValue()">GET</button>
        <div class="response" id="getResponse">Response will appear here...</div>
    </div>
    
    <!-- DELETE Operation -->
    <div class="card">
        <h2 class="operation-title">Delete Key-Value</h2>
        <div class="form-group">
            <label for="deleteKey">Key:</label>
            <input type="text" id="deleteKey" placeholder="Enter key">
        </div>
        <button class="delete-button" onclick="deleteKeyValue()">DELETE</button>
        <div class="response" id="deleteResponse">Response will appear here...</div>
    </div>

    <script>
        // API endpoint (adjust if needed)
        const API_URL = 'http://localhost/kv';
        
        // PUT operation
        async function putKeyValue() {
            const key = document.getElementById('putKey').value.trim();
            const value = document.getElementById('putValue').value.trim();
            const responseElement = document.getElementById('putResponse');
            
            if (!key || !value) {
                responseElement.textContent = 'Error: Both key and value are required';
                return;
            }
            
            try {
                responseElement.textContent = 'Sending request...';
                
                const response = await fetch(API_URL, {
                    method: 'PUT',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        data: {
                            key: key,
                            value: value
                        }
                    })
                });
                
                const data = await response.json();
                responseElement.textContent = JSON.stringify(data, null, 2);
            } catch (error) {
                responseElement.textContent = `Error: ${error.message}`;
            }
        }
        
        // GET operation
        async function getKeyValue() {
            const key = document.getElementById('getKey').value.trim();
            const responseElement = document.getElementById('getResponse');
            
            if (!key) {
                responseElement.textContent = 'Error: Key is required';
                return;
            }
            
            try {
                responseElement.textContent = 'Sending request...';
                
                const response = await fetch(`${API_URL}?key=${encodeURIComponent(key)}`, {
                    method: 'GET'
                });
                
                const data = await response.json();
                responseElement.textContent = JSON.stringify(data, null, 2);
            } catch (error) {
                responseElement.textContent = `Error: ${error.message}`;
            }
        }
        
        // DELETE operation
        async function deleteKeyValue() {
            const key = document.getElementById('deleteKey').value.trim();
            const responseElement = document.getElementById('deleteResponse');
            
            if (!key) {
                responseElement.textContent = 'Error: Key is required';
                return;
            }
            
            try {
                responseElement.textContent = 'Sending request...';
                
                const response = await fetch(`${API_URL}?key=${encodeURIComponent(key)}`, {
                    method: 'DELETE'
                });
                
                const data = await response.json();
                responseElement.textContent = JSON.stringify(data, null, 2);
            } catch (error) {
                responseElement.textContent = `Error: ${error.message}`;
            }
        }
    </script>
</body>
</html>
"""
    except Exception as e:
        print(f"ERROR loading index.html: {str(e)}")
        return "<h1>Error loading interface</h1><p>Check server logs for details.</p>"

# ---------- ROTAS ----------
@app.get("/kv", status_code=status.HTTP_200_OK)
async def get_value(key: str):
    """
    GET /kv?key=<foo> → {"data":{"value":<bar>,"source":"cache|database"}}
    1. Tenta cache Redis
    2. Vai ao backend se falhar ou não existir
    3. (lazy write-back) grava em cache
    """
    # 1. cache
    try:
        cached = await cache_get(key)
        if cached is not None:
            CACHE_HIT.inc()
            return {"data": {"value": cached, "source": "cache"}}
    except Exception:
        pass  # Redis indisponível – continua
    
    CACHE_MISS.inc()
    
    # 2. backend
    start_time = asyncio.get_event_loop().time()
    value = await backend.get(key)
    db_latency = asyncio.get_event_loop().time() - start_time
    DB_OPERATION_LATENCY.labels(operation="get").observe(db_latency)
    
    if value is None:
        raise HTTPException(status_code=404, detail="Key not found")

    # 3. grava em cache de forma assíncrona (não bloqueia resposta)
    asyncio.create_task(cache_set(key, value, CACHE_TTL_SECONDS))
    return {"data": {"value": value, "source": "database"}}


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
    # Enviar para a fila e remover do cache
    await mq.send("del_key", {"key": key})
    asyncio.create_task(cache_del(key))
    return {"detail": "queued"}


@app.get("/cache/stats", status_code=status.HTTP_200_OK)
async def cache_statistics():
    """
    GET /cache/stats
    Retorna estatísticas sobre o uso do cache Redis
    """
    stats = await get_cache_stats()
    return stats


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
