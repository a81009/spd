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

# Criar diretórios necessários e garantir permissões
mkdir -p "$TEST_PLAN_DIR"
mkdir -p "$RESULTS_DIR"
chmod -R 777 "${SCRIPT_DIR}/jmeter"

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
JMETER_VERSION=$(jmeter -v 2>&1 | head -n 1)
echo "Versão do JMeter: $JMETER_VERSION"
echo "Diretório de trabalho: $SCRIPT_DIR"

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
LOG_FILE="${RESULTS_FILE}.log"

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

# Criar um arquivo JMX muito simples para JMeter 2.13
TEST_PLAN_FILE="${TEST_PLAN_DIR}/kv-store-test-v2.jmx"

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
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.connect_timeout"></stringProp>
          <stringProp name="HTTPSampler.response_timeout"></stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.contentEncoding"></stringProp>
          <stringProp name="HTTPSampler.path">/kv/1</stringProp>
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
          <ResponseAssertion guiclass="AssertionGui" testclass="ResponseAssertion" testname="Response Assertion">
            <collectionProp name="Asserion.test_strings"/>
            <stringProp name="Assertion.test_field">Assertion.response_code</stringProp>
            <boolProp name="Assertion.assume_success">false</boolProp>
            <intProp name="Assertion.test_type">16</intProp>
          </ResponseAssertion>
          <hashTree/>
        </hashTree>
      </hashTree>
      <ResultCollector guiclass="ViewResultsFullVisualizer" testclass="ResultCollector" testname="View Results Tree">
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
            <url>true</url>
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

# Comando JMeter simplificado para versões antigas
# Create resultados.jtl in the current directory first
touch "$RESULTS_CSV"
chmod 777 "$RESULTS_CSV"

# Executar jmeter com comando simples
jmeter -n -t "$TEST_PLAN_FILE" \
       -Jhost="$HOST" \
       -Jport="$PORT" \
       -Jusers="$USERS" \
       -Jrampup="$RAMPUP" \
       -l "$RESULTS_CSV" > "$LOG_FILE" 2>&1
       
JMETER_EXIT_CODE=$?

# Verificar se o teste foi executado com sucesso
if [ $JMETER_EXIT_CODE -eq 0 ]; then
    echo "===================================="
    echo "Teste concluído com sucesso!"
    echo "===================================="
else
    echo "===================================="
    echo "ERRO: Teste falhou com código $JMETER_EXIT_CODE"
    echo "Verifique o log para mais detalhes: $LOG_FILE"
    echo "===================================="
fi

# Verificar se o arquivo de resultados foi criado
if [ -f "$RESULTS_CSV" ] && [ -s "$RESULTS_CSV" ]; then
    echo "Arquivo de resultados criado: $RESULTS_CSV"
    
    # Exibir estatísticas básicas
    echo "Estatísticas básicas:"
    echo "Tamanho do arquivo: $(du -h "$RESULTS_CSV" | cut -f1)"
    echo "Primeiras linhas:"
    head -n 2 "$RESULTS_CSV" 2>/dev/null || echo "Arquivo vazio ou não é um arquivo de texto"
else
    echo "AVISO: Arquivo de resultados não foi criado ou está vazio: $RESULTS_CSV"
    
    # Listar todos os arquivos gerados
    echo "Listando arquivos em $RESULTS_DIR:"
    ls -la "$RESULTS_DIR"
    
    echo "Listando arquivos no diretório atual:"
    ls -la .
    
    # Verificar onde foram salvos os resultados (talvez em outro diretório)
    echo "Procurando arquivos .jtl ou .csv recentes:"
    find "$SCRIPT_DIR" -name "*.jtl" -o -name "*.csv" -mtime -1 2>/dev/null || echo "Nenhum arquivo .jtl ou .csv encontrado"
fi

echo "===================================="
echo "Arquivos gerados:"
echo "- Log: $LOG_FILE"
echo "- Resultados: $RESULTS_CSV (se criado)"
echo "===================================="

# Mostrar conteúdo do log
echo "Últimas 10 linhas do log:"
tail -n 10 "$LOG_FILE" 2>/dev/null || echo "Log file não disponível"
echo "====================================" 