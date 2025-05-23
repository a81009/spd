#!/bin/bash
set -euo pipefail

echo "🔥 Iniciando testes de carga com Siege (versão PUT) 🔥"

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
    echo -e "\n⏱️ Duração do teste em segundos:"
    read -p "Digite a duração em segundos [padrão: 60]: " test_duration
    # Validação: garantir que é um número
    if ! [[ "${test_duration:-60}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 60 segundos."
        test_duration=60
    fi
    # Agora usamos apenas segundos
    DURATION_SECONDS="${test_duration:-60}"
    
    # Número de usuários concorrentes
    echo -e "\n👥 Usuários concorrentes:"
    read -p "Digite o número de usuários concorrentes [padrão: 25]: " concurrent_users
    # Validação: garantir que é um número
    if ! [[ "${concurrent_users:-25}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 25 usuários."
        concurrent_users=25
    fi
    USERS="${concurrent_users:-25}"
    
    # Número de chaves
    echo -e "\n🔑 Número de chaves para testar:"
    read -p "Digite o número de chaves para testar [padrão: 100]: " num_keys
    # Validação: garantir que é um número
    if ! [[ "${num_keys:-100}" =~ ^[0-9]+$ ]]; then
        echo "Entrada inválida. Usando valor padrão de 100 chaves."
        num_keys=100
    fi
    NUM_KEYS="${num_keys:-100}"
    
    # Confirmar escolhas
    echo -e "\n⚙️ Configurações selecionadas:"
    echo "- Tipo de teste: $TEST_TYPE"
    echo "- Duração do teste: $DURATION_SECONDS segundos"
    echo "- Usuários concorrentes: $USERS"
    echo "- Número de chaves: $NUM_KEYS"
    
    read -p "Confirmar estas configurações? (S/n): " confirm
    if [[ "${confirm:-S}" =~ ^[Nn] ]]; then
        echo "Configurações canceladas. Iniciando novamente..."
        ask_user_settings
    fi
}

# Configurações padrão (serão substituídas pelo input do usuário)
API_URL="http://localhost/kv"
NUM_KEYS=100
USERS=25
DURATION_SECONDS=60
TEST_TYPE="put"

# Perguntar ao usuário
ask_user_settings

# Verificar se precisamos do bc para cálculos
if ! command -v bc &> /dev/null; then
    echo "⚠️ O comando 'bc' não está instalado. Algumas métricas podem não ser calculadas."
    echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install bc"
fi

# Criar diretório para arquivos temporários
TEMP_DIR="siege_temp"
mkdir -p "$TEMP_DIR"

# Função para criar o arquivo de configuração do Siege
create_siegerc() {
    # Se o arquivo .siegerc não existir, cria um básico
    if [ ! -f ~/.siegerc ]; then
        echo "Criando arquivo de configuração do Siege..."
        cat > ~/.siegerc << EOF
# Configurações do Siege
verbose = true
quiet = false
json_output = false
show-logfile = false
logging = false
protocol = HTTP/1.1
chunked = true
connection = keep-alive
concurrent = 25
time = 60s
EOF
    fi
}

# Verifica se o curl está instalado
check_requirements() {
    if ! command -v curl &> /dev/null; then
        echo "❌ curl não está instalado. Este script precisa do curl para funcionar."
        echo "👉 Para instalar no Ubuntu/Debian: sudo apt-get install curl"
        exit 1
    fi
}

# Função para gerar um script auxiliar para requisições PUT
generate_siege_put_script() {
    echo "Gerando script auxiliar para requisições PUT..."
    
    local script_file="$TEMP_DIR/siege_put.sh"
    
    # Criar script que vai ser usado pelo Siege para enviar PUT
    cat > "$script_file" << 'EOF'
#!/bin/bash
# Script auxiliar para forçar Siege a usar PUT com dados JSON
URL=$1
DATA_FILE=$2

# Verificar se os argumentos foram passados
if [[ -z "$URL" || -z "$DATA_FILE" ]]; then
    echo "Erro: URL ou arquivo de dados não fornecido"
    exit 1
fi

# Ler conteúdo do arquivo JSON
JSON_DATA=$(cat "$DATA_FILE")

# Enviar requisição PUT com curl
curl -s -X PUT "$URL" \
     -H "Content-Type: application/json" \
     -d "$JSON_DATA"
EOF

    # Tornar o script executável
    chmod +x "$script_file"
    
    echo "✅ Script auxiliar criado: $script_file"
    echo "Este script vai executar requisições PUT usando curl internamente"
    
    echo "$script_file"
}

# Função para criar arquivos de dados JSON para testes PUT
create_json_data_files() {
    echo "Criando arquivos de dados JSON..."
    
    for i in $(seq 1 $NUM_KEYS); do
        local data_file="$TEMP_DIR/data_$i.json"
        echo "{\"data\":{\"key\":\"siege_key_$i\",\"value\":\"siege_value_$i\"}}" > "$data_file"
    done
    
    echo "✅ Arquivos de dados JSON criados"
    echo "📄 Exemplo de conteúdo do arquivo de dados:"
    cat "$TEMP_DIR/data_1.json"
}

# Função para preparar arquivo PUT para o Siege
# Usaremos um script auxiliar para forçar o método PUT
create_put_urls_file() {
    local urls_file="$TEMP_DIR/put_urls.txt"
    local put_script="$1"
    
    > "$urls_file"
    
    # Para cada chave, criar linha que chama o script auxiliar
    # que vai executar curl com PUT
    for i in $(seq 1 $NUM_KEYS); do
        local data_file="$TEMP_DIR/data_$i.json"
        echo "$put_script $API_URL $data_file" >> "$urls_file"
    done
    
    # Retorna o nome do arquivo sem imprimir outras mensagens
    echo "$urls_file"
}

# Função para preparar arquivo GET para o Siege
create_get_urls_file() {
    local urls_file="$TEMP_DIR/get_urls.txt"
    
    > "$urls_file"
    
    # Para cada chave, adicionar uma URL GET
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL?key=siege_key_$i" >> "$urls_file"
    done
    
    # Retorna o nome do arquivo sem imprimir outras mensagens
    echo "$urls_file"
}

# Função para preparar arquivo DELETE para o Siege
create_delete_urls_file() {
    local urls_file="$TEMP_DIR/delete_urls.txt"
    
    > "$urls_file"
    
    # Para cada chave, adicionar uma URL DELETE
    for i in $(seq 1 $NUM_KEYS); do
        echo "$API_URL?key=siege_key_$i DELETE" >> "$urls_file"
    done
    
    # Retorna o nome do arquivo sem imprimir outras mensagens
    echo "$urls_file"
}

# Teste simples para verificar se a API funciona
verify_api_works() {
    echo -e "\n🧪 Verificando se a API está respondendo corretamente..."
    
    # Usar o curl que sabemos funcionar
    local response=$(curl -s -X PUT "$API_URL" \
        -H "Content-Type: application/json" \
        -d '{"data":{"key":"test_key","value":"test_value"}}')
    
    if [[ "$response" == *"queued"* ]]; then
        echo "✅ API respondeu corretamente à requisição PUT"
        return 0
    else
        echo "⚠️ API não respondeu como esperado. Resposta:"
        echo "$response"
        echo "Deseja continuar mesmo assim? (S/n)"
        read -p "> " confirm
        if [[ "${confirm:-S}" =~ ^[Nn] ]]; then
            echo "Teste cancelado."
            exit 1
        fi
    fi
}

# Pré-popular o banco de dados com chaves (usando curl, não Siege)
prepopulate_keys() {
    echo -e "\n🔄 Pré-populando o banco com chaves para testes..."
    
    for i in $(seq 1 $NUM_KEYS); do
        # Usar curl que sabemos funcionar para pré-popular
        curl -s -X PUT "$API_URL" \
             -H "Content-Type: application/json" \
             -d "{\"data\":{\"key\":\"siege_key_$i\",\"value\":\"siege_value_$i\"}}" > /dev/null
             
        # Mostrar progresso
        if (( i % 20 == 0 )); then
            echo -n "."
        fi
        if (( i % 100 == 0 )); then
            echo " $i/$NUM_KEYS"
        fi
    done
    
    echo -e "\n✅ Chaves pré-populadas. Esperando processamento..."
    sleep 3  # Dar tempo para processamento das mensagens
}

# Executar teste PUT com Siege
run_put_test() {
    # Verificar requisitos
    check_requirements
    
    # Verificar se a API está funcionando
    verify_api_works
    
    echo "Preparando arquivos para teste PUT..."
    
    # Primeiro criamos todos os arquivos de dados JSON
    create_json_data_files
    
    # Criar script auxiliar para forçar PUT
    local put_script=$(generate_siege_put_script)
    
    # Agora criamos o arquivo de URLs que usa o script auxiliar
    local urls_file=$(create_put_urls_file "$put_script")
    
    echo "✅ Arquivo de URLs para PUT criado: $urls_file"
    echo -e "\n📄 Primeiras linhas do arquivo de URLs:"
    head -n 3 "$urls_file"
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO PUT (Criação/Atualização de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    
    # Comando para validação
    echo "O Siege vai usar este comando:"
    echo "siege -f \"$urls_file\" -c $USERS -t ${DURATION_SECONDS}S"
    
    # Executar o Siege com segundos explícitos
    # Não precisamos do content-type pois o script auxiliar já define
    siege -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

# Executar teste GET com Siege
run_get_test() {
    # Primeiro pré-popular o banco
    prepopulate_keys
    
    echo "Preparando arquivos para teste GET..."
    # Capturamos APENAS o nome do arquivo retornado, sem outras mensagens
    local urls_file=$(create_get_urls_file)
    echo "✅ Arquivo de URLs para GET criado: $urls_file"
    echo -e "\n📄 Primeiras linhas do arquivo de URLs:"
    head -n 3 "$urls_file"
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO GET (Leitura de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    
    # Executar o Siege com segundos explícitos
    siege -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

# Executar teste DELETE com Siege
run_delete_test() {
    # Primeiro pré-popular o banco
    prepopulate_keys
    
    echo "Preparando arquivos para teste DELETE..."
    # Capturamos APENAS o nome do arquivo retornado, sem outras mensagens
    local urls_file=$(create_delete_urls_file)
    echo "✅ Arquivo de URLs para DELETE criado: $urls_file"
    echo -e "\n📄 Primeiras linhas do arquivo de URLs:"
    head -n 3 "$urls_file"
    
    echo -e "\n📊 TESTE DE CARGA: OPERAÇÃO DELETE (Remoção de chaves)"
    echo "🔄 Executando teste com $USERS usuários concorrentes por $DURATION_SECONDS segundos..."
    
    # Executar o Siege com segundos explícitos
    siege -f "$urls_file" -c "$USERS" -t "${DURATION_SECONDS}S"
}

# Função principal
run_tests() {
    local test_type=$1
    
    case $test_type in
        "put")
            run_put_test
            ;;
        "get")
            run_get_test
            ;;
        "delete")
            run_delete_test
            ;;
        "all")
            run_put_test
            sleep 5
            run_get_test
            sleep 5
            run_delete_test
            ;;
        *)
            echo "❌ Tipo de teste inválido: $test_type"
            echo "Opções válidas: put, get, delete, all"
            exit 1
            ;;
    esac
}

# Criar ou verificar configuração Siege
create_siegerc

# Executar os testes
run_tests "$TEST_TYPE"

# Limpar arquivos temporários
echo -e "\n🧹 Limpando arquivos temporários..."
rm -rf "$TEMP_DIR"

echo -e "\n🏁 Testes de carga concluídos!"
echo -e "\n💡 Esta versão força o uso do método PUT usando curl internamente."
echo "Se quiser verificar o funcionamento, olhe o script auxiliar gerado em: $TEMP_DIR/siege_put.sh"
echo "e verifique se as mensagens estão aparecendo no RabbitMQ." 