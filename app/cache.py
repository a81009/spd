import os, redis.asyncio as redis
from .metrics import CACHE_HIT, CACHE_MISS, CACHE_SIZE, measure_time, calculate_duration

_redis = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True,
)

async def get(key: str):
    start_time = measure_time()
    value = await _redis.get(key)
    
    if value is not None:
        CACHE_HIT.inc()
    else:
        CACHE_MISS.inc()
    
    return value

async def set(key: str, value, ttl: int | None = None):
    await _redis.set(key, value, ex=ttl)
    # Atualizar métrica de tamanho estimado do cache periodicamente
    if CACHE_SIZE._value.get() % 10 == 0:  # Atualiza a cada 10 operações para reduzir overhead
        try:
            keys_count = await _redis.dbsize()
            CACHE_SIZE.set(keys_count)
        except:
            pass  # Silencia erros na coleta de métricas

async def delete(key: str):
    await _redis.delete(key)

async def get_health():
    """Verifica a saúde da conexão com o Redis"""
    try:
        await _redis.ping()
        return True
    except Exception:
        return False
