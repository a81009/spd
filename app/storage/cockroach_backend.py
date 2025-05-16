import asyncio
from typing import Any, Optional
import asyncpg
from .base import KVBackend

DEFAULT_DSN = "postgresql://root@cockroach1:26257/kvdb?sslmode=disable"

class CockroachBackend(KVBackend):
    def __init__(self, dsn: str = DEFAULT_DSN):
        self._dsn = dsn
        self._pool: asyncpg.Pool | None = None

    async def _get_pool(self):
        if self._pool is None:
            self._pool = await asyncpg.create_pool(dsn=self._dsn)
            async with self._pool.acquire() as conn:
                await conn.execute(
                    """CREATE TABLE IF NOT EXISTS kv_store (
                           key STRING PRIMARY KEY,
                           value STRING
                       );"""
                )
        return self._pool

    async def put(self, key, value):
        pool = await self._get_pool()
        async with pool.acquire() as conn:
            await conn.execute(
                "UPSERT INTO kv_store (key, value) VALUES ($1, $2);", key, value
            )

    async def get(self, key):
        pool = await self._get_pool()
        async with pool.acquire() as conn:
            row = await conn.fetchrow("SELECT value FROM kv_store WHERE key = $1;", key)
            return row["value"] if row else None

    async def delete(self, key):
        pool = await self._get_pool()
        async with pool.acquire() as conn:
            await conn.execute("DELETE FROM kv_store WHERE key = $1;", key)
