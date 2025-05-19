"""
Métricas de monitoramento para o consumer do sistema distribuído.
"""
import time
from prometheus_client import Counter, Histogram, Gauge, start_http_server

# Métricas para processamento de mensagens
MESSAGES_PROCESSED = Counter(
    'kv_consumer_messages_processed_total', 
    'Total de mensagens processadas',
    ['queue', 'status']
)

PROCESSING_TIME = Histogram(
    'kv_consumer_processing_seconds', 
    'Tempo de processamento de mensagens',
    ['queue', 'operation'],
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 0.75, 1.0)
)

# Métricas para database operations
DB_OPERATION_COUNT = Counter(
    'kv_consumer_db_operations_total', 
    'Total de operações no banco de dados',
    ['operation', 'status']
)

# Métricas para cache operations
CACHE_OPERATION_COUNT = Counter(
    'kv_consumer_cache_operations_total', 
    'Total de operações no cache',
    ['operation', 'status']
)

# Estado do consumer
CONSUMER_STATUS = Gauge(
    'kv_consumer_status', 
    'Estado do consumer (1=healthy, 0=unhealthy)'
)

def set_consumer_healthy():
    """Marca o consumer como saudável"""
    CONSUMER_STATUS.set(1)

def set_consumer_unhealthy():
    """Marca o consumer como não saudável"""
    CONSUMER_STATUS.set(0)

def start_metrics_server(port=8000):
    """Inicia um servidor HTTP para expor métricas"""
    start_http_server(port)
    print(f"✅ Servidor de métricas iniciado na porta {port}")

def measure_time():
    """Retorna o tempo atual para medição de duração"""
    return time.time()

def calculate_duration(start_time):
    """Calcula a duração desde start_time"""
    return time.time() - start_time 