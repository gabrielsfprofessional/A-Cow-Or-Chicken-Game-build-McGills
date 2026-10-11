# Load test (card T09): test bots join a server, play, and report.
# Start the server first (tools\run_server.bat), then double-click
# tools\run_bots.bat (8 bots, this PC, 10 minutes), or run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\run_bots.ps1 [-Count 8] [-Address 127.0.0.1] [-Minutes 10]
# Each bot is a headless game: -- --join=<address> --bot=<n> --quit-after-sec=<minutes x 60>.
# Logs: %TEMP%\acoc-bots\bot<n>.log and .err.log. Every 10 s it prints how many
# bots are alive and, when the server runs on this PC, the server's CPU and
# memory. At the end: each bot's exit code and last [Bot] line, then PASS when
# every bot exited 0. Ctrl+C stops the bots too.
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
param(
    [ValidateRange(1, 16)][int]$Count = 8,
    [string]$Address = "127.0.0.1",
    [ValidateRange(0.1, 600)][double]$Minutes = 10
)
$ErrorActionPreference = "Continue"
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) {
    Write-Host "Godot not found at $godot (see docs/SETUP.md step 5)" -ForegroundColor Red
    exit 2
}
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:TEMP "acoc-bots"
New-Item -ItemType Directory -Force $logDir | Out-Null
Get-ChildItem -Path $logDir -Filter "bot*.log" | Remove-Item -Force -ErrorAction SilentlyContinue
$seconds = [int][Math]::Round($Minutes * 60)
$cores = [Environment]::ProcessorCount

# When the bots join this PC, the server is whoever owns UDP 7777 here.
$thisPc = ($Address -in @("127.0.0.1", "localhost", "::1")) -or
    (@(Get-NetIPAddress -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress }) -contains $Address)
$serverPid = 0
if ($thisPc) {
    $endpoint = Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $endpoint) {
        Write-Host "Nothing is listening on UDP 7777 on this PC. Start tools\run_server.bat first, then run this again." -ForegroundColor Red
        exit 1
    }
    $serverPid = [int]$endpoint.OwningProcess
    Write-Host "$Count bots will join $Address (this PC; server PID $serverPid) for $Minutes minute(s)."
} else {
    Write-Host "$Count bots will join $Address (another PC) for $Minutes minute(s)."
}
Write-Host "Logs: $logDir"
Write-Host "Ctrl+C stops early; the bots stop too."

function Get-ServerSample {
    if ($serverPid -eq 0) { return $null }
    $server = Get-Process -Id $serverPid -ErrorAction SilentlyContinue
    if (-not $server) { return $null }
    return [pscustomobject]@{
        Time = Get-Date
        CpuSec = $server.TotalProcessorTime.TotalSeconds
        MemoryMB = $server.WorkingSet64 / 1MB
    }
}

$bots = @()
$coreSamples = @()
$peakCore = 0.0
$peakMemoryMB = 0.0
try {
    for ($seed = 1; $seed -le $Count; $seed++) {
        $out = Join-Path $logDir "bot$seed.log"
        $err = Join-Path $logDir "bot$seed.err.log"
        $p = Start-Process -FilePath $godot `
            -ArgumentList "--headless --path `"$root`" -- --join=$Address --bot=$seed --quit-after-sec=$seconds" `
            -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
        $null = $p.Handle  # Keeps ExitCode readable once it has exited.
        $bots += [pscustomobject]@{ Seed = $seed; Process = $p; Log = $out }
        # 1 s apart, so they also leave 1 s apart. Two peers leaving in the same
        # server frame make Godot's server relay log an ERROR on the server.
        if ($seed -lt $Count) { Start-Sleep -Seconds 1 }
    }
    $start = Get-Date
    $deadline = $start.AddSeconds($seconds + 60)
    $previous = Get-ServerSample
    $nextReport = $start.AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $alive = @($bots | Where-Object { -not $_.Process.HasExited }).Count
        if ($alive -eq 0) { break }
        if ((Get-Date) -ge $nextReport) {
            $nextReport = $nextReport.AddSeconds(10)
            $elapsed = (Get-Date) - $start
            $line = "[{0:00}:{1:00}] bots alive {2}/{3}" -f [Math]::Floor($elapsed.TotalMinutes), $elapsed.Seconds, $alive, $Count
            $sample = Get-ServerSample
            if ($sample -and $previous) {
                $core = 100.0 * ($sample.CpuSec - $previous.CpuSec) / ($sample.Time - $previous.Time).TotalSeconds
                $coreSamples += $core
                $peakCore = [Math]::Max($peakCore, $core)
                $peakMemoryMB = [Math]::Max($peakMemoryMB, $sample.MemoryMB)
                $line += " | server CPU {0:N1}% of one core, {1:N1}% of this PC ({2} logical cores), memory {3:N0} MB" -f $core, ($core / $cores), $cores, $sample.MemoryMB
            } elseif ($serverPid -ne 0 -and -not $sample) {
                $line += " | the server (PID $serverPid) has stopped"
            }
            $previous = $sample
            Write-Host $line
        }
        Start-Sleep -Seconds 1
    }
} finally {
    foreach ($bot in $bots) {
        if (-not $bot.Process.HasExited) {
            & taskkill /F /T /PID $bot.Process.Id 2>&1 | Out-Null
            $null = $bot.Process.WaitForExit(5000)
            Write-Host "Stopped bot $($bot.Seed) (PID $($bot.Process.Id))" -ForegroundColor Yellow
        }
    }
}

Write-Host ""
Write-Host "Bots:"
$failed = 0
foreach ($bot in $bots) {
    $code = $bot.Process.ExitCode
    $last = Select-String -Path $bot.Log -Pattern "^\[Bot\]" | Select-Object -Last 1
    $lastLine = if ($last) { $last.Line.Trim() } else { "(no [Bot] line)" }
    Write-Host ("  bot {0}: exit {1}  {2}" -f $bot.Seed, $code, $lastLine)
    if ($code -ne 0) { $failed++ }
}
if ($coreSamples.Count -gt 0) {
    $average = ($coreSamples | Measure-Object -Average).Average
    Write-Host ("Server over the run: CPU average {0:N1}% of one core ({1:N1}% of this PC), peak {2:N1}%; memory peak {3:N0} MB" -f `
        $average, ($average / $cores), $peakCore, $peakMemoryMB)
}
if ($failed -eq 0) {
    Write-Host "PASS: all $Count bots exited 0" -ForegroundColor Green
    exit 0
}
Write-Host "FAIL: $failed of $Count bots did not exit 0 (logs: $logDir)" -ForegroundColor Red
exit 1
