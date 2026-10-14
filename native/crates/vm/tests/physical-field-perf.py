#!/usr/bin/env python3
"""Compare physical-field compilations using paired fresh processes."""
import argparse
import importlib.util
import json
from pathlib import Path
import platform
import re


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--baseline-binary", type=Path, help="optional previous runtime for total-change comparison")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pairs", type=int, default=7)
    parser.add_argument("--repeat", type=int, default=7)
    parser.add_argument("--margin", type=float, default=0.05)
    args = parser.parse_args()
    if args.pairs < 2 or args.repeat < 1 or not 0 < args.margin < 1:
        parser.error("need at least two pairs, one repeat, and a margin between zero and one")
    spec = importlib.util.spec_from_file_location("allocation_perf", Path(__file__).with_name("allocation-perf.py"))
    perf = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(perf)
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if (output / "results.json").exists():
        parser.error("results already exist; choose a fresh output directory")
    binary = str(args.binary.resolve())
    binaries = {"baseline": str((args.baseline_binary or args.binary).resolve()), "candidate": binary}
    images = {"baseline": args.baseline.resolve(), "candidate": args.candidate.resolve()}
    env = perf.clean_environment()
    env.pop("NUPP_NATIVE_DUMP", None)
    report = {
        "scope": "Physical scalar field access; identical authored source, two images; " + ("two runtimes" if args.baseline_binary else "one runtime"),
        "host": platform.platform(), "pairs": args.pairs, "repeat": args.repeat,
        "practicalMargin": args.margin, "metric": "warmMs (monotonic wall time; runner cpu_now uses Instant)",
        "binarySha256": {label: perf.digest(path) for label, path in binaries.items()},
        "imageSha256": {key: perf.digest(path) for key, path in images.items()},
        "cases": [], "status": "running",
    }

    def save():
        (output / "results.json").write_text(json.dumps(report, indent=2) + "\n")

    try:
        for case, expected in (("scalar", "-2500"), ("wide", "true"), ("rows", "-4096"), ("dynamic", "-2500")):
            samples = []
            item = {"name": case, "expected": expected, "pairs": samples}
            report["cases"].append(item)
            for pair in range(args.pairs):
                record = {}
                for label in (("baseline", "candidate") if pair % 2 == 0 else ("candidate", "baseline")):
                    command = [binaries[label], "run", str(images[label]), "physical.fields", case, "--repeat", str(args.repeat)]
                    result = perf.execute(command, env, output / f"{case}-{pair}-{label}", 180)
                    if result["exitStatus"] != 0 or result["output"].strip() != expected or result["warmMs"] is None:
                        raise RuntimeError(f"{case}/{label} failed: {result}")
                    stderr = Path(result["stderr"]).read_text()
                    allocated = re.search(r"objects live (\d+) allocated (\d+)", stderr)
                    if allocated:
                        result["firstCallLiveObjects"] = int(allocated[1])
                        result["loadAndFirstCallAllocatedObjects"] = int(allocated[2])
                    record[label] = result
                samples.append(record)
                save()
            item["warm"] = perf.comparison(samples, "warmMs", args.margin)
            item["peakRss"] = perf.comparison(samples, "peakRssBytes", args.margin)
            save()
            print(case, json.dumps(item["warm"]), flush=True)
        report["status"] = "passed"
    except BaseException:
        report["status"] = "failed"
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
