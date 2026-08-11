# Materialization M0 benchmark contract

This document freezes the evidence contract before measuring the PEG
materialization prototypes. Results are added in a later commit; changing a
threshold afterward requires a new benchmark decision and an explanation.

Run from the repository root:

```sh
LUA_CPATH='./.rocks/lib/lua/5.1/?.so;;' \
    luajit bench/comptime-materialization.lua
```

The three named workloads are:

- `identifier`: a capture-free identifier recognizer over a 34-byte subject;
- `captures`: eight comma-separated component field names, each captured;
- `recursive`: a balanced grammar at depth 16, with a separate depth probe.

The pure-Lua reference is a flat instruction table interpreted by one shared
machine. The specialized form is handwritten Lua in the shape a direct
blueprint lowering would emit. LPeg 1.1 is the independent comparison.

The reference machine must sustain 200,000 identifier matches/s, 100,000
capture matches/s and 100,000 recursive matches/s. Both pure-Lua forms must
reach recursive depth 128.

M6 exists only if the specialized form is at least 1.10x the reference on each
workload and its geometric-mean warm-throughput gain is at least 1.50x. Its
total generated source may be at most 12x the reference helper plus programs,
its matcher bytecode at most 8x the shared machine's, and each workload may add
at most four trace aborts. Missing any gate deletes M6 rather than deferring it.

Construction, first-match time, warm throughput, retained allocation per match,
maximum recursive depth, trace aborts, generated source, bytecode, and bundled
LPeg dependency size are all recorded even where they are not pass conditions.

## Field-codec acceptance surface

The second provider replaces the keyed serializer half of
`tecs/internal/fieldcodec.tl`, not its positional `string.buffer` codec and not
struct layout reflection. Its first source shape is:

```nupp
local record Position
    x: number
    y: number
end

const PositionCodec: nupp.fieldcodec.KeyedCodec<Position> = comptime do
    return nupp.fieldcodec.compile(nupp.reflect(Position))
end

local payload: {string: any} = PositionCodec:encode(new Position {
    x = 10,
    y = 20,
})
```

`KeyedCodec<T>:encode(T)` returns a fresh table containing exactly `T`'s
declared fields in declaration order. It reads each with `rawget`, so an absent
field stays absent instead of falling through an instance metatable. Its
fingerprint is `"t:"` followed by the comma-separated ordered field names,
matching tecs's persisted compatibility contract. Empty, repeated, or
non-identifier field sets are rejected during finalization.

The acceptance port replaces `fieldcodec.createSerializer(fields)` and its
handwritten fingerprint with the materialized codec. It must remove that
runtime `load()` path while leaving positional raw serialization, migration,
custom codecs, transient components, and C-layout handling unchanged.

## Recorded results

Measured on 2026-08-09 with LuaJIT 2.1.1785577137 and LPeg 1.1.0. Times are
the benchmark's median of seven rounds.

| Workload | Engine | Build µs | First µs | Matches/s | Bytes/match | Trace aborts |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| identifier | reference | 0.75 | 0.37 | 6,467,469 | 202.9 | 14 |
| identifier | specialized | 5.30 | 11.00 | 11,128,009 | 11.9 | 0 |
| identifier | LPeg | 2.44 | 2.49 | 8,459,760 | 11.3 | 0 |
| captures | reference | 0.95 | 1.46 | 974,371 | 298.9 | 9 |
| captures | specialized | 7.29 | 22.10 | 2,703,482 | 148.3 | 2 |
| captures | LPeg | 3.04 | 3.67 | 1,460,764 | 147.3 | 0 |
| recursive | reference | 0.63 | 1.49 | 968,948 | 466.9 | 13 |
| recursive | specialized | 4.16 | 8.83 | 6,790,864 | 12.0 | 0 |
| recursive | LPeg | 4.27 | 4.96 | 1,318,305 | 11.3 | 0 |

The specialized/reference gains are 1.72x for identifiers, 2.77x for captures,
and 7.01x for recursion: a 3.22x geometric mean against the frozen 1.50x gate.
The reference and specialized forms both reach the probe ceiling of depth 2,048;
LPeg reaches 255. All clear the required depth 128.

Generated source is 1,769 bytes for the shared reference helper plus programs
and 1,588 bytes for the three specialized matchers, a 0.90x ratio. Matcher
bytecode is 1,080 bytes for the reference machine and 1,018 bytes for the
specialized functions, a 0.94x ratio. Neither pure-Lua form has a bundle
dependency; the measured LPeg module is 91,560 bytes.

Decision: **keep M6**. The handwritten specializer clears every frozen M0 gate.
