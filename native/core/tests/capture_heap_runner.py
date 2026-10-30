#!/usr/bin/env python3
"""Bind a completed preflight's runner for graph-only heap preparation.

Read/hash only except the new binding output. Requires exclusive runner access
and uninterrupted source freeze from the completed focused build to capture.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from heap_runner_support import (INPUT_INVENTORY_VERSION, RUNNER_ARTIFACTS, reuse_runner,
                                 runner_attachment, runner_inputs, sha, source_paths, verify_runner_state)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--source-proof", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    root, proof_path, output = args.root.resolve(), args.source_proof.resolve(), args.output.resolve()
    output.relative_to(root / "build")
    assert output.parent.is_dir() and not output.exists()
    proof = json.loads(proof_path.read_text())
    assert proof["status"] in ("passed", "failed") and "active" not in proof
    assert proof["sourceUnchanged"] is True and proof["toolsUnchanged"] is True
    frozen = proof["frozen"]
    assert frozen
    assert any(s["name"] == "union-check" and s["status"] == 0 for s in proof["steps"])
    reused = proof.get("reusedBuild")
    if reused:
        assert not any(s["name"] == "focused" for s in proof["steps"])
        assert proof["status"] == "passed"
        assert reuse_runner(root, reused["path"], frozen, proof["tools"]) == reused
    else:
        focused = [s for s in proof["steps"] if s["name"] == "focused"]
        assert len(focused) == 1
        focused = focused[0]
        assert type(focused["status"]) is int and focused["status"] in (0, 1)
        assert focused["command"][:2] == [str(root / "bin/nupp"), "test"]
        stdout, stderr = proof_path.parent / "focused.out", proof_path.parent / "focused.err"
        assert sha(stdout) == focused["stdoutSHA256"] and sha(stderr) == focused["stderrSHA256"]
        summaries = re.findall(r"(?m)^\s*(\d+) tests, (\d+) passed, (\d+) skipped, (\d+) failed", stdout.read_text())
        assert len(summaries) == 1, "no unique terminal runner totals; build may have failed before tests"
        total, passed, skipped, failed = map(int, summaries[0])
        assert total > 0 and total == passed + skipped + failed
        assert (focused["status"] == 0) == (failed == 0), "runner exit/totals disagree"
    for relative, digest in frozen.items():
        assert not Path(relative).is_absolute() and ".." not in Path(relative).parts
        assert sha(root / relative) == digest, "frozen source changed: " + relative
    for path, digest in proof["tools"].items():
        assert sha(path) == digest, "frozen tool changed: " + path
    folder = root / "build/test-runner"
    assert not (folder / ".nupp-complete.pending").exists()
    paths = {name: root / relative for name, relative in RUNNER_ARTIFACTS.items()}
    artifacts = {name: {"path": str(path), "sha256": sha(path)} for name, path in paths.items()}
    state = json.loads(paths["state"].read_text())
    assert paths["complete"].read_text().strip() == state["compilerHash"]
    assert state["targets"]["testRunner"] == ["build/nupp-test"]
    assert state["outputs"]["build/nupp-test"] is True
    for name in ("nativeframecontract", "nativecellcontract", "nativeunit", "nativegraph", "nativeservice", "nativecleanup", "graph", "lower"):
        item = state["modules"]["nupp.compiler.vm." + name]
        assert item["sourcePath"] == "src/nupp/compiler/vm/" + name + ".nupp"
        assert item["sourcePath"] in frozen
    inputs = None
    if proof.get("inputInventoryVersion") == INPUT_INVENTORY_VERSION:
        inputs = runner_inputs(frozen)
        assert inputs == proof["runnerInputs"]
        verify_runner_state(root, state, inputs)
    payload = paths["payload"].read_bytes()
    assert payload == paths["image"].read_bytes(), "runner payload/image mismatch"
    attachment = runner_attachment(paths["runner"].read_bytes(), payload)
    sources, supplemental = {}, {}
    base_ref = proof["base"]
    assert re.fullmatch(r"[0-9a-f]{40}", base_ref), "exact base commit required"
    for path in source_paths(root):
        relative = str(path.relative_to(root))
        sources[relative] = sha(path)
        if relative in frozen:
            assert frozen[relative] == sources[relative], "production source differs from proof"
        else:
            # The prior preflight excluded every path segment named build,
            # including legitimate tools/build source. No prebuild hash exists
            # for these files. Admit only bytes identical to its exact base.
            original = subprocess.check_output(["git", "show", base_ref + ":" + relative], cwd=root)
            assert path.read_bytes() == original, "unbound source differs from accepted base: " + relative
            supplemental[relative] = sources[relative]
    binding = {"version": 1, "status": "runner-build-completed", "root": str(root),
               "sourceUnchanged": True, "sourceProof": str(proof_path), "sourceProofSha256": sha(proof_path),
               "sources": sources, "supplementalBaseSources": supplemental, "baseRef": base_ref,
               "supplementalEvidence": "bound at capture; exact accepted-base bytes; no prebuild hash claimed",
               "attachment": attachment, **artifacts,
               "captureDriver": {"path": str(Path(__file__).resolve()), "sha256": sha(Path(__file__))}}
    if inputs is not None:
        assert sources == frozen, "fresh inventory differs from prebuild proof"
        binding.update(inputInventoryVersion=INPUT_INVENTORY_VERSION, runnerInputs=inputs)
    if reused:
        binding.update(status="runner-reused", reusedBuild=reused)
    else:
        binding["focusedEvidence"] = {"status": focused["status"], "total": total, "passed": passed,
                                      "skipped": skipped, "failed": failed,
                                      "stdoutSHA256": sha(stdout), "stderrSHA256": sha(stderr)}
    # Close the read/hash race while the caller retains the exclusive token.
    for item in artifacts.values():
        assert sha(item["path"]) == item["sha256"]
    for relative, digest in frozen.items():
        assert sha(root / relative) == digest
    for relative, digest in sources.items():
        assert sha(root / relative) == digest
    assert sha(proof_path) == binding["sourceProofSha256"]
    with output.open("x") as stream:
        stream.write(json.dumps(binding, indent=2, sort_keys=True) + "\n")
    print(str(output), flush=True)


if __name__ == "__main__":
    main()
