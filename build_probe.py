#!/usr/bin/env python3
"""Renders the token probe's files into ./probe from the monorepo's v0.1.7 kit tooling:
ONLY the four runner scripts (PUB_URL = the mock) + the mock + a one-dependency
pubspec. No kit code, no pack art, nothing of the template: this repo is public.
    python3 build_probe.py /path/to/hack-the-future/achrona [PORT]"""
import os, shutil, sys, tempfile
repo = sys.argv[1]
sys.path.insert(0, os.path.join(repo, "tool"))
from kit.config import PUB_URL
from kit.runners import write_runners
PORT = sys.argv[2] if len(sys.argv) > 2 else "8765"  # 8765 on the runner; a dev Mac picks another
URL = f"http://127.0.0.1:{PORT}/pub"
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "probe")
shutil.rmtree(out, ignore_errors=True); os.makedirs(out)
tmp = tempfile.mkdtemp(); write_runners(tmp)
for n in ["run", "run.ps1", "challenge", "challenge.ps1"]:
    t = open(os.path.join(tmp, n), newline="").read()
    assert PUB_URL in t, n
    open(os.path.join(out, n), "w", newline="").write(t.replace(PUB_URL, URL))
    if n in ("run", "challenge"): os.chmod(os.path.join(out, n), 0o755)
open(os.path.join(out, "pubspec.yaml"), "w").write(
    f"name: probe\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\ndependencies:\n  achrona_kit:\n    hosted: {URL}\n    version: 0.1.7\n")
open(os.path.join(out, ".gitattributes"), "w").write("run text eol=lf\nchallenge text eol=lf\n*.sh text eol=lf\n*.ps1 text eol=crlf\n")
open(os.path.join(out, ".fvmrc"), "w").write('{"flutter": "3.47.5"}\n')
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), "src")
for n in os.listdir(src): shutil.copy(os.path.join(src, n), out)
os.chmod(os.path.join(out, "probe.sh"), 0o755)
print("probe:", sorted(os.listdir(out)))
