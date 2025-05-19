#!/bin/bash
set -e

# Diretórios
TEST_PLAN_DIR="/jmeter/test-plans"
RESULTS_DIR="/jmeter/results"

# Valores padrão
HOST="localhost"
PORT="80"
USERS=10
RAMPUP=5
DURATION=60
PUT_THROUGHPUT=50
GET_THROUGHPUT=200
DELETE_THROUGHPUT=20
TEST_NAME="kv-store-test"

# Processar argumentos
while [[ $# -gt 0 ]]; do
  case $1 in
    --host=*)
      HOST="${1#*=}"
      shift
      ;;
    --port=*)
      PORT="${1#*=}"
      shift
      ;;
    --users=*)
      USERS="${1#*=}"
      shift
      ;;
    --rampup=*)
      RAMPUP="${1#*=}"
      shift
      ;;
    --duration=*)
      DURATION="${1#*=}"
      shift
      ;;
    --put-rate=*)
      PUT_THROUGHPUT="${1#*=}"
      shift
      ;;
    --get-rate=*)
      GET_THROUGHPUT="${1#*=}"
      shift
      ;;
    --delete-rate=*)
      DELETE_THROUGHPUT="${1#*=}"
      shift
      ;;
    --test-name=*)
      TEST_NAME="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  --host=HOST             API host (default: localhost)"
      echo "  --port=PORT             API port (default: 80)"
      echo "  --users=USERS           Number of concurrent users (default: 10)"
      echo "  --rampup=RAMPUP         Ramp-up period in seconds (default: 5)"
      echo "  --duration=DURATION     Test duration in seconds (default: 60)"
      echo "  --put-rate=RATE         PUT operations per second (default: 50)"
      echo "  --get-rate=RATE         GET operations per second (default: 200)"
      echo "  --delete-rate=RATE      DELETE operations per second (default: 20)"
      echo "  --test-name=NAME        Test name for results (default: kv-store-test)"
      echo "  --help                  Display this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Carimbo de data/hora para o nome do arquivo
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RESULTS_FILE="${RESULTS_DIR}/${TEST_NAME}-${TIMESTAMP}"

# Exibir configurações
echo "===================================="
echo "Iniciando teste de carga KV Store"
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

# Gerar relatório HTML se solicitado
if [[ "$GENERATE_REPORT" == "true" ]]; then
  echo "Gerando relatório HTML..."
  jmeter -g "${RESULTS_FILE}.jtl" -o "${RESULTS_DIR}/report-${TIMESTAMP}"
  echo "Relatório disponível em: ${RESULTS_DIR}/report-${TIMESTAMP}"
fi 