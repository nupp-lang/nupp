# Portable storage and I/O baselines

Run from the repository root. Keep compiler builds and other benchmarks out of
measured intervals. Preserve raw samples from both baseline and candidate on the
same machine, with the same compiler settings, VM and input counts.

```sh
bench/portable-storage-io/run.sh > native.jsonl
tests/wasm-memory/run.sh wasm bench/portable-storage-io/wasm.lua > wasm.jsonl
bench/span-range-lowering/run.sh > spans.txt
bench/span-range-lowering/trace.sh > traces.txt
```

The Wasm runner needs the same Lua 5.1 source and Emscripten setup as
`tests/wasm-aot/run.sh`. Set `NUPP_LUA51_SOURCE` and `NUPP_WASM_CC` when needed.
It compiles the actual memory service into a temporary Wasm program and removes
its output on exit. The `native` runner mode exercises the same C service with
stock Lua on the host; it is not the native LuaJIT storage representation.

`native.lua` measures ordinary public I/O calls with three warmups and nine raw
samples. `NUPP_IO_STEPS` and `NUPP_IO_ROUNDS` change those sizes. Inputs are fixed
and results are observed; JIT constant propagation and sinking remain enabled.
This is a reproducible comparison, not a promise about every application's cost.
The span benchmark separately measures checked Nupp kernels, compiler wrapper
elimination and AOT. Its timing assertions are gates: retain and investigate a
failed baseline rather than removing them.

Allocation accounting runs separately with JIT disabled and collection stopped.
`ffiNewCalls`, `copyCalls`, `ffiCopiedBytes` and `ffiMaterializedBytes` count only
those FFI operations. They do not count compiler-emitted element-copy loops,
Lua substring operations or allocations sunk by the JIT in a timed run.
`apiTransferBytes` records the bytes deliberately transferred by the public
read/write workload and is separate from any growth copies. `uncollectedKiB` is
Lua GC-accounted growth, including temporary metadata, not process peak RSS.
Do not read a zero FFI-copy count as evidence of a zero-copy transfer.

The borrow/slice case includes initial Buffer construction: its one initial
payload copy must be separated from the later metadata-only views. The Wasm
benchmark measures bulk movement, interpreted scalar calls and uncollected lease
metadata, with no JavaScript call per byte. Wasm AOT and native AOT have separate
conformance/measurement paths; these interpreter measurements cannot prove their
performance or public I/O portability.

The portable-storage execution report under `~/projects/nupp-plans` records the
inspected revision, measurements, missing coverage and remaining milestones.
