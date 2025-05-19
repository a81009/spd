#!/bin/bash
set -e

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PLAN_DIR="${SCRIPT_DIR}/jmeter/test-plans"
RESULTS_DIR="${SCRIPT_DIR}/jmeter/results"
JMETER_LOG_DIR="${SCRIPT_DIR}/jmeter/logs"

# Encontrar JMeter
check_jmeter() {
    JMETER_CMD=$(which jmeter 2>/dev/null || echo "")
    
    if [ -z "$JMETER_CMD" ]; then
        for path in "/usr/bin/jmeter" "/usr/local/bin/jmeter" "/opt/jmeter/bin/jmeter" "$HOME/jmeter/bin/jmeter"; do
            if [ -x "$path" ]; then
                JMETER_CMD="$path"
                break
            fi
        done
    fi
    
    if [ -z "$JMETER_CMD" ]; then
        echo "Apache JMeter não está instalado. Por favor, instale o JMeter primeiro."
        echo "Você pode instalar via:"
        echo "  1. Download direto: https://jmeter.apache.org/download_jmeter.cgi"
        echo "  2. Ou usando package manager (exemplo Ubuntu/Debian):"
        echo "     sudo apt-get update && sudo apt-get install jmeter"
        exit 1
    fi
    
    JMETER_VERSION=$("$JMETER_CMD" --version 2>/dev/null | head -n 1 || "$JMETER_CMD" -v 2>/dev/null | head -n 1)
    
    if [[ "$JMETER_VERSION" =~ 5\.|6\. ]]; then
        IS_JMETER_5_PLUS=true
    else
        IS_JMETER_5_PLUS=false
    fi
    
    export JMETER_CMD
    export IS_JMETER_5_PLUS
}

# Criar diretórios necessários
mkdir -p "$TEST_PLAN_DIR"
mkdir -p "$RESULTS_DIR"
mkdir -p "$JMETER_LOG_DIR"
chmod -R 777 "${SCRIPT_DIR}/jmeter"

# Leitura com valores padrão
read_input() {
    local prompt=$1
    local default=$2
    local value
    
    read -p "${prompt} [${default}]: " value
    echo ${value:-$default}
}

# Verificar JMeter
check_jmeter

# Leitura interativa dos parâmetros (com localhost:8000 por padrão)
echo "===================================="
echo "Configuração do Teste de Carga"
echo "===================================="

HOST="localhost"
PORT="8000"
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
RESULTS_CSV="${RESULTS_FILE}.csv"
LOG_FILE="${JMETER_LOG_DIR}/${TEST_NAME}-${TIMESTAMP}.log"

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
echo "Arquivo resultados: $RESULTS_CSV"
echo "===================================="

# Confirmar execução
read -p "Deseja iniciar o teste com estas configurações? (s/N) " confirm
if [[ ! $confirm =~ ^[Ss]$ ]]; then
    echo "Teste cancelado pelo usuário."
    exit 0
fi

# Criar arquivo JMX
TEST_PLAN_FILE="${TEST_PLAN_DIR}/kv-store-test-${TIMESTAMP}.jmx"

if [ "$IS_JMETER_5_PLUS" = true ]; then
    cat > "$TEST_PLAN_FILE" << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Test Plan">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Thread Group">
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <intProp name="LoopController.loops">-1</intProp>
        </elementProp>
        <stringProp name="ThreadGroup.num_threads">${__P(users,10)}</stringProp>
        <stringProp name="ThreadGroup.ramp_time">${__P(rampup,5)}</stringProp>
        <longProp name="ThreadGroup.start_time">1432618622000</longProp>
        <longProp name="ThreadGroup.end_time">1432618622000</longProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
        <stringProp name="ThreadGroup.duration">${__P(duration,60)}</stringProp>
        <stringProp name="ThreadGroup.delay">0</stringProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Request">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,8000)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv/1</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree/>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOL
else
    cat > "$TEST_PLAN_FILE" << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="2.1">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="Test Plan">
      <stringProp name="TestPlan.comments"></stringProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Thread Group">
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <stringProp name="LoopController.loops">100</stringProp>
        </elementProp>
        <stringProp name="ThreadGroup.num_threads">${__P(users,10)}</stringProp>
        <stringProp name="ThreadGroup.ramp_time">${__P(rampup,5)}</stringProp>
        <longProp name="ThreadGroup.start_time">1685193386000</longProp>
        <longProp name="ThreadGroup.end_time">1685193386000</longProp>
        <boolProp name="ThreadGroup.scheduler">false</boolProp>
        <stringProp name="ThreadGroup.duration"></stringProp>
        <stringProp name="ThreadGroup.delay"></stringProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="HTTP Request">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,8000)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv/1</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree/>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOL
fi

echo "===================================="
echo "Executando teste de carga..."
echo "===================================="

# Configurar JMeter
export JVM_ARGS="-Djava.io.tmpdir=$JMETER_LOG_DIR -Djava.awt.headless=true"
touch "$RESULTS_CSV"
chmod 777 "$RESULTS_CSV"

# Executar JMeter
if [ "$IS_JMETER_5_PLUS" = true ]; then
    "$JMETER_CMD" --nongui \
           --testfile "$TEST_PLAN_FILE" \
           --logfile "$LOG_FILE" \
           --jmeterlogfile "$JMETER_LOG_DIR/jmeter.log" \
           -Jhost="$HOST" \
           -Jport="$PORT" \
           -Jusers="$USERS" \
           -Jrampup="$RAMPUP" \
           -Jduration="$DURATION" \
           --reportatendofloadtests \
           --reportoutputfolder "${RESULTS_DIR}/report-${TIMESTAMP}" \
           -l "$RESULTS_CSV"
else
    "$JMETER_CMD" -n -t "$TEST_PLAN_FILE" \
           -Jhost="$HOST" \
           -Jport="$PORT" \
           -Jusers="$USERS" \
           -Jrampup="$RAMPUP" \
           -l "$RESULTS_CSV" > "$LOG_FILE" 2>&1
fi

# Verificar resultado
if [ $? -eq 0 ]; then
    echo "===================================="
    echo "Teste concluído com sucesso!"
    echo "===================================="
else
    echo "===================================="
    echo "ERRO: Teste falhou"
    echo "Verifique o log: $LOG_FILE"
    echo "===================================="
    exit 1
fi

# Verificar resultados
if [ -f "$RESULTS_CSV" ] && [ -s "$RESULTS_CSV" ]; then
    echo "Arquivo de resultados: $RESULTS_CSV"
    echo "Relatório HTML: ${RESULTS_DIR}/report-${TIMESTAMP}"
else
    echo "AVISO: Arquivo de resultados não foi criado"
fi

echo "===================================="
echo "Teste concluído!"
echo "====================================" 