# Local test fleet

`nupp task test-fleet` snapshots the exact tracked, dirty, staged, deleted, and
nonignored files in the current checkout, then sends one verified Git bundle to
every configured worker. No branch, push, pull request, or GitHub Actions run is
involved.

For an occasional hosted fallback, manually run the **SIMD execution
conformance** workflow in GitHub Actions. It is never selected by automatic CI.

Copy `tests/fleet/config.example.json` to the ignored `.nupp/fleet.json` and
replace its endpoint names and Docker image digests. List the fixed repository
plan before starting it:

```sh
./bin/nupp task test-fleet --list
./bin/nupp task test-fleet
./bin/nupp task test-fleet --rerun .nupp/fleet/runs/RUN/aggregate.json
```

The configuration only maps logical executors to `local`, `ssh`, or `docker`
transports. Commands come from `tests/fleet/plan.json` in the received snapshot,
not from endpoint configuration. Docker images must be pinned by SHA-256 and are
used only for Linux userlands. macOS and Windows evidence comes from native
hosts or full VMs. AVX2, AVX-512, and NEON require real compatible CPUs with the
features exposed to the guest.

Each worker invokes ordinary `./bin/nupp test ... --json`. The coordinator keeps
the raw reports, qualifies stable case IDs by job, verifies report arithmetic,
aggregates capabilities, work, metrics, artifact identities, and witnesses, and
runs the executable SIMD obligation ledger. Missing hardware is incomplete
fleet evidence, even when the individual harness case correctly reports
`not-executed`.

Toolchains, compiler entries, and immutable test fixtures use worker-local
shared caches with their existing identity checks. A newer run supersedes the
active run and terminates its worker process trees without deleting those
caches. Failure reruns return each raw child report to the same logical executor
and use the harness's exact `--rerun` selection.
