# Sistema de Testes Unitários

Este projeto inclui um conjunto abrangente de testes unitários para garantir o funcionamento correto da API de Key-Value Store. Os testes são executados automaticamente durante a inicialização do sistema pelo script `start.sh`.

## Funcionalidades Testadas

O sistema de testes verifica:

1. **Health Checks**:
   - Health check geral
   - Liveness probe (K8s)
   - Readiness probe (K8s)

2. **Estatísticas de Cache**:
   - Disponibilidade do endpoint
   - Formato correto das estatísticas

3. **Operações KV**:
   - PUT: Adicionar/atualizar valores
   - GET: Recuperar valores
   - DELETE: Remover valores

4. **Validação de Erros**:
   - Comportamento para chaves inexistentes
   - Validação de requisições inválidas

## Como os Testes Funcionam

1. **Inicialização**: O script `start.sh` inicia todos os serviços usando Docker Compose
2. **Espera**: O sistema aguarda 10 segundos para garantir que todos os serviços estejam prontos
3. **Verificação**: O script `tests.py` verifica se a API está disponível usando o health check
4. **Execução**: Executa todos os testes unitários definidos
5. **Relatório**: Exibe o número de testes bem-sucedidos e falhas
6. **Continuação**: Se todos os testes passarem, o script continua com a inicialização normal

## Executando Testes Manualmente

Você pode executar os testes manualmente a qualquer momento usando:

```bash
python3 tests.py
```

## Requisitos

Os testes dependem das seguintes bibliotecas Python:
- `requests`: Para fazer chamadas HTTP à API
- `unittest`: Framework de testes padrão do Python

## Adicionando Novos Testes

Para adicionar novos testes:

1. Abra o arquivo `tests.py`
2. Adicione um novo método de teste à classe `KVStoreAPITests` (começando com `test_`)
3. Implemente seus casos de teste usando os métodos de asserção do `unittest`

Exemplo:

```python
def test_nova_funcionalidade(self):
    """Descrição do novo teste"""
    response = requests.get(urljoin(BASE_URL, "/nova-rota"))
    self.assertEqual(response.status_code, 200)
```

## Solução de Problemas

Se os testes falharem:

1. Verifique se todos os serviços estão em execução usando `docker compose ps`
2. Verifique os logs dos serviços com `docker compose logs api consumer`
3. Verifique se o Nginx está encaminhando requisições corretamente
4. Aumente o tempo de espera inicial no `start.sh` se os serviços levarem mais tempo para iniciar 