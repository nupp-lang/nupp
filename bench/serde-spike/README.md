# Serde architecture spike

This benchmark tests whether a format-neutral, schema-driven serde layer can
replace `derive.JSON` without sacrificing its hot paths. It retains both the
original mechanism spike and the production prepared-codec implementation.

The Nupp module compares the current derived implementation with:

- handwritten JSON writer calls;
- generated, format-neutral serializer callbacks;
- generic schema walking over record fields and indexed dynamic slots; and
- a benchmark-only native codec that consumes the same immutable schema in one
  crossing, with pre-encoded keys for writing and raw-byte member lookup for
  reading.

The native decoder speculates that fields arrive in schema order, then falls
back to FNV-1a buckets, length, and byte comparison. It writes either logical
record fields or positional dynamic slots without materializing JSON key
strings. Unknown values are consumed without constructing Lua values.

The two record sizes separate call overhead from field traversal. Decode also
measures schema-order, reverse-order, and unknown nested fields.

Run fifteen samples:

```sh
./run.sh
```

Retain raw samples as JSON:

```sh
./run.sh --json 15
```

Every implementation is warmed independently and measured through unique
monomorphic loop bytecode. Each case calibrates to at least 75 ms, samples run
in alternating order, and returned values are consumed inside the timed loop.

## Prototype result

The retained Apple arm64/LuaJIT run is
`results/arm64-macos-prototype.json`. It contains 15 samples per case. Selected
medians and paired bootstrap intervals are:

| Scenario | Implementation | ns/op | Speedup over current derive |
| --- | --- | ---: | ---: |
| Encode, 3 fields | Current `derive.JSON` | 3,898 | 1.00x |
| Encode, 3 fields | Static serde callbacks | 3,661 | 1.06x (1.02–1.10x) |
| Encode, 3 fields | Native schema + record | 145 | 27.17x (26.29–27.57x) |
| Encode, 3 fields | Native schema + slots | 114 | 34.89x (33.73–35.35x) |
| Encode, 12 fields | Current `derive.JSON` | 11,843 | 1.00x |
| Encode, 12 fields | Static serde callbacks | 11,504 | 1.07x (1.05–1.07x) |
| Encode, 12 fields | Native schema + record | 490 | 24.89x (24.38–25.54x) |
| Encode, 12 fields | Native schema + slots | 321 | 36.46x (36.30–36.93x) |
| Decode, 3 fields | Current `derive.JSON` | 649 | 1.00x |
| Decode, 3 fields | Native schema + record | 243 | 2.67x (2.62–2.68x) |
| Decode, 3 fields | Native schema + slots | 173 | 3.75x (3.74–3.84x) |
| Decode, 12 ordered fields | Current `derive.JSON` | 1,911 | 1.00x |
| Decode, 12 ordered fields | Native schema + record | 613 | 3.06x (2.98–3.10x) |
| Decode, 12 ordered fields | Native schema + slots | 361 | 5.12x (5.03–5.37x) |
| Decode, 12 reverse fields | Native schema + record | 669 | 2.75x (2.70–2.82x) |
| Decode, unknown nested field | Native schema + record | 664 | 3.28x (3.19–3.35x) |

Static serde callbacks, handwritten JSON, and generic Lua schema walking are
all within about seven percent of one another. They share the actual cost: each
key, scalar, and container operation enters the native writer and immediately
drains it into `string.buffer`.

The large gain comes from retaining the schema abstraction while moving the
whole traversal into one codec entry. The static record path performs cached
raw field reads; the dynamic path uses member-indexed slots. Decode compares
simdjson key bytes directly and therefore constructs neither a key string nor
an intermediate document.

This is an upper-bound mechanism result, not a complete serde result. The
native spike handles flat structures and scalar strings, integers, numbers,
and booleans. It does not yet cover recursive structures, optionals, unions,
lists, maps, defaults, streaming values, or the complete validation and error
surface of the current derive. Those cases must be added before replacing the
public derive.

## Prepared implementation result

The retained production run is `results/arm64-macos-prepared.json`, with 15
samples per case on Apple arm64 and LuaJIT. `preparedSerde` includes ordinary
`serde.of`, codec preparation before timing, and the public `Prepared<T>` call;
it is not a direct call to the benchmark-only native module.

| Scenario | Current `derive.JSON` | Prepared serde | Speedup (95% CI) |
| --- | ---: | ---: | ---: |
| Encode, 3 fields | 2,465 ns | 149 ns | 16.52x (16.45–16.53x) |
| Encode, 3 fields, caller buffer | 2,465 ns | 184 ns | 13.37x (13.32–13.43x) |
| Encode, 12 fields | 5,179 ns | 540 ns | 9.60x (9.53–9.62x) |
| Encode, 12 fields, caller buffer | 5,179 ns | 575 ns | 9.02x (8.86–9.06x) |
| Decode, 3 fields | 613 ns | 431 ns | 1.42x (1.41–1.43x) |
| Decode, 12 ordered fields | 1,633 ns | 790 ns | 2.07x (2.05–2.15x) |
| Decode, 12 reverse fields | 1,643 ns | 846 ns | 1.94x (1.92–1.95x) |
| Decode, unknown nested field | 1,932 ns | 840 ns | 2.30x (2.29–2.32x) |

The small gap between the prepared path and the benchmark-only native upper
bound is the public binding and prepared-object dispatch. Encoding keeps most
of the spike's gain. Decode remains faster than the compatibility derive while
also performing raw-byte member matching, duplicate detection, required-member
checks, scalar conversion, and unknown-value skipping.

## Reserved-buffer implementation result

The retained `results/arm64-macos-buffered.json` run measures the prepared
buffer fast path with 15 samples. `preparedSerdeCopied` reproduces the previous
implementation in the same binary: encode a complete Lua string and then append
that string to `string.buffer`. `preparedSerdeBuffered` reserves caller-owned
storage, performs one native traversal, and commits the encoded bytes without
constructing that intermediate Lua string.

| Scenario | Current derive | Previous encode + copy | Reserved buffer | Change from previous | Speedup over derive (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| 3 fields | 2,403 ns | 204 ns | 206 ns | -1.1% | 11.67x (11.65–11.70x) |
| 12 fields | 5,164 ns | 612 ns | 607 ns | +0.8% | 8.51x (8.45–8.53x) |
| 4 KiB string | 3,024 ns | 581 ns | 461 ns | +26.1% | 6.56x (6.48–6.59x) |
| 64 KiB string | 19,288 ns | 7,843 ns | 7,124 ns | +10.1% | 2.71x (2.66–2.75x) |

Small structures are effectively unchanged: their temporary strings were
cheap, and reserving plus committing caller storage replaces that fixed cost.
The benefit appears once copying and allocating the complete result matters.
The 4 KiB and 64 KiB cases are 26% and 10% faster than the exact former path,
respectively, while also reducing peak transient storage by one complete Lua
string.

The reservation starts with a small common-case capacity. When fresh caller
storage is too small, the native encoder retains its pooled scratch result,
the buffer grows to the exact size, and a second native entry copies the result
without traversing the value again. Reused buffers normally retain enough
capacity and stay on the one-entry path.
