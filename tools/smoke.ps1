# Smoke test: import the project, run the game headless for 300 frames and fail
# if Godot prints any script or engine error. Then run every tests/*_test.gd,
# Adam's check_arena.gd and every test_*.gd in game/maps/tools and
# game/modes/tools (when they exist), and fail if any exits non-zero or runs
# longer than 60 s (it is then killed by PID). Then play
# a bot match (cards T09, T18): a headless server and 4 test bots, one per hero, on UDP 7777.
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
# engine error on purpose. Each gets $scriptLimitSec; one still running then is
# killed by PID and fails as timed out, so a hung test can't hang smoke.
$scriptLimitSec = 60
$scripts = @(Get-ChildItem -Path (Join-Path $root "tests") -Filter "*_test.gd" | Sort-Object Name |
    ForEach-Object { "res://tests/" + $_.Name })
if (Test-Path (Join-Path $root "game/maps/tools/check_arena.gd")) { $scripts += "res://game/maps/tools/check_arena.gd" }
foreach ($folder in @("game/maps/tools", "game/modes/tools")) {
    $dir = Join-Path $root $folder
    if (Test-Path $dir) {
        $scripts += @(Get-ChildItem -Path $dir -Filter "test_*.gd" | Sort-Object Name |
            ForEach-Object { "res://$folder/" + $_.Name })
    }
}
$failed = 0
foreach ($script in $scripts) {
    $name = [IO.Path]::GetFileNameWithoutExtension($script)
    $scriptLog = Join-Path $env:TEMP "acoc-smoke-$name.log"
    $scriptErr = Join-Path $env:TEMP "acoc-smoke-$name.err.log"
    $p = Start-Process -FilePath $godot -ArgumentList "--headless --path `"$root`" --script $script" `
        -RedirectStandardOutput $scriptLog -RedirectStandardError $scriptErr -NoNewWindow -PassThru
    $null = $p.Handle  # Keeps ExitCode readable once it has exited.
    if (-not $p.WaitForExit($scriptLimitSec * 1000)) {
        & taskkill /F /T /PID $p.Id 2>&1 | Out-Null
        $null = $p.WaitForExit(5000)
        foreach ($file in @($scriptLog, $scriptErr)) {
            Write-Host "--- $file, last 40 lines:" -ForegroundColor Red
            Get-Content $file -Tail 40 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        }
        Write-Host "SMOKE: $script timed out after $scriptLimitSec s (killed PID $($p.Id))" -ForegroundColor Red
        $failed++
        continue
    }
    $p.WaitForExit()  # Lets the redirected output finish writing.
    $code = $p.ExitCode
    $errors = Select-String -Path @($scriptLog, $scriptErr) -Pattern "SCRIPT ERROR|Parse Error"
    if ($code -ne 0 -or $errors) {
        Get-Content $scriptLog, $scriptErr | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Write-Host "SMOKE: $script FAILED (exit $code, logs: $scriptLog, $scriptErr)" -ForegroundColor Red
        $failed++
    } else {
        Write-Host "SMOKE: $script passed"
    }
}
if ($failed -gt 0) {
    Write-Host "SMOKE: FAIL ($failed script(s) failed)" -ForegroundColor Red
    exit 1
}

# Bot match (cards T09, T18): a headless server (45 s) and test bots 1-4 (25 s
# each, 1 s apart), one per hero, play on UDP 7777, the real network path. Each
# writes %TEMP%\acoc-smoke-<name>.log and .err.log. Passes when all five exit 0,
# no log has an error, the server logged at least one hit and an ability_used
# for each of the four abilities (T18), and nothing was refused ([Move], [Shot]
# or [Ability]). At 15 s the server starts a new match (--respawn-all-at, the
# hook for T15): it must log respawn_all for all 4 heroes once, every bot must
# apply each of those 4 respawns (same player and life), and the server must
# log a hit after it.
# Anything still running after 60 s is killed by PID.
$match = [ordered]@{}
# Bot n plays hero n; each must use its ability (the roster's file names and ability names).
$matchHeroes = @("bruiser", "mage", "scout", "medic")
$matchAbilities = @("Shield Charge", "Blink", "Jet Dash", "Heal Drone")
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
    Start-MatchProcess "server" "--server --quit-after-sec=45 --respawn-all-at=15"
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
        for ($n = 1; $n -le $matchHeroes.Count; $n++) {
            if ($n -gt 1) { Start-Sleep -Seconds 1 }
            Start-MatchProcess "bot$n" "--join=127.0.0.1 --bot=$n --hero=$($matchHeroes[$n - 1]) --quit-after-sec=25"
        }
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
foreach ($ability in $matchAbilities) {
    if (-not (Select-String -Path $serverLog -Pattern "\[Combat\] ability_used: Player \d+ used $ability," -Quiet)) {
        $problems += "the server logged no ability_used for $ability"
    }
}
# The new match: respawn_all prints each hero's hero_respawned line (and its
# protected line, if the rules protect), then its own line. So its 4 respawns are
# the last 4 hero_respawned lines among the 8 lines before it.
$newMatch = @(Select-String -Path $serverLog -Pattern "\[Combat\] respawn_all:")
$newMatchFour = @($newMatch | Where-Object { $_.Line -match "respawn_all: 4 heroes, \d+ shots cleared" })
if ($newMatch.Count -ne 1 -or $newMatchFour.Count -ne 1) {
    $problems += "$($newMatch.Count) respawn_all line(s), $($newMatchFour.Count) for 4 heroes (want 1 and 1)"
} else {
    # LineNumber counts from 1, the array from 0: the respawn_all line is $serverLines[$at - 1].
    $at = $newMatch[0].LineNumber
    $serverLines = @(Get-Content $serverLog)
    $found = @()
    if ($at -gt 1) {
        foreach ($line in $serverLines[([Math]::Max(0, $at - 9))..($at - 2)]) {
            if ($line -match "\[Combat\] hero_respawned: Player (\d+) at \([^)]*\), life (\d+)") {
                $found += , @($Matches[1], $Matches[2])
            }
        }
    }
    $respawns = @($found | Select-Object -Last 4)
    $players = @($respawns | ForEach-Object { $_[0] } | Sort-Object -Unique)
    if ($respawns.Count -ne 4 -or $players.Count -ne 4) {
        $problems += "respawn_all's 4 hero_respawned lines don't name 4 players"
    } else {
        foreach ($respawn in $respawns) {
            for ($n = 1; $n -le $matchHeroes.Count; $n++) {
                $botLog = $match["bot$n"].Logs[0]
                $pattern = "\[Combat\] hero_respawned: Player $($respawn[0]) at \([^)]*\), life $($respawn[1])(?!\d)"
                if (-not (Select-String -Path $botLog -Pattern $pattern -Quiet)) {
                    $problems += "bot$n never moved Player $($respawn[0]) to life $($respawn[1]) (respawn_all)"
                }
            }
        }
    }
    if (-not ($serverLines | Select-Object -Skip $at | Where-Object { $_ -match "\[Combat\] hero_damaged" })) {
        $problems += "the server logged no hit after respawn_all"
    }
}
if ($problems.Count -gt 0) {
    ($matchErrors + $refusals) | ForEach-Object { Write-Host "$($_.Filename):$($_.LineNumber): $($_.Line)" -ForegroundColor Red }
    Write-Host ("SMOKE: FAIL: bot match: {0} (logs: {1}\acoc-smoke-server.log, -bot1 to -bot4)" -f ($problems -join "; "), $env:TEMP) -ForegroundColor Red
    exit 1
}
Write-Host ("SMOKE: bot match passed (server and 4 bots exited 0, all four abilities used, every bot applied the new match's 4 respawns, {0} hits, {1} abilities, {2:N0} s)" -f $damage, $abilities, $seconds)

# Arena check (card T39): a server on Adam's arena (--map=arena) and bots 1-2
# (20 s, 1 s apart). Passes when all three exit 0, the server built the arena and
# spawned both heroes on its Spawn markers, each bot built the map before saying
# hello, and no log has an error or a refusal. Anything left after 45 s is killed by PID.
$match = [ordered]@{}
$started = Get-Date
$state = "timeout"
try {
    Start-MatchProcess "arena-server" "--server --map=arena --quit-after-sec=32"
    $serverLog = $match["arena-server"].Logs[0]
    while (((Get-Date) - $started).TotalSeconds -lt 30) {
        $text = [string](Get-Content $serverLog -Raw -ErrorAction SilentlyContinue)
        if ($text -match "could not host") { $state = "in use"; break }
        if ($text -match "server up") { $state = "up"; break }
        if ($match["arena-server"].Process.HasExited) { $state = "exited"; break }
        Start-Sleep -Milliseconds 200
    }
    if ($state -eq "up") {
        for ($n = 1; $n -le 2; $n++) {
            if ($n -gt 1) { Start-Sleep -Seconds 1 }
            Start-MatchProcess "arena-bot$n" "--join=127.0.0.1 --bot=$n --hero=$($matchHeroes[$n - 1]) --quit-after-sec=20"
        }
        while (((Get-Date) - $started).TotalSeconds -lt 45) {
            if (-not ($match.Values | Where-Object { -not $_.Process.HasExited })) { break }
            Start-Sleep -Milliseconds 250
        }
    }
} finally {
    Stop-MatchLeftovers
}
if ($state -ne "up") {
    Get-Content $serverLog | ForEach-Object { Write-Host $_ -ForegroundColor Red }
    Write-Host "SMOKE: FAIL: the arena check server did not start ($state, log: $serverLog)" -ForegroundColor Red
    exit 1
}
$problems = @()
foreach ($name in $match.Keys) {
    $code = $match[$name].Process.ExitCode
    if ($code -ne 0) { $problems += "$name exited $code" }
}
$matchLogs = @($match.Values | ForEach-Object { $_.Logs })
$matchErrors = @(Select-String -Path $matchLogs -Pattern "SCRIPT ERROR|Parse Error|ERROR:")
$refusals = @(Select-String -Path $matchLogs -Pattern "\[Move\]|\[Shot\]|\[Ability\]")
if ($matchErrors.Count -gt 0) { $problems += "$($matchErrors.Count) error line(s)" }
if ($refusals.Count -gt 0) { $problems += "$($refusals.Count) [Move]/[Shot]/[Ability] line(s)" }
if (-not (Select-String -Path $serverLog -Pattern "\[TestWorld\] map arena built" -Quiet)) { $problems += "the server never built the arena" }
$spawned = @(Select-String -Path $serverLog -Pattern "\[TestWorld\] hero spawned for peer")
$onMarkers = @($spawned | Where-Object { $_.Line -match " at Spawn[AB]\d+ \(" })
if ($spawned.Count -ne 2 -or $onMarkers.Count -ne 2) { $problems += "$($onMarkers.Count) of $($spawned.Count) heroes spawned on a Spawn marker (want 2 of 2)" }
foreach ($n in 1, 2) {
    $botLog = $match["arena-bot$n"].Logs[0]
    $built = Select-String -Path $botLog -Pattern "\[TestWorld\] map arena built" | Select-Object -First 1
    $hello = Select-String -Path $botLog -Pattern "saying hello" | Select-Object -First 1
    if ($null -eq $built -or $null -eq $hello -or $built.LineNumber -gt $hello.LineNumber) { $problems += "arena-bot$n did not build the map before its hello" }
}
if ($problems.Count -gt 0) {
    ($matchErrors + $refusals) | ForEach-Object { Write-Host "$($_.Filename):$($_.LineNumber): $($_.Line)" -ForegroundColor Red }
    Write-Host ("SMOKE: FAIL: arena check: {0} (logs: {1}\acoc-smoke-arena-server.log, -arena-bot1, -arena-bot2)" -f ($problems -join "; "), $env:TEMP) -ForegroundColor Red
    exit 1
}
Write-Host "SMOKE: arena check passed (server and 2 bots exited 0, both heroes on Spawn markers, map built before hello)"
Write-Host "SMOKE: PASS" -ForegroundColor Green
exit 0
