#!/usr/bin/env python3
"""Compare frozen compiler runtimes on macOS, with matching worker engines.

Run from a quiet checkout; no other compiler command may use ROOT while a
check is measured. This script never builds or downloads anything. A LuaJIT
comparison requires that ROOT/build already contains the current compiler.

Example: compiler-frame-perf.py --case emit --baseline OLD --candidate NEW \
    --image ROOT.image --root CHECKOUT --output NEW_DIRECTORY --repeats 3

Checks preserve the original project state, isolate it per runtime, and keep
shared stores separate too. Warm checks must report zero compiled modules.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import statistics
import subprocess
import time


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--case", choices=["emit", "lexer", "cold-check", "warm-check"], required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--luajit", type=Path)
    parser.add_argument("--luajit-once", action="store_true")
    args = parser.parse_args()
    if platform.system() != "Darwin":
        parser.error("this harness reads macOS /usr/bin/time -l counters")
    if args.repeats < 1 or args.jobs < 1:
        parser.error("repeats and jobs must be positive")
    root, image, out = args.root.resolve(), args.image.resolve(), args.output.resolve()
    runtimes = {name: path.resolve() for name, path in [("baseline", args.baseline), ("candidate", args.candidate)]}
    for path in [image, *runtimes.values()]:
        if not path.is_file():
            parser.error(f"missing input: {path}")
    lua_prefix = None
    if args.luajit:
        args.luajit = args.luajit.resolve()
        lua_prefix = args.luajit.parent.parent
        if not (root / "build/nupp/tools/main.lua").is_file():
            parser.error("build the matching LuaJIT compiler before measuring")
        if not (root / "build/lib/libnupp_native_dev.dylib").is_file():
            parser.error("the LuaJIT worker needs ROOT/build/lib/libnupp_native_dev.dylib")
        if platform.machine() == "arm64":
            receipt = lua_prefix / ".nupp-runtime-patch"
            patch = root / "scripts/patches/luajit.patch"
            if not receipt.is_file() or not patch.is_file():
                parser.error("pass the cached LuaJIT build matching ROOT's runtime patch")
            expected = "\n".join(subprocess.check_output(["cksum"], input=p.read_bytes()).decode().strip()
                                 for p in [patch, args.luajit])
            if receipt.read_text().strip() != expected:
                parser.error("the selected LuaJIT does not match ROOT's runtime patch")
    out.mkdir(parents=True, exist_ok=False)
    base = dict(os.environ, NO_JIT="1", NUPP_COMPILER_ROOT=str(root),
                NUPP_VM_AUTO_REBUILD="0", CARGO_NET_OFFLINE="true", NUPP_CHECK_JOBS=str(args.jobs))
    for name in ["NUPP_ENGINE", "NUPP_VM_CLI_IMAGE", "NUPP_VM_BINARY", "NUPP_VM_EMIT_CACHE",
                 "NUPP_CACHE_DIR", "JIT_THRESHOLD", "JIT_SPECIALIZE", "JIT_SPEC_FRAMES", "NO_AOT"]:
        base.pop(name, None)
    report = dict(case=args.case, imageSha256=sha(image), root=str(root), jobs=args.jobs,
                  binaries={name: dict(path=str(path), sha256=sha(path)) for name, path in runtimes.items()},
                  practicalMargin=0.05, results=[])
    if args.luajit:
        report["binaries"]["luajit"] = dict(path=str(args.luajit), sha256=sha(args.luajit))
    def save():
        (out / "results.json").write_text(json.dumps(report, indent=2) + "\n")
    def environment(label, iteration):
        env = dict(base)
        if label == "luajit":
            provider = str(root / "build/lib/libnupp_native_dev.dylib")
            env.update(NUPP_ENGINE="luajit", PATH=str(args.luajit.parent) + os.pathsep + env.get("PATH", ""),
                       NUPP_NATIVE_LIBRARY=provider, NUPP_LAUNCHER_NATIVE_LIBRARY=provider,
                       NUPP_LAUNCHER_NATIVE_ROOT=str(root), NUPP_LAUNCHER_TOOLCHAIN_PREFIX=str(lua_prefix.parent))
            env["NUPP_LAUNCHER_TOOLCHAIN_KEY"] = "|".join([str(root), *(env.get(k, "") for k in
                                                    ["NUPP_CC", "NUPP_CXX", "NUPP_TOOLCHAIN_DIR"])])
        else:
            env.update(NUPP_VM_CLI_IMAGE=str(image), NUPP_VM_BINARY=str(runtimes[label]))
        suffix = f"-{iteration}" if args.case == "cold-check" else ""
        env["NUPP_CACHE_DIR"] = str(out / ("cache-" + label + suffix))
        return env
    def command(label, iteration):
        cli = ([str(args.luajit), "-e", "package.path=" + json.dumps(str(root / "build/?.lua;"), ensure_ascii=False)
                + " .. package.path", str(root / "build/nupp/tools/main.lua")]
               if label == "luajit" else [str(runtimes[label]), "exec", str(image), "nupp.tools.vm.root"])
        if args.case != "emit":
            return [*cli, "check", "--json", *(["src/nupp/compiler/syntax/lexer.nupp"] if args.case == "lexer" else [])]
        dest = out / f"{iteration}-{label}.image"
        if label == "luajit":
            return [*cli, "run", "native/crates/vm/emit/root.lua", str(root), str(dest)]
        text = (root / "src/nupp/tools/vm/project.nupp").read_text()
        extras = "".join(re.findall(r'"([^\"]*)"', re.search(r"project.ROOT_EXTRAS = (.*?)\n\n", text, re.S)[1]))
        return [str(runtimes[label]), "run", str(image), "nupp.tools.vm.project", "emit", str(root),
                "nupp.tools.vm.root", extras, "--output", str(dest)]
    state = root / "build/cache/checks.buf"
    lock = state.parent / ".compiler-frame-perf"
    checking = args.case != "emit"
    original_state = sha(state) if checking and state.exists() else None
    if checking:
        report["originalStateSha256"] = original_state
        state.parent.mkdir(parents=True, exist_ok=True)
        lock.mkdir()
        (lock / "journal.json").write_text(json.dumps(dict(output=str(out), original=state.exists())) + "\n")
        if state.exists():
            os.replace(state, lock / "original.buf")
    warmed = set()
    try:
        for iteration in range(args.repeats):
            labels = ["baseline", *(["luajit"] if args.luajit else []), "candidate"]
            if iteration % 2:
                labels.reverse()
            if iteration and args.luajit_once:
                labels = [label for label in labels if label != "luajit"]
            for label in labels:
                kept = out / ("state-" + label + ".buf")
                if checking:
                    if state.exists():
                        state.unlink()  # Only the immediately preceding benchmark state.
                    if args.case != "cold-check" and kept.exists():
                        shutil.copy2(kept, state)
                cmd, env = command(label, iteration), environment(label, iteration)
                if checking and args.case != "cold-check" and label not in warmed:
                    warm = subprocess.run(cmd, cwd=root, env=env, capture_output=True, check=True)
                    (out / f"warmup-{label}.stdout").write_bytes(warm.stdout)
                    (out / f"warmup-{label}.stderr").write_bytes(warm.stderr)
                    warmed.add(label)
                before = os.getloadavg()
                done = subprocess.run(["/usr/bin/time", "-l", *cmd], cwd=root, env=env, capture_output=True)
                prefix = out / f"{iteration}-{label}"
                prefix.with_suffix(".stdout").write_bytes(done.stdout)
                prefix.with_suffix(".stderr").write_bytes(done.stderr)
                stderr = done.stderr.decode(errors="replace")
                record = dict(label=label, repeat=iteration, status=done.returncode,
                              command=cmd, loadBefore=before, loadAfter=os.getloadavg())
                times = re.search(r"([\d.]+) real\s+([\d.]+) user\s+([\d.]+) sys", stderr)
                if times:
                    record.update(zip(["real", "user", "sys"], map(float, times.groups())))
                for metric in ["instructions retired", "cycles elapsed", "maximum resident set size"]:
                    match = re.search(r"(\d+)\s+" + metric, stderr)
                    if match:
                        record[metric] = int(match[1])
                report["results"].append(record)
                save()
                print(json.dumps(record), flush=True)
                if done.returncode:
                    raise RuntimeError(stderr[-4000:])
                if checking:
                    result = json.loads(done.stdout)
                    assert result["ok"], result
                    record["timing"] = result["timing"]
                    if args.case != "cold-check":
                        assert result["timing"]["compiledModules"] == 0, result["timing"]
                    if state.exists():
                        shutil.copy2(state, kept)
                else:
                    record["outputSha256"] = sha(out / f"{iteration}-{label}.image")
                    assert len({r["outputSha256"] for r in report["results"] if "outputSha256" in r}) == 1
                save()
    finally:
        if checking:
            if (lock / "original.buf").exists():
                os.replace(lock / "original.buf", state)
            elif state.exists():
                state.unlink()
            (lock / "journal.json").unlink()
            lock.rmdir()
            restored_state = sha(state) if state.exists() else None
            report["restoredOriginalState"] = restored_state == original_state
            save()
            assert report["restoredOriginalState"], "project check state was not restored"
    report["medians"] = {}
    for label in {r["label"] for r in report["results"]}:
        rows = [r for r in report["results"] if r["label"] == label]
        report["medians"][label] = {metric: statistics.median(r[metric] for r in rows)
                                   for metric in ["real", "user", "sys", "instructions retired", "cycles elapsed", "maximum resident set size"]}
    save()
    print(json.dumps(report["medians"], indent=2))


if __name__ == "__main__":
    main()
