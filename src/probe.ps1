# The kit's team-key step, run.ps1 and challenge.ps1, against the FAKE hosted pub (mock_pub.py).
# Windows PowerShell 5.1 on the runner. Each check prints ok/FAIL; exit 1 on any FAIL.
# The hidden first-run prompt (Read-Host -AsSecureString) cannot be driven from CI (it reads the console, not
# stdin): the key is registered with `pub token add` first, as the script itself does. That prompt needs ONE
# manual check on a real Windows console (see README.md).
# No real key anywhere: $Key is made up and only the mock knows it.
# Actions starts powershell steps with $ErrorActionPreference = 'Stop', and PS 5.1 then turns ANY native
# stderr line (pub's "No secret token ..." on a token remove with none yet) into a terminating error.
# The students' default is Continue: so is this checker, and the kit scripts run in their own fresh powershell.
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$Key = "htf-fake-probe-key"
$Url = ((Select-String -Path pubspec.yaml -Pattern '^    hosted: (.*)$').Matches[0].Groups[1].Value).Trim()
$Port = ([Uri]$Url).Port
$script:fails = 0
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter { if ($useFvm) { fvm flutter @args } else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args } }
function Say([string]$s) { Write-Host $s; if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $s } }
function Check([string]$what, [bool]$ok) { if ($ok) { Say "| ok | $what |" } else { Say "| FAIL | $what |"; $script:fails++ } }
# A probe-side flutter call that may legitimately fail or print to stderr: never throws, never prints.
function Quiet { try { flutter @args 2>&1 | Out-Null } catch { } ; $global:LASTEXITCODE = 0 }
function Tokens { try { (flutter pub token list 2>$null | Out-String) } catch { "" } }
function Fresh([string]$name) {
  Remove-Item -Recurse -Force pubspec.lock, .dart_tool -ErrorAction SilentlyContinue
  $env:PUB_CACHE = Join-Path $PSScriptRoot ".cache-$name"
  Remove-Item -Recurse -Force $env:PUB_CACHE -ErrorAction SilentlyContinue
}
# Registers a key for the mock the way the kit scripts do (the key on pub's stdin).
function AddToken([string]$k) {
  try { if ($useFvm) { $k | fvm flutter pub token add $Url 2>&1 | Out-Null } else { $k | & (Get-Command flutter -CommandType Application | Select-Object -First 1) pub token add $Url 2>&1 | Out-Null } } catch { }
  $global:LASTEXITCODE = 0
}
# One run of a kit script as a student runs it: its own fresh powershell (default Continue), stdin an EMPTY
# file (a prompt would see EOF, never wait on a console), output to files, and a HARD TIMEOUT: a hang is a
# FAIL after 2 minutes, with the output so far. Returns the output; $script:timedOut says if it was killed.
function Student([string]$kitScript, [string]$arg) {
  $so = Join-Path $PSScriptRoot "student.out"; $se = Join-Path $PSScriptRoot "student.err"; $si = Join-Path $PSScriptRoot "student.in"
  Remove-Item $so, $se -ErrorAction SilentlyContinue; Set-Content -Path $si -Value "" -NoNewline
  $p = Start-Process powershell -PassThru -WindowStyle Hidden -WorkingDirectory $PSScriptRoot `
    -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ".\$kitScript", $arg `
    -RedirectStandardInput $si -RedirectStandardOutput $so -RedirectStandardError $se
  $script:timedOut = -not $p.WaitForExit(120000)
  if ($script:timedOut) { & taskkill /PID $p.Id /T /F 2>&1 | Out-Null; $global:LASTEXITCODE = 0 }
  $o = ""; foreach ($f in @($so, $se)) { if (Test-Path $f) { $o += (Get-Content -Raw $f -ErrorAction SilentlyContinue) } }
  Write-Host $o
  return [string]$o
}
function HasKit { (Test-Path pubspec.lock) -and [bool](Select-String -Path pubspec.lock -Pattern achrona_kit -Quiet) }

Remove-Item mock.log, mock.err -ErrorAction SilentlyContinue
python mock_pub.py --fake fake
$env:MOCK_PUB_KEY = $Key
$mock = Start-Process python -ArgumentList "mock_pub.py", "fake", $Port -PassThru -WindowStyle Hidden -RedirectStandardOutput mock.log -RedirectStandardError mock.err
try {
  for ($i = 0; $i -lt 30; $i++) { try { Invoke-WebRequest "$Url/api/packages/achrona_kit" -UseBasicParsing | Out-Null; break } catch { if ($_.Exception.Response) { break }; Start-Sleep -Milliseconds 500 } }
  $code = 0; try { Invoke-WebRequest "$Url/api/packages/achrona_kit" -UseBasicParsing | Out-Null } catch { $code = [int]$_.Exception.Response.StatusCode }
  if ($code -ne 401 -or -not (Select-String -Path mock.log -Pattern "auth=none 401" -Quiet)) { Say "the mock is not ours (got $code without a key)"; exit 1 }
  Say "| result | check |"; Say "|---|---|"
  # The checker itself: Continue here, a failing native call does not throw, and a student's fresh
  # powershell (the way Student() runs the kit scripts) also starts with the default Continue.
  Check "checker: ErrorActionPreference is Continue" ($ErrorActionPreference -eq "Continue")
  $threw = $false; try { flutter pub token remove "http://127.0.0.1:1/no-such-repo" 2>&1 | Out-Null } catch { $threw = $true }
  Check "checker: a native stderr line (token remove with none) does not throw" (-not $threw)
  $child = (powershell -NoProfile -Command '$ErrorActionPreference' | Out-String).Trim()
  Check "students: a fresh powershell -NoProfile starts with Continue (the kit scripts run in it)" ($child -eq "Continue")
  Quiet pub token remove $Url

  foreach ($s in @(@("run.ps1", "nodevice"), @("challenge.ps1", "base-01"))) {
    $name = $s[0]; $arg = $s[1]
    Say "| -- | **.\$name** (PowerShell, a fresh powershell -NoProfile -File, as a student's) |"
    # 1. A registered key: the script must not ask, pub get downloads the fake kit, the key stays unprinted.
    Fresh $name; Quiet pub token remove $Url; AddToken $Key
    $out = Student $name $arg
    Check "$name`: finished within 2 minutes (a hang is killed)" (-not $script:timedOut)
    Check "$name`: with the key registered it does not ask" (-not ($out -match "First run|no team key given|Team key \(htf"))
    Check "$name`: pub get downloaded the kit with it" (HasKit)
    Check "$name`: the key is never printed" (-not $out.Contains($Key))
    # 2. A WRONG key registered: the message, the token removed, nothing downloaded (a fresh cache).
    Fresh "$name-bad"; Quiet pub token remove $Url; AddToken "htf-wrong-key"
    $out = Student $name $arg
    Check "$name`: bad key: finished within 2 minutes" (-not $script:timedOut)
    Check "$name`: a bad key says to check the team key" ($out -match "check your team key")
    Check "$name`: ...and the token is removed" (-not (Tokens).Contains($Url))
    Check "$name`: ...and nothing was downloaded" (-not (HasKit))
    Check "$name`: the wrong key is never printed" (-not $out.Contains("htf-wrong-key"))
  }
  Say ""; Say "NOT covered here: the first-run hidden prompt (Read-Host -AsSecureString) needs one manual check on a real Windows console."
  Say ""; Say "mock log (what the mock saw):"
  Get-Content mock.log | Select-Object -First 40 | ForEach-Object { Say "    $_" }
  if ($script:fails -eq 0) { Say "ALL OK (PowerShell)" } else { Say "$($script:fails) FAILED (PowerShell)" }
} finally {
  Quiet pub token remove $Url
  if ($mock -and -not $mock.HasExited) { Stop-Process -Id $mock.Id -Force }
}
exit ([int]($script:fails -gt 0))
