#!/usr/bin/env python3
"""Compare frozen runtimes on the same synthetic 10,000-record full captures.

Capture samples within one process are not independent replicates. Statistical
comparisons use one p50, p99, or maximum per fresh process and pair those process
summaries. The first capture is retained. A separate prelude warms host caches,
but does not warm the workers or managed heaps of subsequent fresh processes.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import signal
import statistics
import subprocess
import sys
import time

MODES = ("observed", "threaded", "jit")
METRICS = ("p50_ms", "p99_ms", "max_ms")
# Two-sided 95% Student t critical values, indexed by degrees of freedom.
T95 = (0, 12.7062, 4.3027, 3.1824, 2.7764, 2.5706, 2.4469, 2.3646,
       2.3060, 2.2622, 2.2281, 2.2010, 2.1788, 2.1604, 2.1448, 2.1314,
       2.1199, 2.1098, 2.1009, 2.0930, 2.0860, 2.0796, 2.0739, 2.0687,
       2.0639, 2.0595, 2.0555, 2.0518, 2.0484, 2.0452, 2.0423)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def capture(stdout):
    value = json.loads(stdout)
    if not isinstance(value, str):
        raise ValueError("captureTimes must return a CSV string")
    values = [float(item) for item in value.split(",")]
    if len(values) != 102 or not all(math.isfinite(x) and x > 0 for x in values):
        raise ValueError("expected 101 positive finite capture times and snapshot size")
    samples, size = values[:101], values[101]
    if size <= 80000 or size != int(size):
        raise ValueError("unexpected synthetic snapshot size")
    return dict(capture_ms=samples, snapshot_bytes=int(size), first_ms=samples[0],
                p50_ms=statistics.median(samples), p99_ms=sorted(samples)[99],
                max_ms=max(samples))


def compare(pairs, metric, margin):
    ratios = [pair["candidate"][metric] / pair["baseline"][metric] for pair in pairs]
    logs = [math.log(ratio) for ratio in ratios]
    center = statistics.mean(logs)
    # Using df=30 above 31 forks is conservative, avoiding a stats dependency.
    half = T95[min(len(logs) - 1, 30)] * statistics.stdev(logs) / math.sqrt(len(logs))
    low, high = math.exp(center - half), math.exp(center + half)
    if high < 1 - margin:
        verdict = "improved"
    elif low > 1 + margin:
        verdict = "regressed"
    elif low >= 1 - margin and high <= 1 + margin:
        verdict = "unchanged"
    else:
        verdict = "inconclusive"
    return dict(paired_candidate_over_baseline=ratios, geometric_mean_ratio=math.exp(center),
                interval95=[low, high], observed_verdict=verdict,
                interval_method="paired process log ratios, Student t; normal log-ratio assumption; five forks give limited tail precision")


def git(*arguments):
    result = subprocess.run(["git", *arguments], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def load():
    try:
        return list(os.getloadavg())
    except (AttributeError, OSError):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=Path("/private/tmp/nupp-capture-perf/baseline"))
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--image", type=Path, default=Path("/private/tmp/nupp-supervision/supervision.image"))
    parser.add_argument("--output", type=Path, required=True, help="report JSON path or new evidence directory")
    parser.add_argument("--forks", type=int, default=5)
    parser.add_argument("--preludes", type=int, default=1, help="separate untimed capture processes per executable and mode")
    parser.add_argument("--mode", choices=MODES, action="append")
    parser.add_argument("--margin", type=float, default=.05)
    parser.add_argument("--timeout", type=float, default=10, help="per-process seconds; default bounds each pair to 20 seconds")
    parser.add_argument("--baseline-revision", default="unknown; binary hash is authoritative")
    parser.add_argument("--candidate-revision", default="unknown; binary hash is authoritative")
    parser.add_argument("--host-load-note", action="append", default=[])
    parser.add_argument("--confirmed-quiet", action="store_true", help="caller confirms competing jobs/profilers were stopped")
    parser.add_argument("--allow-snapshot-size-change", action="store_true", help="record known saved-runtime metadata changes instead of rejecting unequal sizes")
    args = parser.parse_args()
    if args.forks < 5 or args.preludes < 0 or not 0 < args.margin < 1 or args.timeout <= 0:
        parser.error("require >=5 forks, >=0 preludes, 0<margin<1 and positive timeout")
    destination = args.output.resolve()
    report_path = destination if destination.suffix == ".json" else destination / "results.json"
    output = destination.with_suffix("") if destination.suffix == ".json" else destination
    output.mkdir(parents=True, exist_ok=True)
    if report_path.exists():
        parser.error("output report already exists; use a fresh destination")
    binaries = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    image = args.image.resolve()
    modes = list(dict.fromkeys(args.mode or MODES))
    report = dict(schema_version=1, status="running", fixture="10,000 Entity records; 101 full captures without advancing gameplay",
                  scope="Synthetic supervisor capture, serialization and transfer; not Tecs, deltas, dirty pages or replay",
                  timestamp_utc=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                  command=[sys.executable, *sys.argv], logs_directory=str(output), harness_sha256=digest(Path(__file__)), platform=platform.platform(), cpu_count=os.cpu_count(),
                  source_revision_at_measurement=git("rev-parse", "HEAD"),
                  source_status_at_measurement=git("status", "--short"),
                  source_patch_sha256=hashlib.sha256((git("diff", "--binary") or "").encode()).hexdigest(),
                  image=dict(path=str(image), sha256=digest(image)), binaries={}, modes={},
                  forks=args.forks, preludes=args.preludes, practical_margin=args.margin,
                  snapshot_size_policy="record known runtime metadata changes" if args.allow_snapshot_size_change else "equal baseline and candidate sizes required",
                  primary_metric="p99_ms", pause_gate=dict(p99_ms_below=2, maximum_ms_below=5),
                  host=dict(confirmed_quiet=args.confirmed_quiet, load_before=load(), notes=args.host_load_note),
                  timing_scope="VM os.clock wall milliseconds; first capture included; separate-process prelude cannot warm measured heaps or worker JITs",
                  inference_scope="Only fresh processes are replicates; 101 within-process captures are not 101 independent trials")
    for label, binary in binaries.items():
        report["binaries"][label] = dict(path=str(binary), sha256=digest(binary), revision=getattr(args, label + "_revision"))

    def save():
        report_path.write_text(json.dumps(report, indent=2) + "\n")

    def run(label, binary, mode, function):
        env = dict(os.environ)
        for name in ("NO_JIT", "NO_THREADED", "JIT_THRESHOLD", "JIT_ONLY", "JIT_SKIP", "JIT_LIMIT", "JIT_OPT", "JIT_VERIFY", "JIT_REGALLOC",
                     "GC_STRESS", "GC_ORACLE", "GC_QUARANTINE", "GC_INTERLEAVE", "NUPP_ALLOCATION_STATS", "OP_STATS", "IC_STATS", "SLOT_STATS", "TRACE_CALLS", "TRACE_OPS"):
            env.pop(name, None)
        settings = {"NO_AOT": "1"}
        if mode != "jit":
            settings["NO_JIT"] = "1"
        if mode == "observed":
            settings["NO_THREADED"] = "1"
        env.update(settings)
        command = [str(binary), "run", str(image), "main", function]
        record = dict(command=command, environment=settings, load_before=load())
        started = time.monotonic()
        process = subprocess.Popen(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(timeout=args.timeout)
        except BaseException:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
            (output / (label + ".stdout")).write_text(stdout)
            (output / (label + ".stderr")).write_text(stderr)
            raise
        record.update(wall_seconds=time.monotonic() - started, exit_status=process.returncode, load_after=load(), stdout_log=label + ".stdout", stderr_log=label + ".stderr")
        (output / record["stdout_log"]).write_text(stdout)
        (output / record["stderr_log"]).write_text(stderr)
        if process.returncode:
            raise RuntimeError(f"{label}: exit {process.returncode}: {stderr[-4000:]}")
        if mode == "jit" and "jit:" not in stderr:
            raise RuntimeError(f"{label}: no JIT execution route evidence in stderr")
        if function == "run":
            if json.loads(stdout) != 42:
                raise ValueError(f"{label}: correctness oracle expected 42")
            record["correctness"] = "passed"
        else:
            record.update(capture(stdout))
        return record

    save()
    try:
        # Complete all correctness checks before collecting any duration samples.
        for mode in modes:
            data = dict(correctness={}, preludes=[], pairs=[])
            report["modes"][mode] = data
            for label, binary in binaries.items():
                data["correctness"][label] = run(mode + "-" + label + "-correctness", binary, mode, "run")
                save()
        for mode in modes:
            data = report["modes"][mode]
            for prelude in range(args.preludes):
                for label, binary in binaries.items():
                    record = run(f"{mode}-{label}-prelude-{prelude}", binary, mode, "captureTimes")
                    data["preludes"].append(dict(binary=label, **record))
                    save()
            for index in range(args.forks):
                order = ["baseline", "candidate"] if index % 2 == 0 else ["candidate", "baseline"]
                pair = dict(index=index, order=order)
                data["pairs"].append(pair)
                for label in order:
                    pair[label] = run(f"{mode}-pair-{index}-{label}", binaries[label], mode, "captureTimes")
                    save()
                pair["snapshot_bytes_delta"] = pair["candidate"]["snapshot_bytes"] - pair["baseline"]["snapshot_bytes"]
                if pair["snapshot_bytes_delta"] and not args.allow_snapshot_size_change:
                    raise ValueError(f"{mode} pair {index}: snapshot size changed by {pair['snapshot_bytes_delta']} bytes")
                print(f"{mode} pair {index + 1}/{args.forks}: p99 {pair['baseline']['p99_ms']:.3f} -> {pair['candidate']['p99_ms']:.3f} ms", flush=True)
            data["comparisons"] = {metric: compare(data["pairs"], metric, args.margin) for metric in METRICS}
            data["summaries"] = {}
            for label in binaries:
                samples = [pair[label] for pair in data["pairs"]]
                data["summaries"][label] = {
                    "median_process_metrics": {metric: statistics.median(row[metric] for row in samples) for metric in METRICS},
                    "pause_gate_all_processes_pass": all(row["p99_ms"] < 2 and row["max_ms"] < 5 for row in samples),
                    "worst_p99_ms": max(row["p99_ms"] for row in samples),
                    "worst_max_ms": max(row["max_ms"] for row in samples),
                    "snapshot_bytes": sorted({row["snapshot_bytes"] for row in samples}),
                }
            data["duration_verdict"] = data["comparisons"]["p99_ms"]["observed_verdict"] if args.confirmed_quiet else "provisional"
            save()
        for label, binary in binaries.items():
            if digest(binary) != report["binaries"][label]["sha256"]:
                raise ValueError(f"{label} binary changed during measurement")
        if digest(image) != report["image"]["sha256"]:
            raise ValueError("fixture image changed during measurement")
        report["frozen_artifact_hashes_verified_after_measurement"] = True
        report["host"]["load_after"] = load()
        report["pause_gate"]["observed_pass"] = all(data["summaries"]["candidate"]["pause_gate_all_processes_pass"] for data in report["modes"].values())
        report["pause_gate"]["acceptance"] = "provisional" if not args.confirmed_quiet else "passed" if report["pause_gate"]["observed_pass"] else "failed"
        report["status"] = "completed" if args.confirmed_quiet else "completed-provisional-host-load"
        save()
        print(f"Capture comparison {report['status']}; pause gate {report['pause_gate']['acceptance']}", flush=True)
    except BaseException as error:
        report.update(status="failed", error=str(error))
        report["host"]["load_after"] = load()
        save()
        raise


if __name__ == "__main__":
    main()
