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
    return nupp.fieldcodec.compile(reflect(Position))
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

Not measured in this commit.
