import os, aio_pika, json, asyncio

MQ_URL = f"amqp://admin:admin@{os.getenv('MQ_HOST','rabbitmq')}:5672"
_QUEUE_ADD, _QUEUE_DEL = "add_key", "del_key"

class MQProducer:
    def __init__(self) -> None:
        self._conn: aio_pika.RobustConnection | None = None

    async def _channel(self):
        if not self._conn:
            self._conn = await aio_pika.connect_robust(MQ_URL)
        ch = await self._conn.channel()
        await ch.declare_queue(_QUEUE_ADD, durable=True)
        await ch.declare_queue(_QUEUE_DEL, durable=True)
        return ch

    async def send(self, queue: str, payload: dict):
        ch = await self._channel()
        await ch.default_exchange.publish(
            aio_pika.Message(body=json.dumps(payload).encode()),
            routing_key=queue,
        )

mq = MQProducer()
