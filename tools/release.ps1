# Release (card T29): turn main into the Windows game and the Windows dedicated
# server, prove both work, and zip the game for the Drive. docs/RELEASE.md has the
# whole routine (the version-bump PR comes first). Run from the main folder:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1 -Out C:\Dev\acoc-releases
# Steps (each one stops the release on a failure):
#   0. Checks: Godot 4.7.2 console build and its export templates, -Out outside the
#      repo, a clean folder on main at origin/main, server.cfg with an address, UDP 7777 free.
#   1. tools\smoke.ps1.
#   2. Exports both presets with --export-release (never debug).
#   3. The game says it has server.cfg inside, and never prints the address.
#   4. The exported game joins the exported server and ignores --version-override.
#   5. Bot test: tools\run_bots.ps1 (8 bots, 10 min, console editor build at this
#      commit, since --bot is debug-only) against the exported server, which is then
#      stopped by PID (a release build ignores --quit-after-sec).
#   6. LICENSES.txt (tools\write_licenses.gd) next to the game.
#   7. Zip (the game + LICENSES.txt) with its SHA-256, then the Drive steps.
# -TestBranch: for testing this script before it merges. HEAD only has to contain
# origin/main; the zip is named TEST-... and no Drive steps are printed.
# Every process it starts is stopped by PID at the end; UDP 7777 is free after.
# Godot path: $env:GODOT if set, else C:\Godot\Godot_v4.7.2-stable_win64_console.exe
param(
    [string]$Out = "C:\Dev\acoc-release-test",
    [switch]$TestBranch,
    [ValidateRange(1, 16)][int]$Bots = 8,
    [ValidateRange(0.1, 60)][double]$BotMinutes = 10
)
$ErrorActionPreference = "Continue"

$GodotVersion = "4.7.2"
$TemplateDir = Join-Path $env:APPDATA "Godot\export_templates\$GodotVersion.stable"
$ClientPreset = "Windows client"
$ServerPreset = "Windows server"
$ClientExe = "ACowOrChicken.exe"
$ServerExe = "ACowOrChickenServer.exe"
$ServerMap = "arena"
$ServerUpSec = 30
$ConfigLineSec = 30
$JoinSec = 30
$OverrideVersion = "0.0.0-ignored"

$godot = $env:GODOT
if (-not $godot) { $godot = "C:\Godot\Godot_v$($GodotVersion)-stable_win64_console.exe" }
$root = Split-Path -Parent $PSScriptRoot
$script:started = @()
$script:configAddress = ""

function Write-Step([string]$text) { Write-Host "RELEASE: $text" }

function Stop-Release([string]$reason) {
    Write-Host "RELEASE: FAIL: $reason" -ForegroundColor Red
    throw "release failed"
}

# Starts a process with its output in <logDir>\<name>.log and .err.log, and keeps its PID.
function Start-Logged([string]$name, [string]$exe, [string]$arguments, [string]$logDir) {
    $out = Join-Path $logDir "$name.log"
    $err = Join-Path $logDir "$name.err.log"
    $p = Start-Process -FilePath $exe -ArgumentList $arguments -RedirectStandardOutput $out `
        -RedirectStandardError $err -NoNewWindow -PassThru
    $null = $p.Handle  # Keeps ExitCode readable once it has exited.
    $entry = [pscustomobject]@{ Name = $name; Process = $p; Log = $out; ErrLog = $err }
    $script:started += $entry
    Write-Step "started $name (PID $($p.Id))"
    return $entry
}

function Stop-Logged($entry) {
    if ($null -eq $entry) { return }
    if (-not $entry.Process.HasExited) {
        & taskkill /F /T /PID $entry.Process.Id 2>&1 | Out-Null
        $null = $entry.Process.WaitForExit(5000)
        Write-Step "stopped $($entry.Name) (PID $($entry.Process.Id))"
    }
}

function Stop-AllStarted {
    foreach ($entry in $script:started) { Stop-Logged $entry }
}

# Waits until the log has a line matching $pattern. True when found.
function Wait-ForLine($entry, [string]$pattern, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Select-String -Path $entry.Log -Pattern $pattern -Quiet -ErrorAction SilentlyContinue) { return $true }
        if ($entry.Process.HasExited) { break }
        Start-Sleep -Milliseconds 250
    }
    return [bool](Select-String -Path $entry.Log -Pattern $pattern -Quiet -ErrorAction SilentlyContinue)
}

function Test-PortFree {
    return -not (Get-NetUDPEndpoint -LocalPort 7777 -ErrorAction SilentlyContinue)
}

# The [server] address from server.cfg, kept in memory only (never printed).
function Read-ConfigAddress([string]$path) {
    $section = ""
    foreach ($line in Get-Content $path) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') { $section = $matches[1]; continue }
        if ($section -eq "server" -and $trimmed -match '^address\s*=\s*"?([^"]*)"?\s*$') { return $matches[1].Trim() }
    }
    return ""
}

function Get-ProjectVersion([string]$project) {
    $line = Select-String -Path (Join-Path $project "project.godot") -Pattern '^config/version="(.+)"' | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Matches[0].Groups[1].Value
}

function Get-NetProtocol([string]$project) {
    $line = Select-String -Path (Join-Path $project "game\core\net.gd") -Pattern '^const NET_PROTOCOL: int = (\d+)' | Select-Object -First 1
    if (-not $line) { return "" }
    return $line.Matches[0].Groups[1].Value
}

# Step 0. Returns the release folder name parts.
function Test-Preconditions {
    if (-not (Test-Path $godot)) { Stop-Release "Godot not found at $godot (docs/SETUP.md step 5)" }
    foreach ($template in @("windows_release_x86_64.exe", "windows_release_x86_64_console.exe")) {
        if (-not (Test-Path (Join-Path $TemplateDir $template))) {
            Stop-Release ("the official $GodotVersion export templates are not installed ($template missing in $TemplateDir). " +
                "Install them: Godot editor > Editor > Manage Export Templates > Download and Install (docs/RELEASE.md).")
        }
    }
    $outFull = [IO.Path]::GetFullPath($Out).TrimEnd('\')
    $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\')
    if ($outFull -eq $rootFull -or $outFull.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Release "-Out $Out is inside the repo. Export outside it (for example C:\Dev\acoc-releases)."
    }
    $dirty = & git -C $root status --porcelain
    if ($dirty) { Stop-Release "the folder has changes. Commit or remove them first:`n$($dirty -join "`n")" }
    & git -C $root fetch --quiet origin
    if ($LASTEXITCODE -ne 0) { Stop-Release "git fetch failed" }
    $head = (& git -C $root rev-parse HEAD).Trim()
    $main = (& git -C $root rev-parse origin/main).Trim()
    if ($TestBranch) {
        & git -C $root merge-base --is-ancestor $main $head
        if ($LASTEXITCODE -ne 0) { Stop-Release "-TestBranch: HEAD doesn't contain origin/main. Merge main first." }
        Write-Host "RELEASE: TEST RUN (-TestBranch): HEAD $($head.Substring(0, 7)) is not main; the zip is named TEST and goes nowhere." -ForegroundColor Yellow
    } else {
        $branch = (& git -C $root branch --show-current).Trim()
        if ($branch -ne "main") { Stop-Release "on branch '$branch'. Release from main: git switch main" }
        if ($head -ne $main) { Stop-Release "main is not origin/main (HEAD $($head.Substring(0, 7)), origin/main $($main.Substring(0, 7))). Run: git pull --ff-only" }
    }
    $config = Join-Path $root "server.cfg"
    if (-not (Test-Path $config)) { Stop-Release "no server.cfg in $root. Create it (docs/RELEASE.md); git ignores it." }
    $script:configAddress = Read-ConfigAddress $config
    if ($script:configAddress -eq "") { Stop-Release "server.cfg has no address under [server] (docs/RELEASE.md)." }
    if (-not (Test-PortFree)) { Stop-Release "UDP 7777 is in use: stop the other server first." }
    $version = Get-ProjectVersion $root
    if ($version -eq "") { Stop-Release "project.godot has no config/version" }
    $net = Get-NetProtocol $root
    Write-Step "version $version+net$net, commit $($head.Substring(0, 7)), server.cfg has an address"
    return [pscustomobject]@{ Version = $version; Net = $net; Sha = $head.Substring(0, 7) }
}

# Step 1.
function Invoke-Smoke {
    Write-Step "step 1: smoke test"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "smoke.ps1") | Out-Host
    if ($LASTEXITCODE -ne 0) { Stop-Release "the smoke test failed" }
}

# Step 2.
function Export-Builds([string]$releaseDir, [string]$logDir) {
    Write-Step "step 2: export (release)"
    $clientDir = Join-Path $releaseDir "client"
    $serverDir = Join-Path $releaseDir "server"
    New-Item -ItemType Directory -Force $clientDir, $serverDir | Out-Null
    & $godot --headless --path $root --import 2>&1 | Out-File (Join-Path $logDir "import.log") -Encoding utf8
    foreach ($job in @(
            @{ Preset = $ClientPreset; Path = (Join-Path $clientDir $ClientExe); Log = "export-client.log" },
            @{ Preset = $ServerPreset; Path = (Join-Path $serverDir $ServerExe); Log = "export-server.log" })) {
        $log = Join-Path $logDir $job.Log
        & $godot --headless --path $root --export-release $job.Preset $job.Path 2>&1 | Out-File $log -Encoding utf8
        $code = $LASTEXITCODE
        $console = $job.Path -replace '\.exe$', '.console.exe'
        if ($code -ne 0 -or -not (Test-Path $job.Path) -or -not (Test-Path $console)) {
            Get-Content $log -Tail 30 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Stop-Release "export of '$($job.Preset)' failed (exit $code, log $log)"
        }
        if (Select-String -Path $log -Pattern "SCRIPT ERROR|Parse Error|ERROR:" -Quiet) {
            Stop-Release "export of '$($job.Preset)' printed an error (log $log)"
        }
        $loose = @(Get-ChildItem -Path (Split-Path $job.Path) -Filter "*.pck")
        if ($loose.Count -gt 0) { Stop-Release "'$($job.Preset)' left a separate .pck: the data must be inside the .exe" }
        Write-Step ("exported {0} ({1:N1} MB)" -f $job.Path, ((Get-Item $job.Path).Length / 1MB))
    }
    return [pscustomobject]@{
        Client = Join-Path $clientDir ($ClientExe -replace '\.exe$', '.console.exe')
        Server = Join-Path $serverDir ($ServerExe -replace '\.exe$', '.console.exe')
        ClientDir = $clientDir
    }
}

# Step 3. The game started with no --join stays on the main menu: it only has to
# say it found server.cfg. The address must be in no line it prints.
function Test-ConfigProof([string]$clientExe, [string]$clientArgs, [string]$logDir) {
    Write-Step "step 3: server.cfg is inside the game"
    $entry = Start-Logged "client-config" $clientExe $clientArgs $logDir
    try {
        if (-not (Wait-ForLine $entry "\[Net\] server\.cfg: found, Play joins its address" $ConfigLineSec)) {
            Get-Content $entry.Log -Tail 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Stop-Release "the exported game didn't say 'server.cfg: found' within $ConfigLineSec s (log $($entry.Log))"
        }
    } finally {
        Stop-Logged $entry
    }
    foreach ($file in @($entry.Log, $entry.ErrLog)) {
        if (Select-String -Path $file -SimpleMatch $script:configAddress -Quiet -ErrorAction SilentlyContinue) {
            Stop-Release "the game printed the server address ($file). Remove that line before releasing."
        }
    }
    Write-Step "server.cfg found inside the game; the address is in none of its output"
}

function Start-Server([string]$exe, [string]$arguments, [string]$name, [string]$logDir) {
    $entry = Start-Logged $name $exe $arguments $logDir
    if (-not (Wait-ForLine $entry "server up" $ServerUpSec)) {
        Get-Content $entry.Log -Tail 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        Stop-Logged $entry
        Stop-Release "$name did not print 'server up' within $ServerUpSec s (log $($entry.Log))"
    }
    return $entry
}

# Step 4. A release build must ignore --version-override, so it still joins and the
# server sees its real version.
function Test-JoinProof([string]$serverExe, [string]$serverArgs, [string]$clientExe, [string]$clientArgs, [string]$expectedVersion, [string]$logDir) {
    Write-Step "step 4: the exported game joins the exported server and ignores --version-override"
    $server = Start-Server $serverExe $serverArgs "server-join" $logDir
    $client = $null
    try {
        $client = Start-Logged "client-join" $clientExe "$clientArgs --version-override=$OverrideVersion" $logDir
        $null = Wait-ForLine $client "\[Net\] connected as peer|\[Net\] join failed" $JoinSec
        if (-not (Select-String -Path $client.Log -Pattern "\[Net\] connected as peer" -Quiet -ErrorAction SilentlyContinue)) {
            Get-Content $client.Log -Tail 20 | ForEach-Object { Write-Host $_ -ForegroundColor Red }
            Stop-Release "the exported game didn't join (log $($client.Log))"
        }
        if (-not (Wait-ForLine $server ([regex]::Escape("version $expectedVersion (")) 10)) {
            Stop-Release "the server's join line doesn't show version $expectedVersion (log $($server.Log))"
        }
        if (Select-String -Path $server.Log -SimpleMatch $OverrideVersion -Quiet) {
            Stop-Release "the server saw --version-override: the release build honored a debug flag"
        }
    } finally {
        Stop-Logged $client
        Stop-Logged $server
    }
    Write-Step "joined as $expectedVersion; --version-override ignored"
}

# Step 5. Bots from the console editor build (this commit) against a server, then
# the server is stopped by PID. Pass: every bot exits 0, one join line per bot, at
# least one hit, and no error or refusal line in the server's log.
function Invoke-BotTest([string]$serverExe, [string]$serverArgs, [string]$logDir) {
    Write-Step "step 5: bot test, $Bots bots for $BotMinutes min"
    $server = Start-Server $serverExe $serverArgs "server-bots" $logDir
    $botsLog = Join-Path $logDir "run_bots.log"
    try {
        $env:GODOT = $godot
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_bots.ps1") `
            -Count $Bots -Address 127.0.0.1 -Minutes $BotMinutes *>&1 | Tee-Object -FilePath $botsLog | Out-Host
        $botsCode = $LASTEXITCODE
    } finally {
        Stop-Logged $server
    }
    $botLogDir = Join-Path $env:TEMP "acoc-bots"
    Copy-Item -Path (Join-Path $botLogDir "bot*.log") -Destination $logDir -ErrorAction SilentlyContinue
    $problems = @()
    if ($botsCode -ne 0) { $problems += "run_bots.ps1 exit $botsCode" }
    $joins = @(Select-String -Path $server.Log -Pattern "\[Net\] join: peer").Count
    if ($joins -ne $Bots) { $problems += "$joins join line(s) for $Bots bots" }
    $hits = @(Select-String -Path $server.Log -Pattern "\[Combat\] hero_damaged").Count
    if ($hits -eq 0) { $problems += "no [Combat] hero_damaged" }
    $errors = @(Select-String -Path @($server.Log, $server.ErrLog) -Pattern "SCRIPT ERROR|Parse Error|ERROR:")
    if ($errors.Count -gt 0) { $problems += "$($errors.Count) error line(s) in the server log" }
    $refusals = @(Select-String -Path $server.Log -Pattern "\[Move\]|\[Shot\]|\[Ability\]")
    if ($refusals.Count -gt 0) { $problems += "$($refusals.Count) [Move]/[Shot]/[Ability] line(s)" }
    $stats = Select-String -Path $server.Log -Pattern "^\[Stats\]" | Select-Object -Last 1
    if ($problems.Count -gt 0) { Stop-Release ("bot test: {0} (logs {1})" -f ($problems -join "; "), $logDir) }
    $statsText = if ($stats) { $stats.Line.Trim() } else { "(no [Stats] line)" }
    Write-Step "bot test passed: $Bots bots exited 0, $joins joins, $hits hits, no errors or refusals. Last: $statsText"
}

# Step 6.
function Write-Licenses([string]$clientDir, [string]$logDir) {
    Write-Step "step 6: LICENSES.txt"
    $path = Join-Path $clientDir "LICENSES.txt"
    & $godot --headless --path $root --script res://tools/write_licenses.gd -- "--out=$path" 2>&1 |
        Out-File (Join-Path $logDir "licenses.log") -Encoding utf8
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $path) -or -not (Select-String -Path $path -Pattern "Godot Engine" -Quiet)) {
        Stop-Release "write_licenses.gd failed (log $(Join-Path $logDir 'licenses.log'))"
    }
    return $path
}

# Step 7. Returns the zip path.
function New-ReleaseZip([string[]]$files, [string]$zipPath) {
    Write-Step "step 7: zip"
    if (Test-Path $zipPath) { Stop-Release "$zipPath already exists" }
    Compress-Archive -Path $files -DestinationPath $zipPath
    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash
    "$hash  $(Split-Path $zipPath -Leaf)" | Out-File "$zipPath.sha256.txt" -Encoding ascii
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        Write-Step "zip contents:"
        foreach ($item in $zip.Entries) { Write-Host ("    {0}  {1:N0} bytes" -f $item.FullName, $item.Length) }
    } finally {
        $zip.Dispose()
    }
    Write-Step ("{0} ({1:N1} MB)" -f $zipPath, ((Get-Item $zipPath).Length / 1MB))
    Write-Step "SHA-256 $hash"
    return $zipPath
}

function Write-DriveSteps([string]$zipPath) {
    $name = Split-Path $zipPath -Leaf
    Write-Host ""
    Write-Host "DRIVE STEPS (by hand, in the family Drive folder 'A Cow or Chicken'):"
    Write-Host "  1. Open the folder Previous and delete what is in it."
    Write-Host "  2. Move the zip that is in Latest into Previous."
    Write-Host "  3. Upload $name and $name.sha256.txt into Latest."
    Write-Host "  4. Post in #dev: the version, and 'download it from Latest'."
}

function Invoke-Release {
    $info = $null
    try {
        $info = Test-Preconditions
        $stamp = Get-Date -Format "yyyyMMdd-HHmm"
        $releaseDir = Join-Path $Out "$($info.Version)-$($info.Sha)-$stamp"
        $logDir = Join-Path $releaseDir "logs"
        New-Item -ItemType Directory -Force $logDir | Out-Null
        Write-Step "output: $releaseDir"
        Invoke-Smoke
        $builds = Export-Builds $releaseDir $logDir
        $expected = "$($info.Version)+net$($info.Net)"
        Test-ConfigProof $builds.Client "--headless" $logDir
        Test-JoinProof $builds.Server "--headless -- --server --map=$ServerMap" $builds.Client "--headless -- --join=127.0.0.1" $expected $logDir
        Invoke-BotTest $builds.Server "--headless -- --server --map=$ServerMap" $logDir
        $licenses = Write-Licenses $builds.ClientDir $logDir
        $prefix = if ($TestBranch) { "TEST-" } else { "" }
        $zipPath = Join-Path $releaseDir "$($prefix)acoc-$($info.Version)-$($info.Sha)-windows.zip"
        $zip = New-ReleaseZip @((Join-Path $builds.ClientDir $ClientExe), $licenses) $zipPath
        if ($TestBranch) {
            Write-Host "RELEASE: TEST RUN PASSED. Not for the Drive (built from a branch)." -ForegroundColor Yellow
        } else {
            Write-DriveSteps $zip
            Write-Host "RELEASE: PASS" -ForegroundColor Green
        }
        return 0
    } catch {
        if ("$_" -ne "release failed") { Write-Host "RELEASE: FAIL: $_" -ForegroundColor Red }
        return 1
    } finally {
        Stop-AllStarted
        if (-not (Test-PortFree)) { Write-Host "RELEASE: warning: UDP 7777 is still in use" -ForegroundColor Yellow }
    }
}

# Dot-sourcing (. .\tools\release.ps1) loads the functions without running a release.
if ($MyInvocation.InvocationName -ne '.') { exit (Invoke-Release) }
