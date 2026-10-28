#!/usr/bin/env python3
"""Exercise checked integer programs on the standalone Nupp core."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import subprocess
import time

EXPECTED = {"add": 42, "wrap": 0x8000000000000000, "bits": 1}
CONTROL_FLOW = {"conditional": 42, "conditional-false": 99,
                "signed-conditional": 42, "join": 42, "loop": 15, "zero": 0, "parallel": 20, "zero-loop": 0, "boolean-join": 42, "copy-cycle": 30}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--programs", type=Path, required=True)
    parser.add_argument("--builder", type=Path, required=True)
    parser.add_argument("--compiler-image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--control-flow", action="store_true")
    args = parser.parse_args()
    bridge, programs, builder, image, out = [p.resolve() for p in
        (args.bridge, args.programs, args.builder, args.compiler_image, args.output)]
    out.mkdir(parents=True, exist_ok=False)
    env = {k: v for k, v in os.environ.items()
           if not k.startswith(("NUPP_", "JIT_", "GC_", "LUA"))
           and k not in ("NO_AOT", "NO_JIT", "OP_STATS")}
    report = {
        "scope": "First checked integer programs on the standalone core; trusted build artifacts, no untrusted runtime-image admission claim",
        "status": "running",
        "inputs": {str(p): sha(p) for p in (bridge, builder, Path(__file__))},
        "runs": [], "refusals": [],
        "measurement": "One fresh-process wall smoke per fixture/mode, including process startup. Diagnostic only; no threshold or comparison."
    }
    if image.exists():
        report["inputs"][str(image)] = sha(image)
    program_proof = programs / "proof.json"
    program_facts = json.loads(program_proof.read_text())
    assert program_facts["status"] in {
        "verified-first-program-artifacts",
        "all-nine-checked-cfg-fixtures-and27-verifier-cases-passed"}
    if args.control_flow:
        assert program_facts["verifierCases"] >= 15
        assert program_facts["guestPath"] == ["checker", "lower.functionGraph", "vm.graph", "graph.lower", "program.fromBlocks"]
        mechanism = programs / "mechanism.json"
        mechanisms = json.loads(mechanism.read_text())
        assert mechanisms["loop"]["negativeJmpCount"] > 0
        for name in ("conditional", "conditional-false", "signed-conditional", "join", "loop"):
            assert mechanisms[name]["conditionalCount"] > 0
        for name, facts in mechanisms.items():
            assert sha(programs / (name + ".program")) == facts["programSha256"]
            assert sha(programs / (name + ".json")) == facts["metadataSha256"]
        report["inputs"][str(mechanism)] = sha(mechanism)
    report["inputs"][str(program_proof)] = sha(program_proof)
    provenance = programs / "driver-hardening.json"
    if provenance.exists():
        report["inputs"][str(provenance)] = sha(provenance)
    empty = out / "input.bin"
    empty.write_bytes(b"")

    def save():
        (out / "receipt.json").write_text(json.dumps(report, indent=2) + "\n")

    def run(label, argv, expected_code=0):
        start = time.monotonic_ns()
        with (out / (label + ".out")).open("xb") as stdout, (out / (label + ".err")).open("xb") as stderr:
            child = subprocess.run(list(map(str, argv)), env=env, stdout=stdout,
                                   stderr=stderr, timeout=1800 if label.endswith("-build") else 60)
        elapsed = time.monotonic_ns() - start
        if expected_code is not None and child.returncode != expected_code:
            raise RuntimeError(f"{label}: exit {child.returncode}; see {out / (label + '.err')}")
        return child.returncode, elapsed

    try:
        bundles = []
        expected_cases = dict(EXPECTED, **(CONTROL_FLOW if args.control_flow else {}))
        fixtures = [(name, expected, programs / (name + ".program"),
                     programs / (name + ".json")) for name, expected in expected_cases.items()]
        # Repeat a checked closed body to exercise tail dispatch far beyond the
        # bounded spill arena's capacity if a transfer leaked its frame extent.
        # This adds no new instruction or arithmetic implementation.
        repeated = out / "dispatch-reuse.program"
        original_add = (programs / "add.program").read_bytes()
        repeated.write_bytes(original_add[:-16] * 4096 + original_add[-16:])
        repeated_meta = out / "dispatch-reuse.json"
        repeated_facts = json.loads((programs / "add.json").read_text())
        repeated_meta.write_text(json.dumps({"slots": repeated_facts["slots"],
            "count": len(repeated.read_bytes()) // 16,
            "provenance": "4096 repetitions of the checked add body, one final CoreStop"}) + "\n")
        fixtures.append(("dispatch-reuse", 42, repeated, repeated_meta))
        for name, expected, source, metadata in fixtures:
            for path in (source, metadata):
                report["inputs"][str(path)] = sha(path)
            facts = json.loads(metadata.read_text())
            for mode in ("normal", "spill"):
                label = name + "-" + mode
                directory = out / label
                run(label + "-build", ["python3", builder, "--program", source,
                    "--slots", str(facts["slots"]), "--output", directory,
                    "--mode", mode, "--compiler-image", image])
                current_image = sha(image)
                assert report["inputs"].setdefault(str(image), current_image) == current_image
                produced = json.loads((directory / "proof.json").read_text())
                assert produced["status"] == "verified-owned-bundle"
                assert produced["mode"] == mode
                handlers = produced["handlers"]
                assert len(handlers) >= 13
                spill_slots = sum(item["spillSlots"] for item in handlers)
                if mode == "spill":
                    assert spill_slots > 0, "forced-spill mode did not allocate spills"
                    assert all(item["integerRegisters"] == 0 and item["floatRegisters"] == 0
                               for item in handlers)
                bundle = directory / "core.bundle"
                result = out / (label + ".bin")
                _, wall = run(label, [bridge, bundle, empty, result])
                raw = result.read_bytes()
                assert len(raw) == 8, (label, "output size", len(raw))
                actual, = struct.unpack("<Q", raw)
                assert actual == expected, (label, hex(actual), hex(expected))
                report["runs"].append({"fixture": name, "mode": mode,
                    "expectedBits": expected, "actualBits": actual,
                    "bundleSha256": sha(bundle), "producerProofSha256": sha(directory / "proof.json"),
                    "allocatedSpillSlots": spill_slots, "wallSmokeNs": wall})
                bundles.append(bundle)
                save()
        if args.control_flow:
            loop_bytes = (programs / "loop.program").read_bytes()
            records = [loop_bytes[i:i + 16] for i in range(0, len(loop_bytes), 16)]
            assert any(row[0] == 20 for row in records), "loop has no conditional transfer"
            assert any(row[0] == 19 and struct.unpack_from("<i", row, 4)[0] < 0
                       for row in records), "loop has no back edge"
            for mode in ("normal", "spill"):
                bundle = out / ("loop-" + mode) / "core.bundle"
                for label, budget, cancelled, status in (
                    ("exact-budget", 5, 0, 0), ("short-budget", 4, 0, 2),
                    ("zero-budget", 0, 0, 2), ("cancelled", (1 << 64) - 1, 1, 3),
                    ("cancel-priority", 0, 1, 3)):
                    name = mode + "-" + label
                    inputs = out / (name + "-input.bin")
                    inputs.write_bytes(struct.pack("<QQ", budget, cancelled))
                    result = out / (name + "-result.bin")
                    sentinel = b"preserve output on failure"
                    result.write_bytes(sentinel)
                    code, wall = run(name, [bridge, bundle, inputs, result], None)
                    if status == 0:
                        assert code == 0 and result.read_bytes() == struct.pack("<Q", 15), name
                    else:
                        assert code != 0 and result.read_bytes() == sentinel, name
                        error = (out / (name + ".err")).read_text()
                        assert f"Nupp entry refused with transport status {status}" in error, (name, error)
                    report.setdefault("policy", []).append({"mode": mode, "probe": label,
                        "budget": budget, "cancelled": cancelled, "expectedStatus": status,
                        "returnCode": code, "wallSmokeNs": wall})
                    save()
        if args.control_flow:
            # Wire fixtures exercise both canonical back-edge handlers. Nupp's
            # verifier admits each packet before the owned code executes it;
            # this driver does not interpret their guest instructions.
            def record(op, a=0, b=0, c=0, displacement=0, immediate=0):
                return struct.pack("<4BiQ", op, a, b, c, displacement, immediate)

            edge_cases = (
                ("unconditional-cycle", record(19, displacement=-1),
                 ((0, 0, 2, None), (2, 0, 2, None), (0, 1, 3, None))),
                ("conditional-cycle", record(1, immediate=0)
                 + record(20, displacement=-1) + record(0),
                 ((0, 0, 2, None), (2, 0, 2, None), (0, 1, 3, None))),
                ("untaken-back-edge", record(1, immediate=1)
                 + record(20, displacement=-1) + record(0),
                 ((0, 0, 0, 1), (0, 1, 0, 1))),
                ("forward-edge", record(1, immediate=7) + record(19) + record(0),
                 ((0, 0, 0, 7), (0, 1, 0, 7))),
            )
            for name, code_bytes, probes in edge_cases:
                source = out / (name + ".program")
                source.write_bytes(code_bytes)
                report["inputs"][str(source)] = sha(source)
                for mode in ("normal", "spill"):
                    directory = out / (name + "-" + mode)
                    run(name + "-" + mode + "-build", ["python3", builder,
                        "--program", source, "--slots", "1", "--output", directory,
                        "--mode", mode, "--compiler-image", image])
                    proof = json.loads((directory / "proof.json").read_text())
                    assert proof["status"] == "verified-owned-bundle"
                    bundle = directory / "core.bundle"
                    for index, (budget, cancelled, status, expected) in enumerate(probes):
                        label = name + "-" + mode + "-" + str(index)
                        inputs = out / (label + "-input.bin")
                        inputs.write_bytes(struct.pack("<QQ", budget, cancelled))
                        result = out / (label + "-result.bin")
                        sentinel = b"preserve output on failure"
                        result.write_bytes(sentinel)
                        code, wall = run(label, [bridge, bundle, inputs, result], None)
                        if status == 0:
                            assert code == 0 and result.read_bytes() == struct.pack("<Q", expected), label
                        else:
                            assert code != 0 and result.read_bytes() == sentinel, label
                            error = (out / (label + ".err")).read_text()
                            assert f"Nupp entry refused with transport status {status}" in error, (label, error)
                        report.setdefault("edgePolicy", []).append({"fixture": name,
                            "mode": mode, "budget": budget, "cancelled": cancelled,
                            "expectedStatus": status, "expectedBits": expected,
                            "returnCode": code, "bundleSha256": sha(bundle),
                            "producerProofSha256": sha(directory / "proof.json"),
                            "wallSmokeNs": wall})
                        save()
        original = bundles[0].read_bytes()
        malformed = {"truncated": original[:71], "wrong-magic": b"X" + original[1:],
                     "trailing-byte": original + b"\0"}
        for label, field, value in (("version", 0, 2), ("architecture", 1, 2),
                                    ("unaligned-entry", 2, 1), ("empty-code", 3, 0),
                                    ("oversized-scratch", 5, (1 << 64) - 1),
                                    ("reserved", 7, 1)):
            payload = bytearray(original)
            struct.pack_into("<Q", payload, 8 + field * 8, value)
            malformed[label] = bytes(payload)
        for label, data in malformed.items():
            path = out / (label + ".bundle")
            path.write_bytes(data)
            result = out / (label + ".bin")
            sentinel = b"preserve existing output"
            result.write_bytes(sentinel)
            code, _ = run("refuse-" + label, [bridge, path, empty, result], None)
            assert code != 0 and result.read_bytes() == sentinel, label
            report["refusals"].append(label)
            save()
        assert all(sha(path) == digest for path, digest in report["inputs"].items())
        report["status"] = "passed"
        print(f"{len(report['runs'])} standalone program executions; {len(report['refusals'])} transport refusals")
    except BaseException as error:
        report["status"] = "failed"
        report["error"] = repr(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
