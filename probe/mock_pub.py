#!/usr/bin/env python3
"""A stand-in for the Worker's /pub (achrona-ai-server/src/features/pub/pub.ts):
the hosted pub repository (spec v2) behind a Bearer team key, for proving the
kit's team-key step (./run, ./challenge, run.ps1, challenge.ps1) where the real
kit can't go, e.g. a public CI runner. Stdlib only.

    python3 mock_pub.py --fake DIR            write a FAKE achrona_kit 0.1.7 (one lib line) to DIR
    MOCK_PUB_KEY=k python3 mock_pub.py DIR PORT   serve DIR on 127.0.0.1:PORT/pub

DIR holds kit_archive.py's layout: <name>.versions.txt, <name>-<v>.tar.gz,
.tar.gz.sha256, .pubspec.json. No Authorization: 401; another key: 401 (the
Worker's messages, in WWW-Authenticate); the key: the listing / the archive.
Each request prints one line: METHOD PATH auth=none|bad|ok STATUS.
"""
import hashlib
import io
import json
import os
import re
import sys
import tarfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LISTING = re.compile(r"^/pub/api/packages/([a-z0-9_]+)$")
ARCHIVE = re.compile(r"^/pub/api/archives/([a-z0-9_]+-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz)$")
NO_KEY = "No team key: run ./run once with your team key (it registers the key for the kit download)."
BAD_KEY = "That team key does not work: check the key on your team card, then run ./run again."


def fake(out, name="achrona_kit", version="0.1.7"):
    """A tiny pure-Dart package as a pub archive, in the Worker's file layout."""
    os.makedirs(out, exist_ok=True)
    spec = {"name": name, "version": version, "environment": {"sdk": ">=3.0.0 <4.0.0"}}
    files = {"pubspec.yaml": f"name: {name}\nversion: {version}\nenvironment:\n  sdk: '>=3.0.0 <4.0.0'\n",
             f"lib/{name}.dart": "const fakeKit = 'not the real kit: the token probe only';\n"}
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tar:
        for path, text in sorted(files.items()):
            data = text.encode()
            info = tarfile.TarInfo(path)
            info.size, info.mode = len(data), 0o644
            tar.addfile(info, io.BytesIO(data))
    base = os.path.join(out, f"{name}-{version}")
    open(base + ".tar.gz", "wb").write(buf.getvalue())
    open(base + ".tar.gz.sha256", "w").write(f"{hashlib.sha256(buf.getvalue()).hexdigest()}  {name}-{version}.tar.gz\n")
    json.dump(spec, open(base + ".pubspec.json", "w"))
    open(os.path.join(out, f"{name}.versions.txt"), "w").write(version + "\n")


def handler(root, key):
    class Pub(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def send(self, status, body, ctype="application/json", extra=()):
            self.send_response(status)
            self.send_header("content-type", ctype)
            self.send_header("content-length", str(len(body)))
            for k, v in extra:
                self.send_header(k, v)
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            got = self.headers.get("authorization")
            auth = "none" if not got else "ok" if got == f"Bearer {key}" else "bad"
            status = self.answer(auth)
            print(f"GET {self.path} auth={auth} {status}", flush=True)

        def answer(self, auth):
            listing, archive = LISTING.match(self.path), ARCHIVE.match(self.path)
            if not (listing or archive):
                self.send(404, b'{"error":"not found"}')
                return 404
            if auth != "ok":
                msg = NO_KEY if auth == "none" else BAD_KEY
                self.send(401, json.dumps({"error": msg}).encode(),
                          extra=[("www-authenticate", f'Bearer realm="pub", message="{msg}"')])
                return 401
            if archive:
                p = os.path.join(root, archive[1])
                if not os.path.exists(p):
                    self.send(404, b'{"error":"not found"}')
                    return 404
                self.send(200, open(p, "rb").read(), "application/octet-stream")
                return 200
            name = listing[1]
            vf = os.path.join(root, f"{name}.versions.txt")
            versions = open(vf).read().split() if os.path.exists(vf) else []
            origin = f"http://{self.headers.get('host')}"
            listed = [{
                "version": v,
                "archive_url": f"{origin}/pub/api/archives/{name}-{v}.tar.gz",
                "archive_sha256": open(os.path.join(root, f"{name}-{v}.tar.gz.sha256")).read().split()[0],
                "pubspec": json.load(open(os.path.join(root, f"{name}-{v}.pubspec.json"))),
            } for v in versions]
            if not listed:
                self.send(404, b'{"error":"not found"}')
                return 404
            body = {"name": name, "latest": listed[-1], "versions": listed}
            self.send(200, json.dumps(body).encode(), "application/vnd.pub.v2+json")
            return 200

    return Pub


def serve(root, port, key):
    return ThreadingHTTPServer(("127.0.0.1", port), handler(root, key))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--fake"]:
        fake(sys.argv[2])
    else:
        serve(sys.argv[1], int(sys.argv[2]), os.environ["MOCK_PUB_KEY"]).serve_forever()
