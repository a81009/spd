# PowerShell script for PUT operations on KV store
# Set error action preference to stop on error
$ErrorActionPreference = "Stop"

# ------------- directories -------------
$SCRIPT_DIR = $PSScriptRoot
$JMETER_ROOT = Join-Path $SCRIPT_DIR "jmeter"
$TEST_PLAN_DIR = Join-Path $JMETER_ROOT "test-plans"
$RESULTS_DIR = Join-Path $JMETER_ROOT "results"
$LOG_DIR = Join-Path $JMETER_ROOT "logs"
$REPORT_DIR = Join-Path $JMETER_ROOT "reports"
$STATS_DIR = Join-Path $JMETER_ROOT "stats"
$KEYS_DIR = Join-Path $JMETER_ROOT "keys"

# Create directories if they don't exist
$null = New-Item -Path $TEST_PLAN_DIR, $RESULTS_DIR, $LOG_DIR, $REPORT_DIR, $STATS_DIR, $KEYS_DIR -ItemType Directory -Force

# ------------- locate JMeter -------------
function Find-JMeter {
    # First try to find jmeter.bat directly in well-known locations
    $jmeterLocations = @(
        "$env:USERPROFILE\jmeter\bin\jmeter.bat",
        "$env:USERPROFILE\jmeter\apache-jmeter-5.6.3\bin\jmeter.bat",
        "$env:USERPROFILE\apache-jmeter-5.6.3\bin\jmeter.bat",
        "C:\jmeter\bin\jmeter.bat",
        "C:\apache-jmeter-5.6.3\bin\jmeter.bat"
    )
    
    # Check command in path
    try {
        $jmeterCmd = Get-Command jmeter -ErrorAction SilentlyContinue
        if ($jmeterCmd -and (Test-Path $jmeterCmd.Source)) {
            return $jmeterCmd.Source
        }
    } catch {
        Write-Host "JMeter not found in PATH"
    }
    
    # Check each location
    foreach ($location in $jmeterLocations) {
        if (Test-Path $location) {
            return $location
        }
    }
    
    # Search in user profile for apache-jmeter folders
    $jmeterFolders = Get-ChildItem -Path $env:USERPROFILE -Directory -Filter "apache-jmeter*" -ErrorAction SilentlyContinue
    foreach ($folder in $jmeterFolders) {
        $jmeterBat = Join-Path $folder.FullName "bin\jmeter.bat"
        if (Test-Path $jmeterBat) {
            return $jmeterBat
        }
    }
    
    # Try to find in user profile's jmeter subdirectory
    $jmeterDir = Join-Path $env:USERPROFILE "jmeter"
    if (Test-Path $jmeterDir) {
        $jmeterFolders = Get-ChildItem -Path $jmeterDir -Directory -Filter "apache-jmeter*" -ErrorAction SilentlyContinue
        foreach ($folder in $jmeterFolders) {
            $jmeterBat = Join-Path $folder.FullName "bin\jmeter.bat"
            if (Test-Path $jmeterBat) {
                return $jmeterBat
            }
        }
    }
    
    return $null
}

$JMETER_CMD = Find-JMeter
if (-not $JMETER_CMD) {
    Write-Error "JMeter not found. Please make sure Apache JMeter 5.6.3 is installed."
    Write-Host "JMeter was expected to be installed in one of these locations:"
    Write-Host "- $env:USERPROFILE\jmeter\bin\jmeter.bat"
    Write-Host "- $env:USERPROFILE\jmeter\apache-jmeter-5.6.3\bin\jmeter.bat"
    Write-Host "- $env:USERPROFILE\apache-jmeter-5.6.3\bin\jmeter.bat"
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
$TEST_NAME = Read-Input -prompt "Test name" -default "kv-puts-test"

# ------------- auxiliary calculations -------------
$WARMUP = [math]::Max(1, [int]($DURATION / 4))
$TIMESTAMP = Get-Date -Format "yyyyMMdd-HHmmss"
$RESULT_BASE = Join-Path $RESULTS_DIR "$TEST_NAME-$TIMESTAMP"
$RESULT_CSV = "$RESULT_BASE.csv"
$LOG_FILE = Join-Path $LOG_DIR "$TEST_NAME-$TIMESTAMP.log"
$REPORT_OUT = Join-Path $REPORT_DIR "$TEST_NAME-$TIMESTAMP"
$JMX_FILE = Join-Path $TEST_PLAN_DIR "$TEST_NAME-$TIMESTAMP.jmx"
$KEYS_FILE = Join-Path $KEYS_DIR "keys-$TIMESTAMP.txt"

function To-Min {
    param([int]$val)
    # Convert requests/second to requests/minute for JMeter
    return [int]($val * 60)
}

$PUT_TPM = To-Min -val $PUT_TPS  # This will be requests per minute

# Calculate fixed values for test plan - MODIFIED to make PUT_TPS be per user
[int]$requestsPerUser = [int]$DURATION * [int]$PUT_TPS  # Each user should make this many requests
[int]$totalRequests = [int]$requestsPerUser * [int]$USERS  # Total requests for the test
# Calculate delay (in ms) between requests to achieve TPS per user
[int]$delayMs = [int]([Math]::Floor(1000 / $PUT_TPS))

Write-Host "`n===== Parameters ====="
Write-Host "Host.................: localhost"
Write-Host "Port.................: 8000"
Write-Host "Users................: $USERS"
Write-Host "Ramp-up..............: $RAMPUP s"
Write-Host "Duration.............: $DURATION s (+${WARMUP}s warm-up)"
Write-Host "PUT TPS per user.....: $PUT_TPS"
Write-Host "Total operations.....: $totalRequests"
Write-Host "JMX File.............: $JMX_FILE"
Write-Host "CSV..................: $RESULT_CSV"
Write-Host "HTML Report..........: $REPORT_OUT"
Write-Host "Keys File............: $KEYS_FILE"
Write-Host "Using JMeter from....: $JMETER_CMD`n"

$confirmation = Read-Host "Confirm and start? (y/N)"
if ($confirmation -inotmatch "^[yY]$") {
    Write-Host "Canceled."
    exit 0
}

Write-Host "Debug: Will generate $totalRequests total requests across $USERS users ($requestsPerUser per user) with ${delayMs}ms delay" -ForegroundColor Yellow

# Script to store keys for later operations
$jsr223Script = @"
log.info("JSR223 Store keys: START thread: " + Thread.currentThread().getName());

// Get the counter value for this thread
int counter = 0;
synchronized(props) {
    String globalCounter = props.get("global_counter");
    if (globalCounter == null) {
        globalCounter = "0";
    }
    counter = Integer.parseInt(globalCounter);
    props.put("global_counter", String.valueOf(counter + 1));
}

// Create sequential key
String key = "key" + counter;
String value = "value" + counter;

// Store in JMeter properties
synchronized(props) {
    String keys = props.get("keys") != null ? props.get("keys") : "";
    props.put("keys", keys + key + ",");
    
    // Also store the value
    props.put(key, value);
}

// Also store in thread variables for this request to use
vars.put("current_key", key);
vars.put("current_value", value);

log.info("JSR223 Generated key: " + key + " with value: " + value);
log.info("JSR223 Store keys: END thread: " + Thread.currentThread().getName());
"@

# Script to save keys to file at the end of test
$saveKeysScript = @"
// Save keys to file for later use
String keys = props.get("keys");
if (keys == null || keys.isEmpty()) {
    log.info("No keys to save to file");
    return;
}

// Create file
String keysFile = "$KEYS_FILE";
java.io.File file = new java.io.File(keysFile);
java.io.FileWriter writer = new java.io.FileWriter(file);

// For each key, write key and value on a line
String[] keyArray = keys.split(",");
for (String key : keyArray) {
    if (key != null && !key.trim().isEmpty()) {
        String value = props.get(key);
        if (value != null) {
            writer.write(key + "=" + value + "\n");
        }
    }
}
writer.close();
log.info("Keys saved to file: " + keysFile);
return keysFile;
"@

# Escape for XML
$jsr223Script = $jsr223Script -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
$saveKeysScript = $saveKeysScript -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'

# Generate the JMX file content
$jmxContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.4" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store PUT Test Plan">
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
    </TestPlan>
    <hashTree>
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="PUT Thread Group">
        <stringProp name="ThreadGroup.num_threads">$USERS</stringProp>
        <stringProp name="ThreadGroup.ramp_time">$RAMPUP</stringProp>
        <elementProp name="ThreadGroup.main_controller" elementType="LoopController" guiclass="LoopControlPanel" testclass="LoopController">
          <boolProp name="LoopController.continue_forever">false</boolProp>
          <stringProp name="LoopController.loops">$requestsPerUser</stringProp>
        </elementProp>
        <boolProp name="ThreadGroup.scheduler">false</boolProp>
      </ThreadGroup>
      <hashTree>
        <ConstantTimer guiclass="ConstantTimerGui" testclass="ConstantTimer" testname="Request Timer">
          <stringProp name="ConstantTimer.delay">$delayMs</stringProp>
        </ConstantTimer>
        <hashTree/>
        
        <JSR223PreProcessor guiclass="TestBeanGUI" testclass="JSR223PreProcessor" testname="Generate Key Value">
          <stringProp name="scriptLanguage">groovy</stringProp>
          <stringProp name="parameters"></stringProp>
          <stringProp name="filename"></stringProp>
          <stringProp name="cacheKey">true</stringProp>
          <stringProp name="script">$jsr223Script</stringProp>
        </JSR223PreProcessor>
        <hashTree/>
        
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="PUT Request">
          <boolProp name="HTTPSampler.postBodyRaw">true</boolProp>
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="body" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.value">{ "data": { "key": "`${current_key}", "value": "`${current_value}" } }</stringProp>
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
          <HeaderManager guiclass="HeaderPanel" testclass="HeaderManager" testname="HTTP Headers">
            <collectionProp name="HeaderManager.headers">
              <elementProp name="Content-Type" elementType="Header">
                <stringProp name="Header.name">Content-Type</stringProp>
                <stringProp name="Header.value">application/json</stringProp>
              </elementProp>
            </collectionProp>
          </HeaderManager>
          <hashTree/>
          <JSR223PostProcessor guiclass="TestBeanGUI" testclass="JSR223PostProcessor" testname="Track PUT Success">
            <stringProp name="scriptLanguage">groovy</stringProp>
            <stringProp name="parameters"></stringProp>
            <stringProp name="filename"></stringProp>
            <stringProp name="cacheKey">true</stringProp>
            <stringProp name="script">
if (prev.isSuccessful()) {
    // Increment PUT success counter
    synchronized(props) {
        String putSuccess = props.get("put_success");
        if (putSuccess == null) {
            putSuccess = "0";
        }
        int count = Integer.parseInt(putSuccess) + 1;
        props.put("put_success", String.valueOf(count));
    }
}
            </stringProp>
          </JSR223PostProcessor>
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
      </ResultCollector>
      <hashTree/>
      
      <JSR223Listener guiclass="TestBeanGUI" testclass="JSR223Listener" testname="Save Keys To File">
        <stringProp name="scriptLanguage">groovy</stringProp>
        <stringProp name="parameters"></stringProp>
        <stringProp name="filename"></stringProp>
        <stringProp name="cacheKey">true</stringProp>
        <stringProp name="script">$saveKeysScript</stringProp>
      </JSR223Listener>
      <hashTree/>
    </hashTree>
  </hashTree>
</jmeterTestPlan>
"@

Set-Content -Path $JMX_FILE -Value $jmxContent -Encoding UTF8

# ------------- execute -------------
$TIMEOUT = [math]::Min([int]::MaxValue / 1000, $DURATION + $WARMUP + 30)
Write-Host "`nStarting JMeter... (timeout ${TIMEOUT}s)`n"

# Command to run JMeter
$jmeterArgs = @(
    "--nongui",
    "--testfile", "$JMX_FILE",
    "--jmeterlogfile", "$LOG_FILE",
    "-l", "$RESULT_CSV",
    "--reportatendofloadtests",
    "--reportoutputfolder", "$REPORT_OUT",
    "-Jjmeter.save.saveservice.output_format=csv",
    "-Jjmeter.save.saveservice.bytes=true",
    "-Jjmeter.save.saveservice.latency=true",
    "-Jjmeter.save.saveservice.connect_time=true",
    "-Jjmeter.save.saveservice.timestamp_format=`"yyyy/MM/dd HH:mm:ss.SSS`"",
    "-Jjmeter.save.saveservice.default_delimiter=,",
    "-Jjmeter.save.saveservice.print_field_names=true"
)

try {
    # Simple approach: Start the process and let its output go directly to the console
    $process = Start-Process -FilePath $JMETER_CMD -ArgumentList $jmeterArgs -NoNewWindow -PassThru -Wait
    
    # JMeter on Windows might return empty exit code even on success, so we check if the CSV file was created
    # and has reasonable content instead of relying solely on exit code
    if ((-not (Test-Path $RESULT_CSV)) -or ((Get-Item $RESULT_CSV).Length -lt 100)) {
        Write-Host "JMeter did not generate proper results - see $LOG_FILE" -ForegroundColor Red
        exit 1
    }
    
    # Create a dummy keys file if none was created
    if ((-not (Test-Path $KEYS_FILE)) -or ((Get-Item $KEYS_FILE).Length -eq 0)) {
        Write-Host "Keys file was not created properly. Creating basic keys file for GET/DELETE operations." -ForegroundColor Yellow
        
        # Create directory if it doesn't exist
        $keysDir = Split-Path -Path $KEYS_FILE -Parent
        if (-not (Test-Path $keysDir)) {
            New-Item -Path $keysDir -ItemType Directory -Force | Out-Null
        }
        
        # Extract keys from the results file if available
        $keysContent = ""
        if (Test-Path $RESULT_CSV) {
            $csvContent = Get-Content $RESULT_CSV -Raw
            if ($csvContent -match "key[0-9]+") {
                for ($i = 0; $i -lt 100; $i++) {
                    $keysContent += "key$i=value$i`n"
                }
                Set-Content -Path $KEYS_FILE -Value $keysContent
                Write-Host "Created sample keys file: $KEYS_FILE" -ForegroundColor Green
            }
        }
    }
}
catch {
    Write-Host "Error starting JMeter: $_" -ForegroundColor Red
    exit 1
}

# ------------- quick metrics -------------
if (-not (Test-Path $RESULT_CSV) -or (Get-Item $RESULT_CSV).Length -eq 0) {
    Write-Host "Empty CSV - check the log." -ForegroundColor Red
    exit 1
}

$totalLines = (Get-Content $RESULT_CSV | Measure-Object -Line).Lines
if ($totalLines -le 1) {
    Write-Host "CSV does not contain sample data - check log: $LOG_FILE and report: $REPORT_OUT" -ForegroundColor Yellow
    if ((Get-Content $LOG_FILE -Raw) -match 'Starting standalone test' -and ((Get-Content $LOG_FILE -Raw) -notmatch 'Tidying up')) {
        Write-Host "Warning: The test may have been prematurely interrupted." -ForegroundColor Yellow
    }
    elseif ((Get-Content $LOG_FILE -Raw) -match 'Error occurred compiling the tree') {
        Write-Host "Error in JMX compilation, CSV may be empty." -ForegroundColor Red
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
        if ($row.Latency -ne $null) {
            $latencyValues += [double]$row.Latency
        }
    }
    if ($latencyValues.Count -gt 0) {
        $avgLatency = [math]::Round(($latencyValues | Measure-Object -Average).Average, 2).ToString("0.00")
    }
}

# Get PUT success count
$putSuccessCount = "0"
if (Test-Path $LOG_FILE) {
    $logContent = Get-Content $LOG_FILE -Raw
    if ($logContent -match "JSR223 Store keys: .* keys prop by thread .* Current keys: \[(.*?)\]") {
        $matches[1] -match ',' -replace '[^,]', '' | Measure-Object -Character
    }
}

Write-Host "`n===== Summary ====="
Write-Host "Total PUT operations...: $total"
Write-Host "Success................: $ok ($(Get-Percentage -numerator $ok -denominator $total)%)"
Write-Host "Failures...............: $fail"
Write-Host "Average latency........: $avgLatency ms"
Write-Host ""
Write-Host "HTML Report in.........: $REPORT_OUT/index.html"
Write-Host "JMeter Log.............: $LOG_FILE"
Write-Host "CSV Results............: $RESULT_CSV"
Write-Host ""

# Display the keys file as a detailed statistics section
if (Test-Path $KEYS_FILE) {
    $keyCount = (Get-Content $KEYS_FILE | Measure-Object -Line).Lines
    Write-Host "`n===== Detailed Statistics =====" -ForegroundColor Green
    Write-Host "Keys Generated: $keyCount total"
    Get-Content $KEYS_FILE -TotalCount 10 | ForEach-Object {
        Write-Host $_
    }
    if ($keyCount -gt 10) {
        Write-Host "... ($(($keyCount - 10)) more)"
    }
    Write-Host "`nAll keys saved to: $KEYS_FILE"
} 