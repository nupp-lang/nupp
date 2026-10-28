# Lua reference oracle

This tool pins the official Lua 5.5.1 source and checks deterministic bounded Lua programs. It prepares differential inputs for a future core adapter; a successful reference-only run is not core acceptance.

```sh
python3 native/core/oracle/oracle.py provision --output build/core-oracle-reference1
python3 native/core/oracle/oracle.py run \
  --reference build/core-oracle-reference1/reference.json \
  --output build/core-oracle-cases1 --seed 0 --seed 42 --steps 24
CORE_ORACLE_REFERENCE="$PWD/build/core-oracle-reference1/reference.json" \
CORE_ORACLE_TEST_OUTPUT="$PWD/build/core-oracle-selftest1" \
  python3 native/core/oracle/test_oracle.py
```

Use a fresh output directory for every invocation. Provisioning verifies the [official archive checksum](https://www.lua.org/ftp/), builds with the local C compiler, and records the exact interpreter hash, compiler identification, build output, integer-width check, and version. It does not use LuaJIT, Nupp-on-Lua, a Rust interpreter, or the repository's existing LuaJIT toolchain. The source archive and its license remain in the output directory. These are correctness checks, not benchmarks.

The versioned generator uses a specified 32-bit LCG and 1–64 template steps. Its subset contains bounded signed integer arithmetic, floor division and modulo with nonzero constant divisors, branches, short-circuit expressions, finite loops, assignments and swaps, captured-local closures, and acyclic tables. Intermediate generated arithmetic stays far inside signed 64-bit bounds. Each case contains its seed, source hash, coverage categories, and exact exclusions. Replay re-generates the source and metadata and refuses any modification or unknown version; arbitrary input source is not admitted by the runner.

Excluded semantics are listed in every case: floating-point arithmetic, overflow, shifts, coercion, metatables, weak tables, finalizers, observable collection timing, iteration-order dependence, sparse table length, recursive calls, coroutines, errors, resource-exhaustion semantics, I/O, dynamic loading, and identity-sensitive or cyclic serialized observations. This bounded generator is not a general Lua conformance suite.

## Observations

A separate reference-side encoder executes the program in an empty environment and captures all return values, including trailing nils. The output grammar is:

- `R<count>:` followed by each returned value and a final newline.
- Nil `N;`, false `B0;`, true `B1;`.
- Signed integers `I<decimal>;`, formatted as integers without passing through floats.
- Byte strings `S<byte-count>:<lowercase-hex>;`, including empty strings.
- Tables `T<entry-count>:{<key><value>...}`. Keys sort by boolean, integer, string; within each type they sort false before true, numeric ascending, or bytewise ascending. Tables are observed after program execution, so order-independent mutation remains covered. Shared references are serialized by value; identity is tested within the guest program when needed.

Unknown value/key types, floats, cycles, metatables, excessive nesting, and excessive output are explicit failures. There is no conversion of unsupported values to strings or nil. The encoder's library calls are reference tooling, not guest requirements. The target adapter must produce this protocol independently.

## Target and replay

```sh
python3 native/core/oracle/oracle.py run \
  --reference build/core-oracle-reference1/reference.json \
  --output build/core-oracle-target1 --seed 42 \
  --target-command '["/absolute/path/core-adapter","{program}","{manifest}","{output}"]'
python3 native/core/oracle/oracle.py run \
  --reference build/core-oracle-reference1/reference.json \
  --output build/core-oracle-replay1 \
  --replay build/core-oracle-target1/case-000/case.json
```

The command is an argv array, never shell text. `{program}` and `{output}` are required whole arguments; `{manifest}` is optional. Exit 77 means explicit target refusal and does not count as success. Exit zero must create the canonical output file; bytes must match exactly. Timeouts, output limits, other exits, missing files, refusals, and mismatches retain per-case receipts and streams. Run directories also bind the tool, serializer, source and interpreter hashes. Reference-only receipts say `oracle-only`; even matched adapter tests retain `coreAcceptance: false` because backend acceptance requires external provenance and coverage review. Selftests use a reference adapter solely to test harness wiring.

The harness bounds wall time and retained output and kills timed-out process groups. Standard streams and canonical output files are each retained up to 1 MiB; receipts record original and retained sizes, truncation, and the retained-byte hash. Any truncation remains an output-limit failure and cannot count as a match. It is not a security sandbox for arbitrary machine code. Only trusted adapter commands should be supplied. Run under the repository's serialized build/test token.
