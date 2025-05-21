#!/bin/bash
set -euo pipefail

echo "🔥 Iniciando testes de carga com Siege 🔥"

# Verificar se o Siege está instalado
if ! command -v siege &> /dev/null; then
    echo "❌ Siege não está instalado. Por favor, instale o Siege primeiro."
    echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install siege"
    exit 1
fi

# Função para perguntar ao usuário sobre as configurações
ask_user_settings() {
    # Tipo de teste
    echo -e "\n📋 Selecione o tipo de teste:"
    echo "1) PUT    - Criação/atualização de chaves"
    echo "2) GET    - Leitura de chaves"
    echo "3) DELETE - Remoção de chaves"
    echo "4) ALL    - Todos os testes acima em sequência"

    read -p "Escolha (1-4) [padrão: 1]: " test_choice
    case "${test_choice:-1}" in
        1) TEST_TYPE="put" ;;
        2) TEST_TYPE="get" ;;
        3) TEST_TYPE="delete" ;;
        4) TEST_TYPE="all" ;;
        *) echo "Opção inválida, usando PUT."; TEST_TYPE="put" ;;
    esac

    echo -e "\n⏱️ Duração do teste em segundos:"
    read -p "Digite a duração em segundos [padrão: 60]: " test_duration
    # Validação: garantir que é um número
    if ! [[ "${test_duration:-60}" =~ ^[0-9]+$ ]]; then
        # echo "Entrada inválida. Usando valor padrão de 60 segundos." # Silenciado
        test_duration=60
    fi
    DURATION_SECONDS="${test_duration:-60}"

    echo -e "\n👥 Usuários concorrentes:"
    read -p "Digite o número de usuários concorrentes [padrão: 25]: " concurrent_users
    # Validação: garantir que é um número
    if ! [[ "${concurrent_users:-25}" =~ ^[0-9]+$ ]]; then
        # echo "Entrada inválida. Usando valor padrão de 25 usuários." # Silenciado
        concurrent_users=25
    fi
    USERS="${concurrent_users:-25}"

    echo -e "\n🔑 Número de chaves para testar:"
    read -p "Digite o número de chaves para testar [padrão: 100]: " num_keys
    # Validação: garantir que é um número
    if ! [[ "${num_keys:-100}" =~ ^[0-9]+$ ]]; then
        # echo "Entrada inválida. Usando valor padrão de 100 chaves." # Silenciado
        num_keys=100
    fi
    NUM_KEYS="${num_keys:-100}"

    echo -e "\n⚙️ Configurações selecionadas:"
    echo "- Tipo de teste: $TEST_TYPE"
    echo "- Duração do teste: $DURATION_SECONDS segundos"
    echo "- Usuários concorrentes: $USERS"
    echo "- Número de chaves: $NUM_KEYS"

    read -p "Confirmar estas configurações? (S/n): " confirm
    if [[ "${confirm:-S}" =~ ^[Nn] ]]; then
        echo "Configurações canceladas. Saindo."
        exit 0
    fi
}

# Configurações padrão
API_URL="http://localhost/kv"
NUM_KEYS=100
USERS=25
DURATION_SECONDS=60
TEST_TYPE="put"

# Perguntar ao usuário
ask_user_settings

# Diretório temporário
TEMP_DIR="siege_temp"
mkdir -p "$TEMP_DIR" # Criação silenciosa

# Criação do .siegerc silenciosa se não existir
create_siegerc() {
    if [ ! -f ~/.siegerc ]; then
        cat > ~/.siegerc << EOF
verbose = true
quiet = false
show-logfile = false
logging = false
protocol = HTTP/1.1
chunked = true
connection = keep-alive
EOF
    fi
}

# Verifica se o curl está instalado (necessário para verify_api_works e prepopulate_keys)
check_curl() {
    if ! command -v curl &> /dev/null; then
        echo "❌ curl não está instalado. Este script precisa do curl para algumas operações."
        echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install curl"
        exit 1
    fi
}

# Criação dos arquivos JSON de dados (silenciosa)
create_json_data_files() {
    for i in $(seq 1 $NUM_KEYS); do
        local data_file="$TEMP_DIR/data_$i.json"
        echo "{\"data\":{\"key\":\"siege_key_$i\",\"value\":\"siege_value_$i\"}}" > "$data_file"
    done
}

# Preparação dos arquivos de URL para o Siege (silenciosa)
create_put_urls_file() {
    local urls_file="$TEMP_DIR/put_urls.txt"
    > "$urls_file"
    for i in $(seq 1 $NUM_KEYS); do
        local data_file="$TEMP_DIR/data_$i.json"
        echo "$API_URL PUT <$data_file" >> "$urls_file"
    done
    echo "$urls_file"
}

create_get_urls_file() {
    local urls_file="$TEMP_DIR/get_urls.txt"
    > "$urls_file"
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL?key=siege_key_$i" >> "$urls_file"
    done
    echo "$urls_file"
}

create_delete_urls_file() {
    local urls_file="$TEMP_DIR/delete_urls.txt"
    > "$urls_file"
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL?key=siege_key_$i DELETE" >> "$urls_file"
    done
    echo "$urls_file"
}

# Verificação da API (silenciosa em caso de sucesso, interativa em falha)
verify_api_works() {
    local response
    response=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$API_URL" \
        -H "Content-Type: application/json" \
        -d '{"data":{"key":"api_connectivity_test_key","value":"test_value"}}')

    if [[ "$response" -ge 200 && "$response" -lt 300 ]]; then
        # Sucesso, limpa a chave de teste silenciosamente
        curl -s -X DELETE "$API_URL?key=api_connectivity_test_key" > /dev/null 2>&1 || true
        return 0
    else
        echo "⚠️ Falha na verificação inicial da API (Código HTTP: $response)."
        echo "   Requisição de teste: PUT $API_URL com 'api_connectivity_test_key'"
        # Para depuração, você pode adicionar: curl -v ... aqui
        read -p "Deseja continuar mesmo assim? (S/n): " confirm_continue
        if [[ "${confirm_continue:-S}" =~ ^[Nn] ]]; then
            echo "Teste cancelado devido à falha na verificação da API."
            rm -rf "$TEMP_DIR" # Limpeza antes de sair
            exit 1
        fi
    fi
}

# Pré-população de chaves (silenciosa)
prepopulate_keys() {
    if [ "$NUM_KEYS" -gt 0 ]; then
        for i in $(seq 1 $NUM_KEYS); do
            curl -s -X PUT "$API_URL" \
                 -H "Content-Type: application/json" \
                 -d "{\"data\":{\"key\":\"siege_key_$i\",\"value\":\"prepopulated_value_$i\"}}" > /dev/null
        done
        sleep 1 # Pequena pausa para processamento
    fi
}

# Funções de execução de teste
run_put_test() {
    if [ "$NUM_KEYS" -gt 0 ]; then create_json_data_files; fi
    local urls_file
    urls_file=$(create_put_urls_file)
    echo -e "\n📊 INICIANDO TESTE DE CARGA: OPERAÇÃO PUT"
    siege -H "Content-Type: application/json" -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

run_get_test() {
    local urls_file
    urls_file=$(create_get_urls_file)
    echo -e "\n📊 INICIANDO TESTE DE CARGA: OPERAÇÃO GET"
    siege -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

run_delete_test() {
    local urls_file
    urls_file=$(create_delete_urls_file)
    echo -e "\n📊 INICIANDO TESTE DE CARGA: OPERAÇÃO DELETE"
    siege -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

# Função principal de execução
run_tests() {
    local current_test_type=$1

    # Pré-requisitos comuns
    check_curl # Curl é necessário para verify_api_works e prepopulate_keys
    verify_api_works # Verifica a API uma vez no início

    case $current_test_type in
        "put")
            run_put_test
            ;;
        "get")
            if [ "$NUM_KEYS" -gt 0 ]; then prepopulate_keys; fi
            run_get_test
            ;;
        "delete")
            if [ "$NUM_KEYS" -gt 0 ]; then prepopulate_keys; fi
            run_delete_test
            ;;
        "all")
            run_put_test
            echo -e "\n--- Teste PUT Concluído ---"
            sleep 1 # Pausa menor

            # Para 'all', GET e DELETE usam as chaves do PUT anterior, sem pré-popular novamente
            run_get_test
            echo -e "\n--- Teste GET Concluído ---"
            sleep 1 # Pausa menor

            run_delete_test
            echo -e "\n--- Teste DELETE Concluído ---"
            ;;
        *)
            echo "❌ Tipo de teste inválido: $current_test_type"
            rm -rf "$TEMP_DIR" # Limpeza antes de sair
            exit 1
            ;;
    esac
}

# Execução
create_siegerc # Cria .siegerc silenciosamente se não existir
run_tests "$TEST_TYPE"

# Limpeza final silenciosa
if [ -d "$TEMP_DIR" ]; then
  rm -rf "$TEMP_DIR"
fi

echo -e "\n🏁 Testes de carga concluídos!"
