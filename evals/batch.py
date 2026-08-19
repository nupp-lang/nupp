#!/usr/bin/env python3
"""Run the tier-1 corpus and report what it says, rather than one task at a time.

One run of one task is a sample. This runs many, holds each one's record, and
reports the distributions -- because the interesting numbers are a pass rate
and a spread, and because two runs of the same task have already been seen to
differ by a turn and a tool call.

Results are sliced by whether the compiler offered a fix for the diagnostic.
A code whose diagnostic carries an edit is a different task from one that only
describes the problem, and a single average over both populations would mostly
report how many of each the catalogue happens to hold.

See plans/065-agent-evaluation-harness.md. Every task spends real money; the
whole corpus is over a hundred of them, so `--limit` before `--jobs`.
"""

from __future__ import annotations

import argparse
import concurrent.futures
import json
import shutil
import statistics
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import tier1  # noqa: E402
from harness import run  # noqa: E402


def runnable(nupp: Path, jobs: int) -> list[str]:
    """Every code the catalogue holds a usable task for, in order.

    A code with no worked example, and one that resolves only through its
    family, are not tasks: there is no program to hand an agent. They are left
    out here rather than counted as failures later.
    """
    listed = json.loads(run([str(nupp), "explain", "--list", "--json"]).stdout)
    codes = listed.get("codes", [])

    def usable(code: str) -> str | None:
        done = run([str(nupp), "explain", code, "--json"])
        if done.returncode != 0:
            return None
        entry = json.loads(done.stdout)
        if entry.get("family") or not entry.get("wrong"):
            return None
        return code

    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        found = list(pool.map(usable, codes))
    return [code for code in found if code]


def one(
    nupp: Path,
    code: str,
    out: Path,
    model: str | None,
    lean: bool = False,
    timeout: float | None = None,
) -> dict:
    """One task's outcome, with a failure to even pose it kept separate.

    A task that could not be set up is not a task the agent failed. It is
    recorded as `invalid` so a sweep's denominator stays honest.
    """
    started = time.monotonic()
    try:
        record = tier1.evaluate(
            nupp, code, out, model, lean=lean, timeout=timeout
        )
        record["invalid"] = None
        return record
    except SystemExit as error:
        return {
            "task": {"tier": 1, "code": code},
            "invalid": str(error),
            "agent": {},
            "grade": {"passed": False},
            "elapsed": round(time.monotonic() - started, 1),
        }
    except Exception as error:  # noqa: BLE001 - one task must not end the sweep
        return {
            "task": {"tier": 1, "code": code},
            "invalid": f"{type(error).__name__}: {error}",
            "agent": {},
            "grade": {"passed": False},
        }


def summarize(records: list[dict]) -> dict:
    """The scoreboard: rates and spreads, and the failures worth reading."""
    valid = [r for r in records if not r.get("invalid")]
    invalid = [r for r in records if r.get("invalid")]
    passed = [r for r in valid if r["grade"].get("passed")]

    def rate(subset: list[dict]) -> dict:
        won = [r for r in subset if r["grade"].get("passed")]
        return {
            "tasks": len(subset),
            "passed": len(won),
            "rate": round(len(won) / len(subset), 3) if subset else None,
        }

    costs = [
        r["agent"]["costUsd"]
        for r in valid
        if isinstance(r["agent"].get("costUsd"), (int, float))
    ]
    tools = [
        r["agent"]["toolCallTotal"]
        for r in valid
        if isinstance(r["agent"].get("toolCallTotal"), int)
    ]
    nupps = [
        r["agent"]["nuppInvocations"]
        for r in valid
        if isinstance(r["agent"].get("nuppInvocations"), int)
    ]

    def spread(values: list[float]) -> dict | None:
        if not values:
            return None
        return {
            "median": round(statistics.median(values), 4),
            "min": round(min(values), 4),
            "max": round(max(values), 4),
            "total": round(sum(values), 4),
        }

    return {
        "overall": rate(valid),
        "withFix": rate([r for r in valid if r["task"].get("hadFix")]),
        "withoutFix": rate([r for r in valid if not r["task"].get("hadFix")]),
        "cost": spread(costs),
        "toolCalls": spread(tools),
        "nuppInvocations": spread(nupps),
        "invalid": [
            {"code": r["task"]["code"], "why": r["invalid"]} for r in invalid
        ],
        "failed": [
            {
                "code": r["task"]["code"],
                "summary": r["task"].get("summary", ""),
                "hadFix": r["task"].get("hadFix"),
                "after": r["grade"].get("diagnosticsAfter"),
                "shrank": r["grade"].get("suspiciousShrink"),
            }
            for r in valid
            if not r["grade"].get("passed")
        ],
        "suspicious": [
            r["task"]["code"]
            for r in passed
            if r["grade"].get("suspiciousShrink")
        ],
    }


def report(summary: dict, model: str | None, elapsed: float) -> None:
    """The scoreboard as a table, in the house's plain-column style."""
    def line(name: str, block: dict) -> str:
        if not block["tasks"]:
            return f" {name:<14} {'-':>6} {'-':>7}  {'-':>6}"
        return (
            f" {name:<14} {block['tasks']:>6} {block['passed']:>7}"
            f"  {block['rate'] * 100:>5.1f}%"
        )

    print()
    print(f" tier 1 sweep, model {model or 'default'}, {elapsed / 60:.1f} min")
    print()
    print(" population      tasks  passed    rate")
    print(" ─────────────  ──────  ──────  ──────")
    print(line("overall", summary["overall"]))
    print(line("fix offered", summary["withFix"]))
    print(line("no fix", summary["withoutFix"]))
    print()
    for name in ("cost", "toolCalls", "nuppInvocations"):
        block = summary[name]
        if not block:
            continue
        print(
            f" {name:<16} median {block['median']:<9}"
            f" min {block['min']:<9} max {block['max']:<9}"
            f" total {block['total']}"
        )
    if summary["invalid"]:
        print(f"\n {len(summary['invalid'])} task(s) could not be posed:")
        for item in summary["invalid"][:10]:
            print(f"   {item['code']}: {item['why'][:90]}")
    if summary["suspicious"]:
        print(
            f"\n passed but the file shrank by half:"
            f" {', '.join(summary['suspicious'])}"
        )
    if summary["failed"]:
        print(f"\n {len(summary['failed'])} failed:")
        for item in summary["failed"]:
            fix = "fix" if item["hadFix"] else "no fix"
            print(f"   {item['code']} ({fix}) left {item['after']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--nupp",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "bin" / "nupp",
        help="the compiler to build tasks from and grade with",
    )
    parser.add_argument("--model", help="model for the agents, e.g. sonnet")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent / "results",
        help="where the per-task records and the scoreboard are written."
        " Defaults inside the checkout, which a removed worktree takes with"
        " it -- name a durable path for a sweep worth keeping",
    )
    parser.add_argument(
        "--codes", nargs="+", help="run only these codes instead of the corpus"
    )
    parser.add_argument(
        "--limit", type=int, help="run only the first N tasks; use before --jobs"
    )
    parser.add_argument(
        "--jobs",
        type=int,
        default=4,
        help="how many agents to run at once (default 4)",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=300,
        help="seconds before one run is killed and graded a failure"
        " (default 300)",
    )
    parser.add_argument(
        "--lean",
        action="store_true",
        help="send only the tools a repair needs; cheaper per turn, and only"
        " comparable with another lean run",
    )
    parser.add_argument(
        "--label",
        default="sweep",
        help="names the scoreboard file, for telling two conditions apart",
    )
    args = parser.parse_args()

    nupp = args.nupp.resolve()
    if not nupp.exists():
        raise SystemExit(f"no compiler at {nupp}")
    if not shutil.which("claude"):
        raise SystemExit("the `claude` CLI is not on PATH")

    codes = args.codes or runnable(nupp, args.jobs)
    if args.limit:
        codes = codes[: args.limit]
    args.out.mkdir(parents=True, exist_ok=True)
    print(
        f"{len(codes)} task(s), {args.jobs} at a time, model"
        f" {args.model or 'default'}",
        flush=True,
    )

    started = time.monotonic()
    records: list[dict] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {
            pool.submit(
                one, nupp, code, args.out, args.model, args.lean, args.timeout
            ): code
            for code in codes
        }
        for done in concurrent.futures.as_completed(futures):
            record = done.result()
            records.append(record)
            code = record["task"]["code"]
            if record.get("invalid"):
                mark = "SKIP"
            elif record["grade"].get("passed"):
                mark = "pass"
            else:
                mark = "FAIL"
            # Flushed: a sweep is long enough that a reader watching a
            # redirected log should see it move, and Python buffers
            # stdout when it is not a terminal.
            print(
                f"  [{len(records):>3}/{len(codes)}] {mark} {code}",
                flush=True,
            )

    elapsed = time.monotonic() - started
    summary = summarize(records)
    summary["model"] = args.model or "default"
    summary["lean"] = args.lean
    summary["timedOut"] = [
        r["task"]["code"] for r in records if r.get("agent", {}).get("timedOut")
    ]
    summary["elapsedSeconds"] = round(elapsed, 1)
    summary["codes"] = sorted(codes)
    board = args.out / f"{args.label}-scoreboard.json"
    board.write_text(json.dumps(summary, indent=2) + "\n")
    report(summary, args.model, elapsed)
    print(f"\n scoreboard={board}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
