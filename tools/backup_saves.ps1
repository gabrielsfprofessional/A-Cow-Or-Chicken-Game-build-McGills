# Backup of the server's player saves (card T21, part 1). Owner: Gabe.
# Copies the saves folder into <name>.partial under -Destination, checks the copy (same
# files, same sizes), then renames it to saves-YYYYMMDD-HHMMSS, so a half-made copy never
# looks like a backup. Then removes the oldest dated folders beyond -Keep. It only ever
# removes folders under -Destination with names it makes. One line per run goes to
# backup-log.txt there and to -LocalLog (default %LOCALAPPDATA%\acoc-backup-log.txt, which
# works even when the Drive is missing).
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_saves.ps1 -Destination "G:\My Drive\A Cow or Chicken\Backups" [-Keep 7] [-Source <folder>] [-LocalLog <file>]
# Default -Source: the release server's saves, %APPDATA%\Godot\app_userdata\A Cow or Chicken\saves
# The 3 am schedule and the restore steps are in server/README.md.
param(
    [Parameter(Mandatory = $true)][string]$Destination,
    [ValidateRange(1, 60)][int]$Keep = 7,
    [string]$Source = "",
    [string]$LocalLog = ""
)
$ErrorActionPreference = "Stop"
$pattern = '^saves-\d{8}-\d{6}(-\d+)?$'
$partial = $null

function Get-FileList([string]$folder) {
    $base = (Resolve-Path -LiteralPath $folder).ProviderPath.TrimEnd('\', '/')
    return @(Get-ChildItem -LiteralPath $base -File -Recurse -Force |
        ForEach-Object { "{0}|{1}" -f $_.FullName.Substring($base.Length), $_.Length } | Sort-Object)
}

function Write-Log([string]$line) {
    $stamped = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $line
    $logFile = if ($LocalLog) { $LocalLog } else { Join-Path $env:LOCALAPPDATA "acoc-backup-log.txt" }
    foreach ($log in @($logFile, (Join-Path $Destination "backup-log.txt"))) {
        try { Add-Content -LiteralPath $log -Value $stamped } catch { }
    }
}

try {
    if (-not $Source) { $Source = Join-Path $env:APPDATA "Godot\app_userdata\A Cow or Chicken\saves" }
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        $test = Join-Path (Split-Path -Parent $Source) "saves_test"
        if (Test-Path -LiteralPath $test -PathType Container) {
            throw "no saves folder at $Source, but $test exists: is the server a debug build without -- --saves=user://saves/ ?"
        }
        throw "no saves folder at $Source"
    }
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    # A copy a crash left half-made earlier: it was never a backup.
    Get-ChildItem -LiteralPath $Destination -Directory |
        Where-Object { $_.Name -match '^saves-\d{8}-\d{6}(-\d+)?\.partial$' } |
        ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $name = "saves-$stamp"
    $n = 2
    while ((Test-Path -LiteralPath (Join-Path $Destination $name)) -or (Test-Path -LiteralPath (Join-Path $Destination "$name.partial"))) {
        $name = "saves-$stamp-$n"
        $n++
    }
    $partial = Join-Path $Destination "$name.partial"
    Copy-Item -LiteralPath $Source -Destination $partial -Recurse
    $sourceList = Get-FileList $Source
    $copyList = Get-FileList $partial
    if (($sourceList -join "`n") -ne ($copyList -join "`n")) {
        throw "the copy doesn't match the saves folder (a save may have changed while copying; the next run tries again)"
    }
    Rename-Item -LiteralPath $partial -NewName $name
    $partial = $null
    $ours = @(Get-ChildItem -LiteralPath $Destination -Directory |
        Where-Object { $_.Name -match $pattern } | Sort-Object Name -Descending)
    $old = @($ours | Select-Object -Skip $Keep)
    foreach ($folder in $old) { Remove-Item -LiteralPath $folder.FullName -Recurse -Force }
    $summary = "{0} files to {1}; {2} backups kept, {3} removed" -f $sourceList.Count, $name, ($ours.Count - $old.Count), $old.Count
    Write-Log "PASS $summary"
    Write-Host "BACKUP: PASS: $summary"
    exit 0
} catch {
    $message = $_.Exception.Message
    if ($partial -and (Test-Path -LiteralPath $partial)) {
        Remove-Item -LiteralPath $partial -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Log "FAIL $message"
    Write-Host "BACKUP: FAIL: $message"
    exit 1
}
