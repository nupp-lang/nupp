#!/usr/bin/env python3
"""Build a committed browser release candidate without seeded project outputs."""

import argparse
import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import threading
import time


FORBIDDEN = (
    ".git", ".rocks", ".nupp-cache", "build", "_stage1", "_stage2", "_stage3",
    "editors/playground/dist", "editors/playground/node_modules",
)


def clean_environment(original, output, toolchain, guest):
    # Reuse pinned external inputs, never a caller's compiler or project cache.
    env = {key: value for key, value in original.items()
           if not key.startswith("NUPP_")
           and not re.fullmatch(r"LUA_(?:PATH|CPATH|INIT)(?:_\d+_\d+)?", key)
           and key not in (
               "NODE_OPTIONS", "NODE_PATH", "CARGO_TARGET_DIR", "RUSTC_WRAPPER",
           )}
    for key in ("NUPP_CC", "NUPP_CXX"):
        if key in original:
            env[key] = original[key]
    env.update(NUPP_TOOLCHAIN_DIR=str(toolchain), NUPP_BROWSER_GUEST_DIR=str(guest),
               RUNNER_TEMP=str(output / "tmp"))
    return env


def assert_source_only(checkout):
    present = [name for name in FORBIDDEN if (checkout / name).exists()
               or (checkout / name).is_symlink()]
    if present:
        raise ValueError("Export contains seeded outputs: " + ", ".join(present))


def file_record(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"bytes": path.stat().st_size, "sha256": digest.hexdigest()}


class Handler(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      ".mjs": "text/javascript", ".wasm": "application/wasm"}

    def log_message(self, *_args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "default-src 'self'; "
                         "script-src 'self' 'wasm-unsafe-eval'; "
                         "style-src 'self' 'unsafe-inline'; "
                         "worker-src 'self' blob:; connect-src 'self'")
        super().end_headers()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path, help="new directory outside the repository")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--ref", default="HEAD", help="committed revision to export")
    parser.add_argument("--guest", type=Path, required=True, help="extracted verified runtime package")
    parser.add_argument("--toolchain-dir", type=Path, required=True,
                        help="external pinned toolchain/download cache")
    parser.add_argument("--keep-checkout", action="store_true")
    args = parser.parse_args(argv)
    repo, output = args.repo.resolve(), args.output.resolve()
    guest, toolchain = args.guest.resolve(), args.toolchain_dir.resolve()
    if output == repo or repo in output.parents:
        parser.error("output must be outside the source repository")
    if not (guest / "guest-manifest.json").is_file():
        parser.error("--guest must contain guest-manifest.json")
    if output.exists():
        parser.error("output already exists; choose a new directory")
    revision = subprocess.check_output(
        ["git", "rev-parse", "--verify", "--end-of-options", args.ref + "^{commit}"],
        cwd=repo, text=True).strip()
    output.mkdir(parents=True)
    checkout = output / "checkout"
    checkout.mkdir()
    (output / "tmp").mkdir()
    env = clean_environment(os.environ, output, toolchain, guest)
    report = {"revision": revision, "scope": "Source-only checkout; only external pinned "
              "toolchain/download caches and the supplied runtime package are reused. "
              "Desktop UI checks do not establish physical-device or performance acceptance.",
              "script": file_record(Path(__file__)), "guestManifest": file_record(guest / "guest-manifest.json"),
              "commands": [], "ok": False}

    def save():
        (output / "result.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(name, command, cwd=checkout):
        print("cold checkout: " + name, flush=True)
        started = time.monotonic()
        log = output / (name + ".log")
        with log.open("wb") as stream:
            result = subprocess.run(command, cwd=cwd, env=env, stdout=stream,
                                    stderr=subprocess.STDOUT)
        report["commands"].append({"name": name, "argv": command,
                                   "exitCode": result.returncode,
                                   "elapsedMs": (time.monotonic() - started) * 1000,
                                   "log": log.name, **file_record(log)})
        save()
        if result.returncode:
            raise RuntimeError(name + " failed; see " + str(log))

    try:
        archive = output / "source.tar"
        run("export", ["git", "archive", "--format=tar", "--output=" + str(archive), revision], repo)
        report["sourceArchive"] = file_record(archive)
        run("extract", ["tar", "-xf", str(archive), "-C", str(checkout)])
        archive.unlink()
        assert_source_only(checkout)
        report["initialAbsent"] = list(FORBIDDEN)
        pins = (checkout / "scripts/toolchain.pins").read_text()
        report["stageZero"] = dict(re.findall(r"^(STAGE0_(?:TAG|SHA256))=(.*)$", pins, re.M))
        report["toolchainPins"] = file_record(checkout / "scripts/toolchain.pins")
        run("toolchain", ["./scripts/toolchain", "--all"])
        # This first invocation must fetch and run the pinned stage zero.
        run("bootstrap", ["./bin/nupp", "build", "--target", "bootstrapCompiler"])
        run("compiler", ["./bin/nupp", "build"])
        run("docs", ["./bin/nupp", "build", "--target", "docs"])
        run("node-dependencies", ["npm", "ci", "--prefix", "editors/playground"])
        run("playground", ["node", "editors/playground/build.mjs"])
        env["NUPP_PLAYGROUND_ALREADY_BUILT"] = "1"
        run("pages", ["node", "scripts/build-pages.mjs"])
        for project, target in (("tests/luajit-browser/aot-project", "app"),
                                ("tests/wasm-aot/platform-project", "luajit")):
            name = Path(project).name
            run(name, ["./scripts/browser-app", project, target, "build/cold-" + name])
        run("fixpoint", ["./bin/nupp", "fixpoint"])
        pages = checkout / "build/pages"
        dist = pages / "playground"
        report["playgroundAssets"] = json.loads((dist / "nupp-playground-assets.json").read_text())
        (dist / "performance-empty.html").write_text("<!doctype html><title>Browser acceptance</title>\n")
        server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(Handler, directory=str(pages)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            run("playground-ui", ["node", "editors/playground/test/luajit-ui.mjs",
                                  "http://127.0.0.1:" + str(server.server_port) + "/playground/",
                                  str(output / "playground-ui.json")])
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        report["ui"] = json.loads((output / "playground-ui.json").read_text())
        report["ok"] = True
        save()
        if not args.keep_checkout:
            shutil.rmtree(checkout)
            shutil.rmtree(output / "tmp")
        print("cold checkout passed: " + str(output / "result.json"))
        return 0
    except Exception as error:
        report["ok"] = False
        report["error"] = str(error)
        save()
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
