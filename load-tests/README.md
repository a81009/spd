# Testes de Carga

Este diretório contém scripts e ferramentas para realizar testes de carga no sistema distribuído de armazenamento chave-valor.

## Estrutura

- `load-tests-siege.sh`: Script para executar testes com a ferramenta Siege
- `README-load-tests.md`: Documentação detalhada sobre testes de carga

## Funcionalidades

- Testes de carga para operações PUT, GET e DELETE
- Simulação de múltiplos usuários concorrentes
- Métricas de desempenho e disponibilidade
- Testes configuráveis (número de usuários, duração, etc.)

## Como Executar

```bash
# Executar todos os testes de carga
./load-tests-siege.sh all

# Testar apenas uma operação específica
./load-tests-siege.sh put    # Testar apenas PUT
./load-tests-siege.sh get    # Testar apenas GET
./load-tests-siege.sh delete # Testar apenas DELETE
```

## Configuração

Os parâmetros dos testes podem ser ajustados editando o script `load-tests-siege.sh`:

- `NUM_KEYS`: Número de chaves para testar
- `USERS`: Número de usuários concorrentes
- `DURATION`: Duração do teste

## Requisitos

- Siege: Ferramenta de benchmarking HTTP
- Sistema em execução (todos os containers ativos)

## Interpretação dos Resultados

O script gera relatórios contendo as seguintes métricas:

- Throughput (transações por segundo)
- Tempo médio de resposta
- Taxa de disponibilidade
- Concorrência média
- Número de transações bem-sucedidas e falhas

Consulte `README-load-tests.md` para mais detalhes sobre a interpretação dos resultados e resolução de problemas comuns. 