# Smoke test v0: import the project, run the game headless for 300 frames,
# and fail if Godot prints any script or engine error.
# Run from the repo folder:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
# Gabe extends this in card T09 to also start the server and 2 test bots.
$ErrorActionPreference = "Continue"
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    Write-Host "SMOKE: Godot not found at $godot (see docs/SETUP.md step 5)" -ForegroundColor Red
    exit 2
}
$root = Split-Path -Parent $PSScriptRoot
$log = Join-Path $env:TEMP "acoc-smoke.log"
& $godot --headless --path $root --import 2>&1 | Out-File -FilePath $log -Encoding utf8
& $godot --headless --path $root --quit-after 300 2>&1 | Out-File -FilePath $log -Encoding utf8 -Append
$hits = Select-String -Path $log -Pattern "SCRIPT ERROR|Parse Error|ERROR:"
if ($hits) {
    $hits | ForEach-Object { Write-Host $_.Line -ForegroundColor Red }
    Write-Host "SMOKE: FAIL (full log: $log)" -ForegroundColor Red
    exit 1
}
Write-Host "SMOKE: PASS" -ForegroundColor Green
exit 0
