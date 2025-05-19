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

# Diretórios (usando caminhos relativos)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PLAN_DIR="${SCRIPT_DIR}/jmeter/test-plans"
RESULTS_DIR="${SCRIPT_DIR}/jmeter/results"

# Criar diretórios necessários
mkdir -p "$TEST_PLAN_DIR"
mkdir -p "$RESULTS_DIR"

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

# Mostrar versão do JMeter
JMETER_VERSION=$(jmeter -v | head -n 1)
echo "Versão do JMeter: $JMETER_VERSION"

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
RESULTS_CSV="${RESULTS_FILE}.csv"

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

# Criar um arquivo JMX simples (formato CSV para evitar problemas de XStream)
TEST_PLAN_FILE="${TEST_PLAN_DIR}/kv-store-test-simple.jmx"

cat > "$TEST_PLAN_FILE" << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="2.1">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store Test Plan">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
      <stringProp name="TestPlan.user_define_classpath"></stringProp>
      <boolProp name="TestPlan.serialize_threadgroups">false</boolProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <stringProp name="TestPlan.comments"></stringProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Thread Group">
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController" testname="Loop Controller">
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
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
            <collectionProp name="Arguments.arguments"/>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.contentEncoding"></stringProp>
          <stringProp name="HTTPSampler.path">/kv/${__Random(1,1000)}</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
          <stringProp name="HTTPSampler.implementation">HttpClient4</stringProp>
          <boolProp name="HTTPSampler.monitor">false</boolProp>
          <stringProp name="HTTPSampler.embedded_url_re"></stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="GET Throughput">
            <stringProp name="ConstantThroughputTimer.throughput">${__P(get_throughput,200)}</stringProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
      </hashTree>
      <ResultCollector guiclass="StatVisualizer" testclass="ResultCollector" testname="Aggregate Report">
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
          <name>saveConfig</name>
          <value class="SampleSaveConfiguration">
            <time>true</time>
            <latency>true</latency>
            <timestamp>true</timestamp>
            <success>true</success>
            <label>true</label>
            <code>true</code>
            <message>true</message>
            <threadName>true</threadName>
            <dataType>true</dataType>
            <encoding>false</encoding>
            <assertions>false</assertions>
            <subresults>false</subresults>
            <responseData>false</responseData>
            <samplerData>false</samplerData>
            <xml>false</xml>
            <fieldNames>true</fieldNames>
            <responseHeaders>false</responseHeaders>
            <requestHeaders>false</requestHeaders>
            <responseDataOnError>false</responseDataOnError>
            <saveAssertionResultsFailureMessage>false</saveAssertionResultsFailureMessage>
            <assertionsResultsToSave>0</assertionsResultsToSave>
            <bytes>true</bytes>
          </value>
        </objProp>
        <stringProp name="filename"></stringProp>
      </ResultCollector>
      <hashTree/>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOL

echo "===================================="
echo "Executando teste de carga..."
echo "===================================="

# Tentar usar a versão mais simples do comando JMeter (para versões antigas)
jmeter -n -t "$TEST_PLAN_FILE" \
       -Jhost="$HOST" \
       -Jport="$PORT" \
       -Jusers="$USERS" \
       -Jrampup="$RAMPUP" \
       -Jduration="$DURATION" \
       -Jget_throughput="$GET_THROUGHPUT" \
       -l "$RESULTS_CSV" \
       > "${RESULTS_FILE}.log" 2>&1
       
JMETER_EXIT_CODE=$?

# Verificar se o teste foi executado com sucesso
if [ $JMETER_EXIT_CODE -eq 0 ]; then
    echo "===================================="
    echo "Teste concluído com sucesso!"
    echo "===================================="
else
    echo "===================================="
    echo "ERRO: Teste falhou com código $JMETER_EXIT_CODE"
    echo "Verifique o log para mais detalhes: ${RESULTS_FILE}.log"
    echo "===================================="
    echo "Últimas 10 linhas de log:"
    tail -n 10 "${RESULTS_FILE}.log"
    echo "===================================="
fi

# Verificar se o arquivo de resultados foi criado
if [ -f "$RESULTS_CSV" ]; then
    echo "Arquivo de resultados criado: $RESULTS_CSV"
    
    # Exibir estatísticas básicas se os utilitários estiverem disponíveis
    if command -v wc &> /dev/null && command -v head &> /dev/null && command -v tail &> /dev/null && command -v awk &> /dev/null; then
        echo "Estatísticas básicas:"
        echo "Total de amostras: $(wc -l < "$RESULTS_CSV")"
        echo "Primeiras linhas:"
        head -n 2 "$RESULTS_CSV"
        echo "..."
        echo "Últimas linhas:"
        tail -n 2 "$RESULTS_CSV"
    fi
else
    echo "AVISO: Arquivo de resultados não foi criado: $RESULTS_CSV"
fi

echo "===================================="
echo "Arquivos gerados:"
echo "- Log: ${RESULTS_FILE}.log"
echo "- Resultados: $RESULTS_CSV (se criado)"
echo "====================================" 