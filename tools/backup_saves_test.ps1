# Test for tools\backup_saves.ps1 (card T21). Owner: Gabe.
# Runs the backup against throwaway folders in %TEMP% and checks what it did:
#   1. An empty saves folder is a FAIL (exit 1, "BACKUP: FAIL"), makes no dated folder and
#      removes none of the backups already there.
#   2. A saves folder with files is a PASS that copies every file.
#   3. A folder under -Destination whose name the backup didn't make is never removed.
# Removes its temp folder at the end. Prints each check and how many it ran.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\backup_saves_test.ps1
$ErrorActionPreference = "Stop"
$script = Join-Path $PSScriptRoot "backup_saves.ps1"
$work = Join-Path $env:TEMP ("acoc-backuptest-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$failed = 0
$checked = 0

function Check([bool]$ok, [string]$what) {
    $script:checked++
    if ($ok) { Write-Host "  ok: $what" } else { Write-Host "  FAIL: $what"; $script:failed++ }
}

## Runs the backup in its own PowerShell and returns its exit code and output.
function Invoke-Backup([string]$source, [string]$destination, [int]$keep) {
    $log = Join-Path $work "local-log.txt"
    # The child's stderr must come back as text, not stop this test.
    $ErrorActionPreference = "Continue"
    $out =& powershell -NoProfile -ExecutionPolicy Bypass -File $script -Destination $destination -Source $source -Keep $keep -LocalLog $log 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

## The dated backup folders (names the backup makes) under a destination.
function Get-Dated([string]$destination) {
    return @(Get-ChildItem -LiteralPath $destination -Directory | Where-Object { $_.Name -match '^saves-\d{8}-\d{6}(-\d+)?$' })
}

try {
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $dest = Join-Path $work "backups"
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    # Two older backups and one folder the backup didn't make.
    foreach ($old in @("saves-20261101-030000", "saves-20261102-030000", "keep-me")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $dest $old) | Out-Null
        Set-Content -LiteralPath (Join-Path $dest "$old\marker.txt") -Value "old"
    }

    Write-Host "case 1: an empty saves folder"
    $empty = Join-Path $work "saves-empty"
    New-Item -ItemType Directory -Force -Path $empty | Out-Null
    $r = Invoke-Backup $empty $dest 1
    Check ($r.Code -eq 1) "exit code 1 (got $($r.Code))"
    Check ($r.Output -match 'BACKUP: FAIL') "prints BACKUP: FAIL"
    Check ($r.Output -notmatch 'BACKUP: PASS') "never prints BACKUP: PASS"
    Check ((Get-Dated $dest).Count -eq 2) "no new dated folder and none removed (found $((Get-Dated $dest).Count) of 2)"
    Check (@(Get-ChildItem -LiteralPath $dest -Directory | Where-Object { $_.Name -like '*.partial' }).Count -eq 0) "no .partial folder left"

    Write-Host "case 2: a saves folder with 2 files"
    $full = Join-Path $work "saves-full"
    New-Item -ItemType Directory -Force -Path (Join-Path $full "sub") | Out-Null
    Set-Content -LiteralPath (Join-Path $full "a.json") -Value "{}"
    Set-Content -LiteralPath (Join-Path $full "sub\b.json") -Value "{}"
    $r = Invoke-Backup $full $dest 2
    Check ($r.Code -eq 0) "exit code 0 (got $($r.Code))"
    Check ($r.Output -match 'BACKUP: PASS: 2 files') "prints BACKUP: PASS: 2 files"
    $dated = Get-Dated $dest | Sort-Object Name -Descending
    Check ($dated.Count -eq 2) "keeps 2 dated folders (found $($dated.Count))"
    Check (-not (Test-Path -LiteralPath (Join-Path $dest "saves-20261101-030000"))) "the oldest backup is the one removed"
    $newest = if ($dated.Count -gt 0) { $dated[0].FullName } else { "" }
    Check ($newest -ne "" -and (Test-Path -LiteralPath (Join-Path $newest "a.json")) -and (Test-Path -LiteralPath (Join-Path $newest "sub\b.json"))) "the new backup holds both files"

    Write-Host "case 3: folders the backup didn't make"
    Check (Test-Path -LiteralPath (Join-Path $dest "keep-me\marker.txt")) "keep-me is still there"
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($checked -eq 0) { Write-Host "BACKUP TEST: FAIL: nothing was checked"; exit 1 }
if ($failed -gt 0) { Write-Host "BACKUP TEST: FAIL: $failed of $checked checks failed"; exit 1 }
Write-Host "BACKUP TEST: PASS: $checked of $checked checks"
exit 0
