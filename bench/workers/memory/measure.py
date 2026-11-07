#!/usr/bin/env python3
"""Sample retained process memory after the benchmark's collection barriers."""

import argparse
import json
import platform
import statistics
import subprocess
import threading
from pathlib import Path


def sample(pid):
    rss = int(subprocess.check_output(["ps", "-o", "rss=", "-p", str(pid)], text=True).strip())
    flag = "-M" if platform.system() == "Darwin" else "-L"
    threads = subprocess.check_output(["ps", flag, "-o", "pid=", "-p", str(pid)], text=True)
    return {"rssBytes": rss * 1024, "threads": len(threads.splitlines())}


def run(binary):
    process = subprocess.Popen([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    watchdog = threading.Timer(300, process.kill)
    watchdog.start()
    snapshots = []
    try:
        for line in process.stdout:
            snapshot = json.loads(line)
            if snapshot["pid"] != process.pid:
                raise RuntimeError("The snapshot came from another process")
            snapshot.update(sample(process.pid))
            snapshots.append(snapshot)
        stderr = process.stderr.read()
        if process.wait() != 0:
            raise RuntimeError(stderr)
        if len(snapshots) != 4:
            raise RuntimeError(f"Expected four collection barriers, got {snapshots!r}")
        return snapshots
    finally:
        watchdog.cancel()
        if process.poll() is None:
            process.kill()
        process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before", type=Path)
    parser.add_argument("after", type=Path)
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.runs < 1:
        parser.error("--runs must be positive")
    measurements = []
    for iteration in range(args.runs):
        order = [("before", args.before), ("after", args.after)]
        if iteration % 2:
            order.reverse()
        for label, binary in order:
            print(f"{label} run {iteration + 1}", flush=True)
            measurements.append({"variant": label, "run": iteration + 1, "snapshots": run(binary.resolve())})
    medians = {}
    for label in ("before", "after"):
        selected = [entry for entry in measurements if entry["variant"] == label]
        medians[label] = []
        for index in range(4):
            rows = [entry["snapshots"][index] for entry in selected]
            medians[label].append({"phase": rows[0]["phase"], **{
                key: statistics.median(row[key] for row in rows)
                for key in ("rssBytes", "luaBytes", "threads")
            }})
    args.output.write_text(json.dumps({"platform": platform.platform(), "runs": measurements, "medians": medians}, indent=2) + "\n")


if __name__ == "__main__":
    main()
