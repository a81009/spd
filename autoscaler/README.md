# Autoscaler

Este diretório contém o serviço responsável por escalar automaticamente os componentes do sistema com base na carga.

## Estrutura

- `autoscaler.py`: Implementação principal do autoscaler
- `Dockerfile`: Configuração para containerização
- `requirements.txt`: Dependências do serviço

## Funcionalidades

- Monitoramento de métricas de carga do sistema via Prometheus
- Escalabilidade automática de serviços API e consumers
- Ajuste dinâmico de réplicas baseado no uso de recursos
- Prevenção de oscilações com cooldown periods
- Limite máximo e mínimo de instâncias configurável

## Como Funciona

O autoscaler opera em ciclos periódicos:

1. Consulta métricas do Prometheus (latência, CPU, memória, tamanho de filas)
2. Aplica algoritmos de decisão para determinar o número ótimo de réplicas
3. Interage com a API do Docker para escalar serviços up/down
4. Registra decisões de escalabilidade para análise posterior

## Configuração

O comportamento do autoscaler pode ser ajustado via variáveis de ambiente:

- `SCALE_INTERVAL`: Intervalo entre decisões de escalabilidade (segundos)
- `MIN_REPLICAS`: Número mínimo de réplicas por serviço
- `MAX_REPLICAS`: Número máximo de réplicas por serviço
- `SCALE_UP_THRESHOLD`: Limite para decisão de escalar para cima
- `SCALE_DOWN_THRESHOLD`: Limite para decisão de escalar para baixo 