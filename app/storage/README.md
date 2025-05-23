# Storage Adapters

Este diretório contém os adaptadores de armazenamento para diferentes backends de persistência.

## Estrutura

- `__init__.py`: Seletor dinâmico do backend com base na configuração
- `base.py`: Interface base (classe abstrata) para todos os backends
- `cockroach_backend.py`: Implementação para CockroachDB
- `sqlite_backend.py`: Implementação para SQLite (desenvolvimento/testes)
- `memory.py`: Implementação em memória (desenvolvimento/testes)

## Design

O sistema foi projetado com um padrão de adaptador, permitindo:

- Mudança de backend sem alterar o código da aplicação
- Isolamento das complexidades específicas de cada sistema de armazenamento
- Testes unitários com backends simulados ou em memória
- Adição fácil de novos backends no futuro

## Backends Disponíveis

### CockroachDB (Produção)
- Persistente e distribuído
- Alta disponibilidade e tolerância a falhas
- Transações ACID entre nós
- Escalabilidade horizontal

### SQLite (Desenvolvimento)
- Persistente mas não distribuído
- Fácil de configurar para desenvolvimento
- Sem dependências externas
- Baixa sobrecarga de recursos

### Memory (Testes)
- Não persistente
- Extremamente rápido
- Útil para testes unitários
- Sem configuração necessária

## Uso

A seleção do backend é feita por variável de ambiente:

```bash
STORAGE_BACKEND=cockroach  # Usa CockroachDB
STORAGE_BACKEND=sqlite     # Usa SQLite
STORAGE_BACKEND=memory     # Usa armazenamento em memória
```

Por padrão, o sistema usa CockroachDB em ambiente de produção. 