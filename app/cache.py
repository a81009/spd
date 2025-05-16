import os, redis.asyncio as redis

_redis = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True,
)

async def get(key: str):
    return await _redis.get(key)

async def set(key: str, value, ttl: int | None = None):
    await _redis.set(key, value, ex=ttl)

async def delete(key: str):
    await _redis.delete(key)
