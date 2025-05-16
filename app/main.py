from fastapi import FastAPI, HTTPException, Body, status
from pydantic import BaseModel
from typing import Dict, Any

app = FastAPI(title="Distributed KV-Store – nó único")

# dicionário em memória (para já)
store: Dict[str, Any] = {}

class KVPair(BaseModel):
    data: Dict[str, Any]

@app.get("/kv", status_code=status.HTTP_200_OK)
def get_value(key: str):
    """
    GET /kv?key=myKey  → {"data":{"value":"..."}}
    """
    if key not in store:
        raise HTTPException(status_code=404, detail="Key not found")
    return {"data": {"value": store[key]}}

@app.put("/kv", status_code=status.HTTP_201_CREATED)
def put_value(body: KVPair = Body(...)):
    """
    PUT /kv  body: {"data":{"key":"k","value":"v"}}
    """
    key = body.data.get("key")
    value = body.data.get("value")
    if key is None or value is None:
        raise HTTPException(status_code=400, detail="key & value required")
    store[key] = value
    return {"detail": "Saved"}  # 201

@app.delete("/kv", status_code=status.HTTP_204_NO_CONTENT)
def delete_value(key: str):
    """
    DELETE /kv?key=myKey
    """
    if key in store:
        del store[key]
    return  # 204

@app.get("/health")
def healthcheck():
    return {"status": "ok"}
