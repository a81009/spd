# Prometheus

Este diretório contém configurações para o Prometheus, sistema de monitoramento e alerta utilizado no projeto.

## Estrutura

- `prometheus.yml`: Configuração principal do Prometheus
- `alert_rules.yml`: Regras para alertas
- Outros arquivos de configuração específicos

## Funcionalidades

- **Coleta de Métricas**: Armazenamento de séries temporais de métricas do sistema
- **Descoberta de Serviços**: Localização automática de targets para monitoramento
- **Expressões PromQL**: Linguagem para consulta de métricas
- **Alertas**: Detecção de condições anômalas no sistema
- **Integração**: Fonte de dados para o Grafana

## Métricas Coletadas

- **API**: Latência, taxa de requisições, erros
- **Cache**: Hits, misses, uso de memória
- **Banco de Dados**: Operações por segundo, latência, uso de armazenamento
- **Filas**: Tamanho, taxa de processamento
- **Recursos de Sistema**: CPU, memória, rede, disco
- **Custom Metrics**: Métricas específicas da aplicação

## Acesso

- URL: http://localhost:9091
- Não requer autenticação por padrão

## Configuração

Para modificar os alvos do Prometheus ou adicionar regras de alertas:

1. Edite o arquivo `prometheus.yml` ou `alert_rules.yml`
2. Reconstrua o container: `docker compose up -d prometheus`

## Retenção de Dados

Por padrão, o Prometheus armazena dados por 15 dias. Esta configuração pode ser ajustada no
arquivo `prometheus.yml` modificando o parâmetro `storage.tsdb.retention.time`. 