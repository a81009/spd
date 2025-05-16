from typing import Any, Optional
from .base import KVBackend

class InMemoryBackend(KVBackend):
    def __init__(self) -> None:
        self._store: dict[str, Any] = {}

    async def put(self, key, value): self._store[key] = value
    async def get(self, key): return self._store.get(key)
    async def delete(self, key): self._store.pop(key, None)

