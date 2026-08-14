#!/usr/bin/env python3
"""Regression cases for byte-based owned-inventory edit application."""
import importlib.util
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "owned_inventory", ROOT / "scripts" / "owned-inventory.py"
)
inventory = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inventory)

source = "-- em dash — before both sites\n@owned\nfunction a(): A\n@owned\nfunction b(): B\n".encode()


def edit(start, end, text):
    return {
        "range": {
            "start": {"offset": start + 1},
            "end": {"offset": end + 1},
        },
        "newText": text,
    }


first = source.index(b"@owned")
second = source.index(b"@owned", first + 1)
rewritten = inventory.apply_edits(source, [
    edit(first, first + len(b"@owned\n"), ""),
    edit(second, second + len(b"@owned\n"), ""),
])
assert rewritten.decode().count("@owned") == 0
assert "—" in rewritten.decode()

try:
    inventory.apply_edits(source, [edit(first, first + 4, ""), edit(first + 2, first + 6, "")])
except inventory.InventoryError as error:
    assert "overlap" in str(error)
else:
    raise AssertionError("overlapping edits were accepted")

try:
    inventory.apply_edits(source, [edit(-1, 0, "")])
except inventory.InventoryError as error:
    assert "outside" in str(error)
else:
    raise AssertionError("out-of-range edit was accepted")
