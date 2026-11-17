# Windows walk (CI probe, throwaway)

Runs the Hack the Future student setup on a fresh `windows-latest` runner, step by step as the
briefing says (choco + fvm, the team-key git helper, clone, pub get, a web build, `./challenge
base-01` in Git Bash and PowerShell, one commit + push), and times each step in the run summary.
It clones a rehearsal team's repo with that team's key (secret `REHEARSAL_TEAM_KEY`). No game
code or answers live here. Archived after the run.
