#!/usr/bin/env python3
"""Create deterministic large scalar machine-IR inputs for the S0 gate."""
import argparse
import hashlib
import json
from pathlib import Path


def generate():
    lines = ["function %long_chain(i64) -> i64 tail {", "block0(v0: i64):"]
    for value in range(1, 16385):
        lines.append(f"    v{value} = iadd v{value - 1}, v0")
    lines += ["    return v16384", "}", "", "function %wide_live(i64) -> i64 tail {", "block0(v0: i64):"]
    for value in range(1, 1025):
        lines.append(f"    v{value} = imul v0, v0")
    last = 1
    for offset, value in enumerate(range(2, 1025), 1025):
        lines.append(f"    v{offset} = iadd v{last}, v{value}")
        last = offset
    lines += [f"    return v{last}", "}", "", "function %many_blocks(i64, i64) -> i64 tail {", "block0(v0: i64, v1: i64):", "    jump block1(v0)"]
    for block in range(1, 1025):
        parameter, result = block * 2, block * 2 + 1
        lines += [f"block{block}(v{parameter}: i64):", f"    v{result} = iadd v{parameter}, v1"]
        lines.append(f"    jump block{block + 1}(v{result})" if block < 1024 else f"    return v{result}")
    lines += ["}", ""]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    data = generate().encode()
    (args.output / "synthetic.clif").write_bytes(data)
    (args.output / "manifest.json").write_text(json.dumps({
        "scope": "Deterministic compile inputs; no duration verdict",
        "generatorSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "clifSha256": hashlib.sha256(data).hexdigest(),
        "functions": ["long_chain: 16384 dependent additions", "wide_live: 1024 overlapping values", "many_blocks: 1025 blocks"],
    }, indent=2) + "\n")


if __name__ == "__main__":
    main()
