#!/bin/bash
set -euo pipefail

echo "🔥 Iniciando testes de carga com Siege 🔥"

# Verificar se o Siege está instalado
if ! command -v siege &> /dev/null; then
    echo "❌ Siege não está instalado. Por favor, instale o Siege primeiro."
    echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install siege"
    echo "👉 Para instalar no CentOS/RHEL: sudo yum install siege"
    echo "👉 Para instalar no Windows: utilize o WSL (Windows Subsystem for Linux)"
    exit 1
fi

# URL base da API
API_URL="http://localhost"
# Número de chaves para teste
NUM_KEYS=100
# Número de usuários concorrentes
USERS=25
# Duração dos testes
DURATION="1M"

# Preparação dos arquivos de URLs para cada operação
PUT_URLS_FILE="put_urls.txt"
GET_URLS_FILE="get_urls.txt"
DELETE_URLS_FILE="delete_urls.txt"

# Criar diretório temporário para arquivos de dados
TEMP_DIR="siege_temp"
mkdir -p "$TEMP_DIR"

# Criar arquivo com URLs para testes de PUT
create_put_urls_file() {
    local filename=$1
    echo "Criando arquivo de URLs para operação PUT..."
    
    # Limpa o arquivo se já existir
    > "$filename"
    
    # Adiciona URLs de PUT com valores diferentes usando arquivos de dados
    for i in $(seq 1 $NUM_KEYS); do
        # Criar um arquivo de dados JSON separado para cada chave
        local data_file="$TEMP_DIR/put_data_$i.json"
        echo "{\"data\":{\"key\":\"test_key_$i\",\"value\":\"test_value_$i\"}}" > "$data_file"
        
        # Formato correto para o Siege: URL POST <arquivo_de_dados
        echo "$API_URL/kv POST <$data_file" >> "$filename"
    done
    
    echo "✅ Arquivo de URLs para PUT criado: $filename"
}

# Criar arquivo com URLs para testes de GET
create_get_urls_file() {
    local filename=$1
    echo "Criando arquivo de URLs para operação GET..."
    
    # Limpa o arquivo se já existir
    > "$filename"
    
    # Adiciona URLs de GET com chaves diferentes
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL/kv?key=test_key_$i" >> "$filename"
    done
    
    echo "✅ Arquivo de URLs para GET criado: $filename"
}

# Criar arquivo com URLs para testes de DELETE
create_delete_urls_file() {
    local filename=$1
    echo "Criando arquivo de URLs para operação DELETE..."
    
    # Limpa o arquivo se já existir
    > "$filename"
    
    # Adiciona URLs de DELETE com chaves diferentes
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL/kv?key=test_key_$i DELETE" >> "$filename"
    done
    
    echo "✅ Arquivo de URLs para DELETE criado: $filename"
}

# Teste de carga para operação PUT
run_put_test() {
    local urls_file=$1
    local concurrent_users=$2
    local test_time=$3
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO PUT (Criação/Atualização de chaves)"
    echo "🔄 Executando teste com $concurrent_users usuários concorrentes por $test_time..."
    siege --content-type="application/json" -f "$urls_file" -c "$concurrent_users" -t "$test_time" -v
}

# Teste de carga para operação GET
run_get_test() {
    local urls_file=$1
    local concurrent_users=$2
    local test_time=$3
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO GET (Leitura de chaves)"
    echo "🔄 Executando teste com $concurrent_users usuários concorrentes por $test_time..."
    siege -f "$urls_file" -c "$concurrent_users" -t "$test_time" -v
}

# Teste de carga para operação DELETE
run_delete_test() {
    local urls_file=$1
    local concurrent_users=$2
    local test_time=$3
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO DELETE (Remoção de chaves)"
    echo "🔄 Executando teste com $concurrent_users usuários concorrentes por $test_time..."
    siege -f "$urls_file" -c "$concurrent_users" -t "$test_time" -v
}

# Análise do resultado
show_result_explanation() {
    echo -e "\n📋 O que os resultados significam:"
    echo "- Transactions: Número total de requisições processadas"
    echo "- Availability: Porcentagem de requisições bem-sucedidas"
    echo "- Elapsed time: Tempo total do teste"
    echo "- Data transferred: Quantidade de dados transferidos"
    echo "- Response time: Tempo médio de resposta por requisição"
    echo "- Transaction rate: Número de transações por segundo"
    echo "- Throughput: Quantidade de dados transferidos por segundo"
    echo "- Concurrency: Número médio de conexões simultâneas"
    echo "- Successful transactions: Número de transações bem-sucedidas"
    echo "- Failed transactions: Número de transações com falha"
}

# Função principal de teste
run_tests() {
    local test_type=$1
    
    case $test_type in
        "put")
            create_put_urls_file "$PUT_URLS_FILE"
            run_put_test "$PUT_URLS_FILE" $USERS $DURATION
            ;;
        "get")
            # Pré-popular as chaves antes de testar GET
            echo -e "\n🔄 Pré-populando chaves antes do teste GET..."
            create_put_urls_file "$PUT_URLS_FILE"
            siege --content-type="application/json" -f "$PUT_URLS_FILE" -c 10 -r 1 -q
            sleep 5  # Espera um pouco para garantir que as chaves foram processadas
            
            create_get_urls_file "$GET_URLS_FILE"
            run_get_test "$GET_URLS_FILE" $USERS $DURATION
            ;;
        "delete")
            # Pré-popular as chaves antes de testar DELETE
            echo -e "\n🔄 Pré-populando chaves antes do teste DELETE..."
            create_put_urls_file "$PUT_URLS_FILE"
            siege --content-type="application/json" -f "$PUT_URLS_FILE" -c 10 -r 1 -q
            sleep 5  # Espera um pouco para garantir que as chaves foram processadas
            
            create_delete_urls_file "$DELETE_URLS_FILE"
            run_delete_test "$DELETE_URLS_FILE" $USERS $DURATION
            ;;
        "all")
            # Executar todos os testes em sequência
            run_tests "put"
            run_tests "get"
            run_tests "delete"
            ;;
        *)
            echo "❌ Tipo de teste inválido: $test_type"
            echo "Opções válidas: put, get, delete, all"
            exit 1
            ;;
    esac
}

# Mensagem de início
echo -e "\n⚙️ Configurações do teste de carga:"
echo "- Número de chaves: $NUM_KEYS"
echo "- Usuários concorrentes: $USERS"
echo "- Duração do teste: $DURATION"

# Se não houver argumento, executa apenas o teste PUT
TEST_TYPE=${1:-"put"}
run_tests "$TEST_TYPE"

# Mostrar explicação dos resultados
show_result_explanation

# Limpar arquivos temporários
rm -f "$PUT_URLS_FILE" "$GET_URLS_FILE" "$DELETE_URLS_FILE"
rm -rf "$TEMP_DIR"

echo -e "\n🏁 Testes de carga concluídos!" 