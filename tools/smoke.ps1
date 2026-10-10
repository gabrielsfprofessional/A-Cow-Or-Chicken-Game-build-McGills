# Smoke test: import the project, run the game headless for 300 frames and fail
# if Godot prints any script or engine error. Then run every tests/*_test.gd and
# Adam's arena checks (when they exist) and fail if any exits non-zero.
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

# Script tests. Each one prints its own cases and exits 1 on a failure. Their own
# logs are judged by exit code and script errors only: a test may provoke an
# engine error on purpose.
$scripts = @(Get-ChildItem -Path (Join-Path $root "tests") -Filter "*_test.gd" | Sort-Object Name |
    ForEach-Object { "res://tests/" + $_.Name })
foreach ($arena in @("game/maps/tools/check_arena.gd", "game/maps/tools/test_arena_check.gd")) {
    if (Test-Path (Join-Path $root $arena)) { $scripts += "res://" + $arena }
}
$failed = 0
foreach ($script in $scripts) {
    $name = [IO.Path]::GetFileNameWithoutExtension($script)
    $scriptLog = Join-Path $env:TEMP "acoc-smoke-$name.log"
    & $godot --headless --path $root --script $script 2>&1 | Out-File -FilePath $scriptLog -Encoding utf8
    $code = $LASTEXITCODE
    $errors = Select-String -Path $scriptLog -Pattern "SCRIPT ERROR|Parse Error"
    if ($code -ne 0 -or $errors) {
        Get-Content $scriptLog | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "SMOKE: $script FAILED (exit $code, log: $scriptLog)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "SMOKE: $script passed"
    }
}
if ($failed -gt 0) {
    Write-Host "SMOKE: FAIL ($failed script(s) failed)" -ForegroundColor Red
    exit 1
}
Write-Host "SMOKE: PASS" -ForegroundColor Green
exit 0
