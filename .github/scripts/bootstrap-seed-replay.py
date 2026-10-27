#!/usr/bin/env python3
"""Locate bootstrap stage divergence using already verified seed artifacts."""
import hashlib
import io
import json
import os
from pathlib import Path
import runpy
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "replay-source"
OUT = ROOT / "release"
PRIOR = ROOT / "prior-release"
OUT.mkdir(exist_ok=True)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def invoke(command, env, log):
    with log.with_suffix(".out").open("w") as stdout, log.with_suffix(".err").open("w") as stderr:
        result = subprocess.run([str(x) for x in command], cwd=SOURCE, env=env,
                                stdout=stdout, stderr=stderr)
    return {"command": [str(x) for x in command], "exitCode": result.returncode,
            "stdout": str(log.with_suffix(".out")), "stderr": str(log.with_suffix(".err"))}


pin = json.loads((PRIOR / "transition-pin.json").read_text())
host = pin.pop("host")
archive = PRIOR / ("transition-" + host + ".tar.gz")
assert sha(archive) == pin["sha256"], "prior seed archive differs from receipt"
pin["url"] = archive.resolve().as_uri()
manifest = OUT / "transition-pins.json"
manifest.write_text(json.dumps({"format": "nupp-bootstrap-seed-1", "hosts": {host: pin}}))
selected = subprocess.check_output(["python3", str(ROOT / "scripts/bootstrap-seed"), "fetch",
                                    "--manifest", str(manifest), "--cache", str(OUT / "cache")],
                                   cwd=ROOT, text=True).strip()
package = Path(selected)
runtime, original = package / "runtime", package / "compiler.image"
assert sha(runtime) == pin["runtimeSha256"] and sha(original) == pin["imageSha256"]

env = dict(os.environ, NO_JIT="1", NO_AOT="1", SIMD_INTERPRET="1",
           NUPP_VM_EMIT_CACHE="", NUPP_COMPILER_ROOT=str(SOURCE), NUPP_VM_BINARY=str(runtime))
env.pop("NO_THREADED", None)
record = {"source": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=SOURCE, text=True).strip(),
          "seedSource": pin["sourceRevision"], "runtimeSha256": sha(runtime),
          "originalImageSha256": sha(original), "host": host, "variants": {}}
layouts = OUT / "layouts.json"
record["layouts"] = invoke([runtime, "native", "layouts", layouts], env, OUT / "layouts")
assert record["layouts"]["exitCode"] == 0, "transition runtime cannot expose its native ABI"

# The compiler image is portable; the archive's runtime is never executed here.
url = "https://github.com/nupp-lang/nupp/releases/download/v0.0.15-native-seed.1/nupp-seed-aarch64-apple-darwin.tar.gz"
with urllib.request.urlopen(url) as response:
    portable = response.read()
assert hashlib.sha256(portable).hexdigest() == "0a914588ef56b85265d21c14ac35c142cb46758fc4bcc376854e8fc85766eef4"
with tarfile.open(fileobj=io.BytesIO(portable), mode="r:gz") as archived:
    stream = archived.extractfile("compiler.image")
    assert stream is not None
    alias = OUT / "portable-alias.image"
    alias.write_bytes(stream.read())
assert sha(alias) == "33299f9d3ba989f7e5b2218000827de3e71e0f0d05877214002910019a2f5299"
record["portableImageSha256"] = sha(alias)
helper = runpy.run_path(str(SOURCE / "scripts/vm-cli"), run_name="bootstrap_replay_import")
extras = helper["root_extras"]()

for name, compiler, reference in (("native-original", original, False),
                                   ("reference-original", original, True),
                                   ("native-portable", alias, False)):
    directory = OUT / name
    directory.mkdir()
    stage_env = dict(env)
    if reference:
        stage_env["NO_THREADED"] = "1"
    results = {"execution": "historical-reference" if reference else "native-only",
               "inputImageSha256": sha(compiler), "stages": [], "compiles": []}
    record["variants"][name] = results
    for stage in (1, 2):
        target = directory / ("stage" + str(stage) + ".image")
        command = [runtime, "run", compiler, "nupp.tools.vm.project", "emit", SOURCE,
                   "nupp.tools.vm.root", extras, "--output", target]
        result = invoke(command, stage_env, directory / ("stage" + str(stage)))
        if target.is_file():
            result["imageSha256"] = sha(target)
        results["stages"].append(result)
        if result["exitCode"]:
            break
        compiler = target
    if len(results["stages"]) == 2 and not results["stages"][-1]["exitCode"]:
        for mode in ("native", "reference"):
            check_env = dict(env)
            if mode == "reference":
                check_env["NO_THREADED"] = "1"
            clif = directory / (mode + ".clif")
            result = invoke([runtime, "run", compiler, "nupp.compiler.clif.lower", "compileRuntime",
                             SOURCE, layouts, "--output", clif], check_env, directory / (mode + "-compile"))
            result["execution"] = mode
            if clif.is_file():
                result["clifSha256"] = sha(clif)
            results["compiles"].append(result)
    (OUT / "replay.json").write_text(json.dumps(record, indent=2) + "\n")

record["stageComparisons"] = {}
for stage in (1, 2):
    name = "stage" + str(stage) + ".image"
    hashes = {variant: sha(OUT / variant / name) for variant in record["variants"]
              if (OUT / variant / name).is_file()}
    record["stageComparisons"][name] = hashes
(OUT / "replay.json").write_text(json.dumps(record, indent=2) + "\n")
print(json.dumps(record, indent=2))
