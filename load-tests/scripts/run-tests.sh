#!/usr/bin/env pwsh
# PowerShell script equivalent to run-tests.sh
# Set error action preference to stop on error
$ErrorActionPreference = "Stop"

# ------------- directories -------------
$SCRIPT_DIR = $PSScriptRoot
$JMETER_ROOT = Join-Path $SCRIPT_DIR "jmeter"
$TEST_PLAN_DIR = Join-Path $JMETER_ROOT "test-plans"
$RESULTS_DIR = Join-Path $JMETER_ROOT "results"
$LOG_DIR = Join-Path $JMETER_ROOT "logs"
$REPORT_DIR = Join-Path $JMETER_ROOT "reports"

# Create directories if they don't exist
$null = New-Item -Path $TEST_PLAN_DIR, $RESULTS_DIR, $LOG_DIR, $REPORT_DIR -ItemType Directory -Force

# ------------- locate JMeter -------------
function Find-JMeter {
    $jmeterPaths = @(
        (Get-Command jmeter -ErrorAction SilentlyContinue).Source,
        "C:\jmeter\bin\jmeter.bat",
        "C:\apache-jmeter\bin\jmeter.bat",
        "$env:USERPROFILE\jmeter\bin\jmeter.bat"
    )
    
    foreach ($path in $jmeterPaths) {
        if ($path -and (Test-Path $path)) {
            return $path
        }
    }
    return $null
}

$JMETER_CMD = Find-JMeter
if (-not $JMETER_CMD) {
    Write-Error "JMeter not found."
    exit 1
}

# ------------- parameter collection -------------
function Read-Input {
    param (
        [string]$prompt,
        [string]$default
    )
    
    $response = Read-Host "$prompt [$default]"
    if ([string]::IsNullOrEmpty($response)) {
        return $default
    }
    return $response
}

$USERS = Read-Input -prompt "Concurrent Users" -default "10"
$RAMPUP = Read-Input -prompt "Ramp-up in seconds" -default "2"
$DURATION = Read-Input -prompt "Test duration (s)" -default "60"
$PUT_TPS = Read-Input -prompt "PUT ops/s" -default "50"
$GET_TPS = Read-Input -prompt "GET ops/s (ignored, simple script)" -default "0"
$DEL_TPS = Read-Input -prompt "DELETE ops/s (ignored, simple script)" -default "0"
$TEST_NAME = Read-Input -prompt "Test name" -default "kv-store-test"

# ------------- auxiliary calculations -------------
$WARMUP = [math]::Max(1, [int]($DURATION / 4))
$TIMESTAMP = Get-Date -Format "yyyyMMdd-HHmmss"
$RESULT_BASE = Join-Path $RESULTS_DIR "$TEST_NAME-$TIMESTAMP"
$RESULT_CSV = "$RESULT_BASE.csv"
$LOG_FILE = Join-Path $LOG_DIR "$TEST_NAME-$TIMESTAMP.log"
$REPORT_OUT = Join-Path $REPORT_DIR "$TEST_NAME-$TIMESTAMP"
$JMX_FILE = Join-Path $TEST_PLAN_DIR "$TEST_NAME-$TIMESTAMP.jmx"

function To-Min {
    param([int]$val)
    return $val * 60
}

$PUT_TPM = To-Min -val $PUT_TPS
$GET_TPM = To-Min -val $GET_TPS
$DEL_TPM = To-Min -val $DEL_TPS

Write-Host "`n===== Parameters ====="
Write-Host "Host.................: localhost"
Write-Host "Port.................: 8000"
Write-Host "Users................: $USERS"
Write-Host "Ramp-up..............: $RAMPUP s"
Write-Host "Duration.............: $DURATION s (+${WARMUP}s warm-up)"
Write-Host "TPS (PUT/GET/DEL)....: $PUT_TPS / $GET_TPS / $DEL_TPS"
Write-Host "JMX File.............: $JMX_FILE"
Write-Host "CSV..................: $RESULT_CSV"
Write-Host "HTML Report..........: $REPORT_OUT`n"

$confirmation = Read-Host "Confirm and start? (y/N)"
if ($confirmation -inotmatch "^[yY]$") {
    Write-Host "Canceled."
    exit 0
}

# ------------- generate JMX plan (JSR223PostProcessor with improved regex and sync) -------------
$jmxContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.4" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store Test - JSR223 Regex Fix">
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments" testname="User Defined Variables" enabled="true">
        <collectionProp name="Arguments.arguments">
          <elementProp name="GET_SCRIPT_SIMPLE" elementType="Argument">
            <stringProp name="Argument.name">GET_SCRIPT_SIMPLE</stringProp>
            <stringProp name="Argument.value">return "fixed_get_key_for_debug";</stringProp>
            <stringProp name="Argument.desc">Groovy script SIMPLIFICADO for GET key</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
          <elementProp name="DEL_SCRIPT_SIMPLE" elementType="Argument">
            <stringProp name="Argument.name">DEL_SCRIPT_SIMPLE</stringProp>
            <stringProp name="Argument.value">return "fixed_del_key_for_debug";</stringProp>
            <stringProp name="Argument.desc">Groovy script SIMPLIFICADO for DELETE key</stringProp>
            <stringProp name="Argument.metadata">=</stringProp>
          </elementProp>
        </collectionProp>
      </elementProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="Threads">
        <stringProp name="ThreadGroup.num_threads">$USERS</stringProp>
        <stringProp name="ThreadGroup.ramp_time">$RAMPUP</stringProp>
        <boolProp name="ThreadGroup.scheduler">true</boolProp>
        <stringProp name="ThreadGroup.duration">$DURATION</stringProp>
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <stringProp name="LoopController.loops">-1</stringProp>
        </elementProp>
      </ThreadGroup>
      <hashTree>

        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="PUT">
          <boolProp name="HTTPSampler.postBodyRaw">true</boolProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="body" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{ "data": { "key": "k-\${__UUID}", "value": "v-\${__Random(1,9999)}" } }</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">localhost</stringProp>
          <stringProp name="HTTPSampler.port">8000</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">PUT</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="CT-PUT">
            <collectionProp name="HeaderManager.headers">
              <elementProp name="h1" elementType="Header">
                <stringProp name="Header.name">Content-Type</stringProp>
                <stringProp name="Header.value">application/json</stringProp>
              </elementProp>
            </collectionProp>
          </HeaderManager>
          <hashTree/>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="PUT TPS">
            <stringProp name="throughput">$PUT_TPM</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
          <JSR223PostProcessor guiclass="TestBeanGUI" testclass="JSR223PostProcessor" testname="Store keys">
            <stringProp name="scriptLanguage">groovy</stringProp>
            <stringProp name="script">log.info("JSR223 Store keys: START thread: " + Thread.currentThread().getName());

// Obter o corpo do request diretamente do samplerData
String samplerData = prev.getSamplerData();
String requestBody = "";

if (samplerData != null && !samplerData.isEmpty()) {
    // Extrair apenas o corpo JSON do samplerData (após a linha em branco que separa cabeçalhos do corpo)
    int bodyStart = samplerData.indexOf("\n\n");
    if (bodyStart > 0) {
        requestBody = samplerData.substring(bodyStart).trim();
    } else {
        requestBody = samplerData;
    }
}

if (requestBody == null || requestBody.isEmpty()) {
    log.error("JSR223 Store keys: Request Body is NULL or EMPTY for thread " + Thread.currentThread().getName() + "!");
    return;
}
log.info("JSR223 Store keys: Request Body for thread " + Thread.currentThread().getName() + ": [" + requestBody + "]");

// Regex mais específica para um valor de chave JSON entre aspas
java.util.regex.Matcher matcher = (requestBody =~ /"key"\s*:\s*"([^"]+)"/);

if (matcher.find()) {
    String newKey = matcher.group(1);
    log.info("JSR223 Store keys: Regex matched for thread " + Thread.currentThread().getName() + ". Key extracted: [" + newKey + "]");
    
    if (newKey == null || newKey.trim().isEmpty()) {
        log.warn("JSR223 Store keys: Extracted newKey is NULL or EMPTY for thread " + Thread.currentThread().getName() + " from Request Body: [" + requestBody + "]");
    } else {
        String keyToAdd = newKey.trim();
        synchronized(props) {
            String currentKeysInProps = props.get('keys');
            if (currentKeysInProps == null) {
                currentKeysInProps = "";
                props.put('keys', ""); 
            }
            String updatedKeys = currentKeysInProps + keyToAdd + ',';
            props.put('keys', updatedKeys);
            log.info("JSR223 Store keys: Updated 'keys' prop by thread " + Thread.currentThread().getName() + ". Current keys: [" + updatedKeys + "]");
        }
    }
} else {
    log.warn("JSR223 Store keys: Regex did NOT find key for thread " + Thread.currentThread().getName() + ". Request Body: [" + requestBody + "]");
}
log.info("JSR223 Store keys: END thread: " + Thread.currentThread().getName());</stringProp>
          </JSR223PostProcessor>
          <hashTree/>
        </hashTree>

        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="GET">
          <stringProp name="HTTPSampler.domain">localhost</stringProp>
          <stringProp name="HTTPSampler.port">8000</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">GET</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="key" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">\${__groovy(\${GET_SCRIPT_SIMPLE})}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
                <stringProp name="Argument.name">key</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="GET TPS">
            <stringProp name="throughput">$GET_TPM</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>

        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="DELETE">
          <stringProp name="HTTPSampler.domain">localhost</stringProp>
          <stringProp name="HTTPSampler.port">8000</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">DELETE</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="key" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">\${__groovy(\${DEL_SCRIPT_SIMPLE})}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
                <stringProp name="Argument.name">key</stringProp>
              </elementProp>
            </collectionProp>
          </elementProp>
        </HTTPSamplerProxy>
        <hashTree>
          <ConstantThroughputTimer guiclass="ConstantThroughputTimerGui" testclass="ConstantThroughputTimer" testname="DEL TPS">
            <stringProp name="throughput">$DEL_TPM</stringProp>
            <intProp name="calcMode">1</intProp>
          </ConstantThroughputTimer>
          <hashTree/>
        </hashTree>

      </hashTree>

      <ResultCollector guiclass="SummaryReport" testclass="ResultCollector" testname="CSV">
        <stringProp name="filename">$RESULT_CSV</stringProp>
        <boolProp name="ResultCollector.error_logging">false</boolProp>
        <objProp>
            <name>saveConfig</name>
            <value class="SampleSaveConfiguration">
              <time>true</time><latency>true</latency><timestamp>true</timestamp><success>true</success><label>true</label><code>true</code><message>true</message><threadName>true</threadName><dataType>true</dataType><encoding>false</encoding><assertions>true</assertions><subresults>true</subresults><responseData>false</responseData><samplerData>false</samplerData><xml>false</xml><fieldNames>true</fieldNames><responseHeaders>false</responseHeaders><requestHeaders>false</requestHeaders><responseDataOnError>false</responseDataOnError><saveAssertionResultsFailureMessage>true</saveAssertionResultsFailureMessage><assertionsResultsToSave>0</assertionsResultsToSave><bytes>true</bytes><sentBytes>true</sentBytes><url>true</url><threadCounts>true</threadCounts><idleTime>true</idleTime><connectTime>true</connectTime>
            </value>
        </objProp>
        <stringProp name="TestPlan.comments">Full CSV output</stringProp>
      </ResultCollector>
      <hashTree/>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
"@

Set-Content -Path $JMX_FILE -Value $jmxContent -Encoding UTF8

# ------------- execute -------------
$TIMEOUT = $DURATION + $WARMUP + 30
Write-Host "`nStarting JMeter... (timeout ${TIMEOUT}s)`n"

# Command to run JMeter
$jmeterCommand = @(
    $JMETER_CMD,
    "--nongui",
    "--testfile", "`"$JMX_FILE`"",
    "--jmeterlogfile", "`"$LOG_FILE`"",
    "-l", "`"$RESULT_CSV`"",
    "--reportatendofloadtests",
    "--reportoutputfolder", "`"$REPORT_OUT`"",
    "-Jjmeter.save.saveservice.output_format=csv",
    "-Jjmeter.save.saveservice.bytes=true",
    "-Jjmeter.save.saveservice.latency=true",
    "-Jjmeter.save.saveservice.connect_time=true",
    "-Jjmeter.save.saveservice.timestamp_format=`"yyyy/MM/dd HH:mm:ss.SSS`"",
    "-Jjmeter.save.saveservice.default_delimiter=,",
    "-Jjmeter.save.saveservice.print_field_names=true"
)

# Run JMeter with timeout
$jmeterProcess = Start-Process -FilePath $jmeterCommand[0] -ArgumentList $jmeterCommand[1..($jmeterCommand.Length-1)] -NoNewWindow -PassThru
$jmeterTimeout = $false

# Wait for the process to exit or timeout
if (-not (Wait-Process -InputObject $jmeterProcess -Timeout $TIMEOUT -ErrorAction SilentlyContinue)) {
    Write-Host "JMeter timeout after ${TIMEOUT}s"
    Stop-Process -InputObject $jmeterProcess -Force
    $jmeterTimeout = $true
}

if ($jmeterProcess.ExitCode -ne 0 -and -not $jmeterTimeout) {
    Write-Host "JMeter returned error $($jmeterProcess.ExitCode) - see $LOG_FILE"
    exit 1
}

# ------------- quick metrics -------------
if (-not (Test-Path $RESULT_CSV) -or (Get-Item $RESULT_CSV).Length -eq 0) {
    Write-Host "Empty CSV - check the log."
    exit 1
}

$totalLines = (Get-Content $RESULT_CSV | Measure-Object -Line).Lines
if ($totalLines -le 1) {
    Write-Host "CSV does not contain sample data - check log: $LOG_FILE and report: $REPORT_OUT"
    if ((Get-Content $LOG_FILE -Raw) -match 'Starting standalone test' -and ((Get-Content $LOG_FILE -Raw) -notmatch 'Tidying up')) {
        Write-Host "Warning: The test may have been prematurely interrupted."
    }
    elseif ((Get-Content $LOG_FILE -Raw) -match 'Error occurred compiling the tree') {
        Write-Host "Error in JMX compilation, CSV may be empty."
    }
    # Just continue to summary even if CSV is empty
}

$total = $totalLines - 1
if ($total -lt 0) { $total = 0 }

$ok = (Select-String -Path $RESULT_CSV -Pattern ',true,' -AllMatches).Matches.Count
$fail = $total - $ok

function Get-Percentage {
    param (
        [int]$numerator,
        [int]$denominator
    )
    
    if ($denominator -eq 0) {
        return "0.00"
    }
    else {
        return [math]::Round(100 * $numerator / $denominator, 2).ToString("0.00")
    }
}

# Calculate average latency
$avgLatency = "0.00"
if ($totalLines -gt 1) {
    $latencyValues = @()
    $csvData = Import-Csv $RESULT_CSV
    foreach ($row in $csvData) {
        $latencyValues += [double]$row.Latency
    }
    if ($latencyValues.Count -gt 0) {
        $avgLatency = [math]::Round(($latencyValues | Measure-Object -Average).Average, 2).ToString("0.00")
    }
}

# Count test types
$putCount = (Select-String -Path $RESULT_CSV -Pattern '(,PUT,|,PUT\s*,)' -AllMatches).Matches.Count
$getCount = (Select-String -Path $RESULT_CSV -Pattern '(,GET,|,GET\s*,)' -AllMatches).Matches.Count
$deleteCount = (Select-String -Path $RESULT_CSV -Pattern '(,DELETE,|,DELETE\s*,)' -AllMatches).Matches.Count

Write-Host "`n===== Summary ====="
Write-Host "Total samples.......: $total"
Write-Host "Success..............: $ok ($(Get-Percentage -numerator $ok -denominator $total)%)"
Write-Host "Failures.............: $fail"
Write-Host "PUT..................: $putCount"
Write-Host "GET..................: $getCount"
Write-Host "DELETE...............: $deleteCount"
Write-Host "Average latency......: $avgLatency ms"
Write-Host ""
Write-Host "HTML Report in.......: $REPORT_OUT/index.html"
Write-Host "JMeter Log...........: $LOG_FILE"
Write-Host "CSV Results..........: $RESULT_CSV"
Write-Host ""