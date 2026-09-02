# Headless test runner for all Test*.tscn scenes (Windows / Godot 4.6)
param(
	[string]$GodotPath = "D:\XunLeiXiaZai\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe"
)

$ErrorActionPreference = "Continue"
$logDir = ".godot\test-logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$projectPath = (Resolve-Path .).Path

$failed = 0
$count = 0

Get-ChildItem -Path . -Filter "Test*.tscn" | Sort-Object Name | ForEach-Object {
	$scene = $_.Name
	$logPath = Join-Path $logDir ($scene -replace '\.tscn$', '.log')
	$count++
	# 同步运行，直接捕获合并输出与退出码
	$content = & $GodotPath --headless --path $projectPath --scene "res://$scene" 2>&1 | Out-String
	$exitCode = $LASTEXITCODE
	[System.IO.File]::WriteAllText((Join-Path $projectPath $logPath), $content)
	$marker = ""
	if ($content -match 'TEST_[A-Z0-9_]+_OK') { $marker = $Matches[0] }
	if ($exitCode -ne 0 -or $content -match 'SCRIPT ERROR|Parse Error|TEST_[A-Z0-9_]+_FAILED' -or -not $marker) {
		Write-Output "FAIL  $scene (exit=$exitCode)"
		$failed++
	} else {
		Write-Output "PASS  $scene  $marker"
	}
}

Write-Output "Ran $count test scenes; failures: $failed"
if ($failed -gt 0) { exit 1 } else { exit 0 }
