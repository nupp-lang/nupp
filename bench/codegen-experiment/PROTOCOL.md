# Typed representation to Cranelift: measurement protocol

P1 of [the runtime plan](../../../nupp-plans/todo/nupp-runtime.md), run before
any collector, interpreter or scheduler exists. The question is whether a
non-speculative lowering of typed Nupp semantics reaches LLVM-class code on the
kernels the plan cares about, what a call boundary costs, and what compilation
costs.

## What is compiled

`src/jit.rs` is a small typed emitter over Cranelift's `FunctionBuilder`: values
carry a type tag checked at emission, span access is either proved (the loop
fact the bytecode's elided `BOUNDS` would cite) or checked with a trap, vectors
are `f64x2` register values, calls are direct or imported. `src/kernels.rs`
writes five kernels against it, mirroring `bench/luajit-simd-replacement`'s
integrated kernels and the SHA-256 benchmark:

- `map`: out = in * scale + bias over a float64x4 species as two `f64x2`
  values, masked tail lowered lane-wise; `map_u2` repeats the step twice per
  iteration.
- `dot`: algebraic reduction with two `f64x2` accumulators and a scalar tail;
  `dot_u2` with four accumulators.
- `sha256_compress`: whole blocks in `u32` arithmetic, rotates, a 64-word
  schedule in a stack slot, three loops rather than unrolled rounds. Padding is
  done by the harness, as the C control does internally.
- `chunk_direct`: 64-element dot per chunk through a direct call to compiled
  `dot`; `chunk_extern` through an imported call to the hand-written C
  kernel. The harness adds the same loop in Rust calling compiled `dot` and
  calling the LLVM artifact.

Optimisation level `speed`, no PIC, native ISA flags.

## Bars

- LLVM NEON: `libkernels_aot.dylib` from the integrated experiment, the `@aot`
  copy of the same Nupp kernels, called through its C ABI.
- Hand-written NEON intrinsics: `bench/simd11/handwritten/neon.c`, built with
  the system clang at `-O2` into `libhand.dylib`.
- SHA-256: the frozen C control `sha256_control.c` built by the SHA-256
  benchmark, clang `-O2`. The LLVM-compiled Nupp SHA-256 takes a Lua string
  through the C API runtime and cannot be called from this harness; its
  throughput from the same-day Lua benchmark is quoted for context only.

## Measurement

Correctness first: every kernel against a Rust reference, the LLVM artifact
and the hand-written kernel at 17 sizes including 0, 1, odd tails, 63, 1024
and 65,539; chunked variants at six widths; SHA-256 against the C control at
every padding boundary and at 64 KiB and 1 MiB. The timed run refuses to start
on a failure.

Timing: CPU time of the calling thread, 20 ms samples calibrated per runner,
four warmups, nine rounds with rotated order within a size group, nine
processes. Ratios are process-median paired ratios combined by geometric mean
with a t95 log interval (df 8); a CV above 5% is reported, not hidden. Sizes
63, 1,024 and 65,539 for map and dot; 32 B, 1 KiB, 64 KiB and 1 MiB for SHA-256;
65,539 in 64-element chunks for the call variants. Compile time per function is
wall time from signature to defined function, recorded per process.

The machine carried other sessions' builds during the run; absolute times are
indicative, paired ratios with low CV are the evidence.
