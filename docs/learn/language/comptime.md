---
order: 120
---

# Comptime

`comptime do ... end` is an expression whose value is computed while the file is
compiled and written into the generated Lua as a literal. The block is ordinary
Nupp, and none of the work survives into the program.

```nupp:playground
@comptime
local function step(acc: integer): integer
    return acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
end

const CRC32 = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = step(acc)
        end
        entries[byte + 1] = acc
    end
    return entries
end

local function checksum(text: string): integer
    local acc = 0xffffffff
    for index = 1, #text do
        acc = CRC32[((acc ~ text:byte(index)) & 0xff) + 1] ~ (acc >> 8)
    end

    return acc ~ 0xffffffff
end
```

`return` supplies the result of a `comptime do` block. This is a separate
construct from a [do expression](do-expressions.md), which supplies its result
with `yield`.

The generated Lua holds a 256-entry table of numbers. The loop that built it is
not in the program at all.

## Accumulating loops

A constant expression does not need `comptime`, because `-O1` folds one already.
What no rewrite of an expression can produce is a table built by iterating, and
that is what this is for.

`comptime` opens a block only when `do` follows it on the same line. Everywhere
else it is an ordinary name.

## Values checked at their destination

A block returns exactly one value, and that value is checked at the site it
initializes. A result that does not fit its declared type is the ordinary error
it would have been if you had typed the literal out.

Quotable results are `nil`, booleans, numbers that read back unchanged, strings,
and acyclic tables of those with no metatable. Every entry commits to a source
spelling permanently, so the set stops where a literal does: NaN, the
infinities, functions, threads, and cdata have no spelling to commit to.

A table the block reaches by two paths is one table while the block runs and
would be two once quoted, so it is refused rather than quoted twice:

```nupp:refused [shared.nupp]
local value: {{integer}} = comptime do
    local shared = {1}
    return {shared, shared}
end

print(value)
```

```text [nupp check shared.nupp]
error: NUPP2413: this table is reachable by more than one path
```

Build a separate table for each position, or return the shared part on its own.

## Opaque results materialize at a declaration

A sealed compiler provider may return a description that has no literal
spelling. One of those materializes only where the block directly initializes a
declaration whose type the provider owns:

```nupp
local record Position
    x: number
    y: number
end

const PositionCodec: types.reflect.FieldCodec<Position> = comptime do
    return types.reflect.fieldcodec(types.reflect(Position))
end

print(PositionCodec)
```

Drop the annotation and the result has nowhere to land. An inferred binding, or
an opaque value nested inside an ordinary table, is refused:

```nupp:refused [codec.nupp]
local record Position
    x: number
    y: number
end

const codec = comptime do
    return types.reflect.fieldcodec(types.reflect(Position))
end

print(codec)
```

```text [nupp check codec.nupp]
error: NUPP2414: an opaque comptime value needs a directly declared materialization boundary
```

`types.reflect.fieldcodec` is the provider shown here. See [Field
codecs](reflection.md#field-codecs) for the descriptor it reads and the codec it
produces.

## Compile-time environment

A block reads its own locals and the compile-time environment, and nothing else.
A runtime local, an upvalue, module state, or a global is refused, and a
block may not write to one either.

The environment is an allowlist: `assert`, `error`, `ipairs`, `pairs`,
`select`, `tonumber`, `tostring`, `type`, and named members of `math`, `string`,
`table`, and `bit`. A member the allowlist leaves out is reported by name. There is no `io`, `os`, `require`, `ffi`, `debug`, `load`, clock, or
randomness.

Evaluation is deterministic: `pairs` is sorted, platform-varying libm functions
are excluded, and `tostring` of a table address is not available. Each block
runs in an isolated cancellable worker under step, call-depth, time, memory,
result, and protocol limits, so a crash or an oversized result fails that block
and leaves the rest of the file to be checked.

## Type functions

A function that is available only during compilation carries the `@comptime`
annotation. One that accepts compiler-only `type` values and returns a `type` is
called with ordinary parentheses in type position, where it builds a structural
type while the program is checked:

```nupp
@comptime
local function Optional(T: type): type
    return types.optional(T)
end

local value: Optional(string) = nil
```

`@comptime function` declares a reusable compile-time-only callable, where
`comptime do ... end` evaluates one scoped expression inside otherwise runtime
code. Both are erased and have no runtime value. `affine(T, cleanup)`,
`affine(T)`, and `pinned(T)` use the same call-like form in type position and
are compile-time type generators rather than runtime constructors; see
[Ownership](../runtime/ownership/index.md) for what they promise.

Types used only by these functions may likewise be declared with `@comptime`, as in
`@comptime local type Field = {name: string, read: type?}`. That lets a helper name
structures containing compiler-only `type` or `typepack` handles once. The alias
body is checked in a comptime context, and naming the alias in runtime code is
`NUPP2421`.

Reach for a type function when the algorithm wants ordinary loops, branches,
string processing, or recursion, and for the direct finite operators when they
state a local operation clearly. A type function builds a structural type and
never a declaration. See [Comptime
types](types/comptime-types.md) for the builders, the finite
operators, and the rules for a call left open inside a generic signature.
