#!/usr/bin/env python3
"""Emit the specialization test images from `tests/specialize/`.

Usage: specialize-emit.py [SEED_RUNTIME SEED_IMAGE]

Defaults to the installed VM CLI (`.nupp/vm-cli/current`). Writes
`specialize.image` (cases, classes, poly, shapes) and `deopt.image` (deopt,
whose leases put every function of its image on heap-frame entries, so it is
kept apart from the programs meant to run on direct entries).
"""
import json
import os
from pathlib import Path
import subprocess
import sys

here = Path(__file__).resolve().parent
root = here.parents[3]
programs = here / "specialize"
if len(sys.argv) == 3:
    runtime, seed = Path(sys.argv[1]), Path(sys.argv[2])
else:
    package = root / ".nupp/vm-cli" / (root / ".nupp/vm-cli/current").read_text().strip()
    runtime, seed = package / "runtime", package / "compiler.image"
env = dict(os.environ, NO_JIT="1", NUPP_COMPILER_ROOT=str(root))
for image, first, rest in (("specialize.image", "cases", "classes,poly,shapes"), ("deopt.image", "deopt", "")):
    args = [str(runtime), "run", str(seed), "nupp.tools.vm.project", "emit", str(programs), first, rest, str(programs)]
    done = subprocess.run(args, env=env, capture_output=True, text=True)
    if done.returncode != 0:
        sys.exit("emit failed:\n" + done.stderr[-4000:])
    text = json.loads(done.stdout).replace(str(programs) + "/", "")
    (programs / image).write_text(text)
    print("wrote", programs / image)
