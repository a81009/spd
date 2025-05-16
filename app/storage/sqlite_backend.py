import aiosqlite
from typing import Any, Optional
from .base import KVBackend

class SQLiteBackend(KVBackend):
    def __init__(self, path: str = "data/kv.db"):
        self._path = path

    async def _conn(self):
        conn = await aiosqlite.connect(self._path)
        await conn.execute(
            "CREATE TABLE IF NOT EXISTS kv_store (key TEXT PRIMARY KEY, value BLOB)"
        )
        return conn

    async def put(self, key, value):
        async with await self._conn() as db:
            await db.execute(
                "INSERT INTO kv_store (key, value) VALUES (?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, value),
            )
            await db.commit()

    async def get(self, key):
        async with await self._conn() as db:
            cur = await db.execute("SELECT value FROM kv_store WHERE key = ?", (key,))
            row = await cur.fetchone()
            return row[0] if row else None

    async def delete(self, key):
        async with await self._conn() as db:
            await db.execute("DELETE FROM kv_store WHERE key = ?", (key,))
            await db.commit()
