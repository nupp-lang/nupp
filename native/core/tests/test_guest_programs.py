#!/usr/bin/env python3
"""Execute checked scalar catalogs through the standalone owned core."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import time

ROOT = Path(__file__).resolve().parents[3]
CASES = {"boolean": 0x7FFB000000000000, "nilValue": 0x7FF9000000000000,
         "live": 0x7FFB000000000000, "fresh": 0x7FFB000000000000,
         "nested": 0x7FFB000000000000,
         "branchTrue": 0x7FFB000000000000, "branchFalse": 0x7FFA000000000000,
         "branchElseif": 0x7FFB000000000000, "branchLive": 0x7FFB000000000000,
         "modulePair": 0x7FFA000000000000,
         "moduleTriple": 0x7FFB000000000000,
         "numberAdd": 0x4017000000000000, "numberNegativeZero": 0x8000000000000000,
         "numberNaN": 0x7FF8000000000000,
         "numberBranch": 0x7FFB000000000000}
FIXTURES = ("catalog-boolean", "catalog-nil", "catalog-live", "catalog-fresh", "catalog-nested",
            "catalog-branch-true", "catalog-branch-false", "catalog-branch-elseif", "catalog-branch-live",
            "catalog-module-prefix", "catalog-module-main",
            "catalog-module-middle", "catalog-module-triple",
            "catalog-number-add", "catalog-number-negative-zero", "catalog-number-nan",
            "catalog-number-branch")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path)
    parser.add_argument("--fresh-guard", action="store_true",
                        help="Build and calibrate a local source-bound bridge and ABI verifier.")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--guard-proof", type=Path, default=ROOT / "native/core/bridge/guard-validation.json")
    parser.add_argument("--guard-binary", type=Path)
    parser.add_argument("--bootstrap", type=Path, default=ROOT.parent / "native-core-bootstrap")
    parser.add_argument("--scratch-bytes", type=int, choices=(65536, 131072), default=131072)
    parser.add_argument("--cases", nargs="+", choices=tuple(CASES),
                        help="Run these fixed cases and their supplemental audits (default: all).")
    args = parser.parse_args()
    selected_cases = [name for name in CASES if args.cases is None or name in args.cases]
    omitted_cases = [name for name in CASES if name not in selected_cases]
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    fresh_guard_build = None
    if args.fresh_guard:
        assert args.bridge is None, "fresh guard builds its own bridge"
        manifest = ROOT / "native/core/bridge/Cargo.toml"
        target = out / "bridge-target"
        cargo_env = {**os.environ, "RUSTC_WRAPPER": "/usr/bin/env"}
        build = subprocess.run(["cargo", "+stable", "test", "--manifest-path", str(manifest),
                                "--offline", "--locked", "--no-run", "--message-format=json",
                                "--target-dir", str(target)], cwd=ROOT, env=cargo_env,
                               capture_output=True, text=True, timeout=1800)
        (out / "fresh-guard-build.out").write_text(build.stdout)
        (out / "fresh-guard-build.err").write_text(build.stderr)
        assert build.returncode == 0, "fresh guard test build failed"
        executables = [Path(item["executable"]) for line in build.stdout.splitlines()
                       if line.startswith("{") for item in [json.loads(line)]
                       if item.get("reason") == "compiler-artifact"
                       and item.get("profile", {}).get("test") and item.get("executable")]
        assert len(executables) == 1, executables
        guard_binary = executables[0].resolve()
        build = subprocess.run(["cargo", "+stable", "build", "--manifest-path", str(manifest),
                                "--offline", "--locked", "--bin", "nupp-core",
                                "--target-dir", str(target)], cwd=ROOT, env=cargo_env,
                               capture_output=True, text=True, timeout=1800)
        (out / "fresh-bridge-build.out").write_text(build.stdout)
        (out / "fresh-bridge-build.err").write_text(build.stderr)
        assert build.returncode == 0, "fresh bridge build failed"
        args.bridge = (target / "debug/nupp-core").resolve()
        assert args.bridge.is_file()
        unit = subprocess.run([guard_binary, "--test-threads=1"], cwd=ROOT, env=cargo_env,
                              capture_output=True, text=True, timeout=120)
        (out / "fresh-guard-units.out").write_text(unit.stdout)
        (out / "fresh-guard-units.err").write_text(unit.stderr)
        assert unit.returncode == 0 and "8 passed; 0 failed; 3 ignored;" in unit.stdout
        source_paths = [path for path in sorted((ROOT / "native/core/bridge").rglob("*"))
                        if path.is_file() and path.suffix in (".rs", ".S", ".toml", ".lock")]
        args.guard_proof = out / "fresh-guard-proof.json"
        args.guard_proof.write_text(json.dumps({
            "status": "passed",
            "scope": "Fresh local ABI verifier calibrated before checked-source guest bundles",
            "binary": {"path": str(guard_binary), "sha256": sha(guard_binary)},
            "bridge": {"path": str(args.bridge), "sha256": sha(args.bridge)},
            "source": {str(path.relative_to(ROOT)): sha(path) for path in source_paths},
            "validation": {"status": "passed", "unitPassed": 8,
                           "generatedTests": "recorded in guest-program receipt"}
        }, indent=2) + "\n")
        fresh_guard_build = {"testBuild": "fresh-guard-build.out", "bridgeBuild": "fresh-bridge-build.out",
                             "unitCalibration": "fresh-guard-units.out"}
    else:
        assert args.bridge is not None, "--bridge or --fresh-guard is required"
    bootstrap = args.bootstrap.resolve()
    freeze = json.loads((bootstrap / "freeze.json").read_text())
    tools = {role: Path(freeze["artifacts"][name]["path"])
             for role, name in freeze["coreBuildTool"].items() if role in ("runtime", "compiler")}
    for role, path in tools.items():
        assert sha(path) == freeze["artifacts"][freeze["coreBuildTool"][role]]["sha256"]
    proof = args.guard_proof.resolve()
    guard = json.loads(proof.read_text())
    guard_binary = (args.guard_binary or Path(guard["binary"]["path"])).resolve()
    assert sha(guard_binary) == guard["binary"]["sha256"]
    assert guard.get("status", guard.get("validation", {}).get("status")) == "passed"
    guard_sources = {}
    for name, digest in guard.get("source", guard.get("sources", {})).items():
        relative = "native/core/bridge/" + name.split("native/core/bridge/", 1)[1]
        path = ROOT / relative
        if path.suffix in (".rs", ".S", ".toml", ".lock"):
            assert sha(path) == digest, relative
            guard_sources[str(path)] = digest
    for name in ("src/main.rs", "src/platform.rs", "tests/support/abi.rs",
                 "tests/support/abi-aarch64.S", "tests/support/scratch.rs"):
        assert str(ROOT / "native/core/bridge" / name) in guard_sources
    directories = [ROOT / "src", ROOT / "native/core/src", ROOT / "spike/native-lowering/src",
                   ROOT / "spike/native-lowering/nativegraph/src"]
    files = [path for directory in directories for path in sorted(directory.rglob("*"))
             if path.is_file() and path.suffix in (".nupp", ".lua")]
    producer = ROOT / "native/core/tests/guest-program-producer.nupp"
    negative = ROOT / "native/core/tests/guest-contract-negatives.nupp"
    audit_leaf = ROOT / "native/core/tests/guest-lifecycle-audit.nupp"
    audit_shim = ROOT / "native/core/tests/guest-audit-shim.nupp"
    fixture_paths = [ROOT / "native/core/tests" / (name + ".nupp") for name in FIXTURES]
    inputs = {str(path.resolve()): sha(path) for path in [*files, producer, negative, audit_leaf, audit_shim, *fixture_paths,
              Path(__file__), args.bridge, proof, guard_binary, *map(Path, guard_sources),
              bootstrap / "freeze.json", *tools.values()]}
    report = {"status": "running", "freshGuardBuild": fresh_guard_build, "inputs": inputs, "steps": [], "programs": [], "failures": [], "audits": [],
              "selectedCases": selected_cases, "omittedCases": omitted_cases,
              "preflightFixtures": list(FIXTURES),
              "scope": "Trusted checked-source catalog derives Boolean/NIL programs, including "
                       "up to three ordered module initializers with fresh entry storage and retained World. "
                       "Closure0, fixed CallK and one-result Ret run through Nupp services; "
                       "one checked static scalar import executes after successful publication; "
                       "named exports, cycles, arbitrary modules, raw loading and GC remain outside.",
              "guardVerifier": {"path": str(guard_binary), "sha256": sha(guard_binary),
                                "proof": str(proof), "proofSha256": sha(proof), "sources": guard_sources}}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA", "CORE_TEST_"))
           and key not in ("NO_AOT", "NO_JIT", "BUILTIN_STATS", "TABLE_STATS", "AOT_VERBOSE")}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD="0", NUPP_VM_AUTO_LINK="0", NUPP_VM_EMIT_CACHE="")

    def save():
        (out / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, argv, cwd=ROOT, extra=None, expected=0):
        for path, digest in inputs.items():
            assert sha(path) == digest, "changed input: " + path
        print(label, flush=True)
        save()
        started = time.perf_counter()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            child = subprocess.run(list(map(str, argv)), cwd=cwd, env={**env, **(extra or {})},
                                   stdout=stdout, stderr=stderr, timeout=1800)
        report["steps"].append({"name": label, "command": list(map(str, argv)),
                               "returnCode": child.returncode, "expectedReturnCode": expected,
                               "elapsedSeconds": time.perf_counter() - started,
                               "environmentOverrides": extra or {}})
        save()
        assert child.returncode == expected, label
        return (out / (label + ".out")).read_bytes()

    def guarded(label, bundle, input_path, high_water, expected=None, status=None):
        overrides = {"CORE_TEST_BUNDLE": str(bundle), "CORE_TEST_INPUT": str(input_path),
                     "CORE_TEST_HIGH_WATER": str(high_water)}
        if status is None:
            overrides["CORE_TEST_EXPECTED"] = str(expected)
            test = "abi::generated_entry_preserves_c_abi_and_output"
        else:
            overrides["CORE_TEST_STATUS"] = str(status)
            test = "abi::generated_entry_returns_requested_status"
        data = run(label, [guard_binary, "--ignored", "--exact", test, "--test-threads=1"], extra=overrides)
        assert b"1 passed; 0 failed; 0 ignored;" in data

    try:
        project = out / "project"
        modules = project / "src/nupp/core"
        modules.mkdir(parents=True)
        staged_producer = modules / "guestprogramproducer.nupp"
        shutil.copyfile(producer, staged_producer)
        staged_shim = modules / "guestauditshim.nupp"
        shutil.copyfile(audit_shim, staged_shim)
        fixed = ROOT / "build/core-guest-programs"
        fixed.mkdir(parents=True, exist_ok=True)
        snapshot = fixed / "snapshot.json"
        if snapshot.exists(): shutil.copyfile(snapshot, out / "previous-active-snapshot.json")
        staged_negative = fixed / "source/nupp/runtime/core/guestnegatives.nupp"
        staged_negative.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(negative, staged_negative)
        canonical = ["native/core/src/nupp/runtime/core/" + name + ".nupp" for name in
                     ("arena", "frames", "context", "frameaccess", "instances", "guestcatalog",
                      "guestentry", "guestops", "guesthandlers")]
        canonical += ["src/nupp/runtime/vm/" + name for name in
                      ("intrinsics.d.nupp", "program.d.nupp", "slots.d.nupp", "values.nupp")]
        canonical += [str(path.relative_to(ROOT)) for path in [negative, *fixture_paths]]
        snapshot.write_text(json.dumps({"version": 1, "target": "aarch64-apple-darwin",
            "sources": {name: (ROOT / name).read_text() for name in canonical}}, indent=2) + "\n")
        retained = out / "canonical-source-snapshot.json"
        shutil.copyfile(snapshot, retained)
        audit_fixed = ROOT / "build/core-guest-audit"
        audit_fixed.mkdir(parents=True, exist_ok=True)
        audit_snapshot = audit_fixed / "snapshot.json"
        if audit_snapshot.exists(): shutil.copyfile(audit_snapshot, out / "previous-audit-snapshot.json")
        audit_modules = audit_fixed / "source/nupp/runtime/core"
        audit_modules.mkdir(parents=True, exist_ok=True)
        staged_audit = audit_modules / "guestaudit.nupp"
        audit_negative = audit_modules / "guestnegatives.nupp"
        shutil.copyfile(audit_leaf, staged_audit)
        shutil.copyfile(negative, audit_negative)
        for source_root in (fixed, audit_fixed):
            module_root = source_root / "source/nupp/core"
            module_root.mkdir(parents=True, exist_ok=True)
            for fixture_name in ("catalog-module-prefix", "catalog-module-main",
                                 "catalog-module-middle", "catalog-module-triple"):
                staged = module_root / (fixture_name.replace("-", "") + ".nupp")
                shutil.copyfile(ROOT / "native/core/tests" / (fixture_name + ".nupp"), staged)
                inputs[str(staged.resolve())] = sha(staged)
        audit_canonical = [*canonical, str(audit_leaf.relative_to(ROOT))]
        audit_snapshot.write_text(json.dumps({"version": 1, "target": "aarch64-apple-darwin",
            "sources": {name: (ROOT / name).read_text() for name in audit_canonical}}, indent=2) + "\n")
        retained_audit = out / "audit-source-snapshot.json"
        shutil.copyfile(audit_snapshot, retained_audit)
        includes = ["src", *directories, ROOT / "native/crates/vm/lib", ROOT / "native/crates/vm/decls"]
        manifest = project / "nupp.lua"
        manifest.write_text("return {include = {" + ",".join(json.dumps(str(path)) for path in includes) + "}}\n")
        for path in (snapshot, retained, staged_negative, staged_producer, staged_shim, manifest,
                     audit_snapshot, retained_audit, staged_audit, audit_negative): inputs[str(path.resolve())] = sha(path)
        report["closedSourceSnapshot"] = {"path": str(retained), "sha256": sha(retained), "activePath": str(snapshot)}
        report["auditSourceSnapshot"] = {"path": str(retained_audit), "sha256": sha(retained_audit),
                                         "activePath": str(audit_snapshot)}
        vm, compiler = tools["runtime"], tools["compiler"]
        # Check every new executable body in one transaction, including fixed
        # source-session inputs not statically imported by the build producer.
        checked_files = [*fixture_paths, staged_producer, staged_shim, staged_audit, staged_negative,
            ROOT / "src/nupp/compiler/vm/nativeframecontract.nupp",
            ROOT / "src/nupp/compiler/vm/nativeframeverify.nupp",
            ROOT / "src/nupp/compiler/vm/coregraphexecutable.nupp",
            ROOT / "src/nupp/compiler/vm/corebytecode.nupp",
            ROOT / "src/nupp/compiler/vm/graphcopies.nupp",
            ROOT / "native/core/src/nupp/core/guestartifact.nupp",
            ROOT / "native/core/src/nupp/core/guestshim.nupp"]
        checked_files += [ROOT / "native/core/src/nupp/runtime/core" / (name + ".nupp")
                          for name in ("context", "guestcatalog", "guestentry", "guestops", "guesthandlers")]
        checked = json.loads(run("check", [vm, "exec", compiler, "nupp.tools.vm.root", "check", "--json",
                                         *checked_files], project))
        assert checked["ok"], checked
        image = out / "producer.image"
        run("emit", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project,
                     "nupp.core.guestprogramproducer", "", "--output", image, "--tasks"], project)
        inputs[str(image)] = sha(image)
        report["imageSha256"] = sha(image)
        empty = out / "empty.bin"
        empty.write_bytes(b"")
        for case_name in selected_cases:
            expected_word = CASES[case_name]
            for mode in ("normal", "spill"):
                case = case_name + "-" + mode
                selected = json.loads(json.loads(run("select-" + case, [vm, "run", image,
                    "nupp.core.guestprogramproducer", "compile", case_name, mode, str(args.scratch_bytes), "--tasks"])))
                selection = out / (case + ".json")
                selection.write_text(json.dumps(selected, indent=2) + "\n")
                assert selected["caseName"] == case_name and selected["mode"] == mode
                if mode == "spill":
                    normal = json.loads((out / (case_name + "-normal.json")).read_text())
                    assert selected["programs"] == normal["programs"], "allocation mode changes guest streams"
                assert selected["scratchBytes"] == args.scratch_bytes
                metrics = selected["metrics"]
                assert metrics and sum(item["spillSlots"] for item in metrics) > 0
                if mode == "spill":
                    assert all(item["integerRegisters"] == item["floatRegisters"] == 0 for item in metrics)
                high_water = selected["spillOffset"] + selected["callBytes"]
                assert high_water <= args.scratch_bytes
                code = b"".join(struct.pack("<I", word) for word in selected["words"])
                data = bytes.fromhex(selected["dataHex"])
                assert len(data) == selected["dataBytes"]
                assert struct.unpack_from("<Q", data)[0] == (4 if case_name == "numberBranch" else
                    3 if case_name.startswith("number") else
                    2 if case_name in ("modulePair", "moduleTriple") else 1)
                if case_name == "boolean":
                    assert struct.unpack_from("<14Q", data) == (
                        1, 2672, 2, 0, 112, 304, 2, 352, 1, 432, 1, 2, 624, 256)
                    assert hashlib.sha256(bytes.fromhex(selected["programs"][0]["codeHex"])).hexdigest() == (
                        "bbaf0a7f9d9dcd6953fd192d9590634ccb5dd148db52caae1f209c1399300289")
                bundle = out / (case + ".bundle")
                bundle.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                                  len(code), len(data), args.scratch_bytes, 1, 0) + code + data)
                expected_path = out / (case + "-expected.bin")
                expected_path.write_bytes(struct.pack("<Q", expected_word))
                output = out / (case + "-output.bin")
                run("native-" + case, [args.bridge, bundle, empty, output])
                assert output.read_bytes() == expected_path.read_bytes()
                guarded("guarded-" + case, bundle, empty, high_water, expected_path)
                if case_name == "modulePair":
                    descriptor = struct.unpack_from("<16Q", data)
                    assert descriptor[0] == 2 and descriptor[3] == 1 and descriptor[14] == 2
                    assert descriptor[10] == selected["instanceBound"] == selected["instanceCapacity"] == 1
                    assert selected["instanceCreations"] == 1
                    assert any(body["owner"] == 1 and any(instruction[0] == "Require"
                               for instruction in body["instructions"])
                               for body in selected["programs"])
                    entry_body = selected["programs"][1]
                    import_pc = next(index for index, instruction in enumerate(entry_body["instructions"])
                                     if instruction[0] == "Require")
                    wrong_target = bytearray(data)
                    struct.pack_into("<i", wrong_target,
                                     selected["catalogOffsets"]["code"][1] + import_pc * 16 + 4, 1)
                    wrong_bundle = out / (case + "-wrong-import.bundle")
                    wrong_bundle.write_bytes(bundle.read_bytes()[:72 + len(code)] + wrong_target)
                    guarded("refuse-" + case + "-wrong-import", wrong_bundle, empty, high_water, status=4)
                    assert struct.unpack_from("<2Q", data, descriptor[15]) == (0, 1)
                    for name, mutation in (("duplicate", "module"), ("count", "count")):
                        damaged = bytearray(data)
                        if mutation == "module":
                            struct.pack_into("<Q", damaged, descriptor[15], 1)
                        else:
                            struct.pack_into("<Q", damaged, 14 * 8, 3)
                        damaged_bundle = out / (case + "-" + name + ".bundle")
                        damaged_bundle.write_bytes(bundle.read_bytes()[:72 + len(code)] + damaged)
                        guarded("refuse-" + case + "-" + name, damaged_bundle, empty, high_water, status=1)
                if case_name == "moduleTriple":
                    descriptor = struct.unpack_from("<16Q", data)
                    assert descriptor[0] == 2 and descriptor[3] == 2 and descriptor[14] == 3
                    assert struct.unpack_from("<3Q", data, descriptor[15]) == (0, 1, 2)
                    assert selected["instanceCreations"] == 2
                    assert selected["programs"][0]["calls"] and selected["programs"][1]["calls"]
                    assert selected["programs"][2]["owner"] == 2
                    damaged = bytearray(data)
                    struct.pack_into("<Q", damaged, descriptor[15] + 8, 2)
                    wrong = out / (case + "-duplicate-middle.bundle")
                    wrong.write_bytes(bundle.read_bytes()[:72 + len(code)] + damaged)
                    guarded("refuse-" + case + "-duplicate-middle", wrong, empty, high_water, status=1)
                if case_name == "numberAdd":
                    body = selected["programs"][-1]
                    add_pc = next(index for index, instruction in enumerate(body["instructions"])
                                  if instruction[0] == "Add")
                    assert body["instructions"][add_pc][0] == "Add"
                    damaged = bytearray(data)
                    damaged[selected["catalogOffsets"]["code"][-1] + add_pc * 16 + 3] = 249
                    wrong = out / (case + "-wrong-add-slot.bundle")
                    wrong.write_bytes(bundle.read_bytes()[:72 + len(code)] + damaged)
                    sentinel = b"invalid numeric slot left output unchanged"
                    unchanged = out / (case + "-wrong-add-slot-output.bin")
                    unchanged.write_bytes(sentinel)
                    run("refuse-" + case + "-wrong-add-slot", [args.bridge, wrong, empty, unchanged], expected=1)
                    assert unchanged.read_bytes() == sentinel
                    malformed = bytearray(data)
                    struct.pack_into("<Q", malformed, selected["catalogOffsets"]["constants"][0],
                                     CASES["boolean"])
                    bad_operand = out / (case + "-tagged-operand.bundle")
                    bad_operand.write_bytes(bundle.read_bytes()[:72 + len(code)] + malformed)
                    operand_output = out / (case + "-tagged-operand-output.bin")
                    operand_output.write_bytes(sentinel)
                    run("refuse-" + case + "-tagged-operand",
                        [args.bridge, bad_operand, empty, operand_output], expected=1)
                    assert operand_output.read_bytes() == sentinel
                if case_name == "numberBranch":
                    body = selected["programs"][-1]
                    less_than = [index for index, instruction in enumerate(body["instructions"])
                                 if instruction[0] == "Lt"]
                    branches = [instruction for instruction in body["instructions"]
                                if instruction[0] == "JmpIf"]
                    assert len(less_than) == len(branches) == 2
                    damaged = bytearray(data)
                    damaged[selected["catalogOffsets"]["code"][-1] + less_than[0] * 16 + 3] = 249
                    wrong = out / (case + "-wrong-lt-slot.bundle")
                    wrong.write_bytes(bundle.read_bytes()[:72 + len(code)] + damaged)
                    sentinel = b"invalid numeric comparison left output unchanged"
                    unchanged = out / (case + "-wrong-lt-slot-output.bin")
                    unchanged.write_bytes(sentinel)
                    run("refuse-" + case + "-wrong-lt-slot", [args.bridge, wrong, empty, unchanged], expected=1)
                    assert unchanged.read_bytes() == sentinel
                    malformed = bytearray(data)
                    struct.pack_into("<Q", malformed, selected["catalogOffsets"]["constants"][-1], CASES["boolean"])
                    bad_operand = out / (case + "-tagged-lt-operand.bundle")
                    bad_operand.write_bytes(bundle.read_bytes()[:72 + len(code)] + malformed)
                    operand_output = out / (case + "-tagged-lt-operand-output.bin")
                    operand_output.write_bytes(sentinel)
                    run("refuse-" + case + "-tagged-lt-operand",
                        [args.bridge, bad_operand, empty, operand_output], expected=1)
                    assert operand_output.read_bytes() == sentinel
                short = run("short-" + case, [guard_binary, "--ignored", "--exact",
                    "abi::generated_entry_refuses_short_regions", "--test-threads=1"], extra={
                        "CORE_TEST_BUNDLE": str(bundle), "CORE_TEST_INPUT": str(empty), "CORE_TEST_HIGH_WATER": "0"})
                assert b"1 passed; 0 failed; 0 ignored;" in short
                report["programs"].append({"case": case, "expectedHex": f"{expected_word:016x}",
                    "bundleSha256": sha(bundle), "selectionSha256": sha(selection), "highWater": high_water,
                    "dataflowRefusals": selected["dataflowRefusals"], "provenanceRefusals": selected["provenanceRefusals"]})
                if case_name == "modulePair" and mode == "spill":
                    refusal = "refuse-modulePair-spill-64KiB"
                    run(refusal, [vm, "run", image, "nupp.core.guestprogramproducer", "compile",
                        case_name, mode, "65536", "--tasks"], expected=1)
                    diagnostic = (out / (refusal + ".err")).read_text()
                    assert "core link call-chain spill extent" in diagnostic, diagnostic
                    report["spillExtentRefusal"] = {"availableBytes": 65536, "diagnostic": diagnostic.strip()}
                # Budget failures run the same authenticated bytes. Success is
                # never inferred from transport alone; the primary run above
                # checked the exact Boolean/NIL output independently.
                budgets = ((0, 0, 2), (0, 1, 3))
                if case_name == "nested": budgets += ((2, 0, 2), (4, 0, 2))
                if case_name == "modulePair": budgets += ((1, 0, 2), (2, 0, 2))
                if case_name == "moduleTriple": budgets += ((1, 0, 2),)
                for budget, cancel, status in budgets:
                    label = f"{case}-budget{budget}-cancel{cancel}"
                    input_path = out / (label + ".bin")
                    input_path.write_bytes(struct.pack("<QQ", budget, cancel))
                    guarded("refuse-" + label, bundle, input_path, high_water, status=status)
                    if (case_name == "modulePair" and budget in (1, 2)
                            or case_name == "moduleTriple" and budget == 1) and cancel == 0:
                        output_path = out / (label + "-unchanged.bin")
                        sentinel = b"initializer refusal left output unchanged"
                        output_path.write_bytes(sentinel)
                        run("native-refuse-" + label, [args.bridge, bundle, input_path, output_path], expected=1)
                        assert output_path.read_bytes() == sentinel, "failed initializer published output"
                    report["failures"].append({"case": case, "budget": budget, "cancel": cancel,
                                               "status": status, "bundleSha256": sha(bundle)})
                save()
        # These are additional fixed audits, after all primary bundles have
        # independently returned their exact guest outputs. They do not replace
        # a primary program run or broaden the production entry's ABI.
        audit_cases = [("fresh", "success"), ("nilValue", "success"), ("nested", "success"),
                       ("nested", "budget0"), ("nested", "budget2"), ("nested", "budget4"),
                       ("nested", "cancel"), ("modulePair", "budget1")]
        audit_cases = [(case_name, scenario) for case_name, scenario in audit_cases
                       if case_name in selected_cases]
        for mode in ("normal", "spill"):
            for case_name, scenario in audit_cases:
                case = f"audit-{case_name}-{mode}-{scenario}"
                selected = json.loads(json.loads(run("select-" + case, [vm, "run", image,
                    "nupp.core.guestprogramproducer", "audit", case_name, mode, str(args.scratch_bytes), scenario, "--tasks"])))
                selection = out / (case + ".json")
                selection.write_text(json.dumps(selected, indent=2) + "\n")
                audit = selected["audit"]
                assert audit["scenario"] == scenario and audit["primaryScratchBytes"] == args.scratch_bytes
                assert selected["caseName"] == case_name and selected["mode"] == mode
                if mode == "spill":
                    assert all(item["integerRegisters"] == item["floatRegisters"] == 0 for item in selected["metrics"])
                high_water = selected["spillOffset"] + selected["callBytes"]
                assert high_water <= selected["scratchBytes"] <= 1048576
                primary = json.loads((out / (case_name + "-" + mode + ".json")).read_text())
                assert selected["programs"] == primary["programs"], "audit changes actual guest stream"
                assert selected["words"][:audit["primaryWords"]] == primary["words"], "audit changes primary linked code"
                assert selected["dispatch"] == primary["dispatch"], "audit changes primary dispatch"
                code = b"".join(struct.pack("<I", word) for word in selected["words"])
                data = bytes.fromhex(selected["dataHex"])
                bundle = out / (case + ".bundle")
                bundle.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                    len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
                input_path = empty
                if scenario != "success":
                    budget, cancel = {"budget0": (0, 0), "budget1": (1, 0), "budget2": (2, 0),
                                      "budget4": (4, 0), "cancel": (0, 1)}[scenario]
                    input_path = out / (case + "-input.bin")
                    input_path.write_bytes(struct.pack("<QQ", budget, cancel))
                    expected_status = 3 if scenario == "cancel" else 2
                    assert audit["expectedStatus"] == expected_status
                    guarded("guarded-" + case, bundle, input_path, high_water, status=expected_status)
                else:
                    assert audit["expectedStatus"] == 0
                    expected_path = out / (case + "-expected.bin")
                    expected_path.write_bytes(struct.pack("<Q", CASES[case_name]))
                    output = out / (case + "-output.bin")
                    run("native-" + case, [args.bridge, bundle, input_path, output])
                    assert output.read_bytes() == expected_path.read_bytes()
                    guarded("guarded-" + case, bundle, input_path, high_water, expected_path)
                report["audits"].append({"case": case, "scenario": scenario, "status": audit["expectedStatus"],
                    "bundleSha256": sha(bundle), "selectionSha256": sha(selection), "highWater": high_water,
                    "expectedUsed": audit["expectedUsed"], "expectedOwner": audit["expectedOwner"],
                    "expectedPC": audit["expectedPC"], "snapshotBytes": audit["snapshotBytes"],
                    "workspaceBytes": audit["workspaceBytes"]})
                save()
        report.update(status="passed", supplementalAudits=len(report["audits"]), nativeOutputs=len(report["programs"]),
                      guardedOutputs=len(report["programs"]), shortRegionRefusals=5 * len(report["programs"]),
                      policyRefusals=len(report["failures"]))
    except Exception as error:
        report.update(status="failed", error=repr(error))
        raise
    finally:
        changed = [path for path, digest in inputs.items() if not Path(path).is_file() or sha(path) != digest]
        if changed:
            report.update(status="failed", changedFinalInputs=changed)
        report["artifactManifest"] = "artifacts.json"
        save()
        artifacts = {str(path.relative_to(out)): sha(path) for path in sorted(out.rglob("*"))
                     if path.is_file() and path != out / "artifacts.json"}
        (out / "artifacts.json").write_text(json.dumps(artifacts, indent=2) + "\n")
        assert not changed, "inputs changed after final child: " + repr(changed)


if __name__ == "__main__":
    main()
