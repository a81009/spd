# API Principal (FastAPI)

Este diretório contém a implementação da API REST que serve como ponto de entrada principal do sistema de armazenamento chave-valor.

## Estrutura

- `main.py`: Definição da aplicação FastAPI e endpoints da API
- `cache.py`: Interface com o Redis para caching
- `mq.py`: Cliente para o RabbitMQ para mensageria
- `metrics.py`: Instrumentação para métricas do Prometheus
- `health_check.py`: Implementação dos health checks
- `storage/`: Adaptadores para diferentes backends de armazenamento

## Funcionalidades

- Endpoints REST para operações PUT, GET e DELETE
- Cache de dados usando Redis
- Publicação de eventos para processamento assíncrono
- Monitoramento via métricas Prometheus
- Health checks para integração com orquestradores

## Dependências

As dependências estão listadas no arquivo `requirements.txt` e incluem:
- FastAPI: Framework web
- uvicorn: Servidor ASGI
- Redis: Cliente para cache
- pika: Cliente para RabbitMQ
- prometheus-client: Cliente para métricas
- psycopg: Cliente para CockroachDB 