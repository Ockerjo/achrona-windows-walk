# Windows probe for the kit's team-key step (a throwaway; nothing of the kit is here)

`python3 build_probe.py <monorepo>/achrona` renders `probe/`: the four runner scripts of the kit
(`run`, `run.ps1`, `challenge`, `challenge.ps1`, with `PUB_URL` pointed at a local mock), `mock_pub.py`
(a stand-in for the Worker's /pub: it checks a made-up Bearer key and serves a one-line fake
`achrona_kit`), a one-dependency pubspec, and the checkers `probe.ps1` / `probe.sh`.
`.github/workflows/token-probe.yml` runs both on windows-latest. No secret, no real key.
