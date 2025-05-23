# Redis

Este diretório contém configurações e scripts relacionados ao Redis, utilizado como sistema de cache no projeto.

## Configuração

O Redis é implementado como um cluster com:
- 1 nó master
- 2 nós slave (réplicas de leitura)
- 3 nós sentinel (monitoramento e failover automático)

## Funcionalidades

- **Cache de Dados**: Armazenamento temporário de valores frequentemente acessados
- **Alta Disponibilidade**: Sentinel para detecção de falhas e failover automático
- **Replicação**: Réplicas para distribuição de carga de leitura
- **TTL**: Tempo de vida configurável para chaves
- **Métricas**: Estatísticas de uso e performance

## Políticas e Limites

- **Política de Expiração**: allkeys-lru (Least Recently Used)
- **Limite de Memória**: 100MB por instância
- **Tempo de Cache**: 5 minutos (configurável)

## Como Funciona

1. Quando um GET é solicitado, o sistema primeiro verifica o cache Redis
2. Se encontrado (cache hit), o valor é retornado imediatamente
3. Se não encontrado (cache miss), o valor é buscado do banco de dados e armazenado no cache
4. Quando um PUT/DELETE é processado, o cache é invalidado para manter consistência

## Persistência

O Redis no projeto é configurado sem persistência em disco, funcionando puramente como cache.
Os volumes Docker mapeados servem apenas para garantir que configurações sejam preservadas
entre reinicializações. 