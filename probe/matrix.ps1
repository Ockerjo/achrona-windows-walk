# Run 5: HOW does a team key reach `pub token add` in Windows PowerShell 5.1 (fvm.exe -> flutter.bat -> dart)?
# The plain pipe failed with exit 65 'not a valid token' (run 4). FAKE key only; per method it prints pub's exit
# code, whether `pub token list` then shows the URL, and whether the stored token equals the key (True/False,
# never a value). Also the exact bytes PowerShell sends, as a python child reads them.
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$Key = "htf-fake-probe-key"
$Url = ((Select-String -Path pubspec.yaml -Pattern '^    hosted: (.*)$').Matches[0].Groups[1].Value).Trim()
$useFvm = [bool](Get-Command fvm -ErrorAction SilentlyContinue)
function flutter { if ($useFvm) { fvm flutter @args } else { & (Get-Command flutter -CommandType Application | Select-Object -First 1) @args } }
function Say([string]$s) { Write-Host $s; if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $s } }
function Reset { try { flutter pub token remove $Url 2>&1 | Out-Null } catch { } ; $global:LASTEXITCODE = 0 }
function Report([string]$name, $code) {
  $listed = $false; try { $listed = ((flutter pub token list 2>$null | Out-String).Contains($Url)) } catch { }
  $eq = "n/a"; $len = -1
  $tf = Join-Path $env:APPDATA "dart\pub-tokens.json"
  if (Test-Path $tf) {
    try {
      $j = Get-Content -Raw $tf | ConvertFrom-Json
      $h = @($j.hosted) | Where-Object { $_.url -like "$Url*" } | Select-Object -First 1
      if ($h) { $eq = ([string]$h.token -ceq $Key); $len = ([string]$h.token).Length }
    } catch { }
  }
  Say "| $name | exit $code | listed=$listed | tokenEqualsKey=$eq | storedLength=$len |"
  Reset
}
# The key + LF as raw bytes on a child's stdin (what the fixed template does); returns "exit|stdout".
function Raw([string]$file, [string]$arguments) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $file; $psi.Arguments = $arguments; $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $p = [System.Diagnostics.Process]::Start($psi)
  $b = [System.Text.Encoding]::ASCII.GetBytes($Key + "`n")
  $p.StandardInput.BaseStream.Write($b, 0, $b.Length); $p.StandardInput.BaseStream.Flush(); $p.StandardInput.Close()
  $o = $p.StandardOutput.ReadToEnd(); $null = $p.StandardError.ReadToEnd(); $p.WaitForExit()
  return "$($p.ExitCode)|$o"
}

Say "#### what PowerShell sends (a python child prints the bytes it reads; fake key)"
Say '```'
$py = '-c "import sys;print(repr(sys.stdin.buffer.read()))"'
Say ("PS pipe `$Key               : " + ($Key | python -c 'import sys;print(repr(sys.stdin.buffer.read()))'))
Say ("PS pipe (`$Key + `"``n`")     : " + (($Key + "`n") | python -c 'import sys;print(repr(sys.stdin.buffer.read()))'))
$oe = $OutputEncoding; $OutputEncoding = New-Object System.Text.UTF8Encoding($false)
Say ("PS pipe, UTF8 no BOM       : " + ($Key | python -c 'import sys;print(repr(sys.stdin.buffer.read()))'))
$OutputEncoding = $oe
$pyexe = (Get-Command python -CommandType Application | Select-Object -First 1).Source
Say ("Process + raw bytes + LF   : " + ((Raw $pyexe $py) -replace "^\d+\|", ""))
Say '```'
Say ""; Say "#### methods of 'pub token add' (fake key; listed = pub token list shows the URL; tokenEqualsKey = stored token equals the key)"
Say "| method | exit | listed | stored == key | stored length (key = $($Key.Length)) |"; Say "|---|---|---|---|---|"
Reset

# Known good (run 5): (d) a temp file (LF, UTF8 no BOM) as Start-Process stdin. Known bad (exit 65, BOM): every pipe,
# Process stdin writer, dart.exe directly. Dropped to save time; (t) is the template as rendered:
# (t) the template's own Add-KitToken, extracted from the rendered run.ps1
$ps1 = Get-Content -Raw (Join-Path $PSScriptRoot "run.ps1")
$m = [regex]::Match($ps1, '(?s)function Add-KitToken.*?\r?\n}\r?\n')
if ($m.Success) { $PubUrl = $Url; Invoke-Expression $m.Value; Add-KitToken $Key; Report "(t) run.ps1's Add-KitToken as rendered: MUST be exit 0, listed, stored == key" $LASTEXITCODE }
else { Say "| (t) no Add-KitToken in run.ps1 | - | - | - | - |" }
Reset

# The refusal: a key with a non-ASCII character is refused first (exit 65, the check-your-team-key message), nothing stored.
if ($m.Success) {
  Add-KitToken ("htf-" + [char]0x00E9 + "-key") 2>&1 | ForEach-Object { Say "    refusal message: $_" }
  Report "(t2) non-ASCII key: refused, MUST be exit 65, not listed" $LASTEXITCODE
}
