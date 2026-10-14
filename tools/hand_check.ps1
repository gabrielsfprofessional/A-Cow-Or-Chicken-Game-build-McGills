# Hand check (T18 follow-up): a headless server and test bots on this PC, and one
# game window per round for a person to play, with every run time worked out up
# front so nothing quits mid-check. Every process is stopped by PID.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\hand_check.ps1 <step> [options]
# Steps, in order:
#   start  [-Rounds 4] [-RoundSec 100] [-GapSec 90] [-Bots 2] [-BotHeroes bruiser,medic]
#          (bot n plays the nth name in -BotHeroes, round robin)
#          Starts the server and the bots. Each runs Rounds x (RoundSec + GapSec)
#          + 120 s: GapSec is the time between rounds (opening the window, a
#          question), 120 s the margin. -GapSec 0 gives exactly Rounds x RoundSec + 120.
#   open   -Hero <bruiser|mage|scout|medic>
#          Opens the game window, joined as that hero, and brings it to the front
#          (tools\focus_game.ps1). It runs RoundSec + GapSec + 60 s at most.
#          Refused when the server has less than that left.
#   mark   The round starts now (after the player says ready).
#   finish Waits until RoundSec after the mark, closes the window by PID and
#          prints the server's [Combat] lines for the round, with counts.
#   stop   Stops everything still running, by PID, and checks UDP 7777 is free.
#   status What is running and how long the server has left.
# Don't pipe 'start' or 'open' into another command: the games inherit its output,
# so the pipe stays open until they exit.
# Logs and state: %TEMP%\acoc-hand (server.log, bot<n>.log, round<k>_<hero>.log).
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
param(
    [Parameter(Mandatory = $true, Position = 0)][ValidateSet("start", "open", "mark", "finish", "stop", "status")][string]$Step,
    [ValidateRange(1, 20)][int]$Rounds = 4,
    [ValidateRange(10, 1800)][int]$RoundSec = 100,
    [ValidateRange(0, 1800)][int]$GapSec = 90,
    [ValidateRange(0, 15)][int]$Bots = 2,
    [string]$BotHeroes = "bruiser,medic",
    [ValidateSet("bruiser", "mage", "scout", "medic")][string]$Hero = "bruiser"
)
$ErrorActionPreference = "Continue"
$MARGIN_SEC = 120
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" }
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $env:TEMP "acoc-hand"
$stateFile = Join-Path $dir "state.json"

function Read-State {
    if (-not (Test-Path $stateFile)) { return $null }
    return Get-Content $stateFile -Raw | ConvertFrom-Json
}
function Write-State($state) { $state | ConvertTo-Json -Depth 5 | Set-Content -Path $stateFile -Encoding utf8 }
function Test-Running([int]$id) { return [bool](Get-Process -Id $id -ErrorAction SilentlyContinue) }
function Stop-ByPid([string]$name, [int]$id) {
    if ($id -le 0) { return }
    if (Test-Running $id) {
        & taskkill /F /T /PID $id 2>&1 | Out-Null
        Write-Host "stopped $name (PID $id)"
    } else {
        Write-Host "$name (PID $id) had already exited"
    }
}
function Start-Godot([string]$name, [string]$godotArgs) {
    $out = Join-Path $dir "$name.log"
    $err = Join-Path $dir "$name.err.log"
    $p = Start-Process -FilePath $godot -ArgumentList $godotArgs -RedirectStandardOutput $out `
        -RedirectStandardError $err -NoNewWindow -PassThru
    Write-Host "started $name (PID $($p.Id)): $godotArgs"
    return $p
}
function Get-ServerLeftSec($state) {
    $ends = [datetime]::Parse($state.ServerEnds)
    return [int][Math]::Floor(($ends - (Get-Date)).TotalSeconds)
}
function Get-Lines([string]$path) { return @(Get-Content $path -ErrorAction SilentlyContinue) }

switch ($Step) {
    "start" {
        if (-not (Test-Path $godot)) { Write-Host "Godot not found at $godot (see docs/SETUP.md step 5)"; exit 2 }
        $old = Read-State
        if ($old -and (Test-Running $old.ServerPid)) { Write-Host "A hand check is already running (server PID $($old.ServerPid)). Run 'stop' first."; exit 1 }
        if (Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue) { Write-Host "UDP 7777 is in use: stop the other server first."; exit 1 }
        New-Item -ItemType Directory -Force $dir | Out-Null
        Get-ChildItem $dir -Filter *.log | Remove-Item -Force -ErrorAction SilentlyContinue
        $botHeroList = @($BotHeroes -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
        $bad = @($botHeroList | Where-Object { $_ -notin @("bruiser", "mage", "scout", "medic") })
        if ($bad.Count -gt 0 -or $botHeroList.Count -eq 0) { Write-Host "-BotHeroes takes a comma list of bruiser, mage, scout, medic (got: $BotHeroes)"; exit 1 }
        $runSec = $Rounds * ($RoundSec + $GapSec) + $MARGIN_SEC
        Write-Host "Run time: $Rounds rounds x ($RoundSec s + $GapSec s gap) + $MARGIN_SEC s margin = $runSec s for the server and each bot"
        $server = Start-Godot "server" "--headless --path `"$root`" -- --server --quit-after-sec=$runSec"
        $started = Get-Date
        $up = $false
        while (((Get-Date) - $started).TotalSeconds -lt 30) {
            if (Select-String -Path (Join-Path $dir "server.log") -Pattern "server up" -Quiet) { $up = $true; break }
            if ($server.HasExited) { break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $up) {
            Stop-ByPid "server" $server.Id
            Write-Host "The server did not start; see $dir\server.log"
            exit 1
        }
        $botPids = @()
        for ($n = 1; $n -le $Bots; $n++) {
            # 1 s apart, so they also leave 1 s apart (see tools/smoke.ps1).
            if ($n -gt 1) { Start-Sleep -Seconds 1 }
            $botHero = $botHeroList[($n - 1) % $botHeroList.Count]
            $bot = Start-Godot "bot$n" "--headless --path `"$root`" -- --join=127.0.0.1 --bot=$n --hero=$botHero --quit-after-sec=$runSec"
            $botPids += $bot.Id
        }
        Write-State ([ordered]@{
            ServerPid = $server.Id; BotPids = $botPids; RoundSec = $RoundSec; GapSec = $GapSec
            ServerEnds = $started.AddSeconds($runSec).ToString("o"); Round = 0
            WindowPid = 0; WindowLog = ""; Hero = ""; MarkLine = 0; MarkTime = ""
        })
        Write-Host "Server and $Bots bot(s) up for $runSec s (until $($started.AddSeconds($runSec).ToString('HH:mm:ss')))."
        exit 0
    }
    "open" {
        $state = Read-State
        if (-not $state -or -not (Test-Running $state.ServerPid)) { Write-Host "No hand-check server is running. Run 'start' first."; exit 1 }
        if ($state.WindowPid -gt 0 -and (Test-Running $state.WindowPid)) { Write-Host "A game window is already open (PID $($state.WindowPid)). Run 'finish' first."; exit 1 }
        $windowSec = $state.RoundSec + $state.GapSec + 60
        $left = Get-ServerLeftSec $state
        if ($left -lt $windowSec) { Write-Host "The server has $left s left, less than this round's $windowSec s. Run 'stop', then 'start' again."; exit 1 }
        $state.Round = $state.Round + 1
        $name = "round$($state.Round)_$Hero"
        $window = Start-Godot $name "--path `"$root`" -- --join=127.0.0.1 --hero=$Hero --quit-after-sec=$windowSec"
        $state.WindowPid = $window.Id
        $state.WindowLog = Join-Path $dir "$name.log"
        $state.Hero = $Hero
        $state.MarkLine = 0
        $state.MarkTime = ""
        Write-State $state
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "focus_game.ps1") -GamePid $window.Id
        $focused = $LASTEXITCODE
        $joined = $false
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline) {
            if (Select-String -Path $state.WindowLog -Pattern "saying hello as peer" -Quiet) { $joined = $true; break }
            Start-Sleep -Milliseconds 250
        }
        $hello = Select-String -Path $state.WindowLog -Pattern "saying hello as peer (\d+)" | Select-Object -First 1
        Write-Host ("Round {0} window: {1}, PID {2}, closes itself after {3} s; joined: {4} ({5}); focus exit {6}" -f
            $state.Round, $Hero, $window.Id, $windowSec, $joined, $(if ($hello) { $hello.Line } else { "no hello yet" }), $focused)
        exit $(if ($joined) { 0 } else { 1 })
    }
    "mark" {
        $state = Read-State
        if (-not $state -or $state.WindowPid -le 0 -or -not (Test-Running $state.WindowPid)) { Write-Host "No game window is open. Run 'open' first."; exit 1 }
        $state.MarkLine = (Get-Lines (Join-Path $dir "server.log")).Count
        $state.MarkTime = (Get-Date).ToString("o")
        Write-State $state
        Write-Host ("Round {0} ({1}) started at {2}; it ends at {3}" -f $state.Round, $state.Hero,
            (Get-Date).ToString("HH:mm:ss"), (Get-Date).AddSeconds($state.RoundSec).ToString("HH:mm:ss"))
        exit 0
    }
    "finish" {
        $state = Read-State
        if (-not $state -or $state.MarkTime -eq "") { Write-Host "No round is marked. Run 'mark' first."; exit 1 }
        $ends = [datetime]::Parse($state.MarkTime).AddSeconds($state.RoundSec)
        $waitSec = ($ends - (Get-Date)).TotalSeconds
        if ($waitSec -gt 0) { Start-Sleep -Milliseconds ([int]($waitSec * 1000)) }
        Stop-ByPid "round $($state.Round) window" $state.WindowPid
        $hello = Select-String -Path $state.WindowLog -Pattern "saying hello as peer (\d+)" | Select-Object -First 1
        $me = if ($hello) { $hello.Matches[0].Groups[1].Value } else { "?" }
        $lines = Get-Lines (Join-Path $dir "server.log")
        $round = @(if ($lines.Count -gt $state.MarkLine) { $lines[$state.MarkLine..($lines.Count - 1)] })
        $combat = @($round | Where-Object { $_ -match "^\[(Combat|Ability|Move|Shot)\]" -and $_ -match "Player $me\b|peer $me\b" })
        Write-Host "=== Round $($state.Round), $($state.Hero), Player $me, $($state.RoundSec) s: server lines $($state.MarkLine + 1)-$($lines.Count)"
        $combat | ForEach-Object { Write-Host $_ }
        $used = @($round | Where-Object { $_ -match "ability_used: Player $me used" }).Count
        $knocked = @($round | Where-Object { $_ -match "knocked_back: Player (\d+) by Player $me$" -and $Matches[1] -ne $me }).Count
        $healedOthers = @($round | Where-Object { $_ -match "hero_healed: Player (\d+) by Player $me for" -and $Matches[1] -ne $me }).Count
        $healedSelf = @($round | Where-Object { $_ -match "hero_healed: Player $me by Player $me for" }).Count
        $refused = @($round | Where-Object { $_ -match "^\[(Ability|Move|Shot)\]" }).Count
        Write-Host ("counts: ability_used {0}, knocked_back by me {1}, hero_healed others {2}, self {3}, [Ability]/[Move]/[Shot] {4}" -f
            $used, $knocked, $healedOthers, $healedSelf, $refused)
        $state.WindowPid = 0
        $state.MarkTime = ""
        Write-State $state
        Write-Host ("Server has {0} s left." -f (Get-ServerLeftSec $state))
        exit 0
    }
    "stop" {
        $state = Read-State
        if ($state) {
            Stop-ByPid "game window" $state.WindowPid
            for ($i = 0; $i -lt @($state.BotPids).Count; $i++) { Stop-ByPid "bot$($i + 1)" @($state.BotPids)[$i] }
            Stop-ByPid "server" $state.ServerPid
            Remove-Item $stateFile -Force
        } else {
            Write-Host "No hand check state; nothing of ours to stop."
        }
        Start-Sleep -Milliseconds 500
        $busy = Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue
        Write-Host ("UDP 7777: {0}" -f $(if ($busy) { "BUSY (PID $($busy[0].OwningProcess))" } else { "free" }))
        exit $(if ($busy) { 1 } else { 0 })
    }
    "status" {
        $state = Read-State
        if (-not $state) { Write-Host "No hand check is running."; exit 0 }
        Write-Host ("server PID {0} running {1}, {2} s left; bots {3}; window PID {4} running {5}; round {6} {7}" -f
            $state.ServerPid, (Test-Running $state.ServerPid), (Get-ServerLeftSec $state),
            ((@($state.BotPids) | ForEach-Object { "$_ $(Test-Running $_)" }) -join ", "),
            $state.WindowPid, ($state.WindowPid -gt 0 -and (Test-Running $state.WindowPid)), $state.Round, $state.Hero)
        exit 0
    }
}
