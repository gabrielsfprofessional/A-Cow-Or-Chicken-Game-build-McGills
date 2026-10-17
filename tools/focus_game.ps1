# Brings one game window to the front, found by process ID only (T18 follow-up).
# Used by tools\hand_check.ps1 after it opens the game window. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\focus_game.ps1 -GamePid <pid> [-WaitSec 15]
# <pid> is the Godot process that was started (the console build starts the game
# as its child, so its direct children count too). It never looks windows up by
# title, never sends key presses, and never touches any other window: it waits
# for that process's main window, minimizes and restores it (Windows lets a
# restored window come to the front), and checks that the window in front now
# belongs to one of those PIDs. Exit 0 when it does, 1 when it doesn't or no
# window appeared, 2 when the PID isn't running.
param(
    [Parameter(Mandatory = $true)][int]$GamePid,
    [ValidateRange(1, 120)][int]$WaitSec = 15
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class AcocWindow {
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
"@
$SW_MINIMIZE = 6
$SW_RESTORE = 9

if (-not (Get-Process -Id $GamePid -ErrorAction SilentlyContinue)) {
    Write-Host "focus: PID $GamePid is not running"
    exit 2
}

function Get-OwnPids {
    $ids = @($GamePid)
    $ids += @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$GamePid" -ErrorAction SilentlyContinue |
        ForEach-Object { [int]$_.ProcessId })
    return $ids
}

$window = $null
$deadline = (Get-Date).AddSeconds($WaitSec)
while ((Get-Date) -lt $deadline) {
    $window = Get-Process -Id (Get-OwnPids) -ErrorAction SilentlyContinue |
        Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero } | Select-Object -First 1
    if ($window) { break }
    Start-Sleep -Milliseconds 250
}
if (-not $window) {
    Write-Host "focus: no window for PID $GamePid or its children after $WaitSec s"
    exit 1
}
$handle = $window.MainWindowHandle
[AcocWindow]::ShowWindow($handle, $SW_MINIMIZE) | Out-Null
Start-Sleep -Milliseconds 150
[AcocWindow]::ShowWindow($handle, $SW_RESTORE) | Out-Null
[AcocWindow]::SetForegroundWindow($handle) | Out-Null
Start-Sleep -Milliseconds 250

$front = [AcocWindow]::GetForegroundWindow()
[uint32]$frontPid = 0
[AcocWindow]::GetWindowThreadProcessId($front, [ref]$frontPid) | Out-Null
$ours = (Get-OwnPids) -contains [int]$frontPid
Write-Host ("focus: game window PID {0} '{1}'; window in front belongs to PID {2}: in front: {3}" -f
    $window.Id, $window.MainWindowTitle, $frontPid, $ours)
if ($ours) { exit 0 }
Write-Host "focus: click the game window once to give it the keyboard"
exit 1
