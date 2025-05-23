#!/bin/bash
set -euo pipefail

echo "🔥 Iniciando testes de carga com curl 🔥"

# Configurações
NUM_REQUESTS=100   # Número total de requisições
CONCURRENCY=10     # Número de solicitações concorrentes
API_URL="http://localhost/kv"
TEST_TYPE=${1:-"put"}  # put, get, delete ou all

# Função para enviar uma requisição PUT
send_put_request() {
    local key=$1
    local value=$2
    local json_data="{\"data\":{\"key\":\"$key\",\"value\":\"$value\"}}"
    
    curl -s -X PUT "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$json_data" > /dev/null
    
    echo -n "."  # Indicador de progresso
}

# Função para enviar uma requisição GET
send_get_request() {
    local key=$1
    
    curl -s "$API_URL?key=$key" > /dev/null
    echo -n "."  # Indicador de progresso
}

# Função para enviar uma requisição DELETE
send_delete_request() {
    local key=$1
    
    curl -s -X DELETE "$API_URL?key=$key" > /dev/null
    echo -n "."  # Indicador de progresso
}

# Função para pré-popular chaves
prepopulate_keys() {
    echo -e "\n🔄 Pré-populando $NUM_REQUESTS chaves..."
    for i in $(seq 1 $NUM_REQUESTS); do
        send_put_request "curl_key_$i" "curl_value_$i"
        if (( i % 50 == 0 )); then
            echo " $i/$NUM_REQUESTS"
        fi
    done
    echo -e "\n✅ Chaves pré-populadas"
    sleep 3  # Espera para garantir que as mensagens sejam processadas
}

# Função para executar teste PUT
run_put_test() {
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO PUT (Criação/Atualização de chaves)"
    local start_time=$(date +%s)
    
    # Executa as requisições em paralelo
    echo "🔄 Enviando $NUM_REQUESTS requisições PUT com concorrência de $CONCURRENCY..."
    (
        # Use a semi-colon to ensure each sub-command is started sequentially
        for i in $(seq 1 $NUM_REQUESTS); do
            # Start a background process
            (send_put_request "curl_key_$i" "curl_value_$i") &
            
            # Limit parallel processes
            if (( i % CONCURRENCY == 0 )); then
                wait  # Wait for all processes to finish before starting more
                echo " $i/$NUM_REQUESTS"
            fi
        done
        wait  # Wait for any remaining processes
    )
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local requests_per_second=$(bc -l <<< "scale=2; $NUM_REQUESTS / $duration")
    
    echo -e "\n✅ Teste PUT concluído"
    echo "⏱️  Tempo total: $duration segundos"
    echo "⚡ Requisições por segundo: $requests_per_second"
}

# Função para executar teste GET
run_get_test() {
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO GET (Leitura de chaves)"
    local start_time=$(date +%s)
    
    # Executa as requisições em paralelo
    echo "🔄 Enviando $NUM_REQUESTS requisições GET com concorrência de $CONCURRENCY..."
    (
        for i in $(seq 1 $NUM_REQUESTS); do
            (send_get_request "curl_key_$i") &
            
            # Limit parallel processes
            if (( i % CONCURRENCY == 0 )); then
                wait
                echo " $i/$NUM_REQUESTS"
            fi
        done
        wait
    )
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local requests_per_second=$(bc -l <<< "scale=2; $NUM_REQUESTS / $duration")
    
    echo -e "\n✅ Teste GET concluído"
    echo "⏱️  Tempo total: $duration segundos"
    echo "⚡ Requisições por segundo: $requests_per_second"
}

# Função para executar teste DELETE
run_delete_test() {
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO DELETE (Remoção de chaves)"
    local start_time=$(date +%s)
    
    # Executa as requisições em paralelo
    echo "🔄 Enviando $NUM_REQUESTS requisições DELETE com concorrência de $CONCURRENCY..."
    (
        for i in $(seq 1 $NUM_REQUESTS); do
            (send_delete_request "curl_key_$i") &
            
            # Limit parallel processes
            if (( i % CONCURRENCY == 0 )); then
                wait
                echo " $i/$NUM_REQUESTS"
            fi
        done
        wait
    )
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local requests_per_second=$(bc -l <<< "scale=2; $NUM_REQUESTS / $duration")
    
    echo -e "\n✅ Teste DELETE concluído"
    echo "⏱️  Tempo total: $duration segundos"
    echo "⚡ Requisições por segundo: $requests_per_second"
}

# Função principal
run_tests() {
    local test_type=$1
    
    case $test_type in
        "put")
            run_put_test
            ;;
        "get")
            prepopulate_keys
            run_get_test
            ;;
        "delete")
            prepopulate_keys
            run_delete_test
            ;;
        "all")
            run_put_test
            sleep 3
            run_get_test
            sleep 3
            run_delete_test
            ;;
        *)
            echo "❌ Tipo de teste inválido: $test_type"
            echo "Opções válidas: put, get, delete, all"
            exit 1
            ;;
    esac
}

# Mensagem de início
echo -e "\n⚙️ Configurações do teste de carga com curl:"
echo "- Número de requisições: $NUM_REQUESTS"
echo "- Concorrência: $CONCURRENCY"

# Executar os testes
run_tests "$TEST_TYPE"

echo -e "\n🏁 Testes de carga concluídos!" 