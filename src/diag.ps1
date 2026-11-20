# Diagnostic (run 4): what a fresh powershell sees of the token store. Prints URLs only, never a key:
# every output is scrubbed of htf-... and the token file is read for its URLs and field NAMES only.
param([string]$Label = "diag")
$PubUrl = ((Select-String -Path (Join-Path $PSScriptRoot pubspec.yaml) -Pattern '^    hosted: (.*)$').Matches[0].Groups[1].Value).Trim()
function Scrub([string]$s) { $s -replace 'htf-[A-Za-z0-9-]+', 'htf-***' }
function P([string]$s) { Write-Host (Scrub "[$Label] $s") }
# The lines of run.ps1 / challenge.ps1, verbatim (flutter wrapper + the detection):
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter {
  if ($useFvm) { fvm flutter @args }
  else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args }
}
$raw = (flutter pub token list 2>$null | Out-String)
$exit = $LASTEXITCODE
$detect = ((flutter pub token list 2>$null | Out-String).Contains($PubUrl))
P "PubUrl = '$PubUrl'"
P "token list output = '$($raw -replace "`r", '\r' -replace "`n", '\n')'  (exit $exit)"
P "run.ps1's detection ((flutter pub token list 2>`$null | Out-String).Contains(`$PubUrl)) = $detect"
P "contains PubUrl + '/' = $($raw.Contains($PubUrl + '/'))"
$o2 = (flutter pub token list 2>&1 | Out-String)
P "with 2>&1 instead of 2>`$null: contains = $($o2.Contains($PubUrl))  output = '$($o2 -replace "`r", '\r' -replace "`n", '\n')'"
foreach ($v in "APPDATA", "LOCALAPPDATA", "PUB_CACHE", "HOME", "USERPROFILE", "XDG_CONFIG_HOME", "DART_CONFIG_DIR", "FVM_CACHE_PATH", "FVM_HOME") {
  P "env $v = $([Environment]::GetEnvironmentVariable($v))"
}
$tf = Join-Path $env:APPDATA "dart\pub-tokens.json"
P "Test-Path $tf = $(Test-Path $tf)"
if (Test-Path $tf) {
  try {
    $j = Get-Content -Raw $tf | ConvertFrom-Json
    foreach ($h in @($j.hosted)) { P "  token entry: url=$($h.url) fields=$(($h.PSObject.Properties.Name) -join ',') tokenLength=$(([string]$h.token).Length)" }
  } catch { P "  could not parse: $($_.Exception.Message)" }
}
P "fvm = $((Get-Command fvm -ErrorAction SilentlyContinue).Source)"
