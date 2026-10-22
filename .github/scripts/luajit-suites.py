#!/usr/bin/env python3
"""The suites the VM runner leaves to LuaJIT, one per line.

The corpus classification marks each suite: `portable` suites run on the VM
runner, and the rest -- `retired`, `harness` and `port-required` -- still run
on LuaJIT (tests/run), which this names them for. A suite the classification
names that the tree no longer has is left out.
"""
import json
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
CLASSIFICATION = ROOT / "native/crates/vm/tests/corpus-classification.json"
DEFERRED = {"retired", "harness", "port-required"}

for row in json.loads(CLASSIFICATION.read_text())["suites"]:
    suite = row["suite"]
    present = any((ROOT / "tests" / f"{suite}.{ext}").is_file() for ext in ("lua", "nupp"))
    if row["class"] in DEFERRED and present:
        print(suite)
