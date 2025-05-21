import os, aio_pika, json, asyncio
from .metrics import MESSAGE_QUEUE_SIZE, MESSAGE_PROCESSING_TIME, measure_time, calculate_duration

MQ_URL = f"amqp://admin:admin@{os.getenv('MQ_HOST','rabbitmq')}:5672"
_QUEUE_ADD, _QUEUE_DEL = "add_key", "del_key"

class MQProducer:
    def __init__(self) -> None:
        self._conn: aio_pika.RobustConnection | None = None
        self._channel: aio_pika.Channel | None = None
        self._queues = [_QUEUE_ADD, _QUEUE_DEL]

    async def _get_channel(self):
        if not self._conn or self._conn.is_closed:
            self._conn = await aio_pika.connect_robust(MQ_URL)
            self._channel = None
            
        if not self._channel or self._channel.is_closed:
            self._channel = await self._conn.channel()
            # Declare queues only once per channel
            await self._channel.declare_queue(_QUEUE_ADD, durable=True)
            await self._channel.declare_queue(_QUEUE_DEL, durable=True)
            
        return self._channel

    async def send(self, queue: str, payload: dict):
        start_time = measure_time()
        ch = await self._get_channel()
        await ch.default_exchange.publish(
            aio_pika.Message(body=json.dumps(payload).encode()),
            routing_key=queue,
        )
        # Medir tempo de processamento
        duration = calculate_duration(start_time)
        MESSAGE_PROCESSING_TIME.labels(queue=queue).observe(duration)
        
        # Atualizar tamanho estimado das filas periodicamente
        await self._update_queue_metrics()
    
    async def _update_queue_metrics(self):
        """Atualiza métricas de tamanho das filas"""
        try:
            ch = await self._get_channel()
            for queue_name in self._queues:
                queue = await ch.get_queue(queue_name)
                declaration = await queue.declare(passive=True)
                MESSAGE_QUEUE_SIZE.labels(queue=queue_name).set(declaration.message_count)
        except Exception:
            # Silencia erros para não afetar o funcionamento normal
            pass
            
    async def get_health(self):
        """Verifica a saúde da conexão com o RabbitMQ"""
        try:
            if not self._conn or self._conn.is_closed:
                self._conn = await aio_pika.connect_robust(MQ_URL, timeout=2)
                self._channel = None
                
            if self._conn.is_closed:
                return False
                
            # Verifica ou cria um canal
            ch = await self._get_channel()
            return True
        except Exception:
            return False

    async def close(self):
        """Fecha a conexão e o canal com o RabbitMQ"""
        if self._channel and not self._channel.is_closed:
            await self._channel.close()
            self._channel = None
            
        if self._conn and not self._conn.is_closed:
            await self._conn.close()
            self._conn = None

mq = MQProducer()
