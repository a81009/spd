#!/bin/bash
set -e

# Diretórios
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_PLAN_DIR="${SCRIPT_DIR}/jmeter/test-plans"
RESULTS_DIR="${SCRIPT_DIR}/jmeter/results"
JMETER_LOG_DIR="${SCRIPT_DIR}/jmeter/logs"
REPORT_DIR="${SCRIPT_DIR}/jmeter/reports"

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
mkdir -p "$REPORT_DIR"
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

# Leitura interativa dos parâmetros
echo "===================================="
echo "Configuração do Teste de Carga"
echo "===================================="

HOST="localhost"
PORT="80"
USERS=$(read_input "Número de usuários concorrentes" "10")
RAMPUP=$(read_input "Tempo de ramp-up (segundos)" "2")  # Reduced default ramp-up time
DURATION=$(read_input "Duração do teste (segundos)" "60")
PUT_THROUGHPUT=$(read_input "Taxa de operações PUT por segundo" "50")
GET_THROUGHPUT=$(read_input "Taxa de operações GET por segundo" "200")
DELETE_THROUGHPUT=$(read_input "Taxa de operações DELETE por segundo" "20")
TEST_NAME=$(read_input "Nome do teste" "kv-store-test")

# Calculate warm-up period - minimum 1 second, maximum 1/4 of test duration
WARMUP_PERIOD=$(echo "scale=0; $DURATION / 4" | bc)
if [ "$WARMUP_PERIOD" -lt 1 ]; then
    WARMUP_PERIOD=1
fi

# Adicionar tempo extra ao tempo de execução para considerar o warm-up
EXTENDED_DURATION=$((DURATION + WARMUP_PERIOD))

# Calcular throughput para todo o grupo, não por thread
TOTAL_PUT_THROUGHPUT=$PUT_THROUGHPUT
TOTAL_GET_THROUGHPUT=$GET_THROUGHPUT
TOTAL_DELETE_THROUGHPUT=$DELETE_THROUGHPUT

# Carimbo de data/hora para o nome do arquivo
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
RESULTS_FILE="${RESULTS_DIR}/${TEST_NAME}-${TIMESTAMP}"
RESULTS_CSV="${RESULTS_FILE}.csv"
LOG_FILE="${JMETER_LOG_DIR}/${TEST_NAME}-${TIMESTAMP}.log"
SUMMARY_FILE="${RESULTS_DIR}/${TEST_NAME}-${TIMESTAMP}-summary.txt"
REPORT_PATH="${REPORT_DIR}/${TEST_NAME}-${TIMESTAMP}"
DETAILED_SUMMARY="${RESULTS_DIR}/${TEST_NAME}-${TIMESTAMP}-detailed.txt"

# Exibir configurações finais
echo "===================================="
echo "Configurações do teste:"
echo "===================================="
echo "Host:               $HOST"
echo "Porta:              $PORT"
echo "Usuários:           $USERS"
echo "Ramp-up:            $RAMPUP segundos"
echo "Duração:            $DURATION segundos (+ $WARMUP_PERIOD segundos warm-up)"
echo "Taxa PUT:           $TOTAL_PUT_THROUGHPUT/seg (total)"
echo "Taxa GET:           $TOTAL_GET_THROUGHPUT/seg (total)"
echo "Taxa DELETE:        $TOTAL_DELETE_THROUGHPUT/seg (total)"
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
    cat > "$TEST_PLAN_FILE" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store Test">
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
        <stringProp name="ThreadGroup.ramp_time">${__P(rampup,2)}</stringProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
        <stringProp name="ThreadGroup.duration">${__P(duration,60)}</stringProp>
        <stringProp name="ThreadGroup.delay">0</stringProp>
        <boolProp name="ThreadGroup.delayedStart">false</boolProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="PUT Request">
          <boolProp name="HTTPSampler.postBodyRaw">true</boolProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{"data":{"key":"test-${__UUID}","value":"value-${__Random(1,10000)}"}}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">PUT</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree>
          <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="Content-Type Header">
            <collectionProp name="HeaderManager.headers">
              <elementProp name="" elementType="Header">
                <stringProp name="Header.name">Content-Type</stringProp>
                <stringProp name="Header.value">application/json</stringProp>
              </elementProp>
            </collectionProp>
          </HeaderManager>
          <hashTree/>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="PUT Throughput">
            <stringProp name="ConstantThroughputTimer.throughput">${__P(put_throughput,50.0)}</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
          <JSR223PostProcessor guiclass="TestBeanGUI" testclass="JSR223PostProcessor" testname="Store Keys for GET">
            <stringProp name="scriptLanguage">groovy</stringProp>
            <stringProp name="parameters"></stringProp>
            <stringProp name="filename"></stringProp>
            <stringProp name="cacheKey">true</stringProp>
            <stringProp name="script">import org.apache.jmeter.util.JMeterUtils;
import java.util.ArrayList;

// Extract the key from the request
String requestBody = prev.getRequestData();
String keyPattern = &quot;key\&quot;:\\s*\&quot;([^\&quot;]+)\&quot;&quot;;
java.util.regex.Pattern pattern = java.util.regex.Pattern.compile(keyPattern);
java.util.regex.Matcher matcher = pattern.matcher(requestBody);

if (matcher.find()) {
    String key = matcher.group(1);
    
    // Get the shared key list, or create it if it doesn&apos;t exist
    ArrayList&lt;String&gt; keyList = props.get(&quot;keyList&quot;);
    if (keyList == null) {
        keyList = new ArrayList&lt;String&gt;();
        props.put(&quot;keyList&quot;, keyList);
    }
    
    // Add the key to the list
    keyList.add(key);
    
    // Keep the list at a reasonable size
    if (keyList.size() &gt; 1000) {
        keyList.remove(0);
    }
}</stringProp>
          </JSR223PostProcessor>
          <hashTree/>
        </hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Request">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="key" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">${__groovy(
                  def keys = props.get("keyList");
                  if (keys != null && !keys.isEmpty()) {
                    return keys.get(new Random().nextInt(keys.size()));
                  } else {
                    return "hello";
                  }
                )}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
                <boolProp name="HTTPArgument.use_equals">true</boolProp>
                <stringProp name="Argument.name">key</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="GET Throughput">
            <stringProp name="ConstantThroughputTimer.throughput">${__P(get_throughput,200.0)}</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
      </hashTree>
      <ResultCollector guiclass="SummaryReport" testclass="ResultCollector" testname="Summary Report">
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
          <n>saveConfig</n>
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
            <sentBytes>true</sentBytes>
            <url>true</url>
            <threadCounts>true</threadCounts>
            <idleTime>true</idleTime>
            <connectTime>true</connectTime>
          </value>
        </objProp>
        <stringProp name="filename">${__P(summary_file,summary.txt)}</stringProp>
      </ResultCollector>
      <hashTree/>
      <ResultCollector guiclass="StatVisualizer" testclass="ResultCollector" testname="Aggregate Report">
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
          <n>saveConfig</n>
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
            <sentBytes>true</sentBytes>
            <url>true</url>
            <threadCounts>true</threadCounts>
            <idleTime>true</idleTime>
            <connectTime>true</connectTime>
          </value>
        </objProp>
        <stringProp name="filename">${__P(detailed_file,detailed.txt)}</stringProp>
      </ResultCollector>
      <hashTree/>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOL
else
    cat > "$TEST_PLAN_FILE" << EOL
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="2.1">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store Test">
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
          <stringProp name="LoopController.loops">-1</stringProp>
        </elementProp>
        <stringProp name="ThreadGroup.num_threads">${__P(users,10)}</stringProp>
        <stringProp name="ThreadGroup.ramp_time">${__P(rampup,2)}</stringProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.duration">${__P(duration,60)}</stringProp>
        <stringProp name="ThreadGroup.delay">0</stringProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="PUT Request">
          <boolProp name="HTTPSampler.postBodyRaw">true</boolProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{"data":{"key":"test-${__time()}","value":"value-${__Random(1,10000)}"}}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">PUT</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree>
          <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="Content-Type Header">
            <collectionProp name="HeaderManager.headers">
              <elementProp name="" elementType="Header">
                <stringProp name="Header.name">Content-Type</stringProp>
                <stringProp name="Header.value">application/json</stringProp>
              </elementProp>
            </collectionProp>
          </HeaderManager>
          <hashTree/>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="PUT Throughput">
            <stringProp name="ConstantThroughputTimer.throughput">${__P(put_throughput,50.0)}</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Request">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments" guiclass="HTTPArgumentsPanel" testclass="Arguments" testname="User Defined Variables">
            <collectionProp name="Arguments.arguments">
              <elementProp name="key" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">hello</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
                <boolProp name="HTTPArgument.use_equals">true</boolProp>
                <stringProp name="Argument.name">key</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <boolProp name="HTTPSampler.auto_redirects">false</boolProp>
          <boolProp name="HTTPSampler.use_keepalive">true</boolProp>
          <boolProp name="HTTPSampler.DO_MULTIPART_POST">false</boolProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="GET Throughput">
            <stringProp name="ConstantThroughputTimer.throughput">${__P(get_throughput,200.0)}</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
      </hashTree>
      <ResultCollector guiclass="SummaryReport" testclass="ResultCollector" testname="Summary Report">
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
          <n>saveConfig</n>
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
            <sentBytes>true</sentBytes>
            <url>true</url>
            <threadCounts>true</threadCounts>
            <idleTime>true</idleTime>
            <connectTime>true</connectTime>
          </value>
        </objProp>
        <stringProp name="filename">${__P(summary_file,summary.txt)}</stringProp>
      </ResultCollector>
      <hashTree/>
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
touch "$SUMMARY_FILE"
chmod 777 "$SUMMARY_FILE"
touch "$DETAILED_SUMMARY"
chmod 777 "$DETAILED_SUMMARY"

# Executar JMeter com uma margem de segurança razoável para o timeout
TIMEOUT_MARGIN=60
if [ $DURATION -lt 30 ]; then
    # Para testes curtos, adicionar uma margem menor
    TIMEOUT_MARGIN=30
fi

echo "Iniciando teste com duração de $DURATION segundos..."
echo "O teste terminará automaticamente após este período."

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
           -Jput_throughput="$TOTAL_PUT_THROUGHPUT" \
           -Jget_throughput="$TOTAL_GET_THROUGHPUT" \
           -Jsummary_file="$SUMMARY_FILE" \
           -Jdetailed_file="$DETAILED_SUMMARY" \
           --reportatendofloadtests \
           --reportoutputfolder "$REPORT_PATH" \
           -l "$RESULTS_CSV"
else
    "$JMETER_CMD" -n -t "$TEST_PLAN_FILE" \
           -Jhost="$HOST" \
           -Jport="$PORT" \
           -Jusers="$USERS" \
           -Jrampup="$RAMPUP" \
           -Jduration="$DURATION" \
           -Jput_throughput="$TOTAL_PUT_THROUGHPUT" \
           -Jget_throughput="$TOTAL_GET_THROUGHPUT" \
           -Jsummary_file="$SUMMARY_FILE" \
           -l "$RESULTS_CSV" > "$LOG_FILE" 2>&1
fi

JMETER_EXIT_CODE=$?

if [ $JMETER_EXIT_CODE -eq 0 ]; then
    echo "===================================="
    echo "Teste concluído com sucesso!"
    echo "===================================="
elif [ $JMETER_EXIT_CODE -eq 124 ] || [ $JMETER_EXIT_CODE -eq 143 ]; then
    echo "===================================="
    echo "Teste interrompido pelo timeout - provavelmente concluído com sucesso."
    echo "===================================="
else
    echo "===================================="
    echo "ERRO: Teste falhou com código $JMETER_EXIT_CODE"
    echo "Verifique o log: $LOG_FILE"
    echo "===================================="
    exit 1
fi

# Verificar resultados
if [ -f "$RESULTS_CSV" ] && [ -s "$RESULTS_CSV" ]; then
    echo "Arquivo de resultados: $RESULTS_CSV"
    
    # Gerar relatório de métricas
    echo "===================================="
    echo "RELATÓRIO DE MÉTRICAS DO TESTE"
    echo "===================================="
    
    # Total de solicitações
    TOTAL_REQUESTS=$(grep -c "^" "$RESULTS_CSV" 2>/dev/null || echo "0")
    echo "Total de solicitações: $TOTAL_REQUESTS"
    
    # Solicitações bem-sucedidas
    SUCCESS_REQUESTS=$(grep -c ",true," "$RESULTS_CSV" 2>/dev/null || echo "0")
    FAIL_REQUESTS=$((TOTAL_REQUESTS - SUCCESS_REQUESTS))
    if [ "$TOTAL_REQUESTS" -gt 0 ]; then
        SUCCESS_RATE=$(echo "scale=2; ($SUCCESS_REQUESTS * 100) / $TOTAL_REQUESTS" | bc 2>/dev/null || echo "N/A")
    else
        SUCCESS_RATE="N/A"
    fi
    echo "Solicitações bem-sucedidas: $SUCCESS_REQUESTS ($SUCCESS_RATE%)"
    echo "Solicitações falhas: $FAIL_REQUESTS"
    
    # Tipos de solicitações
    PUT_REQUESTS=$(grep -c "PUT Request" "$RESULTS_CSV" 2>/dev/null || echo "0")
    GET_REQUESTS=$(grep -c "GET Request" "$RESULTS_CSV" 2>/dev/null || echo "0")
    echo "PUT Requests: $PUT_REQUESTS"
    echo "GET Requests: $GET_REQUESTS"
    
    # Tempo médio de resposta
    AVG_RESP_TIME=$(awk -F, 'NR>1 {sum+=$2; count++} END {print sum/count}' "$RESULTS_CSV" 2>/dev/null || echo "N/A")
    echo "Tempo médio de resposta: ${AVG_RESP_TIME}ms"
    
    # Extrair taxas reais de transação
    if [ "$TOTAL_REQUESTS" -gt 0 ] && [ "$DURATION" -gt 0 ]; then
        ACTUAL_TPS=$(echo "scale=2; $TOTAL_REQUESTS / $DURATION" | bc 2>/dev/null || echo "N/A")
        ACTUAL_PUT_TPS=$(echo "scale=2; $PUT_REQUESTS / $DURATION" | bc 2>/dev/null || echo "N/A")
        ACTUAL_GET_TPS=$(echo "scale=2; $GET_REQUESTS / $DURATION" | bc 2>/dev/null || echo "N/A")
        
        echo "Taxa média de transações: ${ACTUAL_TPS}/segundo"
        echo "Taxa média de PUT: ${ACTUAL_PUT_TPS}/segundo (meta: ${TOTAL_PUT_THROUGHPUT}/segundo)"
        echo "Taxa média de GET: ${ACTUAL_GET_TPS}/segundo (meta: ${TOTAL_GET_THROUGHPUT}/segundo)"
    fi
    
    # Análise da distribuição do tempo de resposta
    echo "===================================="
    echo "DISTRIBUIÇÃO DO TEMPO DE RESPOSTA"
    echo "===================================="
    # Usar percentis se disponíveis ou calcular manualmente
    awk -F, 'NR>1 {print $2}' "$RESULTS_CSV" | sort -n | awk '
      BEGIN {count=0}
      {values[count++]=$1}
      END {
        if (count > 0) {
          print "Mínimo (ms): " values[0];
          print "Máximo (ms): " values[count-1];
          print "Mediana (ms): " values[int(count/2)];
          print "90º Percentil (ms): " values[int(count*0.9)];
          print "95º Percentil (ms): " values[int(count*0.95)];
          print "99º Percentil (ms): " values[int(count*0.99)];
        }
      }' 2>/dev/null || echo "Não foi possível calcular a distribuição do tempo de resposta."
    
    # Análise da taxa de transações ao longo do tempo (para verificar consistência)
    echo "===================================="
    echo "TAXA DE TRANSAÇÕES POR INTERVALO"
    echo "===================================="
    INTERVAL=5 # Intervalo em segundos
    awk -F, -v interval=$INTERVAL '
      NR>1 {
        ts = $1/1000;  # Timestamp em segundos
        bucket = int(ts/interval) * interval;
        count[bucket]++;
      }
      END {
        print "Intervalo de tempo (s) | Transações | Taxa (tx/s)";
        for (b in count) {
          printf "%d-%d | %d | %.2f\n", b, b+interval, count[b], count[b]/interval;
        }
      }' "$RESULTS_CSV" | sort -n 2>/dev/null || echo "Não foi possível calcular a taxa de transações por intervalo."
    
    echo "===================================="
    echo "Relatório detalhado disponível em: $REPORT_PATH"
    echo "===================================="
else
    echo "AVISO: Arquivo de resultados não foi criado ou está vazio."
fi