# PowerShell script for DELETE operations on KV store
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
$DEL_TPS = Read-Input -prompt "DELETE ops/s" -default "50"
$TEST_NAME = Read-Input -prompt "Test name" -default "kv-deletes-test"

# Automatically find the most recent keys file
$KEYS_FILE = Get-ChildItem -Path $KEYS_DIR -Filter "keys-*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
if (-not $KEYS_FILE) {
    Write-Host "No keys file found. Creating a sample keys file for testing..." -ForegroundColor Yellow
    
    # Create keys directory if it doesn't exist
    if (-not (Test-Path $KEYS_DIR)) {
        New-Item -Path $KEYS_DIR -ItemType Directory -Force | Out-Null
    }
    
    # Create a sample keys file
    $TIMESTAMP = Get-Date -Format "yyyyMMdd-HHmmss"
    $KEYS_FILE = Join-Path $KEYS_DIR "keys-$TIMESTAMP.txt"
    
    # Generate sample keys
    $keysContent = ""
    for ($i = 0; $i -lt 100; $i++) {
        $keysContent += "key$i=value$i`n"
    }
    
    Set-Content -Path $KEYS_FILE -Value $keysContent
    Write-Host "Created sample keys file: $KEYS_FILE" -ForegroundColor Green
}
Write-Host "Using keys file: $KEYS_FILE"

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
    # Convert requests/second to requests/minute for JMeter
    return [int]($val * 60)
}

$DEL_TPM = To-Min -val $DEL_TPS  # This will be requests per minute

# Calculate fixed values for test plan - MODIFIED to make DEL_TPS be per user
[int]$requestsPerUser = [int]$DURATION * [int]$DEL_TPS  # Each user should make this many requests
[int]$totalRequests = [int]$requestsPerUser * [int]$USERS  # Total requests for the test
# Calculate delay (in ms) between requests to achieve TPS per user
[int]$delayMs = [int]([Math]::Floor(1000 / $DEL_TPS))

Write-Host "`n===== Parameters ====="
Write-Host "Host.................: localhost"
Write-Host "Port.................: 8000"
Write-Host "Users................: $USERS"
Write-Host "Ramp-up..............: $RAMPUP s"
Write-Host "Duration.............: $DURATION s (+${WARMUP}s warm-up)"
Write-Host "DELETE TPS per user..: $DEL_TPS"
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

# Script to load keys from file
$loadKeysScript = @"
// Load keys from file
String keysFile = "$KEYS_FILE";
java.io.File file = new java.io.File(keysFile);
if (!file.exists()) {
    log.error("Keys file not found: " + keysFile);
    return "ERROR_NO_KEYS_FILE";
}

java.io.BufferedReader reader = new java.io.BufferedReader(new java.io.FileReader(file));
String line;
StringBuilder keysList = new StringBuilder();
int keyCount = 0;

while ((line = reader.readLine()) != null) {
    if (line.contains("=")) {
        String[] parts = line.split("=", 2);
        String key = parts[0].trim();
        String value = parts[1].trim();
        
        // Store key and value in properties
        props.put(key, value);
        keysList.append(key).append(",");
        keyCount++;
        
        // Also store in vars for first time access
        if (keyCount == 1) {
            vars.put("first_key", key);
        }
    }
}
reader.close();

// Store the list of keys
if (keyCount > 0) {
    props.put("keys", keysList.toString());
    props.put("key_count", String.valueOf(keyCount));
    log.info("Loaded " + keyCount + " keys from file");
    return "SUCCESS_LOADED_" + keyCount + "_KEYS";
} else {
    log.error("No valid keys found in file");
    return "ERROR_NO_VALID_KEYS";
}
"@

# Script to get a random key for DELETE operation
$getKeyScript = @"
// Get a random key from the loaded keys
String keyList = props.get("keys");
if (keyList == null || keyList.isEmpty()) {
    log.error("No keys available for DELETE operation");
    return "default_key_no_keys_available";
}

String[] keys = keyList.split(",");
java.util.List<String> validKeys = new java.util.ArrayList<>();

for (String key : keys) {
    if (key != null && !key.trim().isEmpty()) {
        validKeys.add(key.trim());
    }
}

if (validKeys.isEmpty()) {
    log.error("No valid keys in list");
    return "default_key_empty_list";
}

// Get a random key
int randomIndex = (int)(Math.random() * validKeys.size());
String selectedKey = validKeys.get(randomIndex);
log.info("Selected key for DELETE: " + selectedKey);
return selectedKey;
"@

# Stats report script
$statsScript = @"
// Generate statistics report
String delTotal = props.get("del_total") == null ? "0" : props.get("del_total");
String delSuccess = props.get("del_success") == null ? "0" : props.get("del_success");

// Calculate percentages
int delTotalInt = Integer.parseInt(delTotal);
int delSuccessInt = Integer.parseInt(delSuccess);
double delSuccessRate = delTotalInt > 0 ? (delSuccessInt * 100.0 / delTotalInt) : 0;

// Store report in file
String reportPath = "${STATS_DIR}\\del-stats-report-${TIMESTAMP}.txt";
java.io.File file = new java.io.File(reportPath);
java.io.FileWriter writer = new java.io.FileWriter(file);
writer.write("====== DELETE Test Results: ${TEST_NAME} ======\n");
writer.write("Date/Time: " + new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(new java.util.Date()) + "\n");
writer.write("Duration: ${DURATION}s, Users: ${USERS}, TPS: ${DEL_TPS}\n\n");
writer.write("====== Operation Statistics ======\n");
writer.write("DELETE: " + delSuccessInt + "/" + delTotalInt + " successful (" + String.format("%.2f", delSuccessRate) + "%)\n");
writer.write("==============================\n");
writer.close();

return reportPath;
"@

# Escape for XML with special attention to &&
$loadKeysScript = $loadKeysScript -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
$getKeyScript = $getKeyScript -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
$statsScript = $statsScript -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'

# Fix specific && issues in Track DELETE Success script
$deleteSuccessScript = @"
if (prev.isSuccessful()) {
    // Increment DELETE success counter
    synchronized(props) {
        String delSuccess = props.get("del_success");
        if (delSuccess == null) {
            delSuccess = "0";
        }
        int count = Integer.parseInt(delSuccess) + 1;
        props.put("del_success", String.valueOf(count));
    }
    
    // Update the keys list to remove the deleted key
    String key = prev.getUrlAsString();
    if (key.contains("key=")) {
        key = key.substring(key.indexOf("key=") + 4);
        log.info("Successfully deleted key: " + key);
        
        // Remove from keys list
        synchronized(props) {
            String keys = props.get("keys");
            if (keys != null) {
                if (keys.contains(key)) {
                    keys = keys.replace(key + ",", "");
                    props.put("keys", keys);
                    log.info("Removed key from available keys: " + key);
                }
            }
        }
    }
}
"@

# Properly escape this script for XML
$deleteSuccessScript = $deleteSuccessScript -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'

# Generate the JMX file content
$jmxContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<jmeterTestPlan version="1.4" properties="5.0">
  <hashTree>
    <TestPlan guiclass="TestPlanGui" testclass="TestPlan" testname="KV Store DELETE Test Plan">
      <boolProp name="TestPlan.functional_mode">false</boolProp>
      <boolProp name="TestPlan.tearDown_on_shutdown">true</boolProp>
      <elementProp name="TestPlan.user_defined_variables" elementType="Arguments" guiclass="ArgumentsPanel" testclass="Arguments">
        <collectionProp name="Arguments.arguments"/>
      </elementProp>
    </TestPlan>
    <hashTree>
      <JSR223Sampler guiclass="TestBeanGUI" testclass="JSR223Sampler" testname="Load Keys">
        <stringProp name="scriptLanguage">groovy</stringProp>
        <stringProp name="parameters"></stringProp>
        <stringProp name="filename"></stringProp>
        <stringProp name="cacheKey">true</stringProp>
        <stringProp name="script">$loadKeysScript</stringProp>
      </JSR223Sampler>
      <hashTree/>
      
      <ThreadGroup guiclass="ThreadGroupGui" testclass="ThreadGroup" testname="DELETE Thread Group">
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
        
        <JSR223PreProcessor guiclass="TestBeanGUI" testclass="JSR223PreProcessor" testname="Track DELETE Count">
          <stringProp name="scriptLanguage">groovy</stringProp>
          <stringProp name="parameters"></stringProp>
          <stringProp name="filename"></stringProp>
          <stringProp name="cacheKey">true</stringProp>
          <stringProp name="script">
// Increment DELETE total counter
synchronized(props) {
    String delTotal = props.get("del_total");
    if (delTotal == null) {
        delTotal = "0";
    }
    int count = Integer.parseInt(delTotal) + 1;
    props.put("del_total", String.valueOf(count));
}
          </stringProp>
        </JSR223PreProcessor>
        <hashTree/>
        
        <JSR223PreProcessor guiclass="TestBeanGUI" testclass="JSR223PreProcessor" testname="Get Random Key">
          <stringProp name="scriptLanguage">groovy</stringProp>
          <stringProp name="parameters"></stringProp>
          <stringProp name="filename"></stringProp>
          <stringProp name="cacheKey">true</stringProp>
          <stringProp name="script">$getKeyScript</stringProp>
        </JSR223PreProcessor>
        <hashTree/>
        
        <HTTPSamplerProxy guiclass="HttpTestSampleGui" testclass="HTTPSamplerProxy" testname="DELETE Request">
          <elementProp name="HTTPsampler.Arguments" elementType="Arguments">
            <collectionProp name="Arguments.arguments">
              <elementProp name="key" elementType="HTTPArgument">
                <boolProp name="HTTPArgument.always_encode">false</boolProp>
                <stringProp name="Argument.name">key</stringProp>
                <stringProp name="Argument.value">`${__groovy(vars.get("_jsr223PreProcessor_result"))}</stringProp>
                <stringProp name="Argument.metadata">=</stringProp>
                <boolProp name="HTTPArgument.use_equals">true</boolProp>
              </elementProp>
            </collectionProp>
          </elementProp>
          <stringProp name="HTTPSampler.domain">localhost</stringProp>
          <stringProp name="HTTPSampler.port">8000</stringProp>
          <stringProp name="HTTPSampler.path">/kv</stringProp>
          <stringProp name="HTTPSampler.method">DELETE</stringProp>
          <stringProp name="HTTPSampler.protocol">http</stringProp>
        </HTTPSamplerProxy>
        <hashTree>
          <JSR223PostProcessor guiclass="TestBeanGUI" testclass="JSR223PostProcessor" testname="Track DELETE Success">
            <stringProp name="scriptLanguage">groovy</stringProp>
            <stringProp name="parameters"></stringProp>
            <stringProp name="filename"></stringProp>
            <stringProp name="cacheKey">true</stringProp>
            <stringProp name="script">$deleteSuccessScript</stringProp>
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
      
      <JSR223Listener guiclass="TestBeanGUI" testclass="JSR223Listener" testname="Statistics Report">
        <stringProp name="scriptLanguage">groovy</stringProp>
        <stringProp name="parameters"></stringProp>
        <stringProp name="filename"></stringProp>
        <stringProp name="cacheKey">true</stringProp>
        <stringProp name="script">$statsScript</stringProp>
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
    
    # Check the exit code
    if ($process.ExitCode -ne 0) {
        Write-Host "JMeter returned error $($process.ExitCode) - see $LOG_FILE" -ForegroundColor Red
        exit 1
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

Write-Host "`n===== Summary ====="
Write-Host "Total DELETE operations: $total"
Write-Host "Success................: $ok ($(Get-Percentage -numerator $ok -denominator $total)%)"
Write-Host "Failures...............: $fail"
Write-Host "Average latency........: $avgLatency ms"
Write-Host ""
Write-Host "HTML Report in.........: $REPORT_OUT/index.html"
Write-Host "JMeter Log.............: $LOG_FILE"
Write-Host "CSV Results............: $RESULT_CSV"
Write-Host ""

# Display the stats report
$statsFiles = Get-ChildItem -Path $STATS_DIR -Filter "del-stats-report-$TIMESTAMP.txt" -ErrorAction SilentlyContinue
if ($statsFiles.Count -gt 0) {
    $statsFile = $statsFiles[0].FullName
    
    Write-Host "`n===== Detailed Statistics =====" -ForegroundColor Green
    Get-Content $statsFile | ForEach-Object {
        Write-Host $_
    }
    Write-Host "`nDetailed stats saved to: $statsFile" -ForegroundColor Yellow
} 