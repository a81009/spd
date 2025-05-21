import os, redis.asyncio as redis
from .metrics import CACHE_HIT, CACHE_MISS, CACHE_SIZE, measure_time, calculate_duration

# Definir limites para o cache Redis
MAX_CACHE_KEYS = int(os.getenv("MAX_CACHE_KEYS", "10000"))  # Limite de 10,000 chaves por padrão
MAX_CACHE_MEMORY_MB = int(os.getenv("MAX_CACHE_MEMORY_MB", "100"))  # Limite de 100MB por padrão

_redis = redis.Redis(
    host=os.getenv("REDIS_HOST", "redis"),
    port=int(os.getenv("REDIS_PORT", 6379)),
    decode_responses=True,
)

# Configurar limites de memória no Redis durante a inicialização
async def configure_redis_limits():
    try:
        # Definir o limite máximo de memória (em bytes)
        max_memory_bytes = MAX_CACHE_MEMORY_MB * 1024 * 1024
        await _redis.config_set('maxmemory', str(max_memory_bytes))
        
        # Definir política de evicção para remover chaves quando o limite for atingido
        # allkeys-lru: remove as chaves menos recentemente usadas quando a memória estiver cheia
        await _redis.config_set('maxmemory-policy', 'allkeys-lru')
        
        print(f"Redis configurado com limite de memória: {MAX_CACHE_MEMORY_MB}MB, política: allkeys-lru")
    except Exception as e:
        print(f"Aviso: Não foi possível configurar limites Redis: {str(e)}")

# Inicializar as configurações de limites
import asyncio
asyncio.create_task(configure_redis_limits())

async def get(key: str):
    start_time = measure_time()
    value = await _redis.get(key)
    
    if value is not None:
        CACHE_HIT.inc()
    else:
        CACHE_MISS.inc()
    
    return value

async def set(key: str, value, ttl: int | None = None):
    # Verificar se já atingimos o limite de chaves antes de adicionar mais
    try:
        keys_count = await _redis.dbsize()
        if keys_count >= MAX_CACHE_KEYS:
            # Se já atingimos o limite, não adiciona nova chave
            # Podemos escolher entre não fazer nada ou remover uma chave antiga
            # Aqui, vamos confiar na política do Redis para gerenciar isso
            pass
        else:
            # Adiciona a chave normalmente
            await _redis.set(key, value, ex=ttl)
    except Exception:
        # Em caso de erro, tenta definir a chave de qualquer maneira
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

async def get_cache_stats():
    """Retorna estatísticas do cache Redis"""
    try:
        stats = {
            "keys_count": await _redis.dbsize(),
            "max_keys_limit": MAX_CACHE_KEYS,
            "memory_used_bytes": await _redis.info("memory").get("used_memory", 0),
            "max_memory_bytes": MAX_CACHE_MEMORY_MB * 1024 * 1024,
            "hit_rate": CACHE_HIT._value.get() / (CACHE_HIT._value.get() + CACHE_MISS._value.get()) * 100 if (CACHE_HIT._value.get() + CACHE_MISS._value.get()) > 0 else 0
        }
        return stats
    except Exception as e:
        return {"error": str(e)}
