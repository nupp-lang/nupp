---
order: 120
---

# Comptime

`comptime do ... end` is an expression whose value is computed while the file is
compiled and written into the generated Lua as a literal. The block is ordinary
Nupp, and none of the work survives into the program.

```nupp:playground
local comptime function step(acc: integer): integer
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

The generated Lua holds a 256-entry table of numbers. The loop that built it is
not in the program at all.

## Accumulating loops

A constant expression does not need `comptime`, because `-O1` folds one already.
What no rewrite of an expression can produce is a table built by iterating, and
that is what this is for.

`comptime` opens a block only when `do` follows it on the same line. Everywhere
else it is an ordinary name.

::: deepdive
Constant folding looks like a smaller comptime, and it cannot stand in for one,
because the two carry opposite obligations. A fold is an `-O1` rewrite that must
be invisible in the result, is absent at `-O0` and under `nupp check`, and may
decline silently. A block is a language construct that must be visible in the
result, runs at every optimization level, and owes a diagnostic when it cannot
produce a value. Anything whose meaning depends on a compile-time value could
never be a fold, because `-O0` still has to compile the program.

See [NEP 3](../../neps/0003-comptime.md) for more information.
:::

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

```nupp [shared.nupp]
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

const PositionCodec: nupp.reflect.FieldCodec<Position> = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

print(PositionCodec)
```

Drop the annotation and the result has nowhere to land. An inferred binding, or
an opaque value nested inside an ordinary table, is refused:

```nupp [codec.nupp]
local record Position
    x: number
    y: number
end

const codec = comptime do
    return nupp.reflect.fieldCodec(nupp.reflect(Position))
end

print(codec)
```

```text [nupp check codec.nupp]
error: NUPP2414: an opaque comptime value needs a directly declared materialization boundary
```

`nupp.reflect.fieldCodec` is the provider shown here. See [Field
codecs](reflection.md#field-codecs) for the descriptor it reads and the codec it
produces.

::: deepdive
Four invariants separate this from a macro system. The provider table is closed
and compiler-owned, so adding one is a language change. The boundary is an
explicitly declared runtime type rather than inference from a distant call, so
deleting the annotation reports that the result needs one instead of silently
selecting different code. The value cannot observe the program, because it is
assembled through a sealed typed constructor API. And the block does not choose
the emitter; the declared type does.

See [NEP 3](../../neps/0003-comptime.md#quotable-set) for more information.
:::

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

A function that is available only during compilation carries the `comptime`
modifier. One that accepts compiler-only `type` values and returns a `type` is
called with ordinary parentheses in type position, where it builds a structural
type while the program is checked:

```nupp
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
```

`comptime function` declares a reusable compile-time-only callable, where
`comptime do ... end` evaluates one scoped expression inside otherwise runtime
code. Both are erased and have no runtime value. `affine(T, cleanup)`,
`affine(T)`, and `pinned(T)` use the same call-like form in type position and
are compile-time type generators rather than runtime constructors; see
[Ownership](../runtime/ownership/index.md) for what they promise.

Types used only by these functions may likewise be declared with `comptime`, as in
`local comptime type Field = {name: string, read: type?}`. That lets a helper name
structures containing compiler-only `type` or `typepack` handles once. The alias
body is checked in a comptime context, and naming the alias in runtime code is
`NUPP2421`.

Reach for a type function when the algorithm wants ordinary loops, branches,
string processing, or recursion, and for the direct finite operators when they
state a local operation clearly. A type function builds a structural type and
never a declaration. See [Comptime
types](types/comptime-types.md) for the builders, the finite
operators, and the rules for a call left open inside a generic signature.

::: deepdive
Type algorithms used to live in a separate expression language with its own
parser, binders, evaluator, normal forms, recursion admission, five kinds of
budget, and exhaustive handling in every generic type consumer. The evidence
that it was the wrong shape was in the compiler's own source: the format-string
declaration ran to 254 lines of recursive type-state machine, because type
position had no loop. Making types values in the language that already had
loops removed the second compile-time language rather than adding a third.

See [NEP 3](../../neps/0003-comptime.md#there-were-two-compile-time-languages) for
more information.
:::

## FAQ

### Can a comptime block read a file or an environment variable?

No. Nothing that reaches the outside world is in the allowlist, so a result
depends on the block's own source and on nothing that could differ between two
machines. See [Compile-time environment](#compile-time-environment) for the
members a block does get.

### Can a comptime block declare a record?

No. A block produces data and a type function produces a structural type. A
nominal declaration needs a source-owned name, visibility, a tooling location,
and an initialization order, none of which a generated result has. See [Type
functions](#type-functions) for what a call in type position may build.

### Is a comptime function generic?

Not yet. A `comptime function` is neither generic nor variadic, so an algorithm
that has to cover several shapes takes a `type` handle and inspects it with
`nupp.types`.

::: seealso
- [reflection.md](reflection.md#comptime-reflection) for the descriptors a block
  inspects and the codecs it materializes
- [type-level-computation.md](types/comptime-types.md) for the
  builders, the finite type operators, and calls left open in a generic
  signature
- [diagnostics.md](../../reference/diagnostics.md#diagnostic-index) for every code
  a block can report
:::
