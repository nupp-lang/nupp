#!/usr/bin/env python3
"""Inventory and verify the migration from @owned to Owned result types.

The migration lint is opt-in. This command enables it transactionally in the
project manifest, obtains a fresh project diagnostic set, and restores the exact
manifest bytes before exiting. With --verify it applies all fixes in each file
atomically, rechecks that file, and restores its bytes before moving on. With
--write it performs that verification first, then applies the complete set.
"""
import collections
import contextlib
import json
import pathlib
import re
import subprocess
import sys

CODE = "NUPP2515"
REFUSAL = "cannot rewrite: "
LINT_LINE = b'   lints = { ["owned-annotation"] = "warning" },\n'
PRELUDE = "src/nupp/compiler/decls/prelude.d.nupp"
CLASSES = (
    (re.compile(r"^Owned<T>$"), "bare"),
    (re.compile(r"^Owned<T, opaque>$"), "opaque"),
    (re.compile(r"^Owned<T, .+>$"), "named"),
)


class InventoryError(Exception):
    """The inventory could not establish a trustworthy answer."""


def apply_edits(source: bytes, edits) -> bytes:
    """Apply one fix set to bytes; JSON offsets are 1-based byte positions."""
    spans = []
    for edit in edits:
        start = edit["range"]["start"]["offset"] - 1
        end = edit["range"]["end"]["offset"] - 1
        if start < 0 or end < start or end > len(source):
            raise InventoryError(
                f"edit spans {start}..{end}, outside a {len(source)}-byte file"
            )
        spans.append((start, end, edit["newText"].encode()))
    spans.sort(key=lambda span: (span[0], span[1]))
    for (_, first_end, _), (second_start, _, _) in zip(spans, spans[1:]):
        if second_start < first_end:
            raise InventoryError(f"edits overlap at byte {second_start}")
    out = source
    for start, end, replacement in reversed(spans):
        out = out[:start] + replacement + out[end:]
    try:
        out.decode("utf-8", errors="strict")
    except UnicodeDecodeError as broken:
        raise InventoryError(f"rewrite produced invalid UTF-8: {broken}") from None
    return out


@contextlib.contextmanager
def migration_lint(root: pathlib.Path):
    """Enable the lint and restore the byte-identical manifest afterward."""
    manifest = root / "nupp.lua"
    original = manifest.read_bytes()
    if b"owned-annotation" in original:
        yield
        return
    marker = b"return {\n"
    if marker not in original:
        raise InventoryError("nupp.lua has no return table to add the lint to")
    manifest.write_bytes(original.replace(marker, marker + LINT_LINE, 1))
    try:
        yield
    finally:
        manifest.write_bytes(original)


def check(root: pathlib.Path, path=None):
    command = ["./bin/nupp", "check", "--json"]
    if path:
        command.append(path)
    done = subprocess.run(command, cwd=root, capture_output=True, text=True)
    try:
        document = json.loads(done.stdout)
    except json.JSONDecodeError as broken:
        raise InventoryError(
            f"check produced no JSON (exit {done.returncode}): {done.stderr.strip()}"
        ) from broken
    return document.get("diagnostics", [])


def spelling(message):
    found = re.search(r"what (Owned<[^>]*>) says", message)
    return found.group(1) if found else "?"


def rewrite_class(message):
    written = spelling(message)
    for pattern, name in CLASSES:
        if pattern.match(written):
            return name
    return "?"


def stable(diagnostics):
    """A diagnostic multiset unaffected by line shifts from annotation deletion."""
    return collections.Counter(
        (d["code"], d.get("message", ""))
        for d in diagnostics
        if d["code"] != CODE
    )


def verify_file(root, path, fixes):
    target = root / path
    original = target.read_bytes()
    before = check(root, path)
    try:
        edits = [edit for fix in fixes for edit in fix["edits"]]
        target.write_bytes(apply_edits(original, edits))
        after = check(root, path)
    finally:
        target.write_bytes(original)
    surviving = sum(d["code"] == CODE for d in after)
    return surviving, stable(after) - stable(before)


def write_files(root, fixable):
    """Prepare every rewrite, then write them with rollback on failure."""
    by_file = collections.defaultdict(list)
    for path, fix, _ in fixable:
        by_file[path].append(fix)
    originals, rewritten = {}, {}
    for path, fixes in sorted(by_file.items()):
        target = root / path
        originals[path] = target.read_bytes()
        edits = [edit for fix in fixes for edit in fix["edits"]]
        rewritten[path] = apply_edits(originals[path], edits)
    written = []
    try:
        for path, source in rewritten.items():
            (root / path).write_bytes(source)
            written.append(path)
    except Exception:
        for path in written:
            (root / path).write_bytes(originals[path])
        raise
    return sum(len(fixes) for fixes in by_file.values())


def inventory(diagnostics):
    fixable, refused, internal = [], collections.Counter(), []
    seen = set()
    for diagnostic in diagnostics:
        if diagnostic.get("code") != CODE:
            continue
        start = diagnostic["range"]["start"]
        identity = (diagnostic["file"], start["offset"])
        if identity in seen:
            continue
        seen.add(identity)
        where = f"{diagnostic['file']}:{start['line']}"
        fixes = diagnostic.get("fixes") or []
        help_text = diagnostic.get("help") or ""
        if fixes and help_text.startswith(REFUSAL):
            internal.append(f"{where}: both fixed and refused")
        elif fixes:
            edit_count = len(fixes[0].get("edits") or []) if len(fixes) == 1 else 0
            if len(fixes) != 1 or edit_count < 3 or edit_count % 2 == 0:
                internal.append(f"{where}: expected one deletion plus result wrapper pairs")
            else:
                fixable.append(
                    (diagnostic["file"], fixes[0], rewrite_class(diagnostic["message"]))
                )
        elif help_text.startswith(REFUSAL):
            refused[help_text[len(REFUSAL):]] += 1
        else:
            internal.append(f"{where}: neither fixed nor structurally refused")
    if any(kind == "?" for _, _, kind in fixable):
        internal.append("a fix fell into no known rewrite class")
    return fixable, refused, internal


def main():
    write = "--write" in sys.argv[1:]
    verify = write or "--verify" in sys.argv[1:]
    root = pathlib.Path.cwd()
    with migration_lint(root):
        # The bundled prelude is loaded into every environment but is deliberately not
        # a project source file, so enumerate it explicitly. `inventory` deduplicates
        # identities in case project enumeration ever starts including it.
        diagnostics = check(root) + check(root, PRELUDE)
        fixable, refused, internal = inventory(diagnostics)
        classes = collections.Counter(kind for _, _, kind in fixable)
        verified, failures, introduced = 0, [], collections.Counter()
        if verify:
            by_file = collections.defaultdict(list)
            for path, fix, _ in fixable:
                by_file[path].append(fix)
            for path, fixes in sorted(by_file.items()):
                try:
                    surviving, appeared = verify_file(root, path, fixes)
                except InventoryError as broken:
                    surviving = 0
                    appeared = collections.Counter({("HARNESS", str(broken)): 1})
                if surviving or appeared:
                    failures.append((path, len(fixes), surviving, appeared))
                    introduced.update(appeared)
                else:
                    verified += len(fixes)
        applied = 0
        if write and not internal and not failures and verified == len(fixable):
            applied = write_files(root, fixable)

    offered = len(fixable) + sum(refused.values())
    print(f"{offered:>4} offered sites  " + ", ".join(
        f"{count} {kind}" for kind, count in sorted(classes.items())
    ))
    if verify:
        print(f"{verified:>4} verified sites")
        print(f"{sum(n for _, n, _, _ in failures):>4} failed sites  in {len(failures)} files")
    if write:
        print(f"{applied:>4} applied sites")
    print(f"{sum(refused.values()):>4} refused sites")
    for reason, count in refused.most_common():
        print(f"       {count}  {reason}")
    if verify:
        print(f"{sum(introduced.values()):>4} new diagnostics")
        for path, count, surviving, appeared in failures:
            print(f"       {path} ({count} sites, {surviving} lints survived)")
            for (code, message), count in appeared.most_common(4):
                print(f"         {count}x {code} {message}")
    print(f"{len(internal):>4} internal")
    for message in internal:
        print(f"       {message}")
    if internal or (verify and verified != len(fixable)):
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except InventoryError as broken:
        print(f"inventory failed: {broken}", file=sys.stderr)
        sys.exit(1)
