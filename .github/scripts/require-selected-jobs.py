#!/usr/bin/env python3
"""Decide the one status a ruleset requires.

`required-ci` has to mean the same thing after the jobs above it are renamed,
split or reordered, and it has to be impossible to pass by not running. So it
reads the results of every job it waits on and applies two rules:

  * `classify` decides what is required, so a `classify` that did not succeed
    is a failure of the gate itself rather than an absence of obligations; and
  * every other job must have concluded `success` or `skipped`. A `skipped`
    job is one the classifier did not select. Anything else -- `failure`,
    `cancelled` -- is a failure, because a job that produced no answer has not
    answered.
"""

import json
import os
import sys


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

    failed = {
        name: job.get("result")
        for name, job in needs.items()
        if job.get("result") not in ("success", "skipped")
    }
    for name, result in sorted(failed.items()):
        print(f"required-ci: {name} concluded {result!r}", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
