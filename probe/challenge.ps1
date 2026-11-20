# Windows without Git Bash:  .\challenge.ps1 <id>   or   .\challenge.ps1 all
# The same as ./challenge (the first run asks for your team key once, like run.ps1).
param([Parameter(Mandatory = $true)][string]$Id)
Set-Location $PSScriptRoot
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter {
  if ($useFvm) { fvm flutter @args }
  else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args }
}
# The hosted kit's one-time team key (run.ps1 and challenge.ps1 share this; kit/runners.py).
# pub reads the token as ONE line from stdin. A PowerShell pipe ends the string with CRLF and pub keeps the
# CR ("not a valid token", exit 65), so the key goes as raw bytes + LF straight into pub's stdin: no pipe, no
# file, never on a command line or the screen.
function Add-KitToken([string]$Key) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  if ($useFvm) {
    $psi.FileName = (Get-Command fvm -CommandType Application | Select-Object -First 1).Source
    $psi.Arguments = "flutter pub token add $PubUrl"
  } else {
    $psi.FileName = (Get-Command flutter -CommandType Application | Select-Object -First 1).Source
    $psi.Arguments = "pub token add $PubUrl"
  }
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($Key + "`n")
  $p.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
  $p.StandardInput.BaseStream.Flush()
  $p.StandardInput.Close()
  $null = $p.StandardOutput.ReadToEnd()
  $null = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  $global:LASTEXITCODE = $p.ExitCode
}
$PubUrl = "http://127.0.0.1:8765/pub"
$hosted = Select-String -Quiet -SimpleMatch -Pattern "hosted: $PubUrl" pubspec.yaml
$usb = (Test-Path pubspec_overrides.yaml) -and (Select-String -Quiet -Pattern '^  achrona_kit:' pubspec_overrides.yaml)
if ($hosted -and -not $usb) {
  if (-not ((flutter pub token list 2>$null | Out-String).Contains($PubUrl))) {
    Write-Host "First run: the kit downloads from $PubUrl with your team key (asked once)."
    $secure = Read-Host -AsSecureString "Team key (htf-..., on your team card)"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    if (-not $key) { Write-Host "no team key given: nothing downloaded"; exit 1 }
    Add-KitToken $key
    $ok = $LASTEXITCODE -eq 0
    $key = $null
    if (-not $ok) { Write-Host "could not store the team key for $PubUrl"; exit 1 }
  }
  $out = flutter pub get 2>&1 | Out-String
  Write-Host $out
  if ($LASTEXITCODE -ne 0) {
    if ($out -match '401|403|authenticat') {
      flutter pub token remove $PubUrl | Out-Null
      Write-Host "The kit download was refused: check your team key (it is on your team card). The next run asks for the key again."
    }
    exit 1
  }
}
function Run([string]$c) {
  switch ($c) {
    'level-01' { flutter test test/level_spec_test.dart test/level_reach_test.dart }
    'base-01' { flutter test test/challenges/base_01_camera_test.dart }
    'base-02' { flutter test test/challenges/base_02_facing_test.dart }
    'build-01' { flutter test test/challenges/build_01_feet_test.dart }
    'build-02' { flutter test test/challenges/build_02_lean_test.dart }
    'online-01' { flutter test test/run_link_test.dart --plain-name 'RunLink.submit' }
    'bonus-01' { flutter test test/challenges/bonus_01_platform_test.dart }
    'bonus-02' { flutter test test/challenges/bonus_02_door_test.dart }
    'bonus-03' { flutter test test/challenges/bonus_03_chase_test.dart }
    'bonus-04' { flutter test test/challenges/bonus_04_bounce_test.dart }
    'bonus-05' { flutter test test/challenges/bonus_05_checkpoint_test.dart }
    default { Write-Host "unknown challenge: $c (see CHALLENGES.md)"; exit 2 }
  }
}
if ($Id -eq 'all') {
  $reds = 0
  foreach ($c in @('base-01', 'base-02', 'build-01', 'build-02', 'level-01', 'online-01', 'bonus-01', 'bonus-02', 'bonus-03', 'bonus-04', 'bonus-05')) {
    $out = Run $c *>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { Write-Host "GREEN $c" } else {
      $reds++
      # The first failing test's name, or the first compile error.
      $m = [regex]::Match($out, '(?m)^[0-9:]+ [-+0-9 ]+: (.*) \[E\]\r?$|^.*Error: .*$')
      $why = if ($m.Groups[1].Success) { $m.Groups[1].Value } elseif ($m.Success) { $m.Value.Trim() } else { '' }
      if ($why) { Write-Host "red   $c   ($why)" } else { Write-Host "red   $c" }
    }
  }
  if ($reds -gt 0) { Write-Host "A red one? Run .\challenge.ps1 <id> to see why (e.g. .\challenge.ps1 base-01)." }
} else {
  Run $Id
  exit $LASTEXITCODE
}
