# Testes de Carga para a API Key-Value

Este documento descreve como realizar testes de carga na API Key-Value usando a ferramenta Siege.

## O que é o Siege?

Siege é uma ferramenta de teste de carga e benchmarking HTTP para medir o desempenho de servidores web sob pressão. Foi desenvolvida para permitir que desenvolvedores web meçam o comportamento de suas aplicações e vejam como elas se comportam sob diferentes cargas de usuários.

### Principais características do Siege:

- Simula múltiplos usuários concorrentes
- Suporta HTTP e HTTPS
- Gera relatórios detalhados sobre o desempenho
- Permite configurar diferentes níveis de carga
- Utiliza um arquivo de URLs para testar diferentes endpoints

## Instalação do Siege

Dependendo do seu sistema operacional, você pode instalar o Siege de diferentes formas:

### Ubuntu/Debian
```bash
sudo apt-get update
sudo apt-get install siege
```

### CentOS/RedHat
```bash
sudo yum install siege
```

### macOS
```bash
brew install siege
```

### Windows
No Windows, é recomendável usar o WSL (Windows Subsystem for Linux) e seguir as instruções para Ubuntu/Debian.

## Como usar o script de teste de carga

Este projeto inclui um script shell (`load_tests.sh`) para facilitar a execução de testes de carga. O script suporta testes para as operações PUT, GET e DELETE da API.

### Execução básica

```bash
# Tornar o script executável
chmod +x load_tests.sh

# Executar o teste padrão (PUT)
./load_tests.sh

# Especificar o tipo de teste (put, get, delete ou all)
./load_tests.sh put    # Testar apenas a operação PUT
./load_tests.sh get    # Testar apenas a operação GET
./load_tests.sh delete # Testar apenas a operação DELETE
./load_tests.sh all    # Testar todas as operações em sequência
```

### Configuração

Você pode configurar os testes modificando as seguintes variáveis no início do script:

- `NUM_KEYS`: Número de chaves para testar (padrão: 100)
- `USERS`: Número de usuários concorrentes (padrão: 25)
- `DURATION`: Duração do teste (padrão: 1M, ou seja, 1 minuto)

## Interpretação dos Resultados

O Siege fornece um relatório detalhado após a conclusão do teste. Os principais métricas a serem observadas são:

1. **Transactions**: Número total de requisições processadas
2. **Availability**: Porcentagem de requisições bem-sucedidas (idealmente 100%)
3. **Response time**: Tempo médio de resposta por requisição (menor é melhor)
4. **Transaction rate**: Número de transações processadas por segundo (maior é melhor)
5. **Concurrency**: Média de conexões simultâneas mantidas durante o teste
6. **Failed transactions**: Número de transações que falharam (idealmente zero)

## Exemplos de Comandos Siege

Se você preferir usar o Siege diretamente, aqui estão alguns exemplos de comandos úteis:

```bash
# Simular 25 usuários concorrentes por 1 minuto
siege -c 25 -t 1M https://example.com/api

# Usar um arquivo de URLs para testar
siege -f urls.txt -c 25 -t 1M

# Adicionar informações detalhadas durante o teste
siege -f urls.txt -c 25 -t 1M -v

# Simulação com delay aleatório (mais realista)
siege -f urls.txt -c 25 -t 1M -d 10

# Definir um cabeçalho Content-Type
siege --content-type="application/json" -f urls.txt -c 25 -t 1M
```

## Testando Diferentes Cenários

Ao testar sua API, considere os seguintes cenários:

1. **Carga Normal**: Testar com um número de usuários típico do seu ambiente de produção
2. **Carga de Pico**: Testar com um número elevado de usuários para simular picos de tráfego
3. **Stress Test**: Aumentar gradualmente o número de usuários até encontrar o limite da aplicação
4. **Teste de Resistência**: Executar testes por períodos prolongados para identificar problemas de memória/recursos

## Limitações e Considerações

- O Siege é uma ferramenta de linha de comando e não oferece uma interface gráfica
- Configurações muito agressivas podem causar problemas no sistema que está executando o Siege
- Os resultados podem variar dependendo da capacidade da máquina que executa os testes
- Considere o impacto nos recursos do servidor ao executar testes em ambientes compartilhados

## Recomendações para Testes de Carga

1. **Comece pequeno**: Inicie com cargas menores e aumente gradualmente
2. **Monitore recursos**: Observe CPU, memória e rede durante os testes
3. **Teste em ambiente isolado**: Evite impactar usuários reais ou outros serviços
4. **Teste regularmente**: Realize testes de carga como parte do seu ciclo de desenvolvimento

## Referências

- [Documentação oficial do Siege](https://www.joedog.org/siege-manual/)
- [GitHub do projeto Siege](https://github.com/JoeDog/siege) 
