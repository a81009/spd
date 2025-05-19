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
    
    def __init__(self, app):
        self.app = app
    
    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
            
        method = scope.get("method", "")
        path = scope.get("path", "")
        
        start_time = measure_time()
        
        # Captura o status code usando um wrapper para send
        status_code = [200]  # Default
        
        async def send_wrapper(message):
            if message["type"] == "http.response.start":
                status_code[0] = message["status"]
            await send(message)
        
        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            duration = calculate_duration(start_time)
            REQUEST_COUNT.labels(
                method=method, 
                endpoint=path, 
                status_code=status_code[0]
            ).inc()
            REQUEST_LATENCY.labels(
                method=method, 
                endpoint=path
            ).observe(duration) 