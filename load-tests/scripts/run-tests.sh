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

# Criar arquivo de propriedades JMeter para resolver problema de segurança XStream
JMETER_PROPS_FILE="${SCRIPT_DIR}/jmeter/jmeter.properties"
mkdir -p "$(dirname "$JMETER_PROPS_FILE")"
cat > "$JMETER_PROPS_FILE" << 'EOL'
# Propriedades para resolver problema de segurança XStream
jmeter.serializer.xstream.allowedPackages=org.apache.jmeter.save,org.apache.jmeter.protocol.http,org.apache.jmeter.util
EOL

# Criar arquivo de teste JMeter se não existir
TEST_PLAN_FILE="${TEST_PLAN_DIR}/kv-store-test.jmx"
if [ ! -f "$TEST_PLAN_FILE" ]; then
    cat > "$TEST_PLAN_FILE" << 'EOL'
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.2" properties="5.0" jmeter="5.5">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store Test Plan">
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <stringProp name="TestPlan.comments"></stringProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Thread Group">
        <intProp name="ThreadGroup.num_threads">${__P(users,10)}</intProp>
        <intProp name="ThreadGroup.ramp_time">${__P(rampup,5)}</intProp>
        <longProp name="ThreadGroup.duration">${__P(duration,60)}</longProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.on_sample_error">continue</stringProp>
      </ThreadGroup>
      <hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="PUT Request">
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.method">PUT</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <stringProp name="HTTPSampler.path">/kv/${__Random(1,1000)}</stringProp>
          <stringProp name="HTTPSampler.contentEncoding">UTF-8</stringProp>
          <stringProp name="HTTPSampler.postData">{"value": "${__Random(1,1000)}"}</stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="PUT Throughput">
            <intProp name="throughput">${__P(put_throughput,50)}</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET Request">
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <stringProp name="HTTPSampler.path">/kv/${__Random(1,1000)}</stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="GET Throughput">
            <intProp name="throughput">${__P(get_throughput,200)}</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="DELETE Request">
          <stringProp name="HTTPSampler.domain">${__P(host,localhost)}</stringProp>
          <stringProp name="HTTPSampler.port">${__P(port,80)}</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <stringProp name="HTTPSampler.method">DELETE</stringProp>
          <boolProp name="HTTPSampler.follow_redirects">true</boolProp>
          <stringProp name="HTTPSampler.path">/kv/${__Random(1,1000)}</stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="DELETE Throughput">
            <intProp name="throughput">${__P(delete_throughput,20)}</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>
      </hashTree>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
EOL
fi

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
echo "Versão do JMeter: $(jmeter -v | head -n 1)"

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

# Executar JMeter em modo não-GUI com propriedades adicionais para resolver o problema de segurança XStream
jmeter -n \
  -p "$JMETER_PROPS_FILE" \
  -JxstreamAllowAll=true \
  -JxstreamAllowTypes=org.apache.jmeter.save.ScriptWrapper \
  -JxstreamAllowTypesByRegExp=.* \
  -t "$TEST_PLAN_FILE" \
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

# Verificar se o arquivo de resultados foi criado
if [ -f "${RESULTS_FILE}.jtl" ]; then
    echo "Arquivo de resultados criado com sucesso."
else
    echo "AVISO: O arquivo de resultados não foi criado."
fi

# Perguntar se deseja gerar relatório HTML
read -p "Deseja gerar um relatório HTML dos resultados? (s/N) " generate_report
if [[ $generate_report =~ ^[Ss]$ ]]; then
    echo "Gerando relatório HTML..."
    
    # Tentar diferentes sintaxes baseado na versão do JMeter
    JMETER_VERSION=$(jmeter -v | grep -oP '(?<=ApacheJMeter_core-).*?(?= )')
    REPORT_DIR="${RESULTS_DIR}/report-${TIMESTAMP}"
    
    # Criando diretório para relatório
    mkdir -p "$REPORT_DIR"
    
    if [ -f "${RESULTS_FILE}.jtl" ]; then
        # Tentar com a sintaxe padrão
        if jmeter -g "${RESULTS_FILE}.jtl" -o "$REPORT_DIR" 2>/dev/null; then
            echo "Relatório gerado com sucesso."
        # Tentar com a sintaxe alternativa
        elif jmeter -g "${RESULTS_FILE}.jtl" -e -o "$REPORT_DIR" 2>/dev/null; then
            echo "Relatório gerado com sucesso."
        else
            echo "Erro ao gerar relatório HTML. Tentando método alternativo..."
            # Mostrar informações básicas sobre os resultados
            echo "Resumo dos resultados (se disponível):"
            if command -v grep &> /dev/null && [ -f "${RESULTS_FILE}.jtl" ]; then
                echo "Total de amostras: $(grep -c "<sample" "${RESULTS_FILE}.jtl" 2>/dev/null || echo "N/A")"
                echo "Consulte os arquivos de resultados manualmente em: $RESULTS_DIR"
            fi
        fi
    else
        echo "ERRO: Arquivo de resultados ${RESULTS_FILE}.jtl não encontrado."
    fi
    
    echo "Relatório disponível em: $REPORT_DIR (se gerado com sucesso)"
fi 