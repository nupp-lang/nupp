#!/usr/bin/env python3
"""Run one tier-2 agent evaluation: rediscover a change history already made.

A tier-2 task is a merged commit that touched both the compiler and its tests.
The tests it added are kept and everything else it changed is put back the way
it was, which leaves a suite that fails for exactly the reason the commit was
written. The agent is asked to make that suite pass, and the commit itself is
the known-good answer nobody has to author.

The test is the whole specification, so the agent may not edit it. A run that
changes anything under `tests/` fails on that alone, whatever the suite says
afterwards -- weakening the spec until it passes is the one repair that must
never score.

Cases refresh themselves: every future commit that lands with a narrow test
story is a candidate, so the bank grows with the project. Use `--candidates`
to list the ones in recent history.

See plans/065-agent-evaluation-harness.md. This costs real money per run, and
takes minutes rather than seconds -- the compiler has to be built at the
commit under test.
"""

from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from harness import agent_record, run, run_agent, spent  # noqa: E402


PROMPT = """\
The test suite `{suites}` is failing in this source tree. Make it pass.

Run `./bin/nupp test {first}` to see the failures, and read AGENTS.md for how
this project expects to be worked in.

The tests are correct and are the specification: do not edit anything under
`tests/`, and do not weaken or delete a failing case. Fix the code it is
testing.

This is a source tree with no version control in it, so there is no history to
consult; the failing tests and the code are what you have.
"""

# A suite is `tests/<name>test.lua`, and `nupp test <name>test` runs just it.
SUITE = re.compile(r"^tests/(\w+test)\.lua$")


def git(repo: Path, *args: str) -> str:
    """Run git in a repository and return its stdout, raising on failure."""
    done = run(["git", "-C", str(repo), *args])
    if done.returncode != 0:
        raise SystemExit(f"git {' '.join(args)} failed: {done.stderr.strip()}")
    return done.stdout


def changed_files(repo: Path, commit: str) -> list[str]:
    """Every path the commit touched."""
    out = git(repo, "show", "--name-only", "--format=", commit)
    return [line for line in out.splitlines() if line.strip()]


def split_paths(paths: list[str]) -> tuple[list[str], list[str]]:
    """The suites a commit added or changed, and everything else it touched.

    Everything else is what gets put back: a doc written alongside a feature
    describes it, so leaving it in place would hand the agent the specification
    in prose when the point is that the test is the specification.
    """
    suites, rest = [], []
    for path in paths:
        (suites if SUITE.match(path) else rest).append(path)
    return suites, rest


def candidates(repo: Path, depth: int) -> list[tuple[str, str, int, int]]:
    """Commits in recent history that could be replayed, newest first."""
    found = []
    for line in git(
        repo, "log", f"-{depth}", "--format=%h %s"
    ).splitlines():
        sha, _, subject = line.partition(" ")
        if not sha:
            continue
        paths = changed_files(repo, sha)
        suites, rest = split_paths(paths)
        source = [p for p in rest if p.startswith("src/")]
        if suites and source and len(paths) <= 8:
            found.append((sha, subject, len(source), len(suites)))
    return found


def prepare(repo: Path, commit: str, at: Path) -> tuple[list[str], list[str]]:
    """A source tree at the parent commit, carrying only the child's tests.

    Exported rather than checked out, and with no `.git` in it at all. The
    first version of this made a worktree at the commit and reverted the
    files, which put the answer in `HEAD`: the first agent to run it never
    wrote a line of code, it ran `git restore --staged --worktree` and scored
    a pass. History has to be absent, not merely discouraged -- `git archive`
    writes a tree and no repository, so there is nothing to recover the
    implementation from.

    The parent tree is the code before the change; the suites come forward
    from the commit itself. Everything else the commit touched, its docs
    included, stays at the parent version: a guide written alongside a feature
    describes it, and leaving it would hand over in prose the specification the
    test is supposed to be.
    """
    paths = changed_files(repo, commit)
    suites, rest = split_paths(paths)
    if not suites:
        raise SystemExit(f"{commit} changed no test suite; not a tier-2 task")
    if not any(p.startswith("src/") for p in rest):
        raise SystemExit(f"{commit} changed no source; not a tier-2 task")

    at.mkdir(parents=True)
    archive = run(
        f'git -C "{repo}" archive {commit}^ | tar -x -C "{at}"', shell=True
    )
    if archive.returncode != 0:
        raise SystemExit(f"could not export the tree: {archive.stderr[:300]}")

    # The suites come from the commit, so they describe behaviour the exported
    # tree does not have yet.
    for path in suites:
        target = at / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(git(repo, "show", f"{commit}:{path}"))

    # The dependency tree is ignored by git and so is not in the archive, and
    # nothing builds without it.
    rocks = repo / ".rocks"
    if rocks.exists() and not (at / ".rocks").exists():
        (at / ".rocks").symlink_to(rocks)

    # Content-keyed and stamped with what filled them, so a stale entry is a
    # miss rather than a wrong answer. Copying saves the export a little work.
    cache = repo / "build" / "cache"
    if cache.is_dir():
        shutil.copytree(cache, at / "build" / "cache", dirs_exist_ok=True)

    return suites, [p for p in rest if p.strip()]


def digests(at: Path, paths: list[str]) -> dict[str, str]:
    """A hash per path, for noticing afterwards that one was edited."""
    out = {}
    for path in paths:
        target = at / path
        if target.exists():
            out[path] = hashlib.sha256(target.read_bytes()).hexdigest()
    return out


def suite_names(suites: list[str]) -> list[str]:
    """`tests/foo test.lua` -> `footest`, which is what `nupp test` takes."""
    names = []
    for path in suites:
        match = SUITE.match(path)
        if match:
            names.append(match.group(1))
    return names


def run_suites(at: Path, names: list[str]) -> tuple[bool, str]:
    """Whether every named suite passes, and the last report for the record."""
    report = ""
    for name in names:
        done = run([str(at / "bin" / "nupp"), "test", name], cwd=at)
        report = (done.stdout + done.stderr)[-2000:]
        if done.returncode != 0:
            return False, report
    return True, report


def touched_tests(at: Path, before: dict[str, str]) -> list[str]:
    """Any suite the agent edited, which invalidates the run outright.

    Compared by content rather than asked of git, because the workspace has no
    repository in it -- which is the point, see `prepare`.
    """
    after = digests(at, list(before))
    return sorted(
        path
        for path in before
        if after.get(path) != before[path]
    )


def repair_diff(
    repo: Path, commit: str, at: Path, reverted: list[str]
) -> str:
    """What the agent changed, against the code it was given.

    There is no repository in the workspace to ask, so each file the commit
    originally touched is compared with the parent version it started as.
    """
    chunks = []
    for path in reverted:
        target = at / path
        if not target.exists():
            chunks.append(f"--- {path}\n+++ {path}\n(deleted)\n")
            continue
        was = git(repo, "show", f"{commit}^:{path}")
        now = target.read_text()
        if was == now:
            continue
        chunks.extend(
            difflib.unified_diff(
                was.splitlines(keepends=True),
                now.splitlines(keepends=True),
                fromfile=f"a/{path}",
                tofile=f"b/{path}",
            )
        )
    return "".join(chunks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("commit", nargs="?", help="the commit to replay")
    parser.add_argument(
        "--repo",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="the repository to take the commit from",
    )
    parser.add_argument(
        "--candidates",
        type=int,
        metavar="DEPTH",
        help="list replayable commits in the last DEPTH commits and exit",
    )
    parser.add_argument("--model", help="model for the agent, e.g. sonnet")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent / "results",
        help="where to write the run record and transcript",
    )
    parser.add_argument(
        "--keep", action="store_true", help="keep the worktree after the run"
    )
    args = parser.parse_args()
    repo = args.repo.resolve()

    if args.candidates:
        for sha, subject, source, suites in candidates(repo, args.candidates):
            print(f"{sha}  src={source} suites={suites}  {subject}")
        return 0
    if not args.commit:
        parser.error("a commit is required unless --candidates is given")
    if not shutil.which("claude"):
        raise SystemExit("the `claude` CLI is not on PATH")

    commit = git(repo, "rev-parse", "--short", args.commit).strip()
    args.out.mkdir(parents=True, exist_ok=True)
    at = Path(f"/private/tmp/nupp-eval-t2-{commit}")
    if at.exists():
        raise SystemExit(f"{at} already exists; remove it or finish that run")

    suites, reverted = prepare(repo, commit, at)
    names = suite_names(suites)
    spec = digests(at, suites)
    try:
        print(f"replaying {commit}: {len(reverted)} file(s) left at the"
              f" parent, carrying {', '.join(names)}")
        passed, before = run_suites(at, names)
        if passed:
            # The suite is supposed to fail: the commit's own tests, against
            # the code as it was before the commit. If it passes, the revert
            # did not remove the behaviour and a pass afterwards means nothing.
            raise SystemExit(
                f"{', '.join(names)} already passes with {commit} reverted;"
                " not a task"
            )

        transcript = args.out / f"{commit}-transcript.jsonl"
        prompt = PROMPT.format(suites=", ".join(names), first=names[0])
        result, events = run_agent(
            at, prompt, transcript, args.model, path_prefix=at / "bin"
        )

        edited = touched_tests(at, spec)
        passed, after = run_suites(at, names)
        record = {
            "task": {
                "tier": 2,
                "commit": commit,
                "subject": git(repo, "log", "-1", "--format=%s", commit).strip(),
                "suites": names,
                "revertedFiles": reverted,
            },
            "agent": agent_record(result, events, args.model),
            "grade": {
                "suitesPass": passed,
                "editedTests": edited,
                "passed": passed and not edited,
                "reportAfter": after,
                "reportBefore": before,
            },
            "diff": repair_diff(repo, commit, at, reverted),
            "transcript": str(transcript),
        }
        record_path = args.out / f"{commit}-run.json"
        record_path.write_text(json.dumps(record, indent=2) + "\n")

        verdict = "PASS" if record["grade"]["passed"] else "FAIL"
        agent = record["agent"]
        print(f"{verdict}  {commit}  {record['task']['subject']}")
        print(
            f"  turns={agent['turns']} tools={agent['toolCallTotal']}"
            f" nupp={agent['nuppInvocations']} cost={spent(agent)}"
        )
        if edited:
            print(f"  edited the specification: {', '.join(edited)}")
        print(f"  record={record_path}")
        if args.keep:
            print(f"  worktree={at}")
        return 0 if record["grade"]["passed"] else 1
    finally:
        if not args.keep:
            shutil.rmtree(at, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
