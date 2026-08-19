#!/usr/bin/env python3
"""What every evaluation tier needs: run an agent, and count what it did.

The tiers differ in what the task is and how it is graded. They do not differ
in how an agent is started, what is recorded about the run, or what a tool call
costs, so that part lives here and each tier imports it.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path


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


# What a tier-1 repair actually needs: look at the file, change it, ask the
# compiler. Naming them keeps every other tool's schema out of the context that
# is re-sent on every turn, which is where this measurement's money goes --
# input was 87% of the cost of the first sweep and output was 12%.
REPAIR_TOOLS = ["Read", "Edit", "Write", "Bash"]


def run_agent(
    workspace: Path,
    prompt: str,
    transcript: Path,
    model: str | None = None,
    path_prefix: Path | None = None,
    tools: list[str] | None = None,
    bare: bool = False,
    timeout: float | None = None,
) -> tuple[dict, list[dict]]:
    """Run one agent against a workspace, keeping its whole transcript.

    Streaming rather than a single result, because the events say what the
    agent did and not only what it ended with: the tool calls are where the
    cost went, and are the part worth comparing between two runs that both
    passed.

    `tools` trims what is sent every turn, which is where the money goes: input
    was 87% of the first sweep's cost and output was 12%. It changes what the
    agent is and not just what it costs, so a run using it is only comparable
    with another using it -- a tool the task turns out to need is a task made
    harder rather than cheaper.

    `bare` would trim more, and is left unused: it authenticates strictly from
    `ANTHROPIC_API_KEY`, so under an OAuth login every run returns "Not logged
    in" having done nothing, which grades as a failure that says nothing about
    the agent.
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
    if bare:
        argv.append("--bare")
    if tools:
        argv += ["--allowedTools", *tools]
    if model:
        argv += ["--model", model]
    argv.append(prompt)

    environment = dict(os.environ)
    if path_prefix:
        environment["PATH"] = (
            f"{path_prefix}{os.pathsep}{environment['PATH']}"
        )

    started = time.monotonic()
    timed_out = False
    try:
        done = run(argv, cwd=workspace, env=environment, timeout=timeout)
        output = done.stdout
        code = done.returncode
        problem = done.stderr
    except subprocess.TimeoutExpired as expired:
        # A run that will not converge is the expensive kind. One task in the
        # first Haiku sweep spent 172 tool calls and $1.26 failing, which was
        # an eighth of that sweep's whole cost; capping it turns a runaway into
        # an ordinary failure without changing what any other run does.
        timed_out = True
        output = (expired.stdout or b"").decode("utf-8", "replace") if isinstance(
            expired.stdout, bytes
        ) else (expired.stdout or "")
        code, problem = -1, f"timed out after {timeout}s"
    elapsed = time.monotonic() - started

    events = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    transcript.write_text("".join(json.dumps(e) + "\n" for e in events))

    if not events:
        raise SystemExit(
            f"the agent produced no events; exit {code}: {problem[:400]}"
        )
    result = next(
        (event for event in reversed(events) if event.get("type") == "result"),
        {},
    )
    result["wallClockSeconds"] = round(elapsed, 1)
    result["timedOut"] = timed_out
    return result, events


def tool_calls(events: list[dict]) -> tuple[dict[str, int], int]:
    """How many times each tool was called, and how many of those ran `nupp`.

    The second number is the one worth watching: an agent that asks the
    compiler once, reads the answer and repairs is doing the thing the tooling
    is for, and one that asks eight times is paying for something the first
    answer was supposed to have told it.
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


def agent_record(result: dict, events: list[dict], model: str | None) -> dict:
    """The cost side of a run, in the shape every tier records it."""
    counts, nupp_runs = tool_calls(events)
    return {
        "model": model or "default",
        "turns": result.get("num_turns"),
        "costUsd": result.get("total_cost_usd"),
        "durationMs": result.get("duration_ms"),
        "wallClockSeconds": result.get("wallClockSeconds"),
        "outputTokens": result.get("usage", {}).get("output_tokens"),
        "isError": result.get("is_error"),
        "timedOut": result.get("timedOut", False),
        "toolCalls": counts,
        "toolCallTotal": sum(counts.values()),
        "nuppInvocations": nupp_runs,
    }


def spent(record: dict) -> str:
    """The cost as money, or a question mark when the run did not report it."""
    cost = record.get("costUsd")
    return f"${cost:.4f}" if isinstance(cost, (int, float)) else "?"
