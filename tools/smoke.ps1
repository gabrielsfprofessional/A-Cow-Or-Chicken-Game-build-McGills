# Smoke test: import the project, run the game headless for 300 frames and fail
# if Godot prints any script or engine error. Then run every tests/*_test.gd and
# Adam's arena checks (when they exist) and fail if any exits non-zero. Then play
# a bot match (card T09): a headless server and 2 test bots on UDP 7777.
# Run from the repo folder:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools/smoke.ps1
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
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

# Bot match (card T09): a headless server (40 s) and test bots 1 and 2 (25 s)
# play on UDP 7777, the real network path. Each writes %TEMP%\acoc-smoke-<name>.log
# and .err.log. Passes when all three exit 0, no log has an error, the server
# logged at least one hit and one ability_used (T14), and nothing was refused
# ([Move], [Shot] or [Ability]).
# Anything still running after 60 s is killed by PID.
$match = [ordered]@{}
function Start-MatchProcess([string]$name, [string]$userArgs) {
    $out = Join-Path $env:TEMP "acoc-smoke-$name.log"
    $err = Join-Path $env:TEMP "acoc-smoke-$name.err.log"
    $p = Start-Process -FilePath $godot -ArgumentList "--headless --path `"$root`" -- $userArgs" `
        -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
    $null = $p.Handle  # Keeps ExitCode readable once it has exited.
    $match[$name] = @{ Process = $p; Logs = @($out, $err) }
}
function Stop-MatchLeftovers {
    foreach ($name in $match.Keys) {
        $p = $match[$name].Process
        if (-not $p.HasExited) {
            & taskkill /F /T /PID $p.Id 2>&1 | Out-Null
            $null = $p.WaitForExit(5000)
            Write-Host "SMOKE: killed leftover $name (PID $($p.Id))" -ForegroundColor Red
        }
    }
}
$started = Get-Date
$state = "timeout"
try {
    Start-MatchProcess "server" "--server --quit-after-sec=40"
    $serverLog = $match["server"].Logs[0]
    while (((Get-Date) - $started).TotalSeconds -lt 30) {
        $text = [string](Get-Content $serverLog -Raw -ErrorAction SilentlyContinue)
        if ($text -match "could not host") { $state = "in use"; break }
        if ($text -match "server up") { $state = "up"; break }
        if ($match["server"].Process.HasExited) { $state = "exited"; break }
        Start-Sleep -Milliseconds 200
    }
    if ($state -eq "up") {
        # 1 s apart, so they also leave 1 s apart. Two peers leaving in the same
        # server frame make Godot's server relay log an ERROR: it tells the
        # second about the first after ENet has already dropped it.
        Start-MatchProcess "bot1" "--join=127.0.0.1 --bot=1 --quit-after-sec=25"
        Start-Sleep -Seconds 1
        Start-MatchProcess "bot2" "--join=127.0.0.1 --bot=2 --quit-after-sec=25"
        while (((Get-Date) - $started).TotalSeconds -lt 60) {
            if (-not ($match.Values | Where-Object { -not $_.Process.HasExited })) { break }
            Start-Sleep -Milliseconds 250
        }
    }
} finally {
    Stop-MatchLeftovers
}
if ($state -eq "in use") {
    Write-Host "SMOKE: FAIL: UDP 7777 is in use: stop the other server" -ForegroundColor Red
    exit 1
}
if ($state -ne "up") {
    Get-Content $serverLog | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "SMOKE: FAIL: the bot match server did not start ($state, log: $serverLog)" -ForegroundColor Red
    exit 1
}
$seconds = ((Get-Date) - $started).TotalSeconds
$problems = @()
foreach ($name in $match.Keys) {
    $code = $match[$name].Process.ExitCode
    if ($code -ne 0) { $problems += "$name exited $code" }
}
$matchLogs = @($match.Values | ForEach-Object { $_.Logs })
$matchErrors = @(Select-String -Path $matchLogs -Pattern "SCRIPT ERROR|Parse Error|ERROR:")
$refusals = @(Select-String -Path $matchLogs -Pattern "\[Move\]|\[Shot\]|\[Ability\]")
$damage = @(Select-String -Path $serverLog -Pattern "\[Combat\] hero_damaged").Count
$abilities = @(Select-String -Path $serverLog -Pattern "\[Combat\] ability_used").Count
if ($matchErrors.Count -gt 0) { $problems += "$($matchErrors.Count) error line(s)" }
if ($refusals.Count -gt 0) { $problems += "$($refusals.Count) [Move]/[Shot]/[Ability] line(s)" }
if ($damage -eq 0) { $problems += "the server logged no [Combat] hero_damaged" }
if ($abilities -eq 0) { $problems += "the server logged no [Combat] ability_used" }
if ($problems.Count -gt 0) {
    ($matchErrors + $refusals) | ForEach-Object { Write-Host "$($_.Filename):$($_.LineNumber): $($_.Line)" -ForegroundColor Red }
    Write-Host ("SMOKE: FAIL: bot match: {0} (logs: {1}\acoc-smoke-server.log, -bot1, -bot2)" -f ($problems -join "; "), $env:TEMP) -ForegroundColor Red
    exit 1
}
Write-Host ("SMOKE: bot match passed (server and 2 bots exited 0, {0} hits, {1} abilities, {2:N0} s)" -f $damage, $abilities, $seconds)
Write-Host "SMOKE: PASS" -ForegroundColor Green
exit 0
