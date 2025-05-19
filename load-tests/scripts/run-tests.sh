#!/bin/bash
set -e

# Verificar se o JMeter está instalado
check_jmeter() {
    if ! command -v jmeter &> /dev/null; then
        echo "Apache JMeter não está instalado. Por favor, instale o JMeter primeiro."
        echo "Você pode instalar via:"
        echo "  1. Download direto: https://jmeter.apache.org/download_jmeter.cgi"
        echo "  2. Ou usando package manager (exemplo Ubuntu/Debian):"
        echo "     sudo apt-get update && sudo apt-get install jmeter"
        exit 1
    fi
}

# Diretórios
TEST_PLAN_DIR="/jmeter/test-plans"
RESULTS_DIR="/jmeter/results"

# Função para ler input do usuário com valor padrão
read_input() {
    local prompt=$1
    local default=$2
    local value
    
    read -p "${prompt} [${default}]: " value
    echo ${value:-$default}
}

# Verificar JMeter
check_jmeter

# Leitura interativa dos parâmetros
echo "===================================="
echo "Configuração do Teste de Carga"
echo "===================================="

HOST=$(read_input "Host" "localhost")
PORT=$(read_input "Porta" "80")
USERS=$(read_input "Número de usuários concorrentes" "10")
RAMPUP=$(read_input "Tempo de ramp-up (segundos)" "5")
DURATION=$(read_input "Duração do teste (segundos)" "60")
PUT_THROUGHPUT=$(read_input "Taxa de operações PUT por segundo" "50")
GET_THROUGHPUT=$(read_input "Taxa de operações GET por segundo" "200")
DELETE_THROUGHPUT=$(read_input "Taxa de operações DELETE por segundo" "20")
TEST_NAME=$(read_input "Nome do teste" "kv-store-test")

# Carimbo de data/hora para o nome do arquivo
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RESULTS_FILE="${RESULTS_DIR}/${TEST_NAME}-${TIMESTAMP}"

# Exibir configurações finais
echo "===================================="
echo "Configurações do teste:"
echo "===================================="
echo "Host:               $HOST"
echo "Porta:              $PORT"
echo "Usuários:           $USERS"
echo "Ramp-up:            $RAMPUP segundos"
echo "Duração:            $DURATION segundos"
echo "Taxa PUT:           $PUT_THROUGHPUT/seg"
echo "Taxa GET:           $GET_THROUGHPUT/seg"
echo "Taxa DELETE:        $DELETE_THROUGHPUT/seg"
echo "Arquivo resultados: $RESULTS_FILE"
echo "===================================="

# Confirmar execução
read -p "Deseja iniciar o teste com estas configurações? (s/N) " confirm
if [[ ! $confirm =~ ^[Ss]$ ]]; then
    echo "Teste cancelado pelo usuário."
    exit 0
fi

# Criar diretório de resultados se não existir
mkdir -p "$RESULTS_DIR"

# Executar JMeter em modo não-GUI
jmeter -n -t "${TEST_PLAN_DIR}/kv-store-test.jmx" \
  -Jhost="$HOST" \
  -Jport="$PORT" \
  -Jusers="$USERS" \
  -Jrampup="$RAMPUP" \
  -Jduration="$DURATION" \
  -Jput_throughput="$PUT_THROUGHPUT" \
  -Jget_throughput="$GET_THROUGHPUT" \
  -Jdelete_throughput="$DELETE_THROUGHPUT" \
  -Jresults_file="${RESULTS_FILE}-aggregate.csv" \
  -Jperfmon_file="${RESULTS_FILE}-perfmon.csv" \
  -Jtps_file="${RESULTS_FILE}-tps.csv" \
  -Jerror_file="${RESULTS_FILE}-errors.xml" \
  -l "${RESULTS_FILE}.jtl"

echo "===================================="
echo "Teste concluído!"
echo "Resultados salvos em: $RESULTS_FILE"
echo "===================================="

# Perguntar se deseja gerar relatório HTML
read -p "Deseja gerar um relatório HTML dos resultados? (s/N) " generate_report
if [[ $generate_report =~ ^[Ss]$ ]]; then
    echo "Gerando relatório HTML..."
    jmeter -g "${RESULTS_FILE}.jtl" -o "${RESULTS_DIR}/report-${TIMESTAMP}"
    echo "Relatório disponível em: ${RESULTS_DIR}/report-${TIMESTAMP}"
fi 