# Sistema Distribuído de Armazenamento Chave-Valor

Este projeto implementa um sistema distribuído de armazenamento chave-valor, capaz de armazenar, recuperar e gerir pares chave-valor através de múltiplos nós em um ambiente distribuído. O sistema foi projetado para lidar com questões fundamentais de sistemas distribuídos como tolerância a falhas, consistência, disponibilidade e escalabilidade.

## Diagrama de Arquitetura

```
                           ┌─────────────┐                          
                           │   Cliente   │                          
                           └──────┬──────┘                          
                                  │                                 
                                  ▼                                 
             ┌───────────────────────────────────────┐             
             │         Nginx Load Balancer           │             
             └─────────────┬───────────────┬─────────┘             
                           │               │                        
           ┌───────────────▼┐           ┌─▼───────────────┐        
           │     API Node 1 │           │    API Node 2   │        
           └───────┬────────┘           └────────┬────────┘        
                   │                             │                  
┌──────────────────┼─────────────────────────────┼──────────────┐  
│                  │                             │              │  
│    ┌─────────────▼─────────────┐  ┌────────────▼────────────┐ │  
│    │     Redis Cluster         │  │      RabbitMQ Cluster   │ │  
│    │  (Cache + Sentinel)       │  │     (Message Queue)     │ │  
│    └─────────────┬─────────────┘  └────────────┬────────────┘ │  
│                  │                             │              │  
│    ┌─────────────▼─────────────┐  ┌────────────▼────────────┐ │  
│    │    CockroachDB Cluster    │  │   Consumer Workers      │ │  
│    │   (Persistent Storage)    │  │  (Async Processing)     │ │  
│    └───────────────────────────┘  └─────────────────────────┘ │  
│                                                               │  
└───────────────────────────────────────────────────────────────┘  
   
     ┌────────────────────┐  ┌─────────────────┐  ┌───────────┐   
     │  Prometheus/Grafana│  │   Autoscaler    │  │ Healthchecks│  
     │  (Monitoring)      │  │ (Scalability)   │  │ (Reliability)│ 
     └────────────────────┘  └─────────────────┘  └───────────┘   
```

## Funcionalidades

O sistema implementa as seguintes operações básicas:
- **PUT (key, value)**: Armazena um valor associado a uma chave
- **GET (key)**: Recupera o valor associado a uma chave
- **DELETE (key)**: Remove um par chave-valor

## Tecnologias Utilizadas

### API e Serviços
- **FastAPI**: Framework para a API REST
- **Docker & Docker Compose**: Containerização e orquestração
- **Nginx**: Load balancer e proxy reverso

### Armazenamento
- **CockroachDB**: Banco de dados distribuído e resiliente para armazenamento persistente
- **Redis**: Sistema de cache com Sentinel para alta disponibilidade

### Mensageria
- **RabbitMQ**: Sistema de mensageria para operações assíncronas

### Monitoramento
- **Prometheus**: Coleta de métricas
- **Grafana**: Visualização de métricas e dashboards

### Automação
- **Autoscaler**: Escala automaticamente os serviços baseado na carga
- **Health Checks**: Verificação contínua do estado operacional do sistema

## Implementação na Cloud

Um plano detalhado para migração e implementação deste sistema na cloud está disponível no diretório `/CLOUD`. O plano contempla:

- Arquitetura proposta em provedores de cloud (AWS, Azure, GCP)
- Estratégia de migração em fases
- Considerações de segurança e compliance
- Estimativa de custos
- Vantagens da migração para a cloud

Para mais detalhes, consulte [CLOUD/README.md](CLOUD/README.md).

## Aspectos de Sistemas Distribuídos

### Concorrência
O sistema gerencia concorrência através de:
- Operações atômicas no CockroachDB
- Filas de mensagens no RabbitMQ para operações assíncronas
- Cache distribuído com Redis para reduzir contenção

### Escalabilidade
A escalabilidade é garantida por:
- Arquitetura de microserviços com baixo acoplamento
- Load balancer para distribuição de carga
- Autoscaler para ajuste dinâmico de recursos
- Cluster de banco de dados distribuído

### Tolerância a Falhas
O sistema implementa mecanismos para tolerância a falhas:
- Replicação de dados no CockroachDB
- Redis Sentinel para detecção de falhas e failover automático
- Cluster RabbitMQ para garantir processamento de mensagens
- Health checks contínuos para detecção proativa de problemas

### Consistência
A consistência dos dados é garantida por:
- Transações ACID no CockroachDB
- Mecanismo de coordenação distribuída para updates
- Cache com política de expiração para reduzir inconsistências

### Coordenação de Recursos
A coordenação de recursos é gerenciada através de:
- Balanceamento de carga entre nós da API
- Distribuição balanceada de dados no cluster
- Filas de mensagens para coordenar operações assíncronas

## Instalação e Uso

### Requisitos
- Docker e Docker Compose
- Sistema operacional Linux/macOS/Windows com WSL
- Python 3.8+ (para testes manuais)

### Instalação Rápida
O sistema foi projetado para instalação e setup instantâneo:

```bash
# Clone o repositório
git clone https://github.com/seu-usuario/kv-store.git
cd kv-store

# Execute o script de inicialização
./start.sh
```

O script `start.sh` irá:
1. Iniciar todos os containers necessários
2. Configurar o banco de dados e o cache
3. Executar testes unitários para verificar a instalação
4. Iniciar o sistema e exibir informações de acesso

### Endpoints Principais

| Método | Endpoint | Descrição | Parâmetros |
|--------|----------|-----------|------------|
| GET    | /kv      | Recupera valor | key (query param) |
| PUT    | /kv      | Armazena chave-valor | JSON body: `{"data": {"key":"foo", "value":"bar"}}` |
| DELETE | /kv      | Remove chave | key (query param) |
| GET    | /health  | Health check | - |
| GET    | /metrics | Métricas Prometheus | - |

### Interface Web
Uma interface web simples está disponível em http://localhost/ para interagir com a API.

### Serviços de Administração
- Prometheus: http://localhost:9091
- Grafana: http://localhost:3000 (admin/admin)
- RabbitMQ Management: http://localhost:25673 (admin/admin)
- CockroachDB Admin: http://localhost:8080

## Testes

### Testes Unitários
O sistema inclui testes unitários que verificam todas as funcionalidades básicas. Execute-os com:

```bash
python3 -m unitary_tests.run_tests
```

### Testes de Carga
Testes de carga podem ser executados usando o script fornecido:

```bash
./load-tests/load-tests-siege.sh all
```

Consulte o arquivo `load-tests/README-load-tests.md` para mais informações sobre testes de carga.

## Limites e Capacidades do Sistema

- **Armazenamento**: Limitado pelo espaço em disco alocado aos volumes do CockroachDB
- **Cache**: Configurado para usar no máximo 100MB por instância Redis
- **Tamanho máximo de chave**: 1KB
- **Tamanho máximo de valor**: 1MB
- **Throughput**: Aproximadamente 2000 requisições/segundo para leitura e 500 requisições/segundo para escrita em hardware recomendado

## Contribuição

Para contribuir com o projeto:
1. Fork o repositório
2. Crie uma branch para sua feature (`git checkout -b feature/amazing-feature`)
3. Commit suas mudanças (`git commit -m 'Add some amazing feature'`)
4. Push para a branch (`git push origin feature/amazing-feature`)
5. Abra um Pull Request

## Bibliografia

### Referências Acadêmicas
- Tanenbaum, A. S., & Van Steen, M. (2017). Distributed systems: principles and paradigms.
- Kleppmann, M. (2017). Designing data-intensive applications: The big ideas behind reliable, scalable, and maintainable systems. O'Reilly Media, Inc.

### Tecnologias Utilizadas
- [FastAPI Documentation](https://fastapi.tiangolo.com/)
- [CockroachDB Documentation](https://www.cockroachlabs.com/docs/)
- [Redis Documentation](https://redis.io/documentation)
- [RabbitMQ Documentation](https://www.rabbitmq.com/documentation.html)
- [Docker Documentation](https://docs.docker.com/)

### Conteúdo Gerado por IA
Partes da documentação e scripts iniciais foram desenvolvidos com auxílio de ferramentas de IA, incluindo:
- Claude 3.7 Sonnet: Utilizado para estruturação da documentação e refatoração de código 