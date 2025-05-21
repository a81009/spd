# consumer/worker.py
import os
import asyncio
import json
import asyncpg
import redis.asyncio as redis
import aio_pika
import signal
from metrics import (
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
# Recursos globais para poder fechar adequadamente
db_pool = None
redis_client = None
rabbitmq_connection = None
health_runner = None

async def main() -> None:
    global is_healthy, db_pool, redis_client, rabbitmq_connection
    
    try:
        # Inicia o servidor de métricas numa porta diferente do API
        start_metrics_server(METRICS_PORT)
    
        # ---------- ligações ----------
        dsn = os.getenv("COCKROACH_DSN")
        db_pool = await asyncpg.create_pool(dsn=dsn)

        # cria BD/tabela se ainda não existir
        async with db_pool.acquire() as conn:
            await conn.execute(
                """
                CREATE TABLE IF NOT EXISTS kv_store (
                    key   STRING PRIMARY KEY,
                    value STRING
                );
                """
            )

        redis_client = redis.Redis(
            host=os.getenv("REDIS_HOST", "redis"), decode_responses=True
        )

        mq_url = f"amqp://admin:admin@{os.getenv('MQ_HOST', 'rabbitmq')}:5672"
        rabbitmq_connection = await aio_pika.connect_robust(mq_url)
        ch = await rabbitmq_connection.channel()
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
                        await db_pool.execute(
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
                        await redis_client.set(key, value)
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
                        await db_pool.execute("DELETE FROM kv_store WHERE key = $1", key)
                        db_duration = calculate_duration(db_start)
                        PROCESSING_TIME.labels(queue="del_key", operation="db_delete").observe(db_duration)
                        DB_OPERATION_COUNT.labels(operation="delete", status="success").inc()
                    except Exception as e:
                        DB_OPERATION_COUNT.labels(operation="delete", status="error").inc()
                        raise e
                    
                    # Operação no cache
                    try:
                        cache_start = measure_time()
                        await redis_client.delete(key)
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
        
        async def cleanup_resources():
            global is_healthy, db_pool, redis_client, rabbitmq_connection, health_runner
            is_healthy = False
            set_consumer_unhealthy()
            
            # Fecha recursos na ordem inversa da abertura
            if rabbitmq_connection and not rabbitmq_connection.is_closed:
                await rabbitmq_connection.close()
                
            if redis_client:
                await redis_client.close()
                
            if db_pool:
                await db_pool.close()
                
            print("✅ Recursos fechados com sucesso")
            
        def handle_signals():
            print("⚠️ Sinal de término recebido. Encerrando graciosamente...")
            asyncio.create_task(cleanup_resources())
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
        # Tenta limpar recursos em caso de erro
        try:
            await cleanup_resources()
        except Exception:
            pass  # Ignora erros de limpeza
        raise

async def start_health_server():
    """
    Inicia um servidor HTTP simples para health checks do consumer.
    Pode ser usado por Docker/Kubernetes para health probes.
    """
    global health_runner
    from aiohttp import web
    
    async def health_handler(request):
        if is_healthy:
            return web.Response(text='{"status":"healthy"}', content_type='application/json')
        else:
            return web.Response(text='{"status":"unhealthy"}', status=503, content_type='application/json')
    
    app = web.Application()
    app.router.add_get('/health', health_handler)
    
    health_port = int(os.getenv("HEALTH_PORT", 8080))
    health_runner = web.AppRunner(app)
    await health_runner.setup()
    site = web.TCPSite(health_runner, '0.0.0.0', health_port)
    await site.start()
    print(f"✅ Servidor de health check iniciado na porta {health_port}")

async def cleanup_resources():
    global is_healthy, db_pool, redis_client, rabbitmq_connection, health_runner
    is_healthy = False
    set_consumer_unhealthy()
    
    # Fecha recursos na ordem inversa da abertura
    if rabbitmq_connection and not rabbitmq_connection.is_closed:
        await rabbitmq_connection.close()
        
    if redis_client:
        await redis_client.close()
        
    if db_pool:
        await db_pool.close()
        
    if health_runner:
        await health_runner.cleanup()
        
    print("✅ Recursos fechados com sucesso")

if __name__ == "__main__":
    asyncio.run(main())
