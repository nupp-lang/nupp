# Owned heap tests

These tests build the real checked service catalog and select it with the owned backend. Heap and collector functions execute only in the native bridge; the source-bound compiler runner builds and inspects their graphs.

From the checkout root, prepare a fresh runner and retain its binding:

```sh
python3 native/core/tests/heap_runner_support.py \
  --output "$PWD/build/heap-prepare"
python3 native/core/tests/test_heap_graphs.py \
  --root "$PWD" --output "$PWD/build/heap-graphs" \
  --runner-binding "$PWD/build/heap-prepare/runner-binding.json"
```

Preparation uses the installed generation selected by `.nupp/vm-cli/current`. Supply both `--runtime` and `--compiler-image` to select a different frozen compiler. It checks the canonical helpers and their source dependencies, runs the focused compiler suites, verifies that source and tools stayed unchanged, and binds the completed test runner's exact attached image. It does not rebuild the installed compiler. Preparation, graph checks and native runs require exclusive access to this checkout's compiler and test artifacts.

Prepare the unchanged bridge and its calibrated guard in a fresh output directory:

```sh
python3 native/core/tests/prepare_heap_guard.py \
  --output "$PWD/build/heap-guard"
```

This uses the repository Rust toolchain with offline, locked Cargo builds. It records the original bridge sources, build inputs, commands, tool versions and executable hashes, then runs all eight existing calibrations. It neither invokes the Nupp compiler nor formats or changes bridge sources. The three generated-artifact checks remain pending until an actual owned bundle is supplied. Each invocation requires a new output directory.

Generate the first transport artifact and run it with that guard:

```sh
python3 native/core/tests/test_heap_workload.py \
  --root "$PWD" --output "$PWD/build/heap-noop" \
  --runner-binding "$PWD/build/heap-prepare/runner-binding.json" \
  --bridge "$PWD/build/heap-guard/bin/nupp-core" \
  --guard-proof "$PWD/build/heap-guard/receipt.json" \
  --abi-test-binary "$PWD/build/heap-guard/bin/nupp-core-abi-tests"
```

The default is `--mode normal --scenario noop`. `--artifact-only` stops after authenticated artifact generation and does not require bridge arguments. The explicit guard binary must match the supplied proof and current bridge source hashes. A missing old worktree binary is an error; the driver cannot replace it with an unchecked executable. The existing `native/core/bridge/tests/test_guarded.py` calibrates the bridge's guard and ABI checks against generated control-flow bundles. A fresh guard receipt with the same source/binary bindings is also accepted.

Select each acceptance case explicitly:

| Cases | Modes | What they establish |
| --- | --- | --- |
| `noop`, `acquire-refusal`, `release-refusal` | `normal`, `spill` | Original mapping wrappers and their checked refusal paths |
| `cell-normal`, `cell-stress` | `normal`, `spill` | Source-created Heap, CELL construction, root transfer, collection and teardown |

Release refusal means a mismatched extent rejected before the release attempt; it does not simulate an OS unmap failure. CELL cases still require the compiler's exact entry-lifetime proof. A transport pass never counts as Heap acceptance. Each invocation records its selected case; a complete matrix requires all ten cases.

The drivers retain source snapshots, runner binding, generated images and diagnostics, artifact bytes, command outputs and hashes. `graph-build-passed`, `artifact-produced`, and `native-boundary-passed` are distinct results. Native success requires both the bridge checksum and the existing ABI/scratch guard. Missing admission remains a refusal, not a skipped passing test.

The four compiler modules that own checked identities are resolved with ordinary `require` before any dynamic builder image. Their registry identities must remain unchanged. The temporary Lua fixture loads each missing builder module once, compiles the original tracked producer, and preserves its factory, graph, owner and selected-code objects through authenticated linking. It does not add a front end or execute Heap services on the interim VM.

A temporary test suite and `build/core-heap-services/snapshot.json` are installed only for the run, then removed or restored if their bytes are unchanged. All source dependencies, including the dynamic helpers and Python drivers, must still match the preparation binding. The historical accepted-base supplement is read only for older receipts; fresh preparation binds the complete inventory before the build. No script under `build/` is needed to run these tests.

Pure provenance tests do not invoke a compiler or execute native code:

```sh
python3 native/core/tests/test_heap_runner_tools.py
python3 native/core/tests/test_heap_guard_tools.py
```

After editing only existing checked helper files, reuse the original runner:

```sh
python3 native/core/tests/heap_runner_support.py \
  --output "$PWD/build/heap-prepare-helper" \
  --reuse-runner-binding "$PWD/build/heap-prepare/runner-binding.json"
```

Reuse requires an original passing preparation with the complete input inventory.
Older bindings and bindings produced by reuse cannot serve as the original build.
The current source inventory must match, with changed bytes confined to existing
`CHECK_HELPERS` files. Runner modules, includes, resources, configuration, tools,
state, image, payload and executable remain bound to their original hashes. A
changed project manifest requires review of the reuse inventory before reuse is
available again; ordinary preparation still works.

Every reuse checks the helpers and their dependencies again and captures a fresh
source snapshot. Its receipt records the original build and focused-test evidence
separately from the current helper check; it does not claim a new focused run.
Keep the original binding, proof and focused outputs alongside the new receipt.
Unchanged executable bytes alone never authorize reuse.
