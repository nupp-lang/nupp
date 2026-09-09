#!/usr/bin/env bash
# One retained row per required run.
#
# "Is the trunk usually green" and "how long does a change wait" were both
# answerable only by opening runs one at a time in a browser, which is why the
# baseline for this work had to be reconstructed by hand from two hundred of
# them. Writing the answer down as the run finishes costs a second and makes the
# next question a query rather than an afternoon.
set -euo pipefail

results=build/ci-record
mkdir -p "$results"

record="$results/${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}.json"

# The run's own timing is only on the API: a workflow cannot see when it was
# created, only when its steps ran, and the difference between those two is
# exactly the queue delay this is here to measure.
run_json=$(gh api "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}" 2>/dev/null || echo '{}')
jobs_json=$(gh api --paginate \
  "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/attempts/${GITHUB_RUN_ATTEMPT}/jobs" \
  2>/dev/null || echo '{"jobs":[]}')

RUN_JSON="$run_json" JOBS_JSON="$jobs_json" python3 - "$record" <<'PY'
import datetime
import json
import os
import sys


def instant(value):
    if not value:
        return None
    return datetime.datetime.fromisoformat(value.replace("Z", "+00:00"))


def seconds(start, end):
    if start is None or end is None:
        return None
    return round((end - start).total_seconds(), 1)


run = json.loads(os.environ.get("RUN_JSON") or "{}")
jobs = (json.loads(os.environ.get("JOBS_JSON") or "{}")).get("jobs", [])

created = instant(run.get("created_at"))
started = instant(run.get("run_started_at"))
now = datetime.datetime.now(datetime.timezone.utc)

# A failed step is what a person opening a red run is looking for, and the one
# thing a conclusion alone never says.
failures = []
for job in jobs:
    if job.get("conclusion") in (None, "success", "skipped"):
        continue
    for step in job.get("steps") or []:
        if step.get("conclusion") not in (None, "success", "skipped"):
            failures.append({
                "job": job.get("name"),
                "step": step.get("name"),
                "conclusion": step.get("conclusion"),
            })

record = {
    "repository": os.environ.get("GITHUB_REPOSITORY"),
    "runId": os.environ.get("GITHUB_RUN_ID"),
    "runAttempt": os.environ.get("GITHUB_RUN_ATTEMPT"),
    "workflow": os.environ.get("GITHUB_WORKFLOW"),
    "event": os.environ.get("GITHUB_EVENT_NAME"),
    "ref": os.environ.get("GITHUB_REF"),
    "revision": os.environ.get("GITHUB_SHA"),
    "createdAt": run.get("created_at"),
    "startedAt": run.get("run_started_at"),
    "recordedAt": now.isoformat(),
    "queueSeconds": seconds(created, started),
    "executionSeconds": seconds(started, now),
    "selection": json.loads(os.environ["SELECTION"]) if os.environ.get("SELECTION") else None,
    "jobs": [
        {
            "name": job.get("name"),
            "conclusion": job.get("conclusion"),
            "startedAt": job.get("started_at"),
            "completedAt": job.get("completed_at"),
            "seconds": seconds(instant(job.get("started_at")), instant(job.get("completed_at"))),
            "runnerMinutes": (
                None
                if seconds(instant(job.get("started_at")), instant(job.get("completed_at"))) is None
                else round(seconds(instant(job.get("started_at")), instant(job.get("completed_at"))) / 60, 1)
            ),
        }
        for job in jobs
    ],
    "failedSteps": failures,
}

# The number the plan's runner-minute target is measured against, so it is
# recorded rather than recomputed from a job list months later.
minutes = [job["runnerMinutes"] for job in record["jobs"] if job["runnerMinutes"] is not None]
record["runnerMinutes"] = round(sum(minutes), 1) if minutes else None

# From the job conclusions rather than from the failed steps: a job can fail
# without any step failing -- a cancellation, or a failure to provision the
# runner at all -- and a row that called those runs green would be a row that
# quietly answered the question this file exists to answer.
record["conclusion"] = (
    "failure"
    if any(job.get("conclusion") not in (None, "success", "skipped") for job in jobs)
    else "success"
)

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(record, handle, indent=2, sort_keys=True)
    handle.write("\n")

print(json.dumps({key: record[key] for key in
                  ("revision", "event", "queueSeconds", "executionSeconds",
                   "runnerMinutes", "conclusion")}, indent=2))
PY
