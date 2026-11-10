#!/usr/bin/env python3
"""Prove issued v2 raw graph admission reaches the retained guest entry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tarfile
import time

ROOT = Path(__file__).resolve().parents[3]
RAW = ("rawwire", "rawheader", "rawroles", "rawshape", "rawcatalogpolicy",
       "rawcatalog", "rawbudgetpolicy", "rawbudget", "rawsemanticpolicy",
       "rawsemantics", "rawexecutablepolicy", "rawexecutable")
GUEST = ("arena", "frames", "context", "frameaccess", "instances",
         "guestcatalog", "guestentry", "guestops", "guesthandlers")
ARCHIVE_ROOT = "raw-executable-proof-20261030-v2-final/"
KINDS = ("true", "false", "nil", "missing", "call", "require")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bridge", type=Path, required=True)
    parser.add_argument("--bootstrap", type=Path, required=True)
    parser.add_argument("--graph-archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--modes", nargs="+", choices=("normal", "spill"), default=("normal", "spill"))
    parser.add_argument("--kinds", nargs="+", choices=(*KINDS, "truncated"), default=(*KINDS, "truncated"))
    args = parser.parse_args()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    freeze = json.loads((args.bootstrap / "freeze.json").read_text())
    vm = Path(freeze["artifacts"][freeze["coreBuildTool"]["runtime"]]["path"])
    compiler = Path(freeze["artifacts"][freeze["coreBuildTool"]["compiler"]]["path"])
    assert sha(vm) == freeze["artifacts"][freeze["coreBuildTool"]["runtime"]]["sha256"]
    assert sha(compiler) == freeze["artifacts"][freeze["coreBuildTool"]["compiler"]]["sha256"]
    with tarfile.open(args.graph_archive, "r:gz") as archive:
        old = json.load(archive.extractfile(ARCHIVE_ROOT + "receipt.json"))
        assert old["status"] == "passed"
        assert {case["kind"] for case in old["cases"]} >= set(KINDS)
        graphs = {kind: archive.extractfile(ARCHIVE_ROOT + kind + ".graph").read()
                  for kind in KINDS}
    assert all(graph[8:16] == struct.pack("<II", 2, 2) for graph in graphs.values())
    operations = struct.unpack_from("<IIQQQ", graphs["require"], 48 + 13 * 32)
    assert operations[:2] == (13, 24) and operations[2] > 0
    assert any(struct.unpack_from("<I", graphs["require"], operations[3] + i * 24)[0] == 1
               for i in range(operations[2])), "checker-produced graph lacks Require"
    fixture = ROOT / "native/core/tests/raw-executable-fixture.nupp"
    assert any(path.endswith("raw-executable-fixture.nupp") and digest == sha(fixture)
               for path, digest in old["inputs"].items())
    files = [*ROOT.joinpath("src").rglob("*.nupp"),
             *ROOT.joinpath("native/core/src").rglob("*.nupp"),
             ROOT / "native/core/tests/guest-program-producer.nupp",
             ROOT / "native/core/tests/guest-audit-shim.nupp",
             ROOT / "native/core/tests/guest-contract-negatives.nupp",
             ROOT / "native/core/tests/catalog-boolean.nupp",
             Path(__file__), args.bridge, args.graph_archive,
             args.bootstrap / "freeze.json", vm, compiler]
    inputs = {str(path.resolve()): sha(path) for path in files}
    receipt = {"status": "running", "scope": "Issued raw loader, derived v2 graph catalog, "
               "retained guest entry; one initializer and K/Nil/Move/Ret only",
               "limits": "Fixed source-bound acceptance shim only; no general product raw loader API "
                         "or OS page protection for the derived scratch catalog.",
               "inputs": inputs, "graphProofSha256": sha(args.graph_archive),
               "graphReceiptSha256": hashlib.sha256(json.dumps(old, sort_keys=True).encode()).hexdigest(),
               "steps": [], "cases": []}
    env = {key: value for key, value in os.environ.items()
           if not key.startswith(("NUPP_", "JIT_", "GC_", "LUA"))}
    env.update(NO_AOT="1", NO_JIT="1", NUPP_COMPILER_ROOT=str(ROOT),
               NUPP_VM_AUTO_REBUILD="0", NUPP_VM_AUTO_LINK="0", NUPP_VM_EMIT_CACHE="")

    def save():
        (out / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")

    def run(name, command, cwd=ROOT, expected=0):
        for path, digest in inputs.items():
            assert sha(path) == digest, "changed proof input: " + path
        save()
        started = time.perf_counter()
        with (out / (name + ".out")).open("xb") as stdout, (out / (name + ".err")).open("xb") as stderr:
            child = subprocess.run(list(map(str, command)), cwd=cwd, env=env,
                                   stdout=stdout, stderr=stderr, timeout=1800)
        receipt["steps"].append({"name": name, "returnCode": child.returncode,
                                 "seconds": time.perf_counter() - started})
        save()
        assert child.returncode == expected, (name, (out / (name + ".err")).read_text()[-3000:])
        return (out / (name + ".out")).read_bytes()

    try:
        project = out / "project"
        modules = project / "src/nupp/core"
        modules.mkdir(parents=True)
        for source, target in (
            ("guest-program-producer.nupp", "guestprogramproducer.nupp"),
            ("guest-audit-shim.nupp", "guestauditshim.nupp")
        ):
            shutil.copyfile(ROOT / "native/core/tests" / source, modules / target)
        includes = [str(project / "src"), *[str(ROOT / part) for part in (
            "src", "native/core/src", "native/crates/vm/lib",
            "native/crates/vm/decls")]]
        (project / "nupp.lua").write_text("return {include = {" +
                                          ",".join(map(json.dumps, includes)) + "}}\n")
        fixed = ROOT / "build/core-guest-raw-entry"
        fixed.mkdir(parents=True, exist_ok=True)
        snapshot = fixed / "snapshot.json"
        if snapshot.exists():
            shutil.copyfile(snapshot, out / "previous-snapshot.json")
        negative = fixed / "source/nupp/runtime/core/guestnegatives.nupp"
        negative.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "native/core/tests/guest-contract-negatives.nupp", negative)
        canonical = ["native/core/src/nupp/runtime/core/" + name + ".nupp" for name in (*GUEST, *RAW)]
        canonical += ["src/nupp/runtime/vm/" + name for name in (
            "intrinsics.d.nupp", "program.d.nupp", "slots.d.nupp", "values.nupp")]
        canonical += ["native/core/tests/guest-contract-negatives.nupp",
                      "native/core/tests/catalog-boolean.nupp"]
        snapshot.write_text(json.dumps({"version": 1, "target": "aarch64-apple-darwin",
            "sources": {name: (ROOT / name).read_text() for name in canonical}}, indent=2) + "\n")
        shutil.copyfile(snapshot, out / "source-snapshot.json")
        producer = out / "producer.image"
        run("producer-emit", [vm, "run", compiler, "nupp.tools.vm.project", "emit", project,
                              "nupp.core.guestprogramproducer", "", "--output", producer, "--tasks"], project)
        empty = out / "empty.bin"
        empty.write_bytes(b"")
        for mode in args.modes:
            selected = json.loads(json.loads(run("select-" + mode,
                [vm, "run", producer, "nupp.core.guestprogramproducer",
                 "compileRaw", mode, "--tasks"], project)))
            assert selected["scratchBytes"] == 33554432
            assert selected["spillOffset"] + selected["callBytes"] <= selected["scratchBytes"]
            if mode == "spill":
                assert any(row["spillSlots"] > 0 for row in selected["metrics"])
            code = b"".join(struct.pack("<I", word) for word in selected["words"])
            for kind in args.kinds:
                data = graphs["true"][:-8] if kind == "truncated" else graphs[kind]
                bundle = out / (mode + "-" + kind + ".bundle")
                bundle.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                    len(code), len(data), selected["scratchBytes"], 1, 0) + code + data)
                answer = out / (mode + "-" + kind + ".bin")
                sentinel = b"unpublished raw result"
                answer.write_bytes(sentinel)
                refused = kind in ("missing", "call", "require", "truncated")
                run("native-" + mode + "-" + kind,
                    [args.bridge, bundle, empty, answer], expected=1 if refused else 0)
                if refused:
                    assert answer.read_bytes() == sentinel, (mode, kind, "partial result published")
                else:
                    wanted = {"true": 0x7FFB000000000000, "false": 0x7FFA000000000000,
                              "nil": 0x7FF9000000000000}[kind]
                    assert answer.read_bytes() == struct.pack("<Q", wanted), (mode, kind)
                receipt["cases"].append({"mode": mode, "kind": kind, "refused": refused,
                                         "bundleSha256": sha(bundle), "outputSha256": sha(answer)})
                save()
            if "true" in args.kinds:
                true_bundle = out / (mode + "-true.bundle")
                original = true_bundle.read_bytes()
                forged = out / (mode + "-forged-code-extent.bundle")
                forged.write_bytes(struct.pack("<8s8Q", b"NUPPCORE", 1, 1, selected["entry"],
                    len(code) + 4, len(graphs["true"]), selected["scratchBytes"], 1, 0)
                    + code + bytes(4) + graphs["true"])
                assert original != forged.read_bytes()
                answer = out / (mode + "-forged-code-extent.bin")
                answer.write_bytes(b"unpublished raw result")
                run("native-" + mode + "-forged-code-extent",
                    [args.bridge, forged, empty, answer], expected=1)
                assert answer.read_bytes() == b"unpublished raw result"
                receipt["cases"].append({"mode": mode, "kind": "forged-code-extent", "refused": True,
                                         "bundleSha256": sha(forged), "outputSha256": sha(answer)})
                save()
        receipt["status"] = "passed"
    except BaseException as error:
        receipt["status"], receipt["error"] = "failed", str(error)
        raise
    finally:
        save()


if __name__ == "__main__":
    main()
