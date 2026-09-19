# GPU operation costs

Build the native CPU and GPU kernels from this directory:

```sh
../../bin/nupp build --target native
```

From the repository root, compare forced CPU AOT SIMD and GPU paths on the same
64-round unsigned-integer workload at three input sizes:

```sh
./bin/nupp bench --file bench/gpu-costs/costs.bench.lua --forks 3 --json
```

Both variants receive the same input and produce the complete host-visible
output on every invocation. The GPU variant includes upload, dispatch,
synchronization, download and host copying. Setup, the first GPU dispatch and
cleanup are outside the steady-state benchmark samples; GPU cost records include them separately. Each sample
checks every output element against the CPU result at teardown. The harness
refuses to run without the generated GPU binding and verifies the CPU entry
in the runtime compiled-AOT registry. Both are built in the same module with
the `require` AOT policy.

Use `--variant 'cpu%-aot'` or `--variant 'gpu%-transfer'` to force one route, and
`--parameter count=4096` to select an input size. Device cost collection is
optional and adds measurement overhead, so collect an instrumented account
separately from the timing comparison.

Collect per-operation records in a caller-selected directory:

```sh
./bin/nupp bench --file bench/gpu-costs/costs.bench.lua --gpu-costs /private/tmp/nupp-gpu-costs --json
```

Each run uses a unique subdirectory, and each candidate, case and fork gets its
own JSONL file. The benchmark JSON names that file on each fork. For a single
program, `nupp run --gpu-costs PATH --profile PROGRAM` combines device cost
records with CPU sampling.

An untimed compiled-route and full-output check is available separately:

```sh
./bin/nupp run --gpu-costs /private/tmp/nupp-gpu-smoke.jsonl bench/gpu-costs/costs.bench.lua --smoke 4096
```

The [Apple M5 Pro exploratory curve](results/arm64-macos.md) includes all five
forks, observed ranges, operation records, artifact hashes and packaged-VM proof.
