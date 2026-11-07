#!/usr/bin/env python3
"""Apply or remove the temporary same-pool comparison guard in a task worktree."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("root", type=Path)
parser.add_argument("--undo", action="store_true")
args = parser.parse_args()
source = args.root / "src/nupp/runtime/provider/workers.nupp"
plain = '    if packed.count ~= 1 then\n'
guarded = '    if rawget(_G.nupp, "__workerGenericArrays") == true or packed.count ~= 1 then\n'
old, new = (guarded, plain) if args.undo else (plain, guarded)
text = source.read_text()
if text.count(old) != 1:
    parser.error("the expected single-array selector is absent or ambiguous")
source.write_text(text.replace(old, new, 1))
