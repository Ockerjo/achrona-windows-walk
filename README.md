# Windows probe for the kit's team-key step (a throwaway; nothing of the kit is here)

`python3 build_probe.py <monorepo>/achrona` renders `probe/`: the four runner scripts of the kit
(`run`, `run.ps1`, `challenge`, `challenge.ps1`, with `PUB_URL` pointed at a local mock), `mock_pub.py`
(a stand-in for the Worker's /pub: it checks a made-up Bearer key and serves a one-line fake
`achrona_kit`), a one-dependency pubspec, and the checkers `probe.ps1` / `probe.sh`.
`.github/workflows/token-probe.yml` runs both on windows-latest. No secret, no real key.

## What this does NOT prove (needs one manual check)

The first-run hidden prompt (`Read-Host -AsSecureString` in `run.ps1` / `challenge.ps1`) reads the
console, not stdin, so CI cannot drive it (the first attempt hung for 36 minutes on it). The probe
registers the key with `flutter pub token add` first (what the script does right after the prompt) and
proves everything else: no prompt when a key is stored, the download with it, the "check your team key"
message and the token removal on a wrong key, no key ever printed. **One manual check on a real Windows
console** (Jonas or a tester): delete the token (`fvm flutter pub token remove <PUB_URL>`), run
`.\run.ps1`, type a team key at the hidden prompt, and see the kit download. Every probe child runs with a
2-minute hard timeout and the job has 15, so a hang now fails fast.

## Run 4 (diagnostic)

`diag.ps1` prints what the token store looks like to a fresh `powershell -NoProfile -File` child (URLs and
field names only, never a key; the output is scrubbed of `htf-...`): `pub token list` raw, run.ps1's own
detection line, URL forms, the relevant environment variables and `%APPDATA%\dart\pub-tokens.json`'s entries.
`probe.ps1` registers the key without `Quiet` and prints pub's exit code and output.

## Run 5 (method matrix + the fixed template)

Run 4 showed `$Key | fvm flutter pub token add <url>` fails on Windows PowerShell 5.1 (exit 65, "not a valid
token": the pipe ends the string with CRLF and pub keeps the CR). `matrix.ps1` tries the alternatives with
the fake key only and prints exit code, whether `pub token list` shows the URL, and whether the stored
token equals the key. `probe.ps1` now registers keys with the REAL `Add-KitToken` extracted from the
rendered `run.ps1` (the fixed template: raw bytes + LF on pub's stdin through System.Diagnostics.Process).
