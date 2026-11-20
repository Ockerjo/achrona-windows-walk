#!/usr/bin/env bash
# The kit's team-key step, ./run and ./challenge, against the FAKE hosted pub (mock_pub.py).
# Git Bash on the runner, or any bash (a dry run). Each check prints ok/FAIL; exit 1 on any FAIL.
# No real key anywhere: KEY is made up and only the mock knows it.
set -u
cd "$(dirname "$0")"
KEY="htf-fake-probe-key"
URL="$(sed -n 's/^    hosted: //p' pubspec.yaml)"; PORT="${URL##*:}"; PORT="${PORT%%/*}"; FAILS=0
flutter() { if command -v fvm >/dev/null; then fvm flutter "$@"; else command flutter "$@"; fi; }
say() { echo "$*"; [ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "$*" >> "$GITHUB_STEP_SUMMARY"; return 0; }
check() { if eval "$2"; then say "| ok | $1 |"; else say "| FAIL | $1 |"; FAILS=$((FAILS+1)); fi; }
tokens() { flutter pub token list 2>/dev/null; }
fresh() { rm -rf pubspec.lock .dart_tool; export PUB_CACHE="$PWD/.cache-$1"; rm -rf "$PUB_CACHE"; }

PY="$(command -v python3 || command -v python)"  # Git Bash on Windows has python, not python3
rm -f mock.log; "$PY" mock_pub.py --fake fake
MOCK_PUB_KEY="$KEY" "$PY" mock_pub.py fake "$PORT" > mock.log 2>&1 &
MOCK=$!; trap 'kill $MOCK 2>/dev/null; flutter pub token remove "$URL" >/dev/null 2>&1' EXIT
for _ in $(seq 1 30); do curl -s -o /dev/null "$URL/api/packages/achrona_kit" && break; sleep 0.5; done
code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/packages/achrona_kit")
# The port may be someone else's (a dev Mac): ours answers 401 AND logs the request.
{ [ "$code" = 401 ] && grep -q "auth=none 401" mock.log; } || { say "the mock is not ours (got $code without a key)"; exit 1; }
say "| result | check |"; say "|---|---|"
flutter pub token remove "$URL" >/dev/null 2>&1

for script in run challenge; do
  arg=nodevice; [ $script = challenge ] && arg=base-01
  say "| -- | **./$script** (Git Bash) |"
  # 1. first run: asks once, the key piped in, pub downloads the kit.
  fresh $script; flutter pub token remove "$URL" >/dev/null 2>&1
  out=$(printf '%s\n' "$KEY" | ./$script $arg 2>&1)
  check "$script: the first run asks for the team key" 'grep -q "First run: the kit downloads from" <<<"$out"'
  check "$script: pub get downloaded the kit with it" 'grep -q "achrona_kit" pubspec.lock 2>/dev/null'
  check "$script: the token is stored for the pub URL" 'tokens | grep -qF "$URL"'
  check "$script: the key is never printed" '! grep -qF "$KEY" <<<"$out"'
  # 2. second run: no question (stdin is empty: asking would fail 'no team key given').
  out=$(./$script $arg < /dev/null 2>&1)
  check "$script: the second run does not ask" '! grep -q "First run\|no team key given" <<<"$out"'
  # 3. a bad key: the message, the token removed, nothing downloaded (a fresh cache).
  fresh $script-bad; flutter pub token remove "$URL" >/dev/null 2>&1
  out=$(printf '%s\n' "htf-wrong-key" | ./$script $arg 2>&1)
  check "$script: a bad key says to check the team key" 'grep -q "check your team key" <<<"$out"'
  check "$script: ...and the token is removed" '! tokens | grep -qF "$URL"'
  check "$script: ...and nothing was downloaded" '! grep -q "achrona_kit" pubspec.lock 2>/dev/null'
  check "$script: the wrong key is never printed" '! grep -qF "htf-wrong-key" <<<"$out"'
done
say ""; say "mock log (what the mock saw):"; sed 's/^/    /' mock.log | head -40 | while read -r l; do say "$l"; done
[ $FAILS = 0 ] && say "ALL OK (Git Bash)" || say "$FAILS FAILED (Git Bash)"
exit $((FAILS>0))
