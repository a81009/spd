import os
from .memory import InMemoryBackend
from .sqlite_backend import SQLiteBackend
from .cockroach_backend import CockroachBackend

def get_backend():
    kind = os.getenv("STORAGE_BACKEND", "memory").lower()
    if kind == "sqlite":
        return SQLiteBackend(os.getenv("SQLITE_PATH", "data/kv.db"))
    if kind == "cockroach":
        return CockroachBackend(os.getenv("COCKROACH_DSN"))
    return InMemoryBackend()

backend = get_backend()
