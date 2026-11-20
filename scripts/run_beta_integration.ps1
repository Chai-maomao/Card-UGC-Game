param(
    [string]$GodotPath = 'D:\XunLeiXiaZai\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe',
    [string]$RelayUrl = 'http://127.0.0.1:8789',
    [switch]$WithArt,
    [switch]$CheckArtGuard
)
$ErrorActionPreference = 'Stop'
$betaProject = Split-Path -Parent $PSScriptRoot
$betaOutput = Join-Path $betaProject ('artifacts/online-beta-20261021/integration-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $betaOutput -Force | Out-Null
$env:APPDATA = Join-Path $betaOutput 'profile'
$env:LOCALAPPDATA = $env:APPDATA
$env:CARDEX_BETA_TEST_URL = $RelayUrl
$codePath = Join-Path $betaOutput 'room-code.txt'
$clients = @()
function Start-BetaClient([int]$Role) {
	$env:APPDATA = Join-Path $betaOutput "profile-p$Role"
	$env:LOCALAPPDATA = $env:APPDATA
    $arguments = @('--headless', '--path', $betaProject, '--scene', 'res://tests/integration/beta_client.tscn', '--', "--role=$Role", "--code-file=$codePath")
    if ($WithArt) { $arguments += '--art' }
    if ($CheckArtGuard) { $arguments += '--guard-art' }
    Start-Process -FilePath $GodotPath -ArgumentList ($arguments | ForEach-Object { '"{0}"' -f $_ }) -RedirectStandardOutput (Join-Path $betaOutput "p$Role.log") -RedirectStandardError (Join-Path $betaOutput "p$Role.err") -PassThru -WindowStyle Hidden
}
try {
    $clients += Start-BetaClient 1
    $deadline = [DateTime]::UtcNow.AddSeconds(25)
    while (-not (Test-Path -LiteralPath $codePath) -and [DateTime]::UtcNow -lt $deadline -and -not $clients[0].HasExited) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $codePath)) { throw 'Beta host failed to create a room' }
    $clients += Start-BetaClient 2
    foreach ($client in $clients) {
        if (-not $client.WaitForExit(95000)) { throw 'Beta integration timed out' }
    }
    foreach ($role in 1,2) {
        $content = (Get-Content -Raw (Join-Path $betaOutput "p$role.log")) + (Get-Content -Raw (Join-Path $betaOutput "p$role.err"))
        if ($content -match 'SCRIPT ERROR|ERROR:|TEST_.*FAILED' -or $content -notmatch "TEST_BETA_RELAY_INTEGRATION_OK_P$role") { throw "Beta P$role failed; see $betaOutput" }
    }
    Write-Output "TEST_BETA_TWO_PROCESS_OK $betaOutput"
} finally {
    foreach ($client in $clients) { if (-not $client.HasExited) { $client.Kill() }; $client.Dispose() }
}
