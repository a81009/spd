# Grafana

Este diretório contém configurações e dashboards para o Grafana, a ferramenta de visualização e monitoramento do sistema.

## Estrutura

- Dashboards pré-configurados para monitoramento
- Configuração de datasources (Prometheus)
- Alertas e notificações

## Dashboards Disponíveis

1. **Visão Geral do Sistema**: Métricas gerais e estado dos serviços
2. **Performance da API**: Latência, throughput e taxa de erros
3. **Cache Redis**: Taxa de acertos/erros, uso de memória
4. **CockroachDB**: Métricas do banco de dados, operações por segundo
5. **RabbitMQ**: Tamanho de filas, taxa de processamento de mensagens
6. **Recursos do Sistema**: CPU, memória, rede por serviço

## Acesso

- URL: http://localhost:3000
- Credenciais padrão: admin/admin

## Configuração

Os dashboards são provisionados automaticamente durante a inicialização do sistema.
Para adicionar novos dashboards:

1. Crie o dashboard via interface do Grafana
2. Exporte o JSON do dashboard
3. Adicione o arquivo ao diretório `dashboards/`
4. Atualize o arquivo `dashboards.yaml` para incluir o novo dashboard
5. Reconstrua os containers: `docker compose up -d grafana`

## Alertas

O sistema inclui alertas configurados para condições críticas:

- Alta latência na API
- Erros na API acima do threshold
- Fila de processamento muito grande
- Uso de recursos (CPU/memória) acima do limite

Os alertas podem ser configurados para enviar notificações por email ou outros canais de comunicação. 