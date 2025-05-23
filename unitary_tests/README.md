# Testes Unitários

Este diretório contém os testes unitários para verificar o funcionamento correto do sistema de armazenamento chave-valor.

## Estrutura

- `run_tests.py`: Script principal para execução dos testes
- `api_tests.py`: Testes para a API REST
- `README-tests.md`: Documentação detalhada dos testes

## Funcionalidades Testadas

- Health checks e verificação de estado do sistema
- Operações PUT, GET e DELETE da API
- Estatísticas de cache
- Comportamento em casos de erro (chaves inexistentes, formatos inválidos)

## Como Executar

Os testes podem ser executados de duas formas:

1. **Automaticamente durante a inicialização**:
   ```bash
   ./start.sh
   ```
   
2. **Manualmente**:
   ```bash
   python3 -m unitary_tests.run_tests
   ```

## Requisitos

- Python 3.8+
- Módulo requests
- Sistema em execução (todos os containers ativos)

## Extensão dos Testes

Os testes são projetados para serem facilmente estendidos. Para adicionar novos casos de teste:

1. Abra o arquivo `api_tests.py`
2. Adicione um novo método à classe de teste (começando com `test_`)
3. Implemente as verificações necessárias usando os métodos de asserção

Consulte o arquivo `README-tests.md` para mais detalhes sobre a implementação dos testes. 