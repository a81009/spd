# Consumer / Worker

Este diretório contém o serviço de consumidor que processa operações assíncronas de forma distribuída.

## Estrutura

- `worker.py`: Implementação do consumidor RabbitMQ
- `metrics.py`: Instrumentação para métricas
- `Dockerfile`: Configuração para containerização
- `requirements.txt`: Dependências do serviço

## Funcionalidades

- Consumo de mensagens de operações PUT e DELETE da fila
- Processamento assíncrono para melhorar performance do sistema
- Persistência dos dados no armazenamento backend
- Invalidação do cache quando necessário
- Resiliência a falhas com reconhecimento de mensagens

## Como Funciona

O consumer escuta filas no RabbitMQ para operações que exigem persistência. Quando uma mensagem é recebida:

1. A mensagem é desserializada
2. A operação é executada no backend de armazenamento (CockroachDB)
3. O cache é invalidado se necessário
4. A mensagem é confirmada (ack) somente após processamento bem-sucedido

Em caso de falha, as mensagens são reenfileiradas automaticamente pelo RabbitMQ. 