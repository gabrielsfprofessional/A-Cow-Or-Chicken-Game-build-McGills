# Crash test for the server's player saves (card T21, part 1). Owner: Gabe.
# Starts tests\save_crash_writer.gd, which saves players in a loop, hard-kills its whole
# process tree at a random moment (taskkill /F /T), then runs tests\save_crash_check.gd:
# no player that loaded before may be gone or go backwards, every save on disk must load,
# and no file may need moving aside. Repeats -Kills times on one folder in %TEMP%, then
# removes that folder. Same test as tools/save_crash_test.sh.
# A pulled plug can also lose data Windows hadn't written yet; tests\profile_store_test.gd
# covers that with a cut-short file.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\save_crash_test.ps1 [-Kills 20] [-Players 8]
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
param(
    [ValidateRange(1, 500)][int]$Kills = 20,
    [ValidateRange(1, 64)][int]$Players = 8
)
$ErrorActionPreference = "Continue"
$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v4.7.2-stable_win64_console.exe" }
if (-not (Test-Path $godot)) { Write-Host "Godot not found at $godot (see docs/SETUP.md step 5)"; exit 2 }
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $env:TEMP ("acoc-savecrash-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$saves = Join-Path $work "saves"
New-Item -ItemType Directory -Force $work | Out-Null
$random = New-Object System.Random
$writerLog = Join-Path $work "writer.log"
$writerErr = Join-Path $work "writer.err.log"
$checkLog = Join-Path $work "check.log"
$checkErr = Join-Path $work "check.err.log"

# The console build starts the real game as a child, so stop the whole tree.
function Stop-Tree([System.Diagnostics.Process]$p) {
    if ($p -and -not $p.HasExited) {
        & taskkill /F /T /PID $p.Id 2>&1 | Out-Null
        $null = $p.WaitForExit(5000)
    }
}

function Start-Godot([string]$scriptPath, [string]$userArgs, [string]$out, [string]$err) {
    $p = Start-Process -FilePath $godot -NoNewWindow -PassThru `
        -ArgumentList "--headless --path `"$root`" --script $scriptPath -- $userArgs" `
        -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle  # Keeps ExitCode readable once it has exited.
    return $p
}

# The writer and the check need the class cache to know ProfileStore, as smoke does.
& $godot --headless --path $root --import 2>&1 | Out-Null
$exitCode = 0
try {
    for ($k = 1; $k -le $Kills; $k++) {
        Remove-Item $writerLog, $writerErr -ErrorAction SilentlyContinue
        $writer = Start-Godot "res://tests/save_crash_writer.gd" "`"--saves=$saves`" --players=$Players --writer-limit-sec=60" $writerLog $writerErr
        $started = Get-Date
        $writing = $false
        while (((Get-Date) - $started).TotalSeconds -lt 20) {
            if (Select-String -Path $writerLog -Pattern "\[SaveCrash\] writing" -Quiet -ErrorAction SilentlyContinue) { $writing = $true; break }
            if ($writer.HasExited) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $writing) {
            Stop-Tree $writer
            Get-Content $writerLog, $writerErr -ErrorAction SilentlyContinue | Select-Object -Last 20 | ForEach-Object { Write-Host $_ }
            Write-Host "SAVE CRASH: FAIL: the writer never started (kill $k)" -ForegroundColor Red
            $exitCode = 1
            break
        }
        Start-Sleep -Milliseconds $random.Next(100, 1501)  # 0.1 to 1.5 s into the saving loop
        Stop-Tree $writer
        $check = Start-Godot "res://tests/save_crash_check.gd" "`"--saves=$saves`" --players=$Players" $checkLog $checkErr
        if (-not $check.WaitForExit(60000)) {
            Stop-Tree $check
            Write-Host "SAVE CRASH: FAIL: the check hung (kill $k)" -ForegroundColor Red
            $exitCode = 1
            break
        }
        $check.WaitForExit()  # Lets the redirected output finish writing.
        $errors = Select-String -Path @($checkLog, $checkErr, $writerLog, $writerErr) -Pattern "SCRIPT ERROR|Parse Error" -ErrorAction SilentlyContinue
        if ($check.ExitCode -ne 0 -or $errors) {
            Get-Content $checkLog, $checkErr -ErrorAction SilentlyContinue | Select-Object -Last 30 | ForEach-Object { Write-Host $_ }
            Write-Host "SAVE CRASH: FAIL after kill $k of $Kills" -ForegroundColor Red
            $exitCode = 1
            break
        }
        $line = Select-String -Path $checkLog -Pattern "SAVE CRASH CHECK: .*" -ErrorAction SilentlyContinue | Select-Object -Last 1
        $text = if ($line) { $line.Matches[0].Value } else { "(no check line)" }
        Write-Host ("kill {0}/{1}: {2}" -f $k, $Kills, $text)
    }
    if ($exitCode -eq 0) { Write-Host "SAVE CRASH: PASS ($Kills kills, $Players players)" }
} finally {
    Remove-Item -Recurse -Force $work -ErrorAction SilentlyContinue
}
exit $exitCode
