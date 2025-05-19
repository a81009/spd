"""
Métricas de monitoramento para o sistema de KV Store distribuído.
Usa prometheus-client para coletar métricas de performance e disponibilidade.
"""
from prometheus_client import Counter, Histogram, Gauge, Summary
import time

# Métricas para API
REQUEST_COUNT = Counter(
    'kv_request_total', 
    'Total de requisições processadas',
    ['method', 'endpoint', 'status_code']
)

REQUEST_LATENCY = Histogram(
    'kv_request_latency_seconds', 
    'Latência das requisições HTTP',
    ['method', 'endpoint'],
    buckets=(0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0, 2.5, 5.0, 7.5, 10.0)
)

# Métricas para cache
CACHE_HIT = Counter('kv_cache_hit_total', 'Total de hits no cache')
CACHE_MISS = Counter('kv_cache_miss_total', 'Total de misses no cache')
CACHE_SIZE = Gauge('kv_cache_size', 'Número estimado de chaves em cache')

# Métricas para storage
DB_OPERATION_LATENCY = Histogram(
    'kv_db_operation_latency_seconds', 
    'Latência das operações de banco de dados',
    ['operation'],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0)
)

# Métricas para MQ
MESSAGE_QUEUE_SIZE = Gauge(
    'kv_mq_queue_size', 
    'Tamanho das filas de mensagem',
    ['queue']
)
MESSAGE_PROCESSING_TIME = Summary(
    'kv_mq_processing_seconds', 
    'Tempo de processamento de mensagens',
    ['queue']
)

# Funções auxiliares para medir tempo de execução
def measure_time():
    return time.time()

def calculate_duration(start_time):
    return time.time() - start_time

class MetricsMiddleware:
    """Middleware para FastAPI que registra métricas para todas as requisições."""
    
    async def __call__(self, request, call_next):
        method = request.method
        path = request.url.path
        
        start_time = measure_time()
        
        response = await call_next(request)
        
        duration = calculate_duration(start_time)
        status_code = response.status_code
        
        REQUEST_COUNT.labels(method=method, endpoint=path, status_code=status_code).inc()
        REQUEST_LATENCY.labels(method=method, endpoint=path).observe(duration)
        
        return response 