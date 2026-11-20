[CmdletBinding()]
param([Parameter(Mandatory)][int]$RootProcessId)

Add-Type @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class CardexBackgroundWindow {
    private delegate bool WindowCallback(IntPtr window, IntPtr data);
    [DllImport("user32.dll")] private static extern bool EnumWindows(WindowCallback callback, IntPtr data);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll")] private static extern int GetWindowLongW(IntPtr window, int index);
    [DllImport("user32.dll")] private static extern int SetWindowLongW(IntPtr window, int index, int value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr window, IntPtr order, int x, int y, int width, int height, uint flags);

    private static readonly HashSet<IntPtr> Lowered = new HashSet<IntPtr>();

    public static int Lower(uint[] processIds) {
        int count = 0;
        var targets = new HashSet<uint>(processIds);
        EnumWindows((window, _) => {
            uint processId;
            GetWindowThreadProcessId(window, out processId);
            if (!targets.Contains(processId) || !IsWindowVisible(window) || Lowered.Contains(window)) return true;
            const int extendedStyle = -20;
            const int noActivate = 0x08000000;
            SetWindowLongW(window, extendedStyle, GetWindowLongW(window, extendedStyle) | noActivate);
            // HWND_BOTTOM with no move, resize or activation. Refresh the changed window style.
            if (SetWindowPos(window, new IntPtr(1), 0, 0, 0, 0, 0x33)) {
                Lowered.Add(window);
                count++;
            }
            return true;
        }, IntPtr.Zero);
        return count;
    }
}
'@

$gameProcessPattern = '^(Godot.*|Cardex)(\.exe)?$'
while ($rootProcess = Get-Process -Id $RootProcessId -ErrorAction SilentlyContinue) {
    $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $RootProcessId" | Where-Object Name -Match $gameProcessPattern)
    $gameIds = @()
    if ($rootProcess.ProcessName -match $gameProcessPattern) { $gameIds += $RootProcessId }
    foreach ($child in $children) {
        $gameIds += $child.ProcessId
        # The Windows console executable launches the windowed engine as its child.
        $gameIds += @(Get-CimInstance Win32_Process -Filter "ParentProcessId = $($child.ProcessId)" | Where-Object Name -Match $gameProcessPattern | Select-Object -ExpandProperty ProcessId)
    }
    $count = [CardexBackgroundWindow]::Lower([uint32[]]$gameIds)
    if ($count -gt 0) { Write-Verbose "Sent $count Godot test window(s) to the bottom of the desktop stack." }
    Start-Sleep -Milliseconds 350
}
