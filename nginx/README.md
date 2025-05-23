# Nginx

Este diretório contém configurações do Nginx utilizado como load balancer e proxy reverso no sistema.

## Estrutura

- Arquivos de configuração para diferentes serviços
- Templates para geração dinâmica de configurações

## Funcionalidades

- **Load Balancing**: Distribuição de carga entre múltiplas instâncias da API
- **Proxy Reverso**: Exposição dos serviços internos para o mundo exterior
- **TLS Termination**: Gerenciamento de conexões HTTPS (quando configurado)
- **Rate Limiting**: Proteção contra sobrecarga de requisições
- **Health Checking**: Detecção e remoção automática de instâncias não saudáveis

## Configurações Principais

- Configuração para a API principal (distribuição de requisições)
- Configuração para o CockroachDB (balanceamento de conexões)
- Configuração para serviços de administração (Prometheus, Grafana, etc.)

## Como Funciona

O Nginx recebe todas as requisições externas e as distribui para os serviços apropriados:

1. Requisições para `/kv` são encaminhadas para instâncias da API
2. Requisições para `/metrics` são encaminhadas para o Prometheus
3. Requisições para páginas de administração são protegidas e encaminhadas
4. Health checks periódicos verificam a disponibilidade dos serviços

## Customização

Para modificar a configuração do Nginx:

1. Edite os arquivos de configuração neste diretório
2. Reconstrua os containers usando `docker compose up --build -d` 