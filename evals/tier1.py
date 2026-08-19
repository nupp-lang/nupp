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
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import (  # noqa: E402
    REPAIR_TOOLS,
    agent_record,
    run,
    run_agent,
    spent,
)


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

# Written beside every task, matching `tests/explaintest.lua`. A missing
# require is only reportable when the project really holds the module the
# unresolved name would bind; without it that example reports an unknown
# variable instead, and the task stops being the task. Inert for the rest.
COMPANION = (
    "local mathutil = {}\n"
    "function mathutil.double(value: number): number return value * 2 end\n"
    "return mathutil\n"
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
    (workspace / "mathutil.g.nupp").write_text(COMPANION)

    shim = workspace / "bin" / "nupp"
    shim.write_text(f'#!/bin/sh\nexec "{nupp}" "$@"\n')
    shim.chmod(0o755)
    return workspace


def check(nupp: Path, workspace: Path, entry: dict) -> list[dict]:
    """Every diagnostic the project reports now.

    A NUPP3xxx code is what a checked program cannot be lowered to, so those
    are only reachable through `build`; everything else `check` reports and
    there is no output to write.

    `ok` is read before the list, because an empty `diagnostics` means the
    project is clean only when the run got as far as checking one. A manifest
    the command could not use ends it earlier and reports the same empty list,
    and grading that as a repair would pass every task whose workspace was
    broken in the right way.
    """
    verb = "build" if entry["code"].startswith("NUPP3") else "check"
    argv = [str(nupp), verb, "--json"]
    if entry.get("strict"):
        argv.append("--strict")
    done = run(argv, cwd=workspace)
    try:
        answer = json.loads(done.stdout)
    except json.JSONDecodeError:
        raise SystemExit(
            f"{verb} --json wrote no JSON: {done.stdout[:200]}"
            f" / {done.stderr[:200]}"
        )
    diagnostics = answer.get("diagnostics", [])
    if not answer.get("ok") and not diagnostics:
        raise SystemExit(
            f"{verb} --json reported neither success nor a diagnostic;"
            f" the workspace is not checkable: {done.stderr[:200]}"
        )
    return diagnostics


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


def evaluate(
    nupp: Path,
    code: str,
    out: Path,
    model: str | None = None,
    keep: bool = False,
    lean: bool = False,
    timeout: float | None = None,
) -> dict:
    """Run one task end to end and return its record.

    Separate from `main` so a batch can call it directly. Everything that can
    make the task invalid rather than merely failed -- a code with no example,
    an example that does not report its own code, a workspace that cannot be
    checked -- raises, so a sweep can tell "the agent did not repair it" from
    "there was nothing here to repair".
    """
    entry = load_task(nupp, code)
    out.mkdir(parents=True, exist_ok=True)
    root = Path(tempfile.mkdtemp(prefix=f"nupp-eval-{code}-"))
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

        transcript = out / f"{code}-transcript.jsonl"
        result, events = run_agent(
            workspace, PROMPT, transcript, model,
            path_prefix=workspace / "bin",
            tools=REPAIR_TOOLS if lean else None,
            timeout=timeout,
        )

        sample = workspace / "sample.nupp"
        source = sample.read_text() if sample.exists() else ""
        after = check(nupp, workspace, entry)

        record = {
            "task": {
                "tier": 1,
                "code": entry["code"],
                "summary": entry["summary"],
                "strict": bool(entry.get("strict")),
                # Whether the compiler offered an edit for this diagnostic.
                # A code that carries one is a different task from a code that
                # only describes the problem, and a sweep that does not
                # separate them reports the average of two populations.
                "hadFix": any(d.get("fixes") for d in before),
                "lean": lean,
            },
            "agent": agent_record(result, events, model),
            "grade": grade(before, after, entry, source),
            "finalSource": source,
            "transcript": str(transcript),
            "workspace": str(workspace) if keep else None,
        }
        (out / f"{code}-run.json").write_text(json.dumps(record, indent=2) + "\n")
        return record
    finally:
        if not keep:
            shutil.rmtree(root, ignore_errors=True)


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
        help="where to write the run record and transcript. Defaults"
        " inside the checkout, which a removed worktree takes with it",
    )
    parser.add_argument(
        "--keep",
        action="store_true",
        help="keep the workspace after the run, for inspection",
    )
    parser.add_argument(
        "--timeout",
        type=float,
        default=300,
        help="seconds before a run is killed and graded a failure; a run that"
        " will not converge is the expensive kind (default 300)",
    )
    parser.add_argument(
        "--lean",
        action="store_true",
        help="send only the tools a repair needs; cheaper per turn, and only"
        " comparable with another lean run",
    )
    args = parser.parse_args()

    nupp = args.nupp.resolve()
    if not nupp.exists():
        raise SystemExit(f"no compiler at {nupp}")
    if not shutil.which("claude"):
        raise SystemExit("the `claude` CLI is not on PATH")

    record = evaluate(
        nupp, args.code, args.out, args.model, args.keep, args.lean,
        args.timeout,
    )
    verdict = "PASS" if record["grade"]["passed"] else "FAIL"
    agent = record["agent"]
    print(f"{verdict}  {record['task']['code']}  {record['task']['summary']}")
    print(
        f"  turns={agent['turns']} tools={agent['toolCallTotal']}"
        f" nupp={agent['nuppInvocations']} cost={spent(agent)}"
    )
    print(f"  before={record['grade']['diagnosticsBefore']}")
    print(f"  after={record['grade']['diagnosticsAfter']}")
    if record["grade"]["suspiciousShrink"]:
        print("  note: the file shrank by more than half; check the repair")
    if record["workspace"]:
        print(f"  workspace={record['workspace']}")
    return 0 if record["grade"]["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
