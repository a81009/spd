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
        *) echo "Opção inválida, usando PUT"; TEST_TYPE="put" ;;
    esac

    # Duração do teste em segundos
    echo -e "\n⏱️  Duração do teste em segundos:"
    read -p "Digite a duração em segundos [padrão: 60]: " test_duration_input
    if ! [[ "${test_duration_input:-60}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 60 segundos." >&2
        test_duration_input=60
    fi
    DURATION_SECONDS="${test_duration_input:-60}"

    # Número de usuários concorrentes
    echo -e "\n👥 Usuários concorrentes:"
    read -p "Digite o número de usuários concorrentes [padrão: 25]: " concurrent_users_input
    if ! [[ "${concurrent_users_input:-25}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 25 usuários." >&2
        concurrent_users_input=25
    fi
    USERS="${concurrent_users_input:-25}"

    # Número de chaves
    echo -e "\n🔑 Número de chaves para testar:"
    read -p "Digite o número de chaves para testar (para pré-população e variedade de URLs) [padrão: 100]: " num_keys_input
    if ! [[ "${num_keys_input:-100}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 100 chaves." >&2
        num_keys_input=100
    fi
    USER_REQUESTED_NUM_KEYS="${num_keys_input:-100}" # Número que o usuário realmente pediu

    MAX_URL_FILE_ENTRIES=50000 # Limite máximo de arquivos/URLs únicos para o Siege
    NUM_KEYS_FOR_FILE_GENERATION=$USER_REQUESTED_NUM_KEYS

    if [ "$USER_REQUESTED_NUM_KEYS" -gt "$MAX_URL_FILE_ENTRIES" ]; then
        echo "⚠️  O número de chaves solicitado ($USER_REQUESTED_NUM_KEYS) é alto para gerar arquivos de URL/dados individuais." >&2
        echo "    Limitando o número de arquivos de dados JSON e entradas nos arquivos de URL do Siege a $MAX_URL_FILE_ENTRIES." >&2
        echo "    Isso afeta a variedade de chaves *únicas* que o Siege usará por ciclo no arquivo de URLs." >&2
        NUM_KEYS_FOR_FILE_GENERATION=$MAX_URL_FILE_ENTRIES
    fi

    echo -e "\n⚙️ Configurações selecionadas:"
    echo "- Tipo de teste: $TEST_TYPE"
    echo "- Duração do teste: $DURATION_SECONDS segundos"
    echo "- Usuários concorrentes: $USERS"
    echo "- Número de chaves (solicitado pelo usuário para o dataset): $USER_REQUESTED_NUM_KEYS"
    if [ "$USER_REQUESTED_NUM_KEYS" -ne "$NUM_KEYS_FOR_FILE_GENERATION" ]; then
        echo "- Número de chaves (para arquivos de URL/dados do Siege): $NUM_KEYS_FOR_FILE_GENERATION"
    else
        echo "- Número de chaves (para arquivos de URL/dados do Siege): $NUM_KEYS_FOR_FILE_GENERATION"
    fi


    read -p "Confirmar estas configurações? (S/n): " confirm
    if [[ "${confirm:-S}" =~ ^[Nn] ]]; then
        echo "Configurações canceladas. Iniciando novamente..." >&2
        ask_user_settings # Recursive call
    fi
}

API_URL="http://localhost/kv" # URL base da API
# Configurações padrão são substituídas por ask_user_settings
USER_REQUESTED_NUM_KEYS=100
NUM_KEYS_FOR_FILE_GENERATION=100
USERS=25
DURATION_SECONDS=60
TEST_TYPE="put"

ask_user_settings

if ! command -v bc &> /dev/null; then
    echo "⚠️ O comando 'bc' não está instalado. Algumas métricas podem não ser calculadas." >&2
    echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install bc" >&2
fi

TEMP_DIR="siege_temp"
mkdir -p "$TEMP_DIR"

check_requirements() {
    if ! command -v curl &> /dev/null; then
        echo "❌ curl não está instalado. Este script precisa do curl para o script auxiliar e verificação da API." >&2
        echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install curl" >&2
        exit 1
    fi
}

generate_curl_put_helper_script() {
    echo "Gerando script auxiliar com curl para requisições PUT (para testes manuais)..."
    local script_file="$TEMP_DIR/manual_put_request.sh"

    cat > "$script_file" << EOF
#!/bin/bash
# Script auxiliar para forçar Siege a usar PUT com dados JSON (USO MANUAL com curl)
URL=\$1
DATA_FILE=\$2

if [[ -z "\$URL" || -z "\$DATA_FILE" ]]; then
    echo "Erro: URL ou arquivo de dados não fornecido" >&2
    echo "Uso: \$0 <URL> <DATA_FILE_PATH>" >&2
    exit 1
fi
if [ ! -f "\$DATA_FILE" ]; then
    echo "Erro: Arquivo de dados '\$DATA_FILE' não encontrado." >&2
    exit 1
fi

JSON_DATA=\$(cat "\$DATA_FILE")

curl -s -v -X PUT "\$URL" \\
     -H "Content-Type: application/json" \\
     -d "\$JSON_DATA"
echo "" # Newline
EOF
    chmod +x "$script_file"
    echo "✅ Script auxiliar para curl criado: $script_file"
    echo "   Ex: $script_file $API_URL $TEMP_DIR/data_1.json"
}

create_json_data_files() {
    echo "Criando $NUM_KEYS_FOR_FILE_GENERATION arquivos de dados JSON..."
    local count=0
    for i in $(seq 1 "$NUM_KEYS_FOR_FILE_GENERATION"); do
        local data_file="$TEMP_DIR/data_$i.json"
        printf "{\"data\":{\"key\":\"siege_key_%s\",\"value\":\"siege_value_%s\"}}\n" "$i" "$i" > "$data_file"
        count=$((count + 1))
        if (( count % 1000 == 0 && NUM_KEYS_FOR_FILE_GENERATION > 5000 )); then echo -n "."; fi
    done
    echo -e "\n✅ $count arquivos de dados JSON criados em $TEMP_DIR/"
    if [ "$count" -gt 0 ]; then
        echo "📄 Exemplo de conteúdo do arquivo de dados ($TEMP_DIR/data_1.json):"
        cat "$TEMP_DIR/data_1.json"
    fi
}

create_put_urls_file() {
    local urls_file="$TEMP_DIR/put_urls.txt"
    echo "Criando arquivo de URLs PUT com $NUM_KEYS_FOR_FILE_GENERATION entradas..." >&2
    (
    for i in $(seq 1 "$NUM_KEYS_FOR_FILE_GENERATION"); do
        local data_file="$TEMP_DIR/data_$i.json"
        printf "%s PUT <%s\n" "$API_URL" "$data_file"
        if (( i % 1000 == 0 && NUM_KEYS_FOR_FILE_GENERATION > 5000 )); then echo -n "." >&2; fi
    done
    ) > "$urls_file"
    echo -e "\n✅ Arquivo de URLs para PUT criado: $urls_file" >&2
    echo "$urls_file"
}

create_get_urls_file() {
    local urls_file="$TEMP_DIR/get_urls.txt"
    echo "Criando arquivo de URLs GET com $NUM_KEYS_FOR_FILE_GENERATION entradas..." >&2
    (
    for i in $(seq 1 "$NUM_KEYS_FOR_FILE_GENERATION"); do
        printf "%s?key=siege_key_%s\n" "$API_URL" "$i"
        if (( i % 1000 == 0 && NUM_KEYS_FOR_FILE_GENERATION > 5000 )); then echo -n "." >&2; fi
    done
    ) > "$urls_file"
    echo -e "\n✅ Arquivo de URLs para GET criado: $urls_file" >&2
    echo "$urls_file"
}

create_delete_urls_file() {
    local urls_file="$TEMP_DIR/delete_urls.txt"
    echo "Criando arquivo de URLs DELETE com $NUM_KEYS_FOR_FILE_GENERATION entradas..." >&2
    (
    for i in $(seq 1 "$NUM_KEYS_FOR_FILE_GENERATION"); do
        printf "%s?key=siege_key_%s DELETE\n" "$API_URL" "$i"
        if (( i % 1000 == 0 && NUM_KEYS_FOR_FILE_GENERATION > 5000 )); then echo -n "." >&2; fi
    done
    ) > "$urls_file"
    echo -e "\n✅ Arquivo de URLs para DELETE criado: $urls_file" >&2
    echo "$urls_file"
}

verify_api_works() {
    echo -e "\n🧪 Verificando se a API está respondendo corretamente..."
    local response_code
    response_code=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$API_URL" \
        -H "Content-Type: application/json" \
        -d '{"data":{"key":"api_check_key","value":"api_check_value"}}')

    if [[ "$response_code" -ge 200 && "$response_code" -lt 300 ]]; then
        echo "✅ API respondeu corretamente à requisição PUT de verificação (HTTP $response_code)"
        curl -s -o /dev/null -X DELETE "$API_URL?key=api_check_key" # Limpa a chave de teste
        return 0
    else
        echo "⚠️ API não respondeu como esperado na verificação (HTTP $response_code)." >&2
        local full_response
        full_response=$(curl -s -X PUT "$API_URL" -H "Content-Type: application/json" -d '{"data":{"key":"api_check_key","value":"api_check_value"}}')
        echo "Resposta completa (se houver): $full_response" >&2
        read -p "Deseja continuar mesmo assim? (S/n): " confirm_continue
        if [[ "${confirm_continue:-S}" =~ ^[Nn] ]]; then
            echo "Teste cancelado." >&2
            exit 1
        fi
    fi
}

prepopulate_keys() {
    echo -e "\n🔄 Pré-populando o banco com $USER_REQUESTED_NUM_KEYS chaves para testes GET/DELETE..."
    echo "   (As URLs de GET/DELETE geradas para o Siege usarão as primeiras $NUM_KEYS_FOR_FILE_GENERATION chaves deste conjunto)"

    if [ "$USER_REQUESTED_NUM_KEYS" -gt 20000 ]; then
        echo "⚠️  Este número de chaves para pré-popular ($USER_REQUESTED_NUM_KEYS) é grande e pode demorar bastante." >&2
        read -p "    Confirmar pré-população de todas as $USER_REQUESTED_NUM_KEYS chaves? (S/n): " confirm_prepop
        if [[ "${confirm_prepop:-S}" =~ ^[Nn] ]]; then
            echo "Pré-população cancelada. Os testes GET/DELETE podem não ter dados ou ter dados insuficientes." >&2
            return
        fi
    fi

    local count=0
    for i in $(seq 1 "$USER_REQUESTED_NUM_KEYS"); do
        curl -s -X PUT "$API_URL" \
             -H "Content-Type: application/json" \
             -d "{\"data\":{\"key\":\"siege_key_$i\",\"value\":\"prepopulated_value_$i\"}}" -o /dev/null
        count=$((count + 1))
        if (( count % 20 == 0 )); then echo -n "."; fi
        if (( count % 250 == 0 )) || [ "$count" == "$USER_REQUESTED_NUM_KEYS" ]; then
             echo " $count/$USER_REQUESTED_NUM_KEYS"
        fi
    done
    echo -e "\n✅ $count chaves pré-populadas. Esperando um momento para processamento pela API..."
    sleep 3
}

run_put_test() {
    check_requirements
    verify_api_works

    echo "Preparando arquivos para teste PUT..."
    create_json_data_files
    generate_curl_put_helper_script

    local urls_file
    urls_file=$(create_put_urls_file)

    echo -e "\n📄 Primeiras linhas do arquivo de URLs ($urls_file):"
    head -n 3 "$urls_file"

    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO PUT (Criação/Atualização de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    echo "   Siege usará $NUM_KEYS_FOR_FILE_GENERATION URLs/arquivos de dados únicos e os reutilizará se necessário."

    local siege_command="siege -H \"Content-Type: application/json\" -f \"$urls_file\" -c \"$USERS\" -t \"${DURATION_SECONDS}S\" --log=$TEMP_DIR/siege_put_results.log --json-output"
    echo "Comando do Siege:"
    echo "$siege_command"
    eval "$siege_command"
}

run_get_test() {
    check_requirements
    verify_api_works
    prepopulate_keys

    echo "Preparando arquivos para teste GET..."
    local urls_file
    urls_file=$(create_get_urls_file)
    echo -e "\n📄 Primeiras linhas do arquivo de URLs ($urls_file):"
    head -n 3 "$urls_file"

    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO GET (Leitura de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    echo "   Siege tentará ler chaves do conjunto de $NUM_KEYS_FOR_FILE_GENERATION URLs gerados."

    local siege_command="siege -f \"$urls_file\" -c \"$USERS\" -t \"${DURATION_SECONDS}S\" --log=$TEMP_DIR/siege_get_results.log --json-output"
    echo "Comando do Siege:"
    echo "$siege_command"
    eval "$siege_command"
}

run_delete_test() {
    check_requirements
    verify_api_works
    prepopulate_keys

    echo "Preparando arquivos para teste DELETE..."
    local urls_file
    urls_file=$(create_delete_urls_file)
    echo -e "\n📄 Primeiras linhas do arquivo de URLs ($urls_file):"
    head -n 3 "$urls_file"

    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO DELETE (Remoção de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    echo "   Siege tentará remover chaves do conjunto de $NUM_KEYS_FOR_FILE_GENERATION URLs gerados."

    local siege_command="siege -f \"$urls_file\" -c \"$USERS\" -t \"${DURATION_SECONDS}S\" --log=$TEMP_DIR/siege_delete_results.log --json-output"
    echo "Comando do Siege:"
    echo "$siege_command"
    eval "$siege_command"
}

cleanup() {
    echo -e "\n🧹 Limpando arquivos temporários em $TEMP_DIR..."
    echo "Diretório temporário $TEMP_DIR foi mantido para análise. Apague-o manualmente se desejar."
}


# --- Main Logic ---
case "$TEST_TYPE" in
    put)
        run_put_test
        ;;
    get)
        run_get_test
        ;;
    delete)
        run_delete_test
        ;;
    all)
        run_put_test
        echo -e "\n---\n"
        run_get_test
        echo -e "\n---\n"
        run_delete_test
        ;;
esac

cleanup

echo -e "\n🏁 Testes de carga concluídos!"
echo -e "\n💡 DICAS DE PERFORMANCE E ANÁLISE:"
echo "   - Se a 'transaction_rate' (taxa de transações) não aumenta significativamente ao adicionar mais usuários"
echo "     ou ao aumentar a duração do teste, o gargalo provavelmente está no seu servidor (API, banco de dados, etc.)."
echo "   - MONITORE OS RECURSOS DO SERVIDOR (CPU, Memória, I/O de disco, Rede) durante a execução dos testes."
echo "     Ferramentas como 'htop', 'vmstat', 'iostat', 'netstat' no servidor podem ajudar a identificar o gargalo."
echo "   - O 'response_time' (tempo de resposta) reportado pelo Siege é um indicador crucial. Um tempo de resposta alto"
echo "     sob carga limita diretamente a taxa de transações (Taxa de Transações ≈ Concorrência / Tempo de Resposta)."
echo "   - Para este teste, foram gerados no máximo $NUM_KEYS_FOR_FILE_GENERATION URLs/arquivos de dados únicos para o Siege."
echo "     O Siege reutiliza esses URLs se o teste for longo ou a taxa de processamento do servidor for alta."
echo "   - Os resultados detalhados do Siege (se o logging foi habilitado no comando) estão em arquivos dentro de '$TEMP_DIR/'."
echo "   - O script auxiliar para testes manuais de PUT com curl (se gerado) está em: $TEMP_DIR/manual_put_request.sh"
echo "   - Verifique se as mensagens estão sendo processadas corretamente pelo seu backend (ex: RabbitMQ), se aplicável."
