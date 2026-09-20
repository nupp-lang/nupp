#!/usr/bin/env python3
"""Decide the one status a ruleset requires.

`required-ci` has to mean the same thing after the jobs above it are renamed,
split or reordered, and it has to be impossible to pass by not running. So it
reads the results of every job it waits on and the classifier selection:

  * `classify` decides what is required, so a `classify` that did not succeed
    is a failure of the gate itself rather than an absence of obligations; and
  * every selected job must be present and successful; an absent or skipped
    selected job is a failure; and
  * unselected jobs may be successful or skipped. Any reported failure or
    cancellation still fails the aggregate.
"""

import json
import os
from pathlib import Path
import sys


def selected_failures(needs, selection, jobs):
    failed = {
        name: job.get("result")
        for name, job in needs.items()
        if job.get("result") not in ("success", "skipped")
    }
    for name, job in jobs.items():
        if name in ("classify", "required-ci"):
            continue
        selectors = job["selectedBy"].replace(",", " ").split()
        if any(selection.get(selector) is True for selector in selectors):
            result = needs.get(name, {}).get("result", "absent")
            if result != "success":
                failed[name] = result
    return failed


def main() -> int:
    raw = os.environ.get("NEEDS", "")
    print(f"selection: {os.environ.get('SELECTION') or '<none>'}")
    if not raw.strip():
        print("required-ci: no job results were reported", file=sys.stderr)
        return 1

    needs = json.loads(raw)
    for name, job in sorted(needs.items()):
        print(f"  {name:<26} {job.get('result')}")

    classify = needs.get("classify")
    if classify is None or classify.get("result") != "success":
        concluded = classify.get("result") if classify else "absent"
        print(f"required-ci: classify concluded {concluded!r}", file=sys.stderr)
        return 1

    raw_selection = os.environ.get("SELECTION", "")
    if not raw_selection.strip():
        print("required-ci: no classifier selection was reported", file=sys.stderr)
        return 1
    selection = json.loads(raw_selection)
    coverage = json.loads((Path(__file__).resolve().parents[1] / "ci-coverage.json").read_text())
    failed = selected_failures(needs, selection, coverage["jobs"])
    for name, result in sorted(failed.items()):
        print(f"required-ci: {name} concluded {result!r}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
