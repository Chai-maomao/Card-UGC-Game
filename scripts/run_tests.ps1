param(
    [string]$GodotPath = $(if ($env:GODOT_BIN) { $env:GODOT_BIN } else { "D:\XunLeiXiaZai\Godot_v4.6.3-stable_win64.exe\Godot_v4.6.3-stable_win64_console.exe" }),
    [ValidateSet('logic', 'visual')][string]$Suite = 'logic',
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 90,
    [string]$Scene = 'Test*.tscn'
)
$ErrorActionPreference = 'Stop'
$projectPath = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $projectPath ".godot/test-logs/$Suite"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$failed = 0
$count = 0
foreach ($file in (Get-ChildItem -LiteralPath $projectPath -Filter $Scene | Sort-Object Name)) {
    $isVisual = $file.BaseName -like '*Visual'
    if (($Suite -eq 'visual') -ne $isVisual) { continue }
    $count++
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $GodotPath
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.WorkingDirectory = $projectPath
    $arguments = @('--path', $projectPath, '--scene', "res://$($file.Name)")
    if ($Suite -eq 'logic') { $arguments += '--headless' }
    else { $arguments += @('--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3') }
    # ProcessStartInfo.ArgumentList (.NET Core 2.0+) is absent on Windows PowerShell 5.1 / .NET Framework;
    # fall back to a quoted Arguments string so the runner works on both.
    if ($null -ne $startInfo.ArgumentList) { foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) } }
    else { $startInfo.Arguments = ($arguments | ForEach-Object { '"{0}"' -f $_ }) -join ' ' }
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void]$process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $timedOut = -not $process.WaitForExit($TimeoutSeconds * 1000)
        if ($timedOut) { $process.Kill($true); $process.WaitForExit() }
        $content = $stdout.GetAwaiter().GetResult() + $stderr.GetAwaiter().GetResult()
        [System.IO.File]::WriteAllText((Join-Path $logDir "$($file.BaseName).log"), $content)
        $marker = [regex]::Match($content, 'TEST_[A-Z0-9_]+_OK').Value
        if ($timedOut -or $process.ExitCode -ne 0 -or $content -match 'SCRIPT ERROR|Parse Error|ERROR:|TEST_[A-Z0-9_]+_FAILED' -or -not $marker) {
            Write-Output "FAIL $($file.Name) (exit=$($process.ExitCode), timeout=$timedOut); see $logDir"
            $failed++
        } else { Write-Output "PASS $($file.Name) $marker" }
    } finally { $process.Dispose() }
}
Write-Output "Ran $count $Suite scenes; failures: $failed"
if ($failed -gt 0 -or $count -eq 0) { exit 1 }
exit 0
