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

Generate the first transport artifact and run it with an independently calibrated bridge guard:

```sh
python3 native/core/tests/test_heap_workload.py \
  --root "$PWD" --output "$PWD/build/heap-noop" \
  --runner-binding "$PWD/build/heap-prepare/runner-binding.json" \
  --bridge /absolute/path/to/nupp-core \
  --guard-proof /absolute/path/to/guard-proof.json \
  --abi-test-binary /absolute/path/to/proven-guard-binary
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
```

Preparation currently reruns the focused suites after helper-only edits. Reusing
an existing runner requires both its prior completed-build/attachment evidence
and equality of every runner module and dependency input, while the changed
helper still needs a fresh source check and snapshot. Unchanged executable bytes
alone do not prove that relationship; this optimization is deferred.
