#!/usr/bin/env python3
"""Build scalar C, explicit SIMD, and no-vector controls and measure them."""
import argparse
import ctypes as ct
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import re
import statistics as stats
import subprocess
import sys
import threading
import time

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
BUILD = HERE / "build"
NAMES = ("map", "refine", "ordered", "pairwise", "algebraic", "crossLane")
EXPLICIT = {name: "explicit" + name[0].upper() + name[1:] for name in NAMES[:-1]}
SIZES = (63, 65539)


def run(args, **kwargs):
    return subprocess.check_output(args, cwd=ROOT, text=True, **kwargs)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def save(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n")


def assembly_contracts(build, declarations, architecture):
    evidence = {}
    if architecture == "aarch64":
        operation = r"\b(?:fadd|fmul|add|mul|sub|and|orr|eor|smax|smin|fmax|fmin)(?:\.[0-9]+[bhsd])?\s+v\d+"
    else:
        operation = r"\b(?:v?(?:add|mul|sub)(?:ps|pd)|v?p(?:add|sub|mul|and|or|xor)[a-z]*)\s"
    for role in ("native", "auto_vector", "no_vector"):
        assembly = (build / (role + ".s")).read_text()
        counts = {}
        for name, declaration in declarations.items():
            if name == "crossWidth": continue
            suffix = declaration["oracleSuffix"] if role != "native" else ""
            symbol = declaration["symbol"] + suffix
            body = re.search(r"^_?" + re.escape(symbol) + r":.*?(?=^\s*\.glob[a-z]*|\Z)", assembly, re.M | re.S)
            assert body, "assembly is missing " + symbol
            counts[symbol] = len(re.findall(operation, body.group(0)))
            if role == "no_vector" and name in NAMES: assert counts[symbol] == 0, ("no-vector arithmetic contract", symbol, counts[symbol])
            elif role == "native" and (name == "crossLane" or name in EXPLICIT.values()):
                assert counts[symbol] > 0, ("native vector arithmetic contract", symbol)
        evidence[role] = counts
    return evidence


def prepare_group(source_path, names, build):
    build.mkdir(parents=True, exist_ok=True)
    tier = "neon" if platform.machine() in ("arm64", "aarch64") else "baseline"
    artifact = json.loads(run(["./bin/nupp", "aot", "--features", tier, "--format", "json", str(source_path)]))
    save(build / "artifacts.json", artifact)
    source = artifact["c"]
    (build / "original.c").write_text(source)
    (build / "kernel.ir").write_text(artifact["ir"])
    (build / "binding.nupp").write_text(artifact["binding"])
    # Preserve the unmodified oracle. Only the separate performance control
    # removes any O0/optnone attributes; its global flags forbid auto-vectorizing.
    optimized = re.sub(r"^#define KS_SCALAR_ORACLE.*$", "#define KS_SCALAR_ORACLE", source, flags=re.M)
    optimized = re.sub(r"^#pragma clang loop vectorize\(disable\) interleave\(disable\)\n", "", optimized, flags=re.M)
    assert optimized != source, "oracle attribute transformation matched nothing"
    assert "#pragma clang loop vectorize(disable)" not in optimized, "scalar C retains a test-only vectorizer ban"
    declarations = {}
    wrappers = ["#include <time.h>", "static volatile double bench_sink;",
                "static double bench_clock(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec + (double)t.tv_nsec * 1e-9; }"]
    for name in names:
        symbol = next(f["symbol"] for f in artifact["functions"] if f["name"] == name)
        match = re.search(r"KS_API\s+(\w+)\s+" + re.escape(symbol) + r"\(([^)]*)\)\s*\{", source)
        assert match, symbol
        result, params = match.groups()
        params = params.replace(" KS_UNUSED", "")
        arguments = [re.search(r"(\w+)\s*$", p).group(1) for p in params.split(",") if p.strip()]
        oracle_suffix = "_forced_scalar" if re.search(r"\b" + re.escape(symbol) + r"_forced_scalar\s*\(", source) else ""
        declarations[name] = {"symbol": symbol, "result": result, "params": params, "arguments": arguments, "oracleSuffix": oracle_suffix}
        if name == "crossWidth":
            continue
        for suffix in ("", oracle_suffix) if oracle_suffix else ("",):
            selected = symbol + suffix
            # A volatile function pointer keeps repeated identical calls from
            # being hoisted out of the timer loop by interprocedural analysis.
            call = selected + "_timer"
            invocation = "fn(" + ", ".join(arguments) + ")"
            if result != "void":
                invocation = "bench_sink = " + invocation
            wrappers.append(f"KS_API double {call}(size_t repeats, {params}) {{ {result} (*volatile fn)({params}) = {selected}; double start = bench_clock(); for(size_t i=0;i<repeats;i++) {{ {invocation}; }} return bench_clock()-start; }}")
    wrappers.append("KS_API double bench_control(size_t repeats) { volatile uint32_t value=17; double start=bench_clock(); for(size_t i=0;i<repeats;i++) value=value*1664525u+1013904223u; bench_sink=value; return bench_clock()-start; }")
    compiler = os.environ.get("NUPP_NATIVE_CC", "clang")
    version = run([compiler, "--version"])
    is_clang = "clang" in version.lower()
    flags = ["-std=c11", "-O3", "-ffp-contract=off", "-fno-fast-math", "-fPIC", "-D_POSIX_C_SOURCE=200809L", "-Wall", "-Wextra", "-Werror"]
    if is_clang: flags.append("-Wno-parentheses-equality")
    no_vector = ["-fno-vectorize", "-fno-slp-vectorize"] if is_clang else ["-fno-tree-vectorize"]
    extension = "dylib" if sys.platform == "darwin" else "so"
    shared = "-dynamiclib" if sys.platform == "darwin" else "-shared"
    artifacts = {}
    for role, text, extra in (("native", source, []), ("auto_vector", optimized, []),
                              ("no_vector", optimized, no_vector)):
        c_path = build / (role + ".c")
        c_path.write_text(text + "\n" + "\n".join(wrappers) + "\n")
        library = build / (role + "." + extension)
        command = [compiler, *flags, *extra, shared, str(c_path), "-lm", "-o", str(library)]
        run(command)
        assembly = build / (role + ".s")
        run([compiler, *flags, *extra, "-S", str(c_path), "-o", str(assembly)])
        artifacts[role] = {"path": str(library), "sha256": digest(library), "sourceSha256": digest(c_path), "assemblySha256": digest(assembly), "command": command}
    metadata = {"revision": run(["git", "rev-parse", "HEAD"]).strip(), "dirtyDiff": run(["git", "diff"]),
                "sourceSha256": digest(source_path), "compiler": version, "host": platform.platform(),
                "target": artifact["target"], "artifacts": artifacts, "declarations": declarations,
                "controlTransformation": "Removed KS_SCALAR_ORACLE attributes and clang loop vectorize-disable pragmas; both scalar C artifacts use O3 and differ only in vectorizer flags",
                "scope": "Complete exported C entry, including setup/tails/finalization; Lua checked wrapper and input construction outside timer"}
    metadata["assemblyContracts"] = assembly_contracts(build, declarations, artifact["target"]["architecture"])
    metadata["oracle"] = {"sourceSha256": digest(build / "original.c"), "librarySha256": artifacts["native"]["sha256"], "symbols": [d["symbol"] + d["oracleSuffix"] for d in declarations.values() if d["oracleSuffix"]], "timed": False}
    assert artifacts["native"]["sourceSha256"] != artifacts["no_vector"]["sourceSha256"]
    save(build / "metadata.json", metadata)
    return metadata


def prepare():
    core = prepare_group(HERE / "kernels.nupp", (*NAMES, *EXPLICIT.values(), "crossWidth"), BUILD)
    utf8 = prepare_group(ROOT / "bench/utf8simd/src/utf8simd.nupp", ("validPrefix",), BUILD / "utf8")
    print(json.dumps({"prepared": str(BUILD), "target": core["target"], "utf8Target": utf8["target"]}))


def pairwise(values):
    while len(values) > 1:
        values = [values[i] + values[i + 1] if i + 1 < len(values) else values[i] for i in range(0, len(values), 2)]
    return values[0]


def call_inputs(declaration, values, count, element):
    arguments, argtypes = [], []
    for parameter in declaration["arguments"]:
        value = count if parameter.startswith("count") else values[parameter]
        arguments.append(value)
        argtypes.append(ct.c_size_t if parameter.startswith("count") else
                        ct.POINTER(element) if parameter in ("p_output", "p_input", "p_left", "p_right") else ct.c_double)
    return arguments, argtypes


def utf8_rows(index, check_only=False):
    metadata = json.loads((BUILD / "utf8/metadata.json").read_text())
    libraries = {role: ct.CDLL(info["path"]) for role, info in metadata["artifacts"].items()}
    declaration = metadata["declarations"]["validPrefix"]
    rows = []
    for kind, unit in (("ascii", b"abcdefg"), ("unicode", "é€😀".encode())):
        for n in SIZES:
            value = (unit * (n // len(unit) + 1))[:n]
            try: value.decode("utf-8"); expected = n
            except UnicodeDecodeError as error: expected = error.start
            data = (ct.c_uint8 * n).from_buffer_copy(value)
            args = (data, n)
            types = (ct.POINTER(ct.c_uint8), ct.c_size_t)
            oracle_suffix = declaration["oracleSuffix"]
            for role, suffix in (("native", ""), ("native", oracle_suffix),
                                 ("auto_vector", oracle_suffix), ("no_vector", oracle_suffix)):
                fn = getattr(libraries[role], declaration["symbol"] + suffix)
                fn.argtypes = types; fn.restype = ct.c_uint32
                assert fn(*args) == expected, ("utf8", kind, n, role, suffix)
            if check_only:
                rows.append({"name": "utf8-" + kind, "elements": n, "checked": True})
                continue
            timers = []
            for role, suffix in (("native", ""), ("auto_vector", oracle_suffix),
                                 ("no_vector", oracle_suffix)):
                fn = getattr(libraries[role], declaration["symbol"] + suffix + "_timer")
                fn.argtypes = (ct.c_size_t, *types); fn.restype = ct.c_double
                timers.append(fn)
            repeats = max(1, 1_000_000 // n)
            for _ in range(3):
                for fn in timers: fn(repeats, *args)
            samples = []
            for sample in range(15):
                times = [None, None, None]
                for variant in ((0, 1, 2) if (sample + index) % 2 == 0 else (2, 1, 0)):
                    times[variant] = timers[variant](repeats, *args)
                samples.append({"native": times[0], "autoVector": times[1], "noVector": times[2]})
            rows.append({"name": "utf8-" + kind, "elements": n, "repeats": repeats, "samples": samples})
    return rows


def worker(index, check_only=False):
    metadata = json.loads((BUILD / "metadata.json").read_text())
    libraries = {role: ct.CDLL(info["path"]) for role, info in metadata["artifacts"].items()}
    rows = []
    for name in NAMES:
        declaration = metadata["declarations"][name]
        integer = name == "crossLane"
        element = ct.c_int32 if integer else ct.c_double
        for n in SIZES:
            left = (element * n)(*((i % 31 - 15) if integer else (i % 97 + 1) * 0.125 for i in range(n)))
            right = (element * n)(*((i % 17 + 1) * 0.0625 for i in range(n))) if not integer else None
            output = (element * (n + 4))()
            for i in range(n, n + 4): output[i] = -777
            values = {"p_output": output, "p_input": left, "p_left": left, "p_right": right, "p_scale": 1.25, "p_bias": -0.5}
            arguments, argtypes = call_inputs(declaration, values, n, element)
            explicit_declaration = metadata["declarations"].get(EXPLICIT.get(name))
            explicit_arguments, explicit_argtypes = call_inputs(explicit_declaration, values, n, element) if explicit_declaration else (None, None)
            if name == "map": expected = [x * 1.25 - 0.5 for x in left]
            elif name == "refine":
                expected = []
                for x in left:
                    rounds = 0
                    while x > 1 and rounds < 32: x *= 0.5; rounds += 1
                    expected.append(x + rounds)
            elif name in ("ordered", "pairwise", "algebraic"):
                products = [a * b for a, b in zip(left, right)]
                expected = pairwise([0.0] + products) if name == "pairwise" else sum(products)
            else:
                width_decl = metadata["declarations"]["crossWidth"]
                width_fn = getattr(libraries["native"], width_decl["symbol"])
                width_fn.argtypes = []; width_fn.restype = ct.c_uint32
                width = width_fn()
                assert 2 <= width <= 64
                expected = []
                for start in range(0, n, width):
                    block = list(left[start:start + width]); active = len(block)
                    block += [0] * (width - active)
                    running, scan = 0, []
                    for value in reversed(block): running += value; scan.append(running)
                    packed = [value for value in scan if value > 0]
                    expected += (packed + [0] * (width - len(packed)))[:active]
            oracle_suffix = declaration["oracleSuffix"]
            checks = [("native", declaration["symbol"], ""),
                      ("native", declaration["symbol"], oracle_suffix),
                      ("auto_vector", declaration["symbol"], oracle_suffix),
                      ("no_vector", declaration["symbol"], oracle_suffix)]
            if name in EXPLICIT:
                explicit_symbol = explicit_declaration["symbol"]
                checks.extend((("native", explicit_symbol, ""), ("native", explicit_symbol, explicit_declaration["oracleSuffix"])))
            for role, symbol, suffix in checks:
                fn = getattr(libraries[role], symbol + suffix)
                selected_arguments, selected_argtypes = (explicit_arguments, explicit_argtypes) if name in EXPLICIT and symbol == explicit_symbol else (arguments, argtypes)
                fn.argtypes = selected_argtypes; fn.restype = None if declaration["result"] == "void" else ct.c_double
                answer = fn(*selected_arguments)
                if declaration["result"] == "void": assert list(output[:n]) == expected, (name, role, suffix, n)
                elif name == "algebraic": assert abs(answer - expected) <= 1e-12 * max(1, abs(expected)), (name, answer, expected)
                else: assert answer == expected, (name, role, suffix, n, answer, expected)
                assert list(output[n:n + 4]) == [-777] * 4, "tail overwrite"
            if check_only:
                rows.append({"name": name, "elements": n, "checked": True})
                continue
            timers = []
            timed = [("native", declaration["symbol"], ""),
                     ("auto_vector", declaration["symbol"], oracle_suffix),
                     ("no_vector", declaration["symbol"], oracle_suffix)]
            if name in EXPLICIT:
                timed.append(("native", explicit_symbol, ""))
            for role, symbol, suffix in timed:
                fn = getattr(libraries[role], symbol + suffix + "_timer")
                selected_arguments, selected_argtypes = (explicit_arguments, explicit_argtypes) if name in EXPLICIT and symbol == explicit_symbol else (arguments, argtypes)
                fn.argtypes = [ct.c_size_t, *selected_argtypes]; fn.restype = ct.c_double
                timers.append((fn, selected_arguments))
            repeats = max(1, 1_000_000 // n)
            for _ in range(3):
                for fn, selected_arguments in timers: fn(repeats, *selected_arguments)
            samples = []
            for sample in range(15):
                times = [None] * len(timers)
                for variant in (range(len(timers)) if (sample + index) % 2 == 0 else range(len(timers) - 1, -1, -1)):
                    fn, selected_arguments = timers[variant]
                    times[variant] = fn(repeats, *selected_arguments)
                sample_row = {"native": times[0], "autoVector": times[1], "noVector": times[2]}
                if name in EXPLICIT: sample_row["explicit"] = times[3]
                samples.append(sample_row)
            rows.append({"name": name, "elements": n, "repeats": repeats, "samples": samples})
    rows.extend(utf8_rows(index, check_only))
    if check_only:
        print(json.dumps({"rows": rows, "checked": True})); return
    control = libraries["native"].bench_control
    control.argtypes = [ct.c_size_t]; control.restype = ct.c_double
    for _ in range(3): control(2_000_000)
    controls = [control(2_000_000) for _ in range(15)]
    print(json.dumps({"process": index, "pid": os.getpid(), "rows": rows, "control": controls}))


def activity_sample():
    text = run(["ps", "-axo", "pid=,ppid=,pcpu=,args="])
    competing = []
    always = {"clang", "clang++", "cc", "cc1", "gcc", "g++", "rustc", "cargo", "make", "ninja", "cmake", "wasm-opt", "wasm-ld"}
    for line in text.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) != 4: continue
        pid, ppid, cpu, command = parts
        executable = Path(command.split()[0]).name
        compile_python = executable.startswith("python") and ("/emcc.py " in command or "/em++.py " in command)
        busy_runtime = (executable in {"lua", "luajit", "node"} or executable.startswith("nupp")) and float(cpu) > 5
        if executable in always or compile_python or busy_runtime:
            competing.append({"pid": int(pid), "parent": int(ppid), "cpu": float(cpu), "command": command})
    return {"time": time.time(), "competing": competing}


def measure(destination):
    result = {"metadata": json.loads((BUILD / "metadata.json").read_text()), "utf8Metadata": json.loads((BUILD / "utf8/metadata.json").read_text()), "started": time.time(), "processes": []}
    result["environmentSamples"] = []
    # Refuse a busy launch, and retain the failed attempt just like a full run.
    for _ in range(25):
        sample = activity_sample(); result["environmentSamples"].append(sample)
        if sample["competing"]:
            result.update(qualified=False, exclusion="competing activity before timing")
            save(destination, result)
            raise RuntimeError("quiet-window preflight failed; attempt preserved at " + str(destination))
        time.sleep(.2)
    stopped = threading.Event()
    def observe():
        while not stopped.wait(.2):
            try: result["environmentSamples"].append(activity_sample())
            except Exception as error:
                result["environmentSamples"].append({"time": time.time(), "error": str(error)})
    observer = threading.Thread(target=observe)
    observer.start()
    try:
        for i in range(9):
            result["processes"].append(json.loads(run([sys.executable, str(Path(__file__).resolve()), "--worker", str(i)])))
            save(destination, result)
    finally:
        stopped.set(); observer.join(); save(destination, result)
    controls = [stats.median(p["control"]) for p in result["processes"]]
    cv = stats.stdev(controls) / stats.mean(controls)
    result["controlCV"] = cv
    quiet = all(not sample.get("competing") and not sample.get("error") for sample in result["environmentSamples"])
    result["qualified"] = cv <= 0.05 and quiet
    summaries = []
    for offset, row in enumerate(result["processes"][0]["rows"]):
        comparisons = [("native", "autoVector"), ("native", "noVector")]
        if "explicit" in result["processes"][0]["rows"][offset]["samples"][0]:
            comparisons.append(("explicit", "native"))
        for numerator, denominator in comparisons:
            ratios = [stats.median(math.log(s[numerator] / s[denominator]) for s in p["rows"][offset]["samples"]) for p in result["processes"]]
            mean = stats.mean(ratios); half = 2.306004135 * stats.stdev(ratios) / 3
            low, high = math.exp(mean - half), math.exp(mean + half)
            verdict = "improved" if high < 0.99 else "regressed" if low > 1.01 else "unchanged" if low >= 0.99 and high <= 1.01 else "inconclusive"
            summaries.append({"name": row["name"], "elements": row["elements"], "comparison": numerator + "/" + denominator,
                              "ratio": math.exp(mean), "confidence95": [low, high],
                              "verdict": verdict if result["qualified"] else "environment-invalid"})
    result["summary"] = summaries; result["finished"] = time.time()
    save(destination, result)
    print(json.dumps({"controlCV": cv, "qualified": result["qualified"], "summary": summaries}, indent=2))


def report(source):
    data = json.loads(source.read_text())
    metadata = data["metadata"]
    if "summary" not in data:
        destination = source.with_suffix(".md")
        destination.write_text("# Excluded SIMD measurement attempt\n\nNo timing verdict. " + data.get("exclusion", "The run did not complete.") + "\n\n[Preserved attempt](" + source.name + ")\n")
        print(destination)
        return
    lines = ["# Complete-function SIMD measurements", "", "Qualified: **" + str(data["qualified"]).lower() + "**. Colocated control CV: **%.2f%%**." % (100 * data["controlCV"]), "",
             "Nine fresh processes, fifteen alternating samples per process, three warmups. Ratios compare complete-function elapsed durations; lower is faster. The 95% Student-t interval uses process-level median paired log ratios, with a 1% practical margin.", "",
             "| Function | Elements | Comparison | Duration ratio | 95% interval | Verdict |", "| --- | ---: | --- | ---: | --- | --- |"]
    for row in data["summary"]:
        low, high = row["confidence95"]
        lines.append("| %s | %d | %s | %.5f | [%.5f, %.5f] | %s |" % (row["name"], row["elements"], row["comparison"], row["ratio"], low, high, row["verdict"]))
    lines += ["", "Compiler revision: `" + metadata["revision"] + "`. Target: `" + metadata["target"]["triple"] + "` / `" + metadata["target"]["tier"] + "`. Host: " + metadata["host"] + ".", "",
              "The comparison uses the complete exported C entry and two optimized scalar-source controls that differ only in vectorizer flags. Original scalar-source oracles are correctness checks only. Lua span wrappers and cold loading are outside this timing scope. Independent formulas and UTF-8 decoding also check answers before timing.", "",
              "[Raw samples, compiler/flags, artifact hashes, assembly contracts and environment observations](" + source.name + ") are retained. Historical Mandelbrot, Base64 and fused JSON comparisons remain separately identified in the parent README.", ""]
    destination = source.with_suffix(".md")
    destination.write_text("\n".join(lines))
    print(destination)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--prepare", action="store_true")
    group.add_argument("--check", action="store_true")
    group.add_argument("--worker", type=int)
    group.add_argument("--measure", type=Path)
    group.add_argument("--report", type=Path)
    args = parser.parse_args()
    if args.prepare: prepare()
    elif args.check: worker(0, True)
    elif args.worker is not None: worker(args.worker)
    elif args.report: report(args.report)
    else: measure(args.measure)
