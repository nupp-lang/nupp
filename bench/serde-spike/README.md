# Serde architecture spike

This benchmark tests whether a format-neutral, schema-driven serde layer can
replace `derive.JSON` without sacrificing its hot paths. It is a mechanism
spike, not a proposed public API.

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
