# consumer/worker.py
import os
import asyncio
import json
import asyncpg
import redis.asyncio as redis
import aio_pika
import signal
from .metrics import (
    measure_time, 
    calculate_duration, 
    MESSAGES_PROCESSED, 
    PROCESSING_TIME, 
    DB_OPERATION_COUNT, 
    CACHE_OPERATION_COUNT,
    set_consumer_healthy, 
    set_consumer_unhealthy, 
    start_metrics_server
)

# Porta para expor métricas do consumer
METRICS_PORT = int(os.getenv("METRICS_PORT", 9090))

# Flag para controlar estado de saúde
is_healthy = False

async def main() -> None:
    global is_healthy
    
    try:
        # Inicia o servidor de métricas numa porta diferente do API
        start_metrics_server(METRICS_PORT)
    
        # ---------- ligações ----------
        dsn = os.getenv("COCKROACH_DSN")
        db: asyncpg.Pool = await asyncpg.create_pool(dsn=dsn)

        # cria BD/tabela se ainda não existir
        async with db.acquire() as conn:
            await conn.execute(
                """
                CREATE TABLE IF NOT EXISTS kv_store (
                    key   STRING PRIMARY KEY,
                    value STRING
                );
                """
            )

        cache = redis.Redis(
            host=os.getenv("REDIS_HOST", "redis"), decode_responses=True
        )

        mq_url = f"amqp://admin:admin@{os.getenv('MQ_HOST', 'rabbitmq')}:5672"
        conn_mq = await aio_pika.connect_robust(mq_url)
        ch = await conn_mq.channel()
        add_q = await ch.declare_queue("add_key", durable=True)
        del_q = await ch.declare_queue("del_key", durable=True)

        # Marca o consumer como saudável após conectar a todos os recursos
        is_healthy = True
        set_consumer_healthy()

        # ---------- handlers ----------
        async def handle_add(msg: aio_pika.IncomingMessage) -> None:
            start_time = measure_time()
            async with msg.process():
                try:
                    data = json.loads(msg.body)
                    key, value = data["key"], data["value"]
                    
                    # Operação no banco de dados
                    try:
                        db_start = measure_time()
                        await db.execute(
                            "UPSERT INTO kv_store (key, value) VALUES ($1, $2)", key, value
                        )
                        db_duration = calculate_duration(db_start)
                        PROCESSING_TIME.labels(queue="add_key", operation="db_write").observe(db_duration)
                        DB_OPERATION_COUNT.labels(operation="upsert", status="success").inc()
                    except Exception as e:
                        DB_OPERATION_COUNT.labels(operation="upsert", status="error").inc()
                        raise e
                    
                    # Operação no cache
                    try:
                        cache_start = measure_time()
                        await cache.set(key, value)
                        cache_duration = calculate_duration(cache_start)
                        PROCESSING_TIME.labels(queue="add_key", operation="cache_write").observe(cache_duration)
                        CACHE_OPERATION_COUNT.labels(operation="set", status="success").inc()
                    except Exception:
                        CACHE_OPERATION_COUNT.labels(operation="set", status="error").inc()
                        # Não re-levanta a exceção pois o cache falhar não impede o funcionamento
                    
                    # Métricas finais
                    total_duration = calculate_duration(start_time)
                    PROCESSING_TIME.labels(queue="add_key", operation="total").observe(total_duration)
                    MESSAGES_PROCESSED.labels(queue="add_key", status="success").inc()
                except Exception as e:
                    MESSAGES_PROCESSED.labels(queue="add_key", status="error").inc()
                    print(f"Erro ao processar mensagem add_key: {e}")

        async def handle_del(msg: aio_pika.IncomingMessage) -> None:
            start_time = measure_time()
            async with msg.process():
                try:
                    key = json.loads(msg.body)["key"]
                    
                    # Operação no banco de dados
                    try:
                        db_start = measure_time()
                        await db.execute("DELETE FROM kv_store WHERE key = $1", key)
                        db_duration = calculate_duration(db_start)
                        PROCESSING_TIME.labels(queue="del_key", operation="db_delete").observe(db_duration)
                        DB_OPERATION_COUNT.labels(operation="delete", status="success").inc()
                    except Exception as e:
                        DB_OPERATION_COUNT.labels(operation="delete", status="error").inc()
                        raise e
                    
                    # Operação no cache
                    try:
                        cache_start = measure_time()
                        await cache.delete(key)
                        cache_duration = calculate_duration(cache_start)
                        PROCESSING_TIME.labels(queue="del_key", operation="cache_delete").observe(cache_duration)
                        CACHE_OPERATION_COUNT.labels(operation="delete", status="success").inc()
                    except Exception:
                        CACHE_OPERATION_COUNT.labels(operation="delete", status="error").inc()
                        # Não re-levanta a exceção pois o cache falhar não impede o funcionamento
                    
                    # Métricas finais
                    total_duration = calculate_duration(start_time)
                    PROCESSING_TIME.labels(queue="del_key", operation="total").observe(total_duration)
                    MESSAGES_PROCESSED.labels(queue="del_key", status="success").inc()
                except Exception as e:
                    MESSAGES_PROCESSED.labels(queue="del_key", status="error").inc()
                    print(f"Erro ao processar mensagem del_key: {e}")

        # ---------- start consuming ----------
        await add_q.consume(handle_add)
        await del_q.consume(handle_del)
        print("✅ consumer à escuta…")
        
        # Setup Graceful Shutdown
        loop = asyncio.get_event_loop()
        
        def handle_signals():
            global is_healthy
            is_healthy = False
            set_consumer_unhealthy()
            print("⚠️ Sinal de término recebido. Encerrando graciosamente...")
            loop.stop()
        
        # Register signal handlers
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, handle_signals)
            
        # Health check HTTP server in separate task
        asyncio.create_task(start_health_server())
            
        # Block until we're stopped
        await asyncio.Future()
        
    except Exception as e:
        # Marca como não saudável se houver falha na inicialização
        is_healthy = False
        set_consumer_unhealthy()
        print(f"❌ Erro crítico no consumer: {e}")
        raise

async def start_health_server():
    """
    Inicia um servidor HTTP simples para health checks do consumer.
    Pode ser usado por Docker/Kubernetes para health probes.
    """
    from aiohttp import web
    
    async def health_handler(request):
        if is_healthy:
            return web.Response(text='{"status":"healthy"}', content_type='application/json')
        else:
            return web.Response(text='{"status":"unhealthy"}', status=503, content_type='application/json')
    
    app = web.Application()
    app.router.add_get('/health', health_handler)
    
    health_port = int(os.getenv("HEALTH_PORT", 8080))
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', health_port)
    await site.start()
    print(f"✅ Servidor de health check iniciado na porta {health_port}")

if __name__ == "__main__":
    asyncio.run(main())
