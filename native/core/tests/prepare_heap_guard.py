#!/usr/bin/env python3
"""Build the unchanged bridge and calibrate its ABI/scratch guard, without heap execution."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import signal
import subprocess
import time

BRIDGE = Path("native/core/bridge")
CALIBRATIONS = {
    "abi::wrapper_detects_integer_and_float_clobber",
    "scratch::guarded_scratch_preserves_zeroed_usable_bytes_and_canary",
    "scratch::scratch_page_padding_is_also_canaried",
    "tests::accepts_empty_optional_regions",
    "tests::rejects_every_truncated_header_and_wrong_magic",
    "tests::rejects_invalid_fields_before_mapping",
    "tests::rejects_combined_region_limit",
    "tests::mapped_storage_is_zero_and_scoped",
}
GENERATED = {
    "abi::generated_entry_preserves_c_abi_and_output",
    "abi::generated_entry_refuses_short_regions",
    "abi::generated_entry_returns_requested_status",
}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def source_hashes(root):
    paths = sorted(p for p in (root / BRIDGE).rglob("*")
                   if p.is_file() and p.suffix in (".rs", ".S", ".toml", ".lock"))
    required = {"Cargo.toml", "Cargo.lock", "src/main.rs", "src/platform.rs",
                "tests/support/abi.rs", "tests/support/abi-aarch64.S", "tests/support/scratch.rs"}
    assert required <= {str(p.relative_to(root / BRIDGE)) for p in paths}, "bridge source missing"
    return {str(p.relative_to(root)): sha(p) for p in paths}


def build_environment(root, inherited):
    env = {k: v for k, v in inherited.items()
           if not k.startswith(("NUPP_", "JIT_", "GC_", "CORE_TEST_", "LUA", "CARGO_"))
           and k not in ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "RUSTUP_TOOLCHAIN",
                         "RUSTC", "RUSTDOC", "RUSTC_WORKSPACE_WRAPPER", "NO_JIT", "NO_AOT")}
    if "CARGO_HOME" in inherited:
        env["CARGO_HOME"] = inherited["CARGO_HOME"]
    if "RUSTC_WRAPPER" not in env and shutil.which("sccache", path=env.get("PATH")):
        env["RUSTC_WRAPPER"] = str(root / "scripts/sccache-wrapper")
    return env


def executable_from_cargo(text, root, target_dir, test):
    found, finished = [], []
    for line in text.splitlines():
        if not line.startswith("{"):
            continue
        item = json.loads(line)
        if item.get("reason") == "build-finished":
            finished.append(item.get("success"))
        if item.get("reason") != "compiler-artifact" or not item.get("executable"):
            continue
        target = item.get("target", {})
        assert target.get("name") == "nupp-core" and target.get("kind") == ["bin"], "unexpected executable target"
        assert Path(target["src_path"]).resolve() == root / BRIDGE / "src/main.rs", "foreign executable source"
        assert Path(item["manifest_path"]).resolve() == root / BRIDGE / "Cargo.toml", "foreign manifest"
        assert item.get("profile", {}).get("test") is test, "wrong executable profile"
        binary = Path(item["executable"]).resolve()
        assert target_dir in binary.parents and binary.is_file() and os.access(binary, os.X_OK), "executable outside build output or missing"
        found.append(binary)
    assert finished == [True] and len(found) == 1, "build did not produce exactly one successful executable"
    return found[0]


def verify_calibrations(text):
    passed = re.findall(r"^test (\S+) \.\.\. ok$", text, re.M)
    ignored = re.findall(r"^test (\S+) \.\.\. ignored(?:,.*)?$", text, re.M)
    assert len(passed) == len(CALIBRATIONS) and set(passed) == CALIBRATIONS, "calibration inventory differs"
    assert len(ignored) == len(GENERATED) and set(ignored) == GENERATED, "generated checks must remain pending"
    assert "test result: ok. 8 passed; 0 failed; 3 ignored; 0 measured; 0 filtered out;" in text, "calibration summary differs"


def prepare(root, output, timeout=300):
    root, output = Path(root).resolve(), Path(output).resolve()
    assert platform.system() in ("Darwin", "Linux") and platform.machine().lower() in ("arm64", "aarch64"), "guard calibration requires an ARM64 macOS or Linux host"
    assert output != root and output not in root.parents and root / BRIDGE not in output.parents, "output must be outside bridge sources"
    output.mkdir(parents=True, exist_ok=False)
    sources = source_hashes(root)
    inputs = {str(p): sha(root / p) for p in (Path("rust-toolchain.toml"), Path(".cargo/config.toml"), Path("scripts/sccache-wrapper"))}
    env = build_environment(root, os.environ)
    report = {"status": "running", "scope": __doc__, "sources": sources, "buildInputs": inputs,
              "tool": {"path": str(Path(__file__).resolve()), "sha256": sha(__file__)},
              "platform": {"system": platform.system(), "machine": platform.machine()},
              "steps": [], "nativeHeapExecution": False, "guestExecution": False,
              "generatedArtifactChecks": "pending", "productionChange": False,
              "environmentOverrides": {k: env[k] for k in ("RUSTC_WRAPPER",) if k in env}}

    def save():
        (output / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    def stable():
        assert source_hashes(root) == sources, "bridge source content or inventory changed"
        assert all(sha(root / p) == h for p, h in inputs.items()), "build input changed"
        assert sha(__file__) == report["tool"]["sha256"], "preparation tool changed"

    def run(name, argv):
        stable()
        start = time.monotonic()
        log, err = output / (name + ".out"), output / (name + ".err")
        with log.open("xb") as stdout, err.open("xb") as stderr:
            child = subprocess.Popen(list(map(str, argv)), cwd=root, env=env,
                                     stdout=stdout, stderr=stderr, start_new_session=True)
            timed_out = False
            try:
                status = child.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                os.killpg(child.pid, signal.SIGKILL)
                status = child.wait()
        report["steps"].append({"name": name, "command": list(map(str, argv)), "status": status,
                                "timedOut": timed_out, "elapsedSecondsNongating": time.monotonic() - start,
                                "stdoutSHA256": sha(log), "stderrSHA256": sha(err)})
        save()
        assert status == 0 and not timed_out, name + " failed; see retained output"
        stable()
        return log.read_text()

    save()
    try:
        run("cargo-version", ["cargo", "-vV"])
        run("rustc-version", ["rustc", "-vV"])
        target_dir = output / "cargo"
        common = ["--manifest-path", str(root / BRIDGE / "Cargo.toml"), "--offline", "--locked",
                  "--bin", "nupp-core", "--target-dir", str(target_dir), "--message-format=json"]
        bridge = executable_from_cargo(run("build-bridge", ["cargo", "build", "--release", *common]), root, target_dir, False)
        guard = executable_from_cargo(run("build-guard", ["cargo", "test", "--no-run", *common]), root, target_dir, True)
        originals = {str(p): sha(p) for p in (bridge, guard)}
        (output / "bin").mkdir()
        for source, name in ((bridge, "nupp-core"), (guard, "nupp-core-abi-tests")):
            shutil.copy2(source, output / "bin" / name)
            assert sha(output / "bin" / name) == originals[str(source)], "copied binary differs"
        binary = output / "bin/nupp-core-abi-tests"
        report["binary"] = {"path": str(binary), "sha256": sha(binary)}
        report["bridge"] = {"path": str(output / "bin/nupp-core"), "sha256": sha(output / "bin/nupp-core")}
        report["cargoArtifacts"] = originals
        verify_calibrations(run("calibration", [binary, "--test-threads=1", "--format=pretty"]))
        assert all(sha(p) == h for p, h in originals.items()), "Cargo executable changed"
        for name in ("binary", "bridge"):
            assert sha(report[name]["path"]) == report[name]["sha256"], "prepared executable changed"
        stable()
        report.update(status="passed", unitPassed=len(CALIBRATIONS), sourcesUnchanged=True)
    except BaseException as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        try:
            report["sourcesUnchanged"] = source_hashes(root) == sources
        except (AssertionError, OSError):
            report["sourcesUnchanged"] = False
        save()
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--timeout", type=int, default=300, help="maximum seconds per build or calibration command")
    args = parser.parse_args()
    assert args.timeout > 0, "timeout must be positive"
    prepare(args.root, args.output, args.timeout)
    print("8 bridge calibrations passed; generated heap checks remain pending")


if __name__ == "__main__":
    main()
