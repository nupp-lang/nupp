# Comptime

`comptime do ... end` is an expression whose value is computed while the file is
compiled and written into the generated Lua as a literal. The block is ordinary
Nupp, and nothing of the work survives into the program.

```nupp:playground
local m = {}

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

function m.checksum(text: string): integer
    local acc = 0xffffffff
    for index = 1, #text do
        acc = CRC32[((acc ~ text:byte(index)) & 0xff) + 1] ~ (acc >> 8)
    end

    return acc ~ 0xffffffff
end

return m
```

The generated Lua holds a 256-entry table of numbers. The loop that built it is
not in the program at all.

## Type functions

Any function that is available only during compilation is declared with the
`comptime` modifier. A `comptime function` may accept compiler-only `type`
values and return a `type`. Calling it with ordinary parentheses in type
position constructs a structural type during checking:

```nupp
local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
```

`comptime function` declares a reusable compile-time-only callable;
`comptime do ... end` evaluates one scoped expression inside otherwise runtime
code. Compile-time-only declarations are erased and have no runtime value.

Some built-in type operations use the same call-like spelling directly in type
position. In particular, `affine(T, cleanup)`, `affine(T)`, and `pinned(T)` are
compile-time type-generator calls, not runtime constructors. The programmable
`nupp.types.affine` builder lets a comptime type function produce the same
affine types while preserving a cleanup declaration's identity.

The opaque handles have no runtime representation and are illegal in ordinary
function signatures or values. `nupp.types` supplies immutable inspection and
structural builders; it can preserve an existing nominal identity but cannot
create a record, interface, struct, declaration, or runtime member. An open call
inside a generic signature is deferred until inference supplies concrete type
and const arguments. A `type<Bound>` result exposes only `Bound` while the call
is open and checks every generated result against that promise.

Use the direct finite operators—`keyof`, indexed members, mapped shapes,
template construction, const parameters, associated projections, and
`unpackof`—when they state a local operation clearly. Type functions are for
algorithms needing ordinary loops, branches, string processing, or recursion.

## Accumulating loops are the reason

A constant expression does not need `comptime`, because `-O1` folds one already.
What no rewrite of an expression can produce is a table built by iterating, and
that is what this is for.

`comptime` opens a block only when `do` follows it on the same line. Everywhere
else it is an ordinary name.

## One value, checked where it lands

A block returns exactly one value, and that value is checked at the site it
initializes. A result that does not fit its declared type is the ordinary error
it would have been if you had typed the literal out.

Quotable results are `nil`, booleans, numbers that read back unchanged, strings,
and acyclic tables of those with no metatable. A table reachable by two paths is
**NUPP2413** rather than two tables, and NaN and the infinities have no literal
spelling.

## Opaque results materialize at a declaration

A sealed compiler provider may return a description with no literal spelling.
One of those materializes only when the block directly initializes a declaration
whose type the provider owns. An inferred binding, or an opaque value hidden
inside an ordinary table, is **NUPP2414**.

Reflection's `FieldCodec` is the canonical example; its descriptor shape,
read-only rules, and materialization boundary live on
[Reflection](reflection.md#comptime-reflection).

## Diagnostics

- **NUPP2410** / **NUPP2411** / **NUPP2412**: the block cannot be evaluated at
  compile time.
- **NUPP2413**: a result table is reachable by two paths, so it has no literal
  spelling.
- **NUPP2414**: an opaque provider result reached a binding that cannot
  materialize it.
- **NUPP2415**: a declared type has no registered materialization for the
  opaque result, or a worker payload failed the provider's checks.
- **NUPP2416** / **NUPP2419**: a provider rejected the request.
- **NUPP2420**: a comptime type function deliberately rejected its application
  through `nupp.types.error`.
- **NUPP2421**: a type-position comptime call has an invalid callee, signature,
  argument, result kind, or result bound.

## Next

- [Reflection](reflection.md): the descriptor a comptime block reads
  to generate code from a declaration.
- [Type system overview](../type-system/overview.md): the finite type operators
  that remain direct language syntax.
- [Affine types](../type-system/affine-types.md): the built-in generator and its
  programmable comptime builder.
