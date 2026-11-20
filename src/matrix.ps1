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

# (a) the current method
if ($useFvm) { $Key | fvm flutter pub token add $Url 2>&1 | Out-Null } else { $Key | flutter pub token add $Url 2>&1 | Out-Null }
Report "(a) PS pipe: `$Key | fvm flutter pub token add (the v0.1.7 scripts)" $LASTEXITCODE
# (b) UTF-8 without BOM for the pipe
$OutputEncoding = New-Object System.Text.UTF8Encoding($false)
$Key | fvm flutter pub token add $Url 2>&1 | Out-Null
Report "(b) PS pipe with `$OutputEncoding = UTF8 no BOM" $LASTEXITCODE
$OutputEncoding = $oe
# (h) key + LF piped: PowerShell then adds CRLF after it, pub reads the first line only
($Key + "`n") | fvm flutter pub token add $Url 2>&1 | Out-Null
Report "(h) PS pipe of (`$Key + LF): pub reads the first line" $LASTEXITCODE
# (c) cmd echo (INFORMATIONAL: puts the key on a command line, never usable for a real key)
cmd /c "echo $Key| fvm flutter pub token add $Url" 2>&1 | Out-Null
Report "(c) cmd /c echo | fvm (key on a command line: info only)" $LASTEXITCODE
# (d) a temp file as stdin, in its own temp dir, deleted in finally
$dir = Join-Path ([IO.Path]::GetTempPath()) ("kt-" + [Guid]::NewGuid().ToString("N"))
try {
  New-Item -ItemType Directory -Path $dir | Out-Null
  $f = Join-Path $dir "in.txt"
  [IO.File]::WriteAllText($f, $Key + "`n", (New-Object System.Text.UTF8Encoding($false)))
  $p = Start-Process fvm -ArgumentList "flutter", "pub", "token", "add", $Url -NoNewWindow -Wait -PassThru -RedirectStandardInput $f -RedirectStandardOutput (Join-Path $dir "o.txt") -RedirectStandardError (Join-Path $dir "e.txt")
  Report "(d) temp file (LF, UTF8 no BOM) + Start-Process -RedirectStandardInput" $p.ExitCode
} finally { Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue }
# (e) the Dart SDK directly (the fvm-resolved dart.exe), piped
$dart = $null
try {
  $root = (fvm flutter --version --machine 2>$null | Out-String | ConvertFrom-Json).flutterRoot
  $dart = Join-Path $root "bin\cache\dart-sdk\bin\dart.exe"
} catch { }
if ($dart -and (Test-Path $dart)) {
  $Key | & $dart pub token add $Url 2>&1 | Out-Null
  Report "(e) dart.exe directly, PS pipe" $LASTEXITCODE
  $r = Raw $dart "pub token add $Url"
  Report "(e2) dart.exe directly, Process + raw bytes + LF" ($r -split "\|")[0]
} else { Say "| (e) dart.exe not found ($dart) | - | - | - | - |" }
# (g) fvm.exe via Process + raw bytes + LF (no pipe, no file, no command line)
$fvmexe = (Get-Command fvm -CommandType Application | Select-Object -First 1).Source
$r = Raw $fvmexe "flutter pub token add $Url"
Report "(g) fvm.exe via Process + raw bytes + LF (the fixed template's method)" ($r -split "\|")[0]
# (t) the template's own Add-KitToken, extracted from the rendered run.ps1
$ps1 = Get-Content -Raw (Join-Path $PSScriptRoot "run.ps1")
$m = [regex]::Match($ps1, '(?s)function Add-KitToken.*?\r?\n}\r?\n')
if ($m.Success) { $PubUrl = $Url; Invoke-Expression $m.Value; Add-KitToken $Key; Report "(t) run.ps1's Add-KitToken as rendered" $LASTEXITCODE }
else { Say "| (t) no Add-KitToken in run.ps1 | - | - | - | - |" }
Reset
