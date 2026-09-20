# Explicit SIMD correctness inventory

The generated primitive and reducer corpora share `tests/simd/runner.lua`.
Native runs request one exact tier and intercept each exported probe's actual
C entry; Wasm runs consume the same source and scalar expectations. A source or
assembly assertion alone is not an execution result. The native corpus also runs
through each emitted forced-scalar C twin, using its actual generated ABI and
counting completed calls, against the same independent expectations.

## Public domain

Elements: `float`, `number`, `int8`, `uint8`, `int16`, `uint16`, `int32`,
`uint32`, `int64`, `uint64`. Species: every `Fixed<2>` through `Fixed<64>` and
`Preferred`. `Fixed<1>` has a positioned refusal. The logical species can span
several native vectors; padding lanes are not lanes of the program.

Native tiers are `baseline`, `avx2`, `avx512f`, and `neon`; browser execution
uses `simd128`. The matrix reports unavailable host tiers rather than claiming
that inspecting their generated C executed them. Compiler/OS jobs own the
cross-target execution record.

## Primitive families

| Family | Executable scalar comparison |
| --- | --- |
| load/store, masked load/store, splat, iota | `primitives.lua`, every element/species, every tail 0..N |
| arithmetic, comparisons, elementwise named extrema | `primitives.lua`, every element/species |
| mask and/or/xor/not/equality, scalar/vector select, boolean masks | `primitives.lua`, every element/species and four mask patterns |
| mask any/all/count/first/bits | `primitives.lua`, every bit independently checked including zero padding |
| reverse/rotate/align/insert/extract | `primitives.lua`, every element/species |
| interleave/deinterleave | `primitives.lua`, every element/species including odd widths |
| compress/expand/ordered prefix sum | `primitives.lua`, every element/species |
| integer and/or/xor/shifts/prefix xor/swizzle/paired swizzle | `primitives.lua`, all eight integer elements/species; `integeredges.lua` adds signed/wrapping boundaries, exact 64-bit values and count edges for all three shifts |
| transpose and bit-preserving reinterpretation | `transpose.lua`, all ten elements and every Fixed width 2..64; raw words include signed zero and NaN payloads |
| numeric conversion | `conversions.lua`, all 100 numeric pairs at every Fixed width, same-width Preferred pairs, every tail; independent ordinary scalar storage conversions |
| indexed load/store and strided fields | `memory.lua`, all elements/species, four admitted index types, every tail, zero/out-of-range indices and scalar address oracle |
| scalar helper and closed math map | `primitives.lua`, scalar helper for every element/species and floating absolute value; `aotbuildtest` retains square-root plus binary32 helper-rounding differential |
| horizontal reductions and exact reducers | `reducers.lua`, maintained separately from primitive lane operations |

Every generator reports the actual selected cases in its coverage record.
Preferred indexed memory requires index and value elements of the same physical
width; narrow 8/16-bit values consequently have no admitted Preferred index
species. Square transpose requires Fixed. The refusal suite covers these
restrictions, incompatible conversion/reinterpretation, floating integer-only
operations and invalid literal lane indices. Alignment requires a nonnegative
literal offset: zero, one, the species boundary and a clamped larger offset are
compared; a species-property expression retains its positioned refusal.

The main lane family uses small exact inputs, all-zero/all-selected/mixed masks,
and floating signed zero, NaN and infinities. The unsigned 64-bit operations
that wrap under those inputs compare exact wide values. The integer edge family
also checks every storage boundary, negative/high-bit values, wrapping arithmetic,
and shifts at counts -1, 0, 1, 2, width-1, width and width+1. Narrow shift
references explicitly use physical lane bits rather than promoted int32 values.
Conversion uses full integer boundaries and a shared finite floating domain; existing `aotbuildtest`
conversion regressions retain host-specific out-of-range float-to-integer
behavior. Bit-preserving transpose compares raw storage words, including NaN
payloads, rather than converting them through binary64.

## Migrated algorithms and independent references

| Explicit algorithm | Independent reference and corpus |
| --- | --- |
| UTF-8 lookup validator | `bench/utf8simd/src/utf8reference.nupp`; all bytes/pairs, constrained leads, boundary/tail errors and deterministic random strings, also checked against shipped UTF-8 validation |
| Base64 encoder | `bench/base64simd/src/base64reference.nupp`; every byte in every group/tail position, lengths and deterministic random input, also checked against shipped codec |
| structural JSON indexer | `bench/simd-json/src/simd_json/indexer_reference.nupp`; exact tape/status/first-error, byte positions, escape parity, Unicode and capacity boundaries |
| fused JSON decoder | `tests/jsonfuseddifferentialtest.lua`; independent byte-wise scalar indexing/decoding and nine shared native differentials, including every byte at block transitions |

Algorithm runners must observe execution of the tested artifact's compiled
entry. An unrelated registry entry, a loaded library, or a scalar fallback that
returns the right answer does not prove this.
