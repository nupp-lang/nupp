#!/usr/bin/env python3
"""Pinned reference Lua tooling; no core acceptance without an explicit target."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import subprocess
import tarfile
import time
import urllib.request

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
VERSION = "5.5.1"
ARCHIVE = f"lua-{VERSION}.tar.gz"
URL = "https://www.lua.org/ftp/" + ARCHIVE
SHA256 = "1c4b4068d67061f2a2231ad2b5422e77acea1487ea9890f6320af614f4373dce"
FORMAT = "nupp-lua-subset-v1"
OUTPUT_LIMIT = 1024 * 1024
EXCLUSIONS = [
    "floats, integer overflow, shifts and numeric string coercion",
    "metatables, weak tables, finalizers and observable GC timing",
    "iteration-order-dependent programs and sparse table length",
    "recursive functions, coroutines, exceptions and resource exhaustion semantics",
    "userdata, threads, function values or table keys in observations",
    "cyclic observations and observable table identity in serialization",
    "I/O, clocks, randomness, dynamic loading and arbitrary supplied source",
]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")


def fresh_output(path):
    path = Path(path).resolve()
    if path.parent != ROOT / "build" or not path.name.startswith("core-oracle-"):
        raise ValueError("output must be a fresh build/core-oracle-* directory")
    path.mkdir(parents=True, exist_ok=False)
    return path


def clean_environment():
    env = dict(os.environ, LC_ALL="C", LANG="C", TZ="UTC")
    for key in list(env):
        if key.startswith("LUA_") or key in ("LUA_PATH", "LUA_CPATH"):
            del env[key]
    return env


def execute(argv, directory, label, timeout=5, watched=()):
    """Bound wall time and retained streams, killing the complete child group."""
    if not 0 < timeout <= 300:
        raise ValueError("timeout must be in (0, 300]")
    stdout, stderr = directory / (label + ".out"), directory / (label + ".err")
    started = time.monotonic()
    result = {"argv": [str(x) for x in argv], "status": "launch-error"}
    with stdout.open("wb") as out, stderr.open("wb") as err:
        try:
            child = subprocess.Popen(
                result["argv"], cwd=directory, env=clean_environment(),
                stdout=out, stderr=err, start_new_session=True,
            )
        except OSError as error:
            result["error"] = str(error)
        else:
            while True:
                code = child.poll()
                sizes = sum(p.stat().st_size for p in (stdout, stderr, *watched) if p.exists())
                status = "output-limit" if sizes > OUTPUT_LIMIT else None
                if status is None and code is None and time.monotonic() - started > timeout:
                    status = "timeout"
                if status:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    child.wait()
                    result.update(status=status, exitCode=child.returncode)
                    break
                if code is not None:
                    try:
                        os.killpg(child.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                    result.update(status="ok" if code == 0 else "exit", exitCode=code)
                    break
                time.sleep(0.02)
    result["wallSeconds"] = time.monotonic() - started
    def retain(path):
        size = path.stat().st_size
        truncated = size > OUTPUT_LIMIT
        if truncated:
            with path.open("r+b") as stream:
                stream.truncate(OUTPUT_LIMIT)
            # A final size check also covers writes racing with process exit.
            # Truncated canonical output must never reach the comparison path.
            result["status"] = "output-limit"
        return {
            "path": str(path), "bytes": size,
            "retainedBytes": path.stat().st_size, "truncated": truncated,
            "sha256": digest(path.read_bytes()),
        }

    for name, path in (("stdout", stdout), ("stderr", stderr)):
        result[name] = retain(path)
    result["watchedOutputs"] = [retain(path) for path in watched if path.exists()]
    return result


def provision(output):
    out = fresh_output(output)
    receipt = {"status": "failed", "version": VERSION, "url": URL, "archiveSha256": SHA256}
    try:
        request = urllib.request.Request(URL, headers={"User-Agent": "nupp-core-oracle/1"})
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.url != URL:
                raise ValueError("unexpected archive redirect")
            data = response.read(2 * 1024 * 1024 + 1)
        if len(data) > 2 * 1024 * 1024 or digest(data) != SHA256:
            raise ValueError("reference source checksum mismatch")
        archive = out / ARCHIVE
        archive.write_bytes(data)
        with tarfile.open(archive, "r:gz") as tar:
            members = tar.getmembers()
            if sum(m.size for m in members) > 16 * 1024 * 1024:
                raise ValueError("archive expanded extent refused")
            for member in members:
                parts = Path(member.name).parts
                if not parts or parts[0] != f"lua-{VERSION}" or ".." in parts:
                    raise ValueError("archive path refused")
                if not (member.isfile() or member.isdir()):
                    raise ValueError("archive special entry refused")
            tar.extractall(out, members=members)
        compiler = shutil.which("cc")
        if not compiler:
            raise ValueError("C compiler unavailable")
        receipt["compiler"] = execute([compiler, "--version"], out, "cc-version")
        receipt["build"] = execute(
            ["make", "-C", str(out / f"lua-{VERSION}" / "src"), "generic", "CC=" + compiler],
            out, "build", timeout=300,
        )
        if receipt["build"]["status"] != "ok":
            raise ValueError("reference build failed")
        binary = out / f"lua-{VERSION}" / "src" / "lua"
        receipt["binary"] = str(binary)
        receipt["binarySha256"] = digest(binary.read_bytes())
        receipt["versionProbe"] = execute([binary, "-v"], out, "version")
        receipt["integerProbe"] = execute(
            [binary, "-e", 'assert(_VERSION=="Lua 5.5" and math.maxinteger==9223372036854775807 and math.mininteger==(-9223372036854775807-1)); io.write("int64\\n")'],
            out, "integer",
        )
        if any(receipt[k]["status"] != "ok" for k in ("versionProbe", "integerProbe")):
            raise ValueError("reference version/integer width refused")
        receipt["platform"] = platform.platform()
        receipt["status"] = "ready"
    except Exception as error:
        receipt["error"] = str(error)
        raise
    finally:
        save(out / "reference.json", receipt)
    return out / "reference.json"


def reference(path):
    value = json.loads(Path(path).read_text())
    if value.get("status") != "ready" or value.get("version") != VERSION or value.get("archiveSha256") != SHA256:
        raise ValueError("unverified reference receipt")
    binary = Path(value["binary"])
    if digest(binary.read_bytes()) != value["binarySha256"]:
        raise ValueError("reference binary hash mismatch")
    return value


class Random32:
    def __init__(self, seed):
        if type(seed) is not int or not 0 <= seed < 2**32:
            raise ValueError("seed must be an unsigned 32-bit integer")
        self.state = seed

    def below(self, limit):
        self.state = (1664525 * self.state + 1013904223) & 0xFFFFFFFF
        return self.state % limit


def generate(seed, steps=24):
    rng = Random32(seed)
    if type(steps) is not int or not 1 <= steps <= 64:
        raise ValueError("steps must be 1..64")
    lines = [
        "-- " + FORMAT + "; seed=" + str(seed),
        f"local a, b = {rng.below(201) - 100}, {rng.below(201) - 100}",
        'local t = { [false] = "false-key", [true] = "true-key", [0] = false, ["empty"] = "" }',
        "local alias = t",
        "local cell = 0",
        "local function bump(delta) cell = cell + delta; return cell end",
        "local first = bump(1)",
    ]
    coverage = {"closure", "table-alias", "nil-false-empty", "parallel-assignment"}
    for index in range(steps):
        choice, amount, count = rng.below(8), rng.below(17) - 8, rng.below(9)
        if choice == 0:
            lines.append(f"a = (a + ({amount})) % 997")
            coverage.add("integer-add-mod")
        elif choice == 1:
            lines.append(f"b = (b * ({amount}) - a) % 991")
            coverage.add("integer-mul-sub")
        elif choice == 2:
            divisor = amount or -3
            lines.append(f"a, b = b // ({divisor}), a % ({divisor})")
            coverage.add("floor-div-mod")
        elif choice == 3:
            lines.append(f"if (a < b and b ~= 0) or a == 0 then a, b = b, a else b = b + ({amount}) end")
            coverage.add("branch-short-circuit")
        elif choice == 4:
            lines.append(f"for i = 1, {count} do a = (a + i) % 997 end")
            coverage.add("bounded-for")
        elif choice == 5:
            lines.append(f"do local i = 0; while i < {count} do b = (b - i) % 991; i = i + 1 end end")
            coverage.add("bounded-while")
        elif choice == 6:
            lines.extend([f't["k{index}"] = a', 'alias["gone"] = b', 't["gone"] = nil'])
            coverage.add("table-write-delete")
        else:
            lines.append(f't["c{index}"] = bump({amount})')
            coverage.add("captured-mutation")
    lines.extend([
        "local last = bump(0)",
        'local chosen = (false or "") and (nil or "selected")',
        "return a, b, t, first, last, nil, false, \"\", chosen, alias == t",
    ])
    source = ("\n".join(lines) + "\n").encode()
    manifest = {"format": FORMAT, "seed": seed, "steps": steps, "sourceSha256": digest(source),
                "coverage": sorted(coverage), "exclusions": EXCLUSIONS}
    return source, manifest


def generate_case(directory, seed, steps):
    directory.mkdir()
    source, manifest = generate(seed, steps)
    (directory / "program.lua").write_bytes(source)
    save(directory / "case.json", manifest)
    return directory / "case.json"


def validate_case(path):
    path = Path(path).resolve()
    manifest = json.loads(path.read_text())
    source, expected = generate(manifest.get("seed"), manifest.get("steps"))
    if manifest != expected or (path.parent / "program.lua").read_bytes() != source:
        raise ValueError("case is not an exact supported generator replay")
    return manifest


def target_argv(template, case, output):
    if not isinstance(template, list) or not template or any(type(x) is not str or not x for x in template):
        raise ValueError("target command must be a nonempty JSON argv array")
    substitutions = {"{program}": str(case.parent / "program.lua"), "{manifest}": str(case), "{output}": str(output)}
    if "{program}" not in template or "{output}" not in template:
        raise ValueError("target requires standalone {program} and {output} arguments")
    for arg in template:
        if ("{" in arg or "}" in arg) and arg not in substitutions:
            raise ValueError("unknown or embedded target placeholder")
    return [substitutions.get(arg, arg) for arg in template]


def run_case(case, ref, directory, template=None, timeout=5):
    directory.mkdir()
    result = {"status": "refused", "case": str(case), "coreAcceptance": False}
    try:
        manifest = validate_case(case)
        result.update(seed=manifest["seed"], sourceSha256=manifest["sourceSha256"])
        expected, actual = directory / "expected.bin", directory / "actual.bin"
        result["reference"] = execute(
            [ref["binary"], HERE / "reference.lua", case.parent / "program.lua", expected],
            directory, "reference", timeout, watched=(expected,),
        )
        if result["reference"]["status"] != "ok" or not expected.is_file():
            result["status"] = "reference-failed"
        else:
            result["expectedSha256"] = digest(expected.read_bytes())
            if template is None:
                result["status"] = "oracle-only"
            else:
                argv = target_argv(template, case, actual)
                executable = shutil.which(argv[0])
                bindings = [Path(executable)] if executable else []
                bindings.extend(Path(arg) for arg in argv[1:] if Path(arg).is_file())
                result["targetFileSha256"] = {
                    str(path.resolve()): digest(path.read_bytes()) for path in bindings
                }
                result["target"] = execute(argv, directory, "target", timeout, watched=(actual,))
                target = result["target"]
                if target["status"] == "exit" and target["exitCode"] == 77:
                    result["status"] = "target-refused"
                elif target["status"] != "ok":
                    result["status"] = "target-" + target["status"]
                elif not actual.is_file():
                    result["status"] = "target-missing-output"
                elif actual.stat().st_size > OUTPUT_LIMIT:
                    result["status"] = "target-output-limit"
                else:
                    result["actualSha256"] = digest(actual.read_bytes())
                    result["status"] = "matched" if actual.read_bytes() == expected.read_bytes() else "mismatch"
    except (ValueError, OSError, KeyError, TypeError) as error:
        result["error"] = str(error)
    save(directory / "receipt.json", result)
    return result


def run(reference_path, output, seeds, steps=24, target=None, replay=None, timeout=5):
    out = fresh_output(output)
    receipt = {"status": "failed", "coreAcceptance": False, "cases": [], "format": FORMAT}
    try:
        ref = reference(reference_path)
        receipt["reference"] = ref
        receipt["toolSha256"] = digest(Path(__file__).read_bytes())
        receipt["serializerSha256"] = digest((HERE / "reference.lua").read_bytes())
        receipt["targetCommand"] = target
        if replay:
            paths = [Path(p).resolve() for p in replay]
        else:
            if not 1 <= len(seeds) <= 256:
                raise ValueError("case count must be 1..256")
            paths = [generate_case(out / f"case-{i:03}", seed, steps) for i, seed in enumerate(seeds)]
        if not 1 <= len(paths) <= 256:
            raise ValueError("replay count must be 1..256")
        for i, path in enumerate(paths):
            receipt["cases"].append(run_case(path, ref, out / f"run-{i:03}", target, timeout))
        wanted = "oracle-only" if target is None else "matched"
        receipt["status"] = wanted if all(c["status"] == wanted for c in receipt["cases"]) else "failed"
    except Exception as error:
        receipt["error"] = str(error)
        raise
    finally:
        save(out / "receipt.json", receipt)
    return receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    p = commands.add_parser("provision")
    p.add_argument("--output", required=True)
    r = commands.add_parser("run")
    r.add_argument("--reference", required=True)
    r.add_argument("--output", required=True)
    r.add_argument("--seed", type=int, action="append", default=[])
    r.add_argument("--steps", type=int, default=24)
    r.add_argument("--replay", action="append")
    r.add_argument("--target-command", help="JSON argv; whole arguments {program}, {manifest}, {output}")
    r.add_argument("--timeout", type=float, default=5)
    args = parser.parse_args()
    if args.command == "provision":
        print(provision(args.output))
    else:
        result = run(args.reference, args.output, args.seed or [0, 1, 42], args.steps,
                     json.loads(args.target_command) if args.target_command else None, args.replay, args.timeout)
        print(result["status"])
        return 0 if result["status"] in ("oracle-only", "matched") else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
