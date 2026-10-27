#!/usr/bin/env python3
"""Compare frozen VM binaries in serial, alternating process pairs.

Images and inputs must be emitted before this driver starts. Timing has no GC
stress, counters, or sampling profiler. Optional diagnostic processes run after
all timing pairs and retain their separate raw logs and heap metrics.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, TimeoutError as WaitTimeout
from contextlib import contextmanager
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import signal
import statistics
import subprocess
import tempfile
import time


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


@contextmanager
def isolated_project_cache(project_cache, output, label):
    """Yield a fresh project cache, then archive it and restore the original.

    Use around one binary's cold and warm calls. The original directory or
    symlink is renamed, never copied, followed, deleted, or overwritten. All
    moves stay on one filesystem. This helper also serves single-binary gates.
    """
    # Resolve parent links, but preserve the cache itself if it is a symlink.
    requested = Path(os.path.abspath(project_cache))
    cache = requested.parent.resolve() / requested.name
    output = Path(output).resolve()
    cwd = Path.cwd().resolve()
    resolved_cache = cache.resolve()
    if (cache == cwd or cache in cwd.parents or cache == output or cache in output.parents or output in cache.parents
            or resolved_cache == output or resolved_cache in output.parents or output in resolved_cache.parents):
        raise ValueError("project cache must not contain the working directory or overlap the output directory")
    if not cache.parent.is_dir() or not output.is_dir():
        raise ValueError("project cache parent and output directory must already exist")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", label):
        raise ValueError("cache label must contain only letters, digits, underscores, and hyphens")
    if cache.parent.stat().st_dev != output.stat().st_dev:
        raise ValueError("cache preservation requires project cache and output on the same filesystem")
    existed = os.path.lexists(cache)
    if existed and not cache.is_symlink() and not cache.is_dir():
        raise ValueError("project cache must be a directory or symlink")
    archive = Path(tempfile.mkdtemp(prefix="project-cache-" + label + "-", dir=output))
    original, generated = archive / "original", archive / "generated"
    journal = archive / "state.json"
    state = {"projectCache": str(cache), "original": str(original) if existed else None,
             "generated": str(generated), "status": "preparing"}

    def save():
        journal.write_text(json.dumps(state, indent=2) + "\n")

    save()
    moved = False
    created = False
    try:
        if existed:
            cache.rename(original)
            moved = True
        cache.mkdir()
        created = True
        state["status"] = "isolated"
        save()
        yield cache
    finally:
        # A failed command still has useful cache artifacts. Keep them and
        # restore the exact original entry, including a dangling symlink.
        try:
            if (moved or created) and os.path.lexists(cache):
                if os.path.lexists(generated):
                    raise RuntimeError("generated cache archive unexpectedly exists: " + str(generated))
                cache.rename(generated)
            if moved:
                if os.path.lexists(cache):
                    raise RuntimeError("refusing to replace an unexpected cache entry: " + str(cache))
                original.rename(cache)
            state["status"] = "restored"
            save()
        except BaseException as error:
            raise RuntimeError(f"cache preservation failed; inspect {cache}, {original}, and journal {journal}") from error


def clean_environment():
    env = dict(os.environ)
    for key in list(env):
        if key.startswith(("GC_", "JIT_", "NO_JIT", "NO_THREADED", "NUPP_ALLOCATION_")) or key in (
            "TABLE_STATS", "BUILTIN_STATS", "OP_STATS", "SLOT_STATS", "IC_STATS",
            "NO_PROBE", "NO_AOT", "NO_SLOT_GUARD", "NO_DIRECT", "SIMD_INTERPRET",
            "TRACE_CALLS", "TRACE_OPS", "NUPP_NATIVE_DUMP", "SLOT_STATS_SITES",
            "EMIT_STUBS", "EMIT_SURVEY", "NUPP_VM_CLI_IMAGE", "NUPP_CACHE_DIR",
        ):
            env.pop(key, None)
    return env


def output_value(stdout):
    # Keep every application output line. Only the runner's timing line varies.
    return "\n".join(line for line in stdout.splitlines()
                     if not re.fullmatch(r"median [\d.]+ ms over \d+\s+min [\d.]+ ms", line))


def peak_rss(raw, system):
    # wait4 returns bytes on macOS and KiB on Linux.
    return int(raw) if system == "Darwin" else int(raw) * 1024


def comparison(pairs, metric, margin):
    values = [(pair["baseline"][metric], pair["candidate"][metric]) for pair in pairs]
    if any(a is None or b is None or a <= 0 or b <= 0 for a, b in values):
        return {"verdict": "unavailable"}
    logs = [math.log(a / b) for a, b in values]
    rng = random.Random(4719)
    boot = sorted(math.exp(statistics.mean(rng.choices(logs, k=len(logs)))) for _ in range(10000))
    interval = [boot[250], boot[9749]]
    low, high = 1 / (1 + margin), 1 / (1 - margin)
    verdict = ("improved" if interval[0] > high else "regressed" if interval[1] < low
               else "unchanged" if interval[0] >= low and interval[1] <= high else "inconclusive")
    return {"baselineMedian": statistics.median(a for a, _ in values),
            "candidateMedian": statistics.median(b for _, b in values),
            "baselineOverCandidate": math.exp(statistics.mean(logs)),
            "pairedBootstrap95": interval, "verdict": verdict}


def execute(command, env, stem, timeout, measured=True):
    system = platform.system()
    if system not in ("Darwin", "Linux"):
        raise RuntimeError("RSS measurement currently supports Darwin and Linux only")
    timed_out = False
    # A direct wait4 owns this child's status and rusage. RUSAGE_CHILDREN in
    # this long-lived Python parent would mix the RSS of earlier processes.
    # Files avoid pipe backpressure and retain partial output after a timeout.
    with stem.with_suffix(".stdout").open("w") as stdout_file, stem.with_suffix(".stderr").open("w") as stderr_file:
        with ThreadPoolExecutor(max_workers=1) as waiter:
            started = time.perf_counter()
            process = subprocess.Popen(command, env=env, stdout=stdout_file, stderr=stderr_file, start_new_session=True)
            future = waiter.submit(os.wait4, process.pid, 0)
            try:
                _, status, usage = future.result(timeout=timeout)
            except WaitTimeout:
                timed_out = True
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                _, status, usage = future.result()
            except BaseException:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                _, status, _ = future.result()
                process.returncode = os.waitstatus_to_exitcode(status)
                raise
            wall = (time.perf_counter() - started) * 1000
            process.returncode = os.waitstatus_to_exitcode(status)
    stdout = stem.with_suffix(".stdout").read_text()
    stderr = stem.with_suffix(".stderr").read_text()
    record = {"command": command, "exitStatus": process.returncode, "timedOut": timed_out,
              "stdout": str(stem.with_suffix(".stdout")), "stderr": str(stem.with_suffix(".stderr")),
              "output": output_value(stdout)}
    if measured:
        record.update(wallMs=wall, peakRssBytes=peak_rss(usage.ru_maxrss, system))
        for name, pattern in (("warmMs", r"median ([\d.]+) ms"),
                              ("firstMs", r"first call ([\d.]+) ms"),
                              ("loadMs", r"load ([\d.]+) ms")):
            match = re.search(pattern, stdout + "\n" + stderr)
            record[name] = float(match[1]) if match else None
    else:
        record["heapMetrics"] = [json.loads(line[len("allocation_stats "):])
                                 for line in stderr.splitlines() if line.startswith("allocation_stats ")]
        record["globalMetrics"] = [json.loads(line[len("global_allocation_stats "):])
                                   for line in stderr.splitlines() if line.startswith("global_allocation_stats ")]
    return record


def workloads(args):
    if args.repository_only:
        return []
    rows = []
    for kind, image, function, sources in (
        ("checker", args.check_image, "check", [args.small_input, Path("src/nupp/compiler/syntax/lexer.nupp")]),
        ("parser", args.parser_image, "parse", [args.small_input, Path("src/nupp/compiler/syntax/parser.nupp")]),
    ):
        for index, source in enumerate(sources):
            rows.append({"name": kind + ("-small" if index == 0 else "-source"), "metric": "warmMs",
                         "argv": ["run", str(image.resolve()), "nupp.bench." + ("checkbench" if kind == "checker" else "parsebench"),
                                  function, "@" + str(source.resolve()), "--setup", "setup", "--repeat", str(args.repeat)],
                         "env": {}, "files": [image, source]})
    if args.cli_image:
        for name, command in (("version", ["version", "--json"]), ("help", ["--help"])):
            rows.append({"name": "cli-" + name, "metric": "wallMs", "launcher": True,
                         "argv": command, "files": [args.cli_image, Path("bin/nupp")],
                         "env": {"NO_JIT": "1", "NUPP_VM_CLI_IMAGE": str(args.cli_image.resolve()),
                                 "NUPP_COMPILER_ROOT": str(Path.cwd()), "NUPP_CHECK_JOBS": "1"}})
    if args.tasks_image:
        for function, expected in (("cpu", "2000001000000"), ("worker", "2000001000000"),
                                   ("checkpoints", "10000"), ("channels", "50005000"), ("coroutines", "50005000")):
            rows.append({"name": "tasks-" + function, "metric": "warmMs", "expected": expected,
                         "argv": ["run", str(args.tasks_image.resolve()), "perf", function, "--tasks", "--repeat", str(args.repeat)],
                         "env": {}, "files": [args.tasks_image]})
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--check-image", type=Path)
    parser.add_argument("--parser-image", type=Path)
    parser.add_argument("--small-input", type=Path, default=Path("native/crates/vm/tests/project/lib/demo/math.nupp"),
                        help="pinned small source; defaults to tracked demo.math fixture")
    parser.add_argument("--cli-image", type=Path)
    parser.add_argument("--tasks-image", type=Path, help="pre-emitted tasks-project entry perf")
    parser.add_argument("--output", type=Path, required=True, help="new directory; never overwrites an earlier run")
    parser.add_argument("--forks", type=int, default=7)
    parser.add_argument("--repeat", type=int, default=7)
    parser.add_argument("--margin", type=float, default=0.05)
    parser.add_argument("--timeout", type=float, default=600)
    parser.add_argument("--diagnostics", action="store_true", help="separate untimed TABLE_STATS and allocation-metrics runs")
    parser.add_argument("--diagnostics-only", action="store_true", help="collect counters only; no duration verdict")
    parser.add_argument("--repository-check", action="store_true", help="one cold/warm repository acceptance run per binary, no speed verdict")
    parser.add_argument("--repository-only", action="store_true", help="only the cold/warm repository gate; requires --cli-image")
    parser.add_argument("--project-cache", type=Path, default=Path("build/cache"),
                        help="actual project cache to preserve and isolate during repository checking")
    parser.add_argument("--case", action="append", help="select one or more workload names")
    args = parser.parse_args()
    if args.forks < 7 or args.repeat < 7 or not 0 < args.margin < 1 or args.timeout <= 0:
        parser.error("require at least seven forks/repeats, 0 < margin < 1, and positive timeout")
    if not args.repository_only and (not args.check_image or not args.parser_image):
        parser.error("--check-image and --parser-image are required unless --repository-only")
    if (args.repository_check or args.repository_only) and not args.cli_image:
        parser.error("repository checking requires --cli-image")
    if args.repository_only and (args.case or args.diagnostics or args.diagnostics_only):
        parser.error("repository-only is an acceptance gate; use separate diagnostic processes")
    rows = workloads(args)
    if args.case:
        unknown = set(args.case) - {row["name"] for row in rows}
        if unknown:
            parser.error("unknown or unconfigured cases: " + ", ".join(sorted(unknown)))
        rows = [row for row in rows if row["name"] in args.case]
    files = {p.resolve() for row in rows for p in row["files"]} | {args.baseline.resolve(), args.candidate.resolve()}
    if args.repository_check or args.repository_only:
        files.update((args.cli_image.resolve(), Path("bin/nupp").resolve(), Path("nupp.lua").resolve()))
    hashes = {str(path): digest(path) for path in sorted(files)}
    args.output.mkdir(parents=True, exist_ok=False)
    report = {"host": platform.platform(), "revision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
              "hashes": hashes, "forks": args.forks, "repeat": args.repeat, "practicalMargin": args.margin,
              "baseline": str(args.baseline.resolve()), "candidate": str(args.candidate.resolve()),
              "scope": "Serial alternating process pairs over identical frozen images and sources. Warm samples exclude setup; wall time and peak RSS include startup and compilation. CLI samples include the launcher and use the interpreted root image. File-system caches are not flushed. Diagnostics are separate processes. Paired bootstrap describes process pairs, not repeats within one process.",
              "status": "running", "results": [], "diagnostics": [], "repository": [],
              "projectCache": str(args.project_cache.absolute()) if args.repository_check or args.repository_only else None}
    target = args.output / "results.json"

    def save():
        target.write_text(json.dumps(report, indent=2) + "\n")

    def run(row, role, suffix, measured):
        binary = str(getattr(args, role).resolve())
        env = dict(clean_environment(), **row["env"], NUPP_VM_BINARY=binary)
        if not measured:
            env.update(TABLE_STATS="1", NUPP_ALLOCATION_STATS="1")
        command = [str(Path("bin/nupp").resolve()) if row.get("launcher") else binary, *row["argv"]]
        return execute(command, env, args.output / (row["name"] + "-" + role + "-" + suffix), args.timeout, measured)

    def validate(record, expected, row):
        if record["exitStatus"] != 0 or record["timedOut"]:
            raise RuntimeError("workload failed; see " + record["stderr"])
        if not record["output"] or expected is not None and record["output"] != expected:
            raise RuntimeError("workload output changed; see " + record["stdout"])
        if "wallMs" in record and (record["peakRssBytes"] is None or record[row["metric"]] is None):
            raise RuntimeError("required measurement missing; see " + record["stderr"])

    save()
    try:
        expected_by_case = {}
        if not args.diagnostics_only:
            for row in rows:
                result = {"name": row["name"], "primaryMetric": row["metric"], "pairs": []}
                report["results"].append(result)
                expected = row.get("expected")
                for fork in range(args.forks):
                    pair = {}
                    result["pairs"].append(pair)
                    for role in (("baseline", "candidate") if fork % 2 == 0 else ("candidate", "baseline")):
                        pair[role] = run(row, role, str(fork), True)
                        save()
                        validate(pair[role], expected, row)
                        expected = pair[role]["output"]
                    print(f"{row['name']}: pair {fork + 1}/{args.forks} passed", flush=True)
                expected_by_case[row["name"]] = expected
                result["comparisons"] = {metric: comparison(result["pairs"], metric, args.margin)
                                         for metric in ("warmMs", "firstMs", "wallMs", "peakRssBytes")}
                save()
        if args.diagnostics or args.diagnostics_only:
            for row in rows:
                expected = expected_by_case.get(row["name"], row.get("expected"))
                for role in ("baseline", "candidate"):
                    record = run(row, role, "diagnostic", False)
                    report["diagnostics"].append({"name": row["name"], "role": role, **record})
                    save()
                    validate(record, expected, row)
                    if not record["heapMetrics"]:
                        raise RuntimeError("diagnostics require binaries built with allocation-metrics; see " + record["stderr"])
                    if not record["globalMetrics"]:
                        raise RuntimeError("global allocator metrics missing; see " + record["stderr"])
                    heap_ids = [metric["heap_id"] for metric in record["heapMetrics"]]
                    if len(heap_ids) != len(set(heap_ids)):
                        raise RuntimeError("heap metrics emitted more than once; see " + record["stderr"])
                    if row["name"] == "tasks-worker" and len(heap_ids) < 2:
                        raise RuntimeError("worker heap metrics missing; see " + record["stderr"])
                    expected = record["output"]
        if args.repository_check or args.repository_only:
            diagnostics = None
            total_modules = None
            for role in ("baseline", "candidate"):
                binary = str(getattr(args, role).resolve())
                cache = (args.output / ("repository-cache-" + role)).resolve()
                cache.mkdir()
                env = dict(clean_environment(), NO_JIT="1", NUPP_CHECK_JOBS="1", NO_COLOR="1",
                           NUPP_VM_BINARY=binary, NUPP_VM_CLI_IMAGE=str(args.cli_image.resolve()),
                           NUPP_CACHE_DIR=str(cache), NUPP_COMPILER_ROOT=str(Path.cwd()))
                with isolated_project_cache(args.project_cache, args.output, role):
                    for phase in ("cold", "warm"):
                        record = execute([str(Path("bin/nupp").resolve()), "check", "--json"], env,
                                         args.output / ("repository-" + role + "-" + phase), args.timeout)
                        record.update(role=role, phase=phase, verdict="acceptance only; one observation")
                        report["repository"].append(record)
                        save()
                        validate(record, None, {"metric": "wallMs"})
                        payload = json.loads(record["output"])
                        timing = payload["timing"]
                        compiled, reused = timing["compiledModules"], timing["reusedModules"]
                        if not payload.get("ok") or any(d.get("severity", "error") == "error" for d in payload["diagnostics"]):
                            raise RuntimeError("repository check failed: " + record["stdout"])
                        if diagnostics is not None and diagnostics != payload["diagnostics"]:
                            raise RuntimeError("repository diagnostics changed: " + record["stdout"])
                        diagnostics = payload["diagnostics"]
                        if phase == "cold" and (compiled <= 0 or reused != 0):
                            raise RuntimeError("repository cold run was not fully cold: " + record["stdout"])
                        if phase == "warm" and (compiled != 0 or reused != total_modules):
                            raise RuntimeError("repository warm run did not reuse every module: " + record["stdout"])
                        if total_modules is not None and compiled + reused != total_modules:
                            raise RuntimeError("repository module inventory changed: " + record["stdout"])
                        total_modules = compiled + reused
                        record["moduleCounts"] = {"compiled": compiled, "reused": reused}
                        save()
                        print(f"repository {role} {phase}: {compiled} compiled, {reused} reused", flush=True)
        if any(digest(path) != sha for path, sha in hashes.items()):
            raise RuntimeError("a frozen artifact changed during the run")
        report["status"] = "complete"
        # This harness does not establish correctness under GC stress, repository
        # checking, supported-target builds, or embedding/worker teardown limits.
        report["runtimeAcceptance"] = "not established by this measurement alone"
    except Exception as error:
        report.update(status="failed", error=str(error))
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
