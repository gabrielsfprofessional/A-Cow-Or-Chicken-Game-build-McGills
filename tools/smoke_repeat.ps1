# Runs the smoke test several times in a row (T18 follow-up), for a change that
# touches timing or the network, where one pass can be luck. Run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\smoke_repeat.ps1 [-Times 3]
# Each run's full output goes to %TEMP%\acoc-smoke-run<n>.log. Prints one line per
# run with its exit code and last SMOKE line, then "<passed>/<Times> passed".
# Exit 0 only when every run exited 0; 1 otherwise. All runs go, even after a
# failure, so the count is the true count.
param([ValidateRange(1, 20)][int]$Times = 3)
$smoke = Join-Path $PSScriptRoot "smoke.ps1"
$passed = 0
for ($n = 1; $n -le $Times; $n++) {
    $log = Join-Path $env:TEMP "acoc-smoke-run$n.log"
    & powershell -NoProfile -ExecutionPolicy Bypass -File $smoke *>&1 | ForEach-Object { "$_" } | Out-File -FilePath $log -Encoding utf8
    $code = $LASTEXITCODE
    $last = Select-String -Path $log -Pattern "^SMOKE: " | Select-Object -Last 1
    $lastText = if ($last) { $last.Line } else { "(no SMOKE line)" }
    if ($code -eq 0) { $passed++ }
    Write-Host ("run {0}/{1}: exit {2}: {3}" -f $n, $Times, $code, $lastText)
}
Write-Host ("SMOKE REPEAT: {0}/{1} passed" -f $passed, $Times)
if ($passed -eq $Times) { exit 0 }
exit 1
