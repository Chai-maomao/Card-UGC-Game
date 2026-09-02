param(
    [string]$GodotBin = "godot",
    [int]$Port = 5178
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("card-ugc-lan-" + [Guid]::NewGuid().ToString("N"))
$prefix = "lan" + [Guid]::NewGuid().ToString("N").Substring(0, 12)
New-Item -ItemType Directory -Path $tempRoot | Out-Null

function Start-Client([int]$Role, [string]$Phase, [string]$LogPath) {
    $arguments = @(
        "--headless", "--path", $repoRoot,
        "--scene", "res://tests/integration/lan_reconnect_client.tscn", "--",
        "--role=$Role", "--phase=$Phase", "--prefix=$prefix", "--port=$Port"
    )
    Start-Process -FilePath $GodotBin -ArgumentList $arguments -RedirectStandardOutput $LogPath -RedirectStandardError ($LogPath + ".err") -PassThru -WindowStyle Hidden
}

function Wait-Pair([System.Diagnostics.Process]$HostProcess, [System.Diagnostics.Process]$ClientProcess) {
    if (-not $HostProcess.WaitForExit(25000)) { $HostProcess.Kill(); throw "LAN host timed out" }
    if (-not $ClientProcess.WaitForExit(25000)) { $ClientProcess.Kill(); throw "LAN client timed out" }
    if ($HostProcess.ExitCode -ne 0 -or $ClientProcess.ExitCode -ne 0) {
        throw "LAN integration process failed (host=$($HostProcess.ExitCode), client=$($ClientProcess.ExitCode))"
    }
}

function Start-DiscoveryProbe([string]$Role, [string]$LogPath) {
    $arguments = @(
        "--headless", "--path", $repoRoot,
        "--scene", "res://tests/integration/lan_discovery_probe.tscn", "--",
        "--role=$Role", "--prefix=$prefix", "--port=$Port"
    )
    Start-Process -FilePath $GodotBin -ArgumentList $arguments -RedirectStandardOutput $LogPath -RedirectStandardError ($LogPath + ".err") -PassThru -WindowStyle Hidden
}

try {
    $discoveryHostLog = Join-Path $tempRoot "discovery-host.log"
    $discoveryClientLog = Join-Path $tempRoot "discovery-client.log"
    $discoveryHost = Start-DiscoveryProbe "host" $discoveryHostLog
    Start-Sleep -Milliseconds 500
    $discoveryClient = Start-DiscoveryProbe "client" $discoveryClientLog
    Wait-Pair $discoveryHost $discoveryClient
    if (-not (Select-String -Quiet -Path $discoveryHostLog -Pattern "TEST_LAN_DISCOVERY_HOST_READY") -or
        -not (Select-String -Quiet -Path $discoveryClientLog -Pattern "TEST_LAN_DISCOVERY_FOUND")) {
        throw "LAN discovery markers missing"
    }

    $liveHostLog = Join-Path $tempRoot "live-host.log"
    $liveClientLog = Join-Path $tempRoot "live-client.log"
    $liveHost = Start-Client 1 "live" $liveHostLog
    Start-Sleep -Milliseconds 700
    $liveClient = Start-Client 2 "live" $liveClientLog
    Wait-Pair $liveHost $liveClient
    if (-not (Select-String -Quiet -Path $liveHostLog -Pattern "TEST_LAN_LIVE_RECONNECT_OK_P1") -or
        -not (Select-String -Quiet -Path $liveClientLog -Pattern "TEST_LAN_LIVE_RECONNECT_OK_P2")) {
        throw "LAN live reconnect markers missing"
    }

    $seedHostLog = Join-Path $tempRoot "seed-host.log"
    $seedClientLog = Join-Path $tempRoot "seed-client.log"
    $seedHost = Start-Client 1 "seed" $seedHostLog
    Start-Sleep -Milliseconds 700
    $seedClient = Start-Client 2 "seed" $seedClientLog
    Wait-Pair $seedHost $seedClient
    if (-not (Select-String -Quiet -Path $seedHostLog -Pattern "TEST_LAN_SESSION_SEEDED_P1") -or
        -not (Select-String -Quiet -Path $seedClientLog -Pattern "TEST_LAN_SESSION_SEEDED_P2")) {
        throw "LAN seed markers missing"
    }

    $resumeHostLog = Join-Path $tempRoot "resume-host.log"
    $resumeClientLog = Join-Path $tempRoot "resume-client.log"
    $resumeHost = Start-Client 1 "resume" $resumeHostLog
    Start-Sleep -Milliseconds 700
    $resumeClient = Start-Client 2 "resume" $resumeClientLog
    Wait-Pair $resumeHost $resumeClient
    if (-not (Select-String -Quiet -Path $resumeHostLog -Pattern "TEST_LAN_PROCESS_RESTART_RESUME_OK_P1") -or
        -not (Select-String -Quiet -Path $resumeClientLog -Pattern "TEST_LAN_PROCESS_RESTART_RESUME_OK_P2")) {
        throw "LAN restart-resume markers missing"
    }
    Write-Output "PASS  LAN discovery, transport reconnect, and process-restart snapshot resume"
}
catch {
    Get-ChildItem $tempRoot -File | ForEach-Object {
        Write-Output ("--- " + $_.Name)
        Get-Content $_.FullName
    }
    throw
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
