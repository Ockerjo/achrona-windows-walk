# Windows without Git Bash:  .\run.ps1 [device]   (chrome by default)
# The same as ./run: the event's public values from config/event.json, or offline.
# The kit downloads from http://127.0.0.1:8765/pub with your team key: the first run asks for
# it once (hidden) and hands it to pub; a kit in pubspec_overrides.yaml (the
# coaches' USB copy) needs no key.
param([string]$Device = "chrome")
Set-Location $PSScriptRoot
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter {
  if ($useFvm) { fvm flutter @args }
  else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args }
}
# The hosted kit's one-time team key (run.ps1 and challenge.ps1 share this; kit/runners.py).
function Add-KitToken([string]$Key) {
  if ($useFvm) { $Key | fvm flutter pub token add $PubUrl | Out-Null }
  else { $Key | & (Get-Command flutter -CommandType Application | Select-Object -First 1) pub token add $PubUrl | Out-Null }
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
      Write-Host "The kit download was refused: check your team key (on your team card) or run Connect GitHub on your team page. The next run asks for the key again."
    }
    exit 1
  }
}
if (Test-Path config/event.json) {
  flutter run -d $Device --dart-define-from-file=config/event.json @args
} else {
  Write-Host "no config/event.json: the game runs offline (no login, no online features)"
  flutter run -d $Device @args
}
