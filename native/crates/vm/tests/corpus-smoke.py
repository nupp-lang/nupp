#!/usr/bin/env python3
"""Build and execute classified Lua suites using a VM compiler seed.

Usage: corpus-smoke.py SEED [--binary PATH] [--class CLASS] [--suite NAME ...]
                  [--output DIRECTORY]

The classification is the P0 baseline. A result is recorded for every selected
suite; failures remain failures, including unavailable host facilities.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import shlex
import hashlib
import os
from pathlib import Path
import subprocess
import signal
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("seed", type=Path)
parser.add_argument("--binary", type=Path, default=Path("build/rust/target/release/nupp-vm"))
parser.add_argument("--image", type=Path, help="execute a previously emitted corpus image")
parser.add_argument("--emitter", type=Path, help="reuse a previously emitted test compiler")
parser.add_argument("--class", dest="classification", default="portable")
parser.add_argument("--suite", action="append")
parser.add_argument("--unavailable-module", action="append", default=[],
                    help="leave a known migration dependency unresolved; affected suites fail at runtime")
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--jobs", type=int, default=2, help="independent VM processes (default: 2)")
parser.add_argument("--engine", choices=("rust", "threaded", "jit"), default="threaded")
parser.add_argument("--jit-compilation", choices=("eager", "on-demand"), default="eager")
parser.add_argument("--gc-stress", action="store_true")
parser.add_argument("--cli-image", type=Path, help="route every compiler subprocess through this VM root CLI image")
parser.add_argument("--cli-binary", type=Path,
                    help="runtime for compiler subprocesses, run without collector stress (default: --binary, stressed)")
parser.add_argument("--gc-interleave", action="store_true", help="step incremental collection on every allocation")
args = parser.parse_args()
assert args.jobs > 0, "jobs must be positive"
assert not (args.gc_stress and args.gc_interleave), "choose one collector stress mode"
root = Path.cwd()
binary = str(args.binary.resolve())
seed = str(args.seed.resolve())
args.output.mkdir(parents=True, exist_ok=True)
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


run = {"seed": seed, "binary": binary, "seedSha256": digest(seed), "binarySha256": digest(binary),
       "engine": args.engine, "gcStress": args.gc_stress, "gcInterleave": args.gc_interleave,
       "compilation": args.jit_compilation + " frames" if args.engine == "jit" else "none", "path": "", "timeoutSeconds": 600,
       "unavailableModules": args.unavailable_module}
(args.output / "run.json").write_text(json.dumps(run, indent=2) + "\n")
classification = json.loads(Path("native/crates/vm/tests/corpus-classification.json").read_text())
selected = [row for row in classification["suites"]
            if row["suite"].endswith("test") and
            (row["suite"] in args.suite if args.suite else row["class"] == args.classification)]
if args.suite:
    assert set(args.suite) == {row["suite"] for row in selected}, "suite not in the classification"
assert selected, "no suites selected"
env = dict(os.environ, NO_JIT="1", NUPP_CHECK_JOBS="1", NUPP_COMPILER_ROOT=str(root), PATH="")
for key in ("EMIT_SURVEY", "EMIT_STUBS", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_EAGER_FRAMES"):
    env.pop(key, None)
if args.cli_image:
    cli_binary = binary
    if args.cli_binary:
        # Collector stress verifies the suite's own VM. A compiler subprocess
        # is the product CLI, not the code under test: it drops the stress
        # settings it would otherwise inherit.
        args.output.mkdir(parents=True, exist_ok=True)
        wrapper = (args.output / "cli-runtime").resolve()
        wrapper.write_text("#!/bin/sh\nunset GC_STRESS GC_INTERLEAVE GC_ORACLE GC_QUARANTINE\nexec %s \"$@\"\n"
                           % shlex.quote(str(args.cli_binary.resolve())))
        wrapper.chmod(0o755)
        cli_binary = str(wrapper)
        run.update(cliBinary=str(args.cli_binary.resolve()), cliBinarySha256=digest(args.cli_binary))
    env.update(PATH=os.environ.get("PATH", ""), NUPP_VM_CLI_IMAGE=str(args.cli_image.resolve()), NUPP_VM_BINARY=cli_binary)
    run.update(path=env["PATH"], cliImage=str(args.cli_image.resolve()), cliImageSha256=digest(args.cli_image))
    (args.output / "run.json").write_text(json.dumps(run, indent=2) + "\n")
host_extras = [
    "nupp.compiler.hostservices", "nupp.compiler.fs", "nupp.compiler.project.projectconfig",
    "nupp.compiler.project.store", "nupp.compiler.project.fingerprint",
    "nupp.compiler.hash", "nupp.compiler.project.preludecache",
    "nupp.runtime.provider.nativeprocess",
]
extras = [row["suite"] for row in selected if row["suite"] not in args.unavailable_module] + host_extras
def emission_failure(problem):
    records = [dict(row, status="image-failed", error=problem[-12000:]) for row in selected]
    (args.output / "results.json").write_text(json.dumps(records, indent=2) + "\n")
    raise RuntimeError(problem[-12000:])


if args.image:
    image = args.image.resolve()
else:
    emitter = args.emitter.resolve() if args.emitter else args.output / "emitter.image"
    if not args.emitter:
        result = subprocess.run([binary, "run", seed, "nupp.tools.vm.project", "emit", str(root),
                                 "nupp.compiler.vm.corpus", ",".join(host_extras), "src,native/crates/vm/tests"],
                                env=env, capture_output=True, text=True, timeout=1800)
        if result.returncode != 0:
            emission_failure(result.stderr)
        emitter.write_text(json.loads(result.stdout))
    image = args.output / "corpus.image"
    with (args.output / "emit.json").open("w") as output, (args.output / "emit.log").open("w") as errors:
        emitted = subprocess.run([binary, "run", str(emitter), "nupp.compiler.vm.corpus", "emit", str(root),
                                  ",".join(extras), ",".join(args.unavailable_module)],
                                 env=env, stdout=output, stderr=errors, timeout=3600)
    if emitted.returncode != 0:
        emission_failure((args.output / "emit.log").read_text())
    image.write_text(json.loads((args.output / "emit.json").read_text()))
    (args.output / "emit.json").unlink()
    verified = subprocess.run([binary, "verify", str(image)], env=env, capture_output=True, text=True)
    if verified.returncode != 0:
        emission_failure(verified.stderr)
run.update(image=str(image), imageSha256=digest(image), selectedSuites=len(selected))
(args.output / "run.json").write_text(json.dumps(run, indent=2) + "\n")


def execute(row):
    suite = row["suite"]
    started = time.monotonic()
    execution_env = dict(env)
    execution_env.pop("NO_THREADED", None)
    if args.engine == "rust":
        execution_env["NO_THREADED"] = "1"
    elif args.engine == "jit":
        execution_env.pop("NO_JIT", None)
        execution_env["JIT_VERIFY"] = "1"
        if args.jit_compilation == "eager":
            execution_env["JIT_EAGER_FRAMES"] = "1"
    # One store per suite, kept between runs, as the Lua test runner gives each
    # shard one: a compiler a case starts in a fresh project then checks the
    # standard library it requires once rather than in every case. The stores
    # are stamped with the compiler that wrote them, so a new image misses.
    cache = root / "build" / ".nupp-corpus-cache" / suite
    cache.mkdir(parents=True, exist_ok=True)
    execution_env["NUPP_CACHE_DIR"] = str(cache)
    if args.gc_stress:
        execution_env.update(GC_STRESS="1", GC_ORACLE="1", GC_QUARANTINE="1")
    if args.gc_interleave:
        execution_env.update(GC_INTERLEAVE="1", GC_ORACLE="1", GC_QUARANTINE="1")
    process = subprocess.Popen([binary, "exec", str(image), "corpus-runner", suite], env=execution_env,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=os.name != "nt")
    try:
        stdout, stderr = process.communicate(timeout=600)
        status, timed_out = process.returncode, False
    except subprocess.TimeoutExpired:
        if os.name == "nt":
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], capture_output=True)
        else:
            os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        status, timed_out = None, True
    (args.output / f"{suite}.jsonl").write_bytes(stdout)
    (args.output / f"{suite}.log").write_bytes(stderr)
    records = []
    for line in stdout.splitlines():
        try:
            item = json.loads(line)
        except (ValueError, UnicodeError):
            continue
        if isinstance(item, dict) and item.get("suite") == suite:
            records.append(item)
    summary = next((line for line in reversed(records) if "total" in line), {})
    cases = [item for item in records if isinstance(item.get("ok"), bool)]
    passed = sum(item["ok"] for item in cases)
    # A case gated on a capability this runtime lacks reports not-executed with
    # the capability it declared unavailable; the runner counts it apart.
    gated = [item for item in cases if not item["ok"] and item.get("disposition") == "not-executed"
             and any(c.get("available") is False for c in (item.get("capabilities") or []))]
    failed = len(cases) - passed - len(gated)
    complete = summary.get("total", 0) > 0 and summary.get("total") == len(cases)
    complete = complete and summary.get("passed") == passed and summary.get("failed") == failed
    complete = complete and summary.get("notExecuted", 0) == len(gated)
    outcome = "timeout" if timed_out else "passed" if status == 0 and complete and failed == 0 else "failed"
    record = dict(row, status=outcome, exitStatus=status, passed=passed, failed=failed, total=len(cases),
                  notExecuted=[{"name": item["name"], "capabilities": [c.get("name") for c in item["capabilities"]
                                                                       if c.get("available") is False]}
                               for item in gated],
                  completed=complete, durationSeconds=round(time.monotonic() - started, 3))
    if outcome != "passed":
        record["error"] = stderr.decode("utf-8", errors="replace")[-8000:]
        record["failureSamples"] = [item for item in cases if item["ok"] is False and item not in gated][:8]
    return record


results = []
with ThreadPoolExecutor(max_workers=args.jobs) as pool:
    pending = [pool.submit(execute, row) for row in selected]
    for future in as_completed(pending):
        record = future.result()
        results.append(record)
        results.sort(key=lambda row: row["suite"])
        (args.output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
        print(f"{record['suite']}: {record['status']}", flush=True)
assert all(row["status"] == "passed" for row in results), "classified corpus failures; see results.json"
