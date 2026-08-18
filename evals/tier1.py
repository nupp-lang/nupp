#!/usr/bin/env python3
"""Run one tier-1 agent evaluation: repair a file that reports a known code.

A tier-1 task is built from the compiler's own diagnostic catalogue. Every
entry `nupp explain --list` names carries a `wrong` program that
`tests/explaintest.lua` has already compiled and asserted really does report
the code it is filed under, so the task bank is data the compiler maintains
for other reasons rather than fixtures this harness has to keep true.

The agent is given the `wrong` program and nothing else: not the code, not the
rule, not the corrected program. It is expected to run `nupp check` itself and
repair what that reports, which is the loop `docs/diagnostics.md` describes.
Grading re-runs the same command and asks whether the code is gone, so a
different correct repair passes and only the diagnostic decides.

See plans/065-agent-evaluation-harness.md. This costs real money per run.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


# What the agent is told. It names no code and quotes no rule: the point of the
# measurement is whether the compiler's own output is enough to repair from, so
# anything this prompt explains is a thing the tooling is no longer being asked
# to explain for itself.
PROMPT = """\
The file `sample.nupp` in this directory does not type-check.

Run `nupp check` to see what is wrong with it, and then fix it. Keep the
program doing what it was evidently written to do -- repair the mistake rather
than deleting the code that has one, and leave the file checking cleanly.

Work only inside this directory. Do not look for the Nupp compiler's own
source; `nupp` and its subcommands are the tools available to you.
"""

# A real target, not just an include root. `tests/explaintest.lua` gets away
# with a bare `return {include = {"."}}` because it always names the file it
# compiles, but a bare `nupp check` against that manifest writes
# `build.entries must contain at least one entry` to stderr and then reports
# `{"diagnostics":[]}` -- so an agent doing the obvious thing is told nothing
# is wrong. The task has to be a project a plain `nupp check` really checks,
# or what gets measured is the manifest rather than the agent.
MANIFEST = """\
return {
   include = { "." },
   build = {
      outDir = "build",
      default = "app",
      targets = { app = { kind = "modules", entries = { "sample" } } },
   },
}
"""

# `nupp` followed by one of its subcommands, so that `which nupp` and a
# workspace path with the word in it are not counted as the agent asking the
# compiler something. Several chained in one Bash call each count, since each
# is a question asked and answered.
NUPP_COMMAND = re.compile(
    r"\bnupp\s+(?:check|build|test|explain|fmt|lsp|bc|aot|run|lints|tasks)\b"
)


def run(argv: list[str], **kwargs: object) -> subprocess.CompletedProcess:
    """Run a command, capturing output, without raising on a non-zero exit."""
    return subprocess.run(
        argv, capture_output=True, text=True, check=False, **kwargs
    )


def load_task(nupp: Path, code: str) -> dict:
    """The catalogue entry for one code, as the task to repair.

    Raises when the code has no worked example, since there is then no program
    to hand an agent, and when it resolves only through its family, since the
    example would be the family's rather than the code's.
    """
    done = run([str(nupp), "explain", code, "--json"])
    if done.returncode != 0:
        raise SystemExit(f"nupp explain {code} failed: {done.stderr.strip()}")
    entry = json.loads(done.stdout)
    if entry.get("family"):
        raise SystemExit(f"{code} resolves only through its family; no example")
    if not entry.get("wrong"):
        raise SystemExit(f"{code} has no `wrong` example to repair")
    return entry


def make_workspace(root: Path, nupp: Path, entry: dict) -> Path:
    """A project holding just the broken file, and a `nupp` for the agent.

    The compiler is reached through a shim on PATH rather than by its real
    path, so the task reads like an ordinary project with the toolchain
    installed and the prompt never has to name the checkout the answers live
    in.
    """
    workspace = root / "workspace"
    (workspace / "bin").mkdir(parents=True)
    (workspace / "nupp.lua").write_text(MANIFEST)
    (workspace / "sample.nupp").write_text(entry["wrong"])

    shim = workspace / "bin" / "nupp"
    shim.write_text(f'#!/bin/sh\nexec "{nupp}" "$@"\n')
    shim.chmod(0o755)
    return workspace


def check(nupp: Path, workspace: Path, entry: dict) -> list[dict]:
    """Every diagnostic the project reports now.

    A NUPP3xxx code is what a checked program cannot be lowered to, so those
    are only reachable through `build`; everything else `check` reports and
    there is no output to write.
    """
    verb = "build" if entry["code"].startswith("NUPP3") else "check"
    argv = [str(nupp), verb, "--json"]
    if entry.get("strict"):
        argv.append("--strict")
    done = run(argv, cwd=workspace)
    try:
        return json.loads(done.stdout).get("diagnostics", [])
    except json.JSONDecodeError:
        raise SystemExit(
            f"{verb} --json wrote no JSON: {done.stdout[:200]}"
            f" / {done.stderr[:200]}"
        )


def run_agent(
    workspace: Path, transcript: Path, model: str | None
) -> tuple[dict, list[dict]]:
    """Run one agent against the workspace, keeping its whole transcript.

    Streaming rather than a single result, because the events say what the
    agent did and not only what it ended with: the tool calls are where the
    cost went and are the part worth comparing between two runs that both
    passed.
    """
    argv = [
        "claude",
        "-p",
        "--output-format",
        "stream-json",
        "--verbose",
        "--permission-mode",
        "bypassPermissions",
    ]
    if model:
        argv += ["--model", model]
    argv.append(PROMPT)

    environment = dict(os.environ)
    environment["PATH"] = f"{workspace / 'bin'}{os.pathsep}{environment['PATH']}"

    started = time.monotonic()
    done = run(argv, cwd=workspace, env=environment)
    elapsed = time.monotonic() - started

    events = []
    for line in done.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    transcript.write_text(
        "".join(json.dumps(event) + "\n" for event in events)
    )

    if not events:
        raise SystemExit(
            f"the agent produced no events; exit {done.returncode}:"
            f" {done.stderr[:400]}"
        )
    result = next(
        (event for event in reversed(events) if event.get("type") == "result"),
        {},
    )
    result["wallClockSeconds"] = round(elapsed, 1)
    return result, events


def tool_calls(events: list[dict]) -> tuple[dict[str, int], int]:
    """How many times each tool was called, and how many of those ran `nupp`.

    The second number is the one worth watching: an agent that checks once,
    reads the diagnostic and repairs is doing the thing the tooling is for,
    and one that checks eight times is paying for something the first answer
    was supposed to have told it.
    """
    counts: dict[str, int] = {}
    nupp_runs = 0
    for event in events:
        if event.get("type") != "assistant":
            continue
        content = event.get("message", {}).get("content", [])
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict) or block.get("type") != "tool_use":
                continue
            name = block.get("name", "?")
            counts[name] = counts.get(name, 0) + 1
            command = block.get("input", {}).get("command", "")
            if name == "Bash" and isinstance(command, str):
                nupp_runs += len(NUPP_COMMAND.findall(command))
    return counts, nupp_runs


def grade(before: list[dict], after: list[dict], entry: dict, source: str) -> dict:
    """Whether the repair landed, and what is worth knowing when it did not.

    Passing is the filed-under code being gone with no error left behind. The
    corrected program is never compared against the catalogue's own: a repair
    the compiler accepts is a repair, and requiring it to match would be
    grading style rather than the thing the diagnostic asked for.
    """
    code = entry["code"]
    reported = {diagnostic.get("code") for diagnostic in after}
    errors = [
        diagnostic
        for diagnostic in after
        if diagnostic.get("severity") == "error"
    ]
    # A file emptied or gutted also stops reporting, so the size it kept is
    # recorded beside the verdict rather than trusted silently. This does not
    # decide the grade; it marks a pass a reader should look at.
    original = entry["wrong"]
    shrank = len(source.strip()) < len(original.strip()) * 0.5

    return {
        "code": code,
        "targetCodeGone": code not in reported,
        "errorsRemaining": len(errors),
        "passed": code not in reported and not errors,
        "suspiciousShrink": shrank,
        "diagnosticsBefore": [d.get("code") for d in before],
        "diagnosticsAfter": [d.get("code") for d in after],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "code", help="the diagnostic code to build the task from, e.g. NUPP2105"
    )
    parser.add_argument(
        "--nupp",
        type=Path,
        default=Path(__file__).resolve().parent.parent / "bin" / "nupp",
        help="the compiler to grade with (default: this checkout's)",
    )
    parser.add_argument("--model", help="model for the agent, e.g. sonnet")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent / "results",
        help="where to write the run record and transcript",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="keep the workspace after the run, for inspection",
    )
    args = parser.parse_args()

    nupp = args.nupp.resolve()
    if not nupp.exists():
        raise SystemExit(f"no compiler at {nupp}")
    if not shutil.which("claude"):
        raise SystemExit("the `claude` CLI is not on PATH")

    entry = load_task(nupp, args.code)
    args.out.mkdir(parents=True, exist_ok=True)

    root = Path(tempfile.mkdtemp(prefix=f"nupp-eval-{args.code}-"))
    try:
        workspace = make_workspace(root, nupp, entry)

        before = check(nupp, workspace, entry)
        reported = {diagnostic.get("code") for diagnostic in before}
        if entry["code"] not in reported:
            # The catalogue says this program reports this code. If it does not
            # here, the task is not the task, and a pass would mean nothing.
            raise SystemExit(
                f"{entry['code']} is not reported by its own example;"
                f" got {sorted(c for c in reported if c)}"
            )

        transcript = args.out / f"{args.code}-transcript.jsonl"
        result, events = run_agent(workspace, transcript, args.model)
        counts, nupp_runs = tool_calls(events)

        source = (workspace / "sample.nupp").read_text() if (
            workspace / "sample.nupp"
        ).exists() else ""
        after = check(nupp, workspace, entry)

        record = {
            "task": {
                "tier": 1,
                "code": entry["code"],
                "summary": entry["summary"],
                "strict": bool(entry.get("strict")),
            },
            "agent": {
                "model": args.model or "default",
                "turns": result.get("num_turns"),
                "costUsd": result.get("total_cost_usd"),
                "durationMs": result.get("duration_ms"),
                "wallClockSeconds": result.get("wallClockSeconds"),
                "outputTokens": result.get("usage", {}).get("output_tokens"),
                "isError": result.get("is_error"),
                "toolCalls": counts,
                "toolCallTotal": sum(counts.values()),
                "nuppInvocations": nupp_runs,
            },
            "grade": grade(before, after, entry, source),
            "finalSource": source,
            "transcript": str(transcript),
        }
        record_path = args.out / f"{args.code}-run.json"
        record_path.write_text(json.dumps(record, indent=2) + "\n")

        verdict = "PASS" if record["grade"]["passed"] else "FAIL"
        cost = record["agent"]["costUsd"]
        spent = f"${cost:.4f}" if isinstance(cost, (int, float)) else "?"
        print(f"{verdict}  {entry['code']}  {entry['summary']}")
        print(
            f"  turns={record['agent']['turns']}"
            f" tools={record['agent']['toolCallTotal']}"
            f" nupp={nupp_runs}"
            f" cost={spent}"
        )
        print(f"  before={record['grade']['diagnosticsBefore']}")
        print(f"  after={record['grade']['diagnosticsAfter']}")
        if record["grade"]["suspiciousShrink"]:
            print("  note: the file shrank by more than half; check the repair")
        print(f"  record={record_path}")
        if args.keep:
            print(f"  workspace={workspace}")
        return 0 if record["grade"]["passed"] else 1
    finally:
        if not args.keep:
            shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
