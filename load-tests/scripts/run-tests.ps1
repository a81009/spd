# PowerShell script for Key-Value Store load testing
# This is a wrapper script that explains the separate test scripts

Write-Host "==================================================================="
Write-Host "                 KV Store Load Testing Framework                   "
Write-Host "==================================================================="
Write-Host ""
Write-Host "The load testing has been divided into three separate scripts:"
Write-Host ""
Write-Host "1. run-puts.ps1  - Tests PUT operations (inserting key-value pairs)"
Write-Host "2. run-gets.ps1  - Tests GET operations (retrieving values by key)"
Write-Host "3. run-deletes.ps1 - Tests DELETE operations (removing key-value pairs)"
Write-Host ""
Write-Host "Usage instructions:"
Write-Host "-----------------"
Write-Host "1. First run 'run-puts.ps1' to create keys in the KV store"
Write-Host "2. Then run 'run-gets.ps1' to test retrieving those keys"
Write-Host "3. Finally run 'run-deletes.ps1' to test deleting those keys"
Write-Host ""
Write-Host "Each script will:"
Write-Host "- Ask for test parameters (users, duration, TPS, etc.)"
Write-Host "- Run JMeter test plans automatically"
Write-Host "- Store results in the jmeter/results directory"
Write-Host "- Generate HTML reports in the jmeter/reports directory"
Write-Host ""
Write-Host "Which test would you like to run now?"
Write-Host "1. PUT operations (run-puts.ps1)"
Write-Host "2. GET operations (run-gets.ps1)"
Write-Host "3. DELETE operations (run-deletes.ps1)"
Write-Host "q. Quit"
Write-Host ""

$choice = Read-Host "Enter your choice (1, 2, 3, or q)"

switch ($choice) {
    "1" {
        Write-Host "Running PUT operations test..."
        & "$PSScriptRoot\run-puts.ps1"
    }
    "2" {
        Write-Host "Running GET operations test..."
        & "$PSScriptRoot\run-gets.ps1"
    }
    "3" {
        Write-Host "Running DELETE operations test..."
        & "$PSScriptRoot\run-deletes.ps1"
    }
    "q" {
        Write-Host "Exiting..."
    }
    default {
        Write-Host "Invalid choice. Please run one of the following scripts directly:"
        Write-Host "- $PSScriptRoot\run-puts.ps1"
        Write-Host "- $PSScriptRoot\run-gets.ps1"
        Write-Host "- $PSScriptRoot\run-deletes.ps1"
    }
}