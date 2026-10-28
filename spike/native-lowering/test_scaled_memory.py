#!/usr/bin/env python3
"""Prove the bounded i64 indexed-memory fold against independent oracles."""
import json
from pathlib import Path

from test_differential import main

MASK = (1 << 64) - 1


def generate(project, directory):
    cases = []
    rows = []
    variants = ("single", "basefirst", "shared", "reverse", "scale4", "offset",
                "productuse", "addressuse", "gap", "effect", "edge", "narrow", "signed",
                "pressure", "storealias", "float", "load32")
    for store in (False, True):
        for variant in variants:
            if variant == "storealias" and not store:
                continue
            for slot in (-1, 0, 1, 3):
                for high in (False, True):
                    scale = 4 if variant == "scale4" else 8
                    index = (slot + ((1 << 61) if high else 0)) & MASK
                    if scale == 4 and high:
                        continue
                    if variant == "narrow" and high:
                        continue
                    delta = slot * scale
                    displacement = 8 if variant == "offset" else 0
                    address_offset = 32 + delta + displacement
                    value = (0xfedcba9876543210 ^ (slot & MASK)) & MASK
                    fold = variant in ("single", "basefirst", "shared", "pressure", "storealias") or (store and variant == "signed")
                    name = f'{"fold" if fold else "keep"}{int(store)}{variant}p{slot + 1}h{int(high)}'
                    width = 32 if variant == "narrow" else 64
                    start = ("    v10 = stack_addr.i64 ss0+32\n"
                             f"    v11 = stack_addr.i64 ss0+{address_offset}\n")
                    # Distinct initial contents make a wrong base-only load fail.
                    start += "    v12 = bnot v1\n    store v12, v10\n"
                    start += "    store v1, v11\n" if not store else "    store v12, v11\n"
                    convert = "    v13 = ireduce.i32 v0\n" if width == 32 else ""
                    left, right = ("v2", "v0") if variant == "reverse" else ("v13" if width == 32 else "v0", "v2")
                    pressure = "".join(f"    v{30 + n} = bnot v1\n" for n in range(30)) if variant == "pressure" else ""
                    if variant == "float":
                        start += "    v16 = bitcast.f64 v1\n"
                    body = start + pressure + convert + f"    v2 = iconst.i{width} {scale}\n    v3 = imul {left}, {right}\n"
                    product = "v3"
                    if width == 32:
                        body += "    v14 = sextend.i64 v3\n"
                        product = "v14"
                    arguments = f"v10, {product}" if variant == "basefirst" else f"{product}, v10"
                    body += f"    v4 = iadd {arguments}\n"
                    if variant == "gap":
                        body += "    v15 = bnot v1\n"
                    if variant == "effect":
                        body += "    store v1, v11\n"
                    if variant == "edge":
                        body += "    jump block1(v4)\nblock1(v20: i64):\n"
                    address = "v20" if variant == "edge" else "v4"
                    suffix = f"+{displacement}" if displacement else ""
                    load = "sload32.i64" if variant == "signed" else "uload32.i64" if variant == "load32" else "load.i64"
                    if store:
                        stored = "v0" if variant == "storealias" else "v16" if variant == "float" else "v1"
                        operation = "istore32" if variant == "load32" else "store"
                        body += f"    {operation} {stored}, {address}{suffix}\n    v5 = {load} v11\n"
                    elif variant == "float":
                        body += f"    v17 = load.f64 {address}{suffix}\n    v5 = bitcast.i64 v17\n"
                    else:
                        body += f"    v5 = {load} {address}{suffix}\n"
                    expected = index if variant == "storealias" else value
                    if variant == "load32":
                        expected &= 0xffffffff
                    if variant == "signed":
                        expected = value & 0xffffffff
                        if expected & 0x80000000:
                            expected |= MASK ^ 0xffffffff
                    if variant == "pressure":
                        body += "    v60 = bxor v5, v30\n"
                        body += "".join(f"    v{61 + n} = bxor v{60 + n}, v{31 + n}\n" for n in range(29))
                        body += "    return v89\n"
                    elif variant == "productuse":
                        body += "    v6 = bxor v5, v3\n    return v6\n"
                        expected ^= delta & MASK
                    elif variant == "addressuse":
                        body += "    v6 = isub v4, v10\n    v7 = bxor v5, v6\n    return v7\n"
                        expected ^= delta & MASK
                    elif variant == "shared":
                        body += "    v6 = bxor v5, v2\n    return v6\n"
                        expected ^= scale
                    else:
                        body += "    return v5\n"
                    source = (f"function %{name}(i64, i64) -> i64 tail {{\n"
                              "    ss0 = explicit_slot 128, align = 16\n"
                              "block0(v0: i64, v1: i64):\n" + body + "}\n")
                    (directory / (name + ".clif")).write_text(source)
                    for mode in ("normal", "spill"):
                        (directory / mode / name).mkdir(parents=True)
                    rows.append(f"{name} {index} {value}\n")
                    cases.append(dict(name=name, inputWords=[index, value], pythonReference=expected,
                                      resultKinds=["i64"], arithmeticNaNsEquivalent=False))
    (directory / "inputs.tsv").write_text("".join(rows))
    (directory / "cases.json").write_text(json.dumps(cases, indent=2) + "\n")
    return cases


if __name__ == "__main__":
    main(generate, "s0.scaledmemorytests", (Path(__file__).resolve(),))
