param(
    [string]$PairToken = ""
)

$ErrorActionPreference = "Stop"
$ServerUrl = "http://ufe5879.glddns.com:8893"
$Base = Join-Path $env:LOCALAPPDATA "OriginsActivityHelper"
$ConfigPath = Join-Path $Base "config.json"
$HelperPath = Join-Path $Base "OriginsActivityHelper.ps1"
$HelperLog = Join-Path $Base "helper.log"
$Startup = [Environment]::GetFolderPath("Startup")
$StartupCmd = Join-Path $Startup "Origins Activity Helper.cmd"

function Fail([string]$Message) {
    Write-Host ""
    Write-Host "INSTALLATION FAILED" -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Nothing in Windows security was disabled."
    Write-Host "Send a screenshot of this window to an Origins administrator."
    Write-Host ""
    Read-Host "Press Enter to close"
    exit 1
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "              ORIGINS ACTIVITY HELPER v1.5" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "One-time installer. No Administrator rights are required."
Write-Host "PowerShell security policy is NOT changed permanently."
Write-Host ""

try {
    $health = Invoke-RestMethod -Uri "$ServerUrl/health" -Method Get -TimeoutSec 12
    if (-not $health.ok) {
        Fail "The Origins Activity Helper server did not pass its health check."
    }
} catch {
    Fail "Could not reach Origins at $ServerUrl`n$($_.Exception.Message)"
}

if (-not $PairToken) {
    $secure = Read-Host "Paste your private Pairing Token" -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $PairToken = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }
}

if ($PairToken -notmatch '^([0-9a-f]{16})\.(.{20,})$') {
    Fail "That pairing token is not valid. Generate a fresh token with /activity-helper-setup in Discord."
}

$keyId = $Matches[1]
$secret = $Matches[2]

New-Item -ItemType Directory -Force -Path $Base | Out-Null

$runtime = @'
param(
    [switch]$Once
)

$ErrorActionPreference = "Stop"
$Base = Join-Path $env:LOCALAPPDATA "OriginsActivityHelper"
$ConfigPath = Join-Path $Base "config.json"
$GameLogPath = Join-Path $env:LOCALAPPDATA "TheIsle\Saved\Logs\TheIsle.log"
$CachePath = Join-Path $Base "servers-cache.json"
$HelperLog = Join-Path $Base "helper.log"

function Write-HelperLog([string]$Message) {
    New-Item -ItemType Directory -Force -Path $Base | Out-Null
    $stamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$stamp $Message" | Add-Content -Encoding ASCII $HelperLog
}

function Get-GameRunning {
    return [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -like "TheIsleClient-Win64-Shipping*" -or
        $_.ProcessName -eq "TheIsle"
    } | Select-Object -First 1)
}

function Get-DetectedEndpoint {
    if (-not (Test-Path $GameLogPath)) {
        return @{ endpoint = $null; menu = $true }
    }

    $lines = Get-Content -Path $GameLogPath -Tail 8000 -ErrorAction SilentlyContinue
    $latestBrowse = -1
    $latestDisconnect = -1
    $endpoint = $null
    $browseWithoutEndpoint = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]

        if ($line -match 'UEngine::Browse Started Browse:\s*"([^"]*)"') {
            $latestBrowse = $i
            $target = $Matches[1]
            if ($target -match '^((?:\d{1,3}\.){3}\d{1,3})(?::(\d{1,5}))?/') {
                $endpoint = if ($Matches[2]) { "$($Matches[1]):$($Matches[2])" } else { $Matches[1] }
                $browseWithoutEndpoint = $false
            } else {
                $endpoint = $null
                $browseWithoutEndpoint = $true
            }
        }

        if ($line -match '(NetworkFailure|ConnectionLost|Connection\s+TIMED\s+OUT|UNetConnection::Close|TravelFailure|DestroyNamedNetDriver|Failed\s+to\s+connect|Connection\s+closed)') {
            $latestDisconnect = $i
        }
    }

    $menu = (($latestDisconnect -gt $latestBrowse) -and ($latestBrowse -ge 0)) -or
            (($latestBrowse -ge 0) -and $browseWithoutEndpoint)

    return @{ endpoint = $endpoint; menu = $menu }
}

function Convert-ObjectToHashtable($Object) {
    $map = @{}
    if ($null -eq $Object) { return $map }

    foreach ($prop in $Object.PSObject.Properties) {
        $map[[string]$prop.Name] = @($prop.Value | ForEach-Object { [string]$_ })
    }
    return $map
}

function Get-ServerMap($Cfg) {
    try {
        $response = Invoke-RestMethod -Uri "$($Cfg.endpoint)/v1/servers" -Method Get -TimeoutSec 12
        $map = @{}
        foreach ($row in $response.servers) {
            $map[[string]$row.name] = @($row.endpoints | ForEach-Object { [string]$_ })
        }
        $map | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $CachePath
        Write-HelperLog "Server map refreshed: $($map.Count) entries"
        return $map
    } catch {
        Write-HelperLog "Server map refresh failed: $($_.Exception.Message)"
        if (Test-Path $CachePath) {
            try {
                $cached = Get-Content $CachePath -Raw | ConvertFrom-Json
                return Convert-ObjectToHashtable $cached
            } catch {
                Write-HelperLog "Cached map load failed: $($_.Exception.Message)"
            }
        }
        return @{}
    }
}

function Resolve-State($Map) {
    if (-not (Get-GameRunning)) {
        return @{ state = "offline"; server = "" }
    }

    $det = Get-DetectedEndpoint
    if (-not $det.endpoint -or $det.menu) {
        return @{ state = "main_menu"; server = "" }
    }

    foreach ($name in $Map.Keys) {
        if (@($Map[$name]) -contains [string]$det.endpoint) {
            if ($name -eq "Origins") {
                return @{ state = "origins"; server = "Origins" }
            }
            if ($name -match '^Official EU \d{1,2}$') {
                return @{ state = "official_eu"; server = [string]$name }
            }
        }
    }

    return @{ state = "other"; server = "" }
}

function New-Nonce {
    $bytes = New-Object byte[] 12
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($bytes)
    } finally {
        $rng.Dispose()
    }
    return ([Convert]::ToBase64String($bytes)).TrimEnd('=').Replace('+','_').Replace('/','_')
}

function Get-HmacHex([byte[]]$Key, [string]$Text) {
    $h = New-Object System.Security.Cryptography.HMACSHA256
    try {
        $h.Key = $Key
        $hash = $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text))
    } finally {
        $h.Dispose()
    }
    return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

function Send-Status($Cfg, $State, $Server) {
    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $nonce = New-Nonce
    $keyId = [string]$Cfg.key_id

    $canonical = "v1|$keyId|$timestamp|$nonce|$State|$Server"
    $key = [Text.Encoding]::UTF8.GetBytes([string]$Cfg.secret)
    $signature = Get-HmacHex $key $canonical

    $body = @{
        key_id = $keyId
        timestamp = $timestamp
        nonce = $nonce
        state = $State
        server = $Server
        signature = $signature
    } | ConvertTo-Json -Compress

    $result = Invoke-RestMethod -Uri "$($Cfg.endpoint)/v1/activity" -Method Post `
        -ContentType "application/json" -Body $body -TimeoutSec 12

    if (-not $result.ok) {
        throw "Origins returned an unsuccessful response."
    }
}

function Test-And-SendOnce($Cfg) {
    Write-Host ""
    Write-Host "Testing Origins Activity Helper..."
    Write-Host "Server: $($Cfg.endpoint)"

    $map = Get-ServerMap $Cfg
    if ($map.Count -eq 0) {
        throw "Could not download the Origins / Official EU server map."
    }

    $det = Get-DetectedEndpoint
    if (Get-GameRunning) {
        Write-Host "The Isle: running"
        if ($det.endpoint) {
            Write-Host "Detected game endpoint: $($det.endpoint)"
        } else {
            Write-Host "Detected game endpoint: none (likely main menu)"
        }
    } else {
        Write-Host "The Isle: not running"
    }

    $resolved = Resolve-State $map
    Write-Host "Resolved state: $($resolved.state) $($resolved.server)"

    Send-Status $Cfg $resolved.state $resolved.server
    Write-HelperLog "Sent state=$($resolved.state) server=$($resolved.server)"
    Write-Host "Origins update: SUCCESS"
}

if (-not (Test-Path $ConfigPath)) {
    Write-Error "Origins Activity Helper is not configured. Re-run the installer."
    exit 1
}

$cfg = Get-Content $ConfigPath -Raw | ConvertFrom-Json

if ($Once) {
    try {
        Test-And-SendOnce $cfg
        exit 0
    } catch {
        Write-HelperLog "Test failed: $($_.Exception.Message)"
        Write-Error $_.Exception.Message
        exit 1
    }
}

$map = @{}
$mapAt = [DateTime]::MinValue
$lastState = ""
$lastServer = ""
$lastSent = [DateTime]::MinValue

Write-HelperLog "Helper started"

while ($true) {
    try {
        if ((Get-Date) -gt $mapAt.AddMinutes(5) -or $map.Count -eq 0) {
            $map = Get-ServerMap $cfg
            $mapAt = Get-Date
        }

        $result = Resolve-State $map
        if ($result.state -ne $lastState -or $result.server -ne $lastServer -or
            (Get-Date) -gt $lastSent.AddSeconds(60)) {
            Send-Status $cfg $result.state $result.server
            Write-HelperLog "Sent state=$($result.state) server=$($result.server)"
            $lastState = $result.state
            $lastServer = $result.server
            $lastSent = Get-Date
        }
    } catch {
        Write-HelperLog "Update failed: $($_.Exception.Message)"
    }

    Start-Sleep -Seconds 30
}

'@

# Write our own local copy. ASCII avoids Windows PowerShell 5.1 encoding issues.
[IO.File]::WriteAllText($HelperPath, $runtime, [Text.Encoding]::ASCII)

@{
    endpoint = $ServerUrl
    key_id = $keyId
    secret = $secret
    poll_seconds = 30
} | ConvertTo-Json | Set-Content -Encoding UTF8 $ConfigPath

# Ensure an old helper instance does not keep the old script/config in memory.
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*OriginsActivityHelper.ps1*" } |
    ForEach-Object {
        try { Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop } catch {}
    }

Write-Host ""
Write-Host "Running end-to-end test..." -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HelperPath -Once
if ($LASTEXITCODE -ne 0) {
    Fail "The helper was installed locally, but its end-to-end test failed. Check $HelperLog"
}

$startupText = "@echo off`r`nstart `"`" /min powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$HelperPath`"`r`n"
[IO.File]::WriteAllText($StartupCmd, $startupText, [Text.Encoding]::ASCII)

# Start it now; future Windows sign-ins use the Startup entry above.
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$HelperPath`""

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                  INSTALLATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Origins Activity Helper is running."
Write-Host "It will start automatically whenever you sign into Windows."
Write-Host ""
Write-Host "Installed to:"
Write-Host "  $Base"
Write-Host ""
Write-Host "You can close this window."
Write-Host ""
Read-Host "Press Enter to finish"
