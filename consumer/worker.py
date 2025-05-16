# consumer/worker.py
import os
import asyncio
import json
import asyncpg
import redis.asyncio as redis
import aio_pika


async def main() -> None:
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

    # ---------- handlers ----------
    async def handle_add(msg: aio_pika.IncomingMessage) -> None:
        async with msg.process():
            data = json.loads(msg.body)
            key, value = data["key"], data["value"]
            await db.execute(
                "UPSERT INTO kv_store (key, value) VALUES ($1, $2)", key, value
            )
            await cache.set(key, value)

    async def handle_del(msg: aio_pika.IncomingMessage) -> None:
        async with msg.process():
            key = json.loads(msg.body)["key"]
            await db.execute("DELETE FROM kv_store WHERE key = $1", key)
            await cache.delete(key)

    # ---------- start consuming ----------
    await add_q.consume(handle_add)
    await del_q.consume(handle_del)
    print("✅ consumer à escuta…")
    await asyncio.Future()  # bloqueia para manter o processo vivo


if __name__ == "__main__":
    asyncio.run(main())
