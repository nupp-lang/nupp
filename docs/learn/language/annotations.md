---
order: 180
---

# Annotations

Annotations attach typed, type-erased metadata to declarations and statements.
User-defined annotations are records or structs whose fields hold values and
whose targets restrict applications.

```nupp
@annotation(targets = {"function"})
record retry
    attempts: integer
end
```

An application names the definition and supplies its fields:

```nupp:fragment
@retry(attempts = 3)
local function fetch(url: string): string
    return url
end
```

Unknown annotations, invalid targets, missing values, and values of the wrong
type are errors. An annotation never becomes a silently erased comment.

## Defining an annotation

Apply the built-in `@annotation` annotation to a record or struct. Its `targets`
value is a non-empty array of [semantic target names](#attachment-targets):

```nupp
@annotation(targets = {"record", "struct"})
record serializable
    format: string
    version: integer?
end
```

That definition admits an application on either kind of declaration:

```nupp:fragment
@serializable(format = "json")
local record User
    id: uint64
end

@serializable(format = "binary", version = 2)
local struct Header
    tag: uint32
end
```

The record's fields are the annotation's members, so ordinary Nupp types apply
and an optional field may be omitted. Annotation values are literal compile-time
constants: strings, numbers, booleans, nil, and literal tables composed from
those values. A field marked [`@ref`](#type-reference-members) accepts a type
reference instead.

A zero-field definition creates a marker annotation:

```nupp
@annotation(targets = {"record"})
record internal
end

@internal
local record CacheEntry
end
```

An annotation definition is registered project-wide under its own name, which is
why it is written without a visibility: applications name an unqualified
`@name`, so the name has to be unique across the project and there is no table
to reach it through. It is the one declaration exempt from `NUPP2119`; see
[modules.md](modules.md#exports-and-privacy) for the visibility rule
every other declaration holds to. Definitions and applications may live in
different files, no runtime import is required, and the definition record itself
and every application are erased from generated Lua.

## Single-value applications

Apply `@annotationvalue` to one field to designate it as the annotation's
single-value member:

```nupp
@annotation(targets = {"record", "field"})
record documentation
    @annotationvalue text: string
end
```

The designated field may then be supplied positionally:

```nupp:fragment
@documentation("A user")
local record User
    @documentation("The stable user ID")
    id: uint64
end
```

That is the same metadata as writing `@documentation(text = "A user")`. There
may be at most one `@annotationvalue` field, and an annotation without one
requires named members.

The formatter treats the positional form as canonical: whenever an application
contains only the designated named member, it rewrites it to the single-value
form. That works for definitions in the same file and for definitions resolved
elsewhere in the project. See [fmt.md](../tooling/formatter.md#formatting-rules) for
the rest of what the formatter rewrites.

## Type-reference members

Apply `@ref` to an annotation-definition field when its value names a type
rather than an ordinary compile-time constant:

```nupp
@annotation(targets = {"record"})
record relatesTo
    @annotationvalue @ref target: any
end
```

An application then writes the type's name where a literal would go:

```nupp:fragment
local record User
end

@relatesTo(User)
local record UserEvent
end
```

The value must be a bare or module-qualified type name. It is resolved in the
type namespace and checked against the member's declared type; `any` accepts any
valid type reference. Editors navigate from the reference to the type
declaration through the [language server](../tooling/language-server.md). `@ref` is valid
only on a field inside an `@annotation` record or struct.

## Attachment targets

Targets are semantic categories rather than parser node names. A definition must
name at least one target and may name several; the list is a union, and an
unrecognized target makes the definition invalid.

- `statement`: every annotatable statement.
- `declaration`: value, function, type, and C declarations.
- `binding`, `local-binding`: local/const value bindings.
- `function`: local, const, and named functions with bodies.
- `local-function`, `named-function`: only the indicated function form.
- `type-declaration`: alias, record, interface, struct, and C struct
  declarations.
- `alias`, `record`, `interface`, `struct`: only that type declaration.
- `field`: a record, interface, or struct field.
- `c-declaration`: `cdef function` and `cdef struct`.
- `c-function`: only `cdef function`.
- `block`, `loop`, `conditional`, `assignment`, `call`: the corresponding
  statement family.

A statement annotation decorates exactly the immediately following statement,
and stacked annotations all target the innermost non-annotation statement:

```nupp
@allow("unused-binding")
@allow("discarded-result")
local pending = 1
```

They do not insert `do ... end` and do not extend to later sibling statements.
The grammar's terminal `return` is not an ordinary statement, so it cannot
currently be annotated directly.

## Unsafe operations

`@unsafe` authorizes operations requiring unsafe permission in one statement or
expression. Ordinary type, ownership, borrow, lifetime and cleanup checks still
apply. It takes no arguments and cannot be redefined.

On statements it supports `do`, `if`, numeric and generic `for`, `while`,
`repeat`, local/const value bindings, assignments and calls. Permission covers
conditions, loop setup, assignment destinations and initializers, as well as
bodies. An annotated binding keeps its ordinary scope.

These helpers assume the caller supplies the elements they access.

```nupp
local function readAndClear(exclusive pointer: int32*): integer
    @unsafe local first = pointer[0]
    @unsafe if first > 0 then
        pointer[0] = 0
    end
    return first
end
```

In expression position the annotation covers the following operand, including
unary operators, calls, indexing, member access and casts. Binary operators
remain outside it; parentheses include a larger expression. Both
`@unsafe(expression)` and `@unsafe (expression)` annotate that parenthesized
operand. Annotated calls retain their normal multiple results. Unary/power
precedence is unchanged: `@unsafe -x ^ y` still means `-(x ^ y)`, while
permission ends before `^`.

```nupp
local function combine(borrows pointer: int32*): integer
    local first = @unsafe pointer[0]
    local sum = @unsafe (pointer[0] + pointer[1])
    local chosen = @unsafe do
        if first > 0 then
            yield pointer[0]
        end
        yield 0
    end
    return sum + chosen
end
```

For example, `@unsafe pointer[0] + other[0]` authorizes only the first read,
and `(@unsafe pointer)[0]` does not authorize indexing. A `switch`
expression includes its selector, guards and arms, retaining lazy execution.

Permission ends with the annotated construct and resets in every nested
function body, including an immediately called literal. Function and type
declarations, function literals, fields, foreign declarations and whole files
are unsupported targets. Annotate operations inside functions; write
`return @unsafe expression` or `yield @unsafe expression` for terminal values.
`@aot` continues to reject unsafe constructs, and comptime gains no operations.

Ownership transfers remain explicit: `@unsafe own.release(owner)` consumes an
affine obligation without cleanup, and `@unsafe own.adopt<Owner>(raw)` creates
one with the target's cleanup policy. These compiler-recognized calls require
`@unsafe` even inside an annotated block.

The former contextual forms are rejected with a fix that inserts `@` at the
old marker. Comments, strings, grouping and ordinary identifiers are preserved.

| Rejected form | Replacement |
| --- | --- |
| `unsafe do ... end` | `@unsafe do ... end` |

Names such as `unsafe`, `adopt` and `release` remain ordinary identifiers
outside these annotation forms.

## File-level directives

A file-level inner annotation is written `@!name` and applies to the file it
opens rather than to any statement. There are two, and both are compiler
directives rather than user-defined annotation definitions:

```nupp
@!internal
module app.internals
```

`@!nofmt` disables formatting for one file. `@!internal` hides one file from
public generated documentation and, when it is placed on `init.nupp`, hides the
entire module namespace beneath it. Checked imports are restricted to the same
package namespace; see [internal modules](modules.md#internal-modules). See
[doc.md](../tooling/documentation.md#public-surface) for what the documentation generator
publishes.

## Compile-time reflection

Checked user-defined annotations on records, interfaces, structs, and their
fields are available through `types.reflect(T)` inside
[comptime](comptime.md). Applications retain source order, and
arguments follow the annotation definition's member order:

```nupp:fragment
return comptime do
    local info = types.reflect(User)
    local recordMetadata = info.annotations
    local fieldMetadata = info.fields[1].annotations
    return {recordMetadata = #recordMetadata, fieldMetadata = #fieldMetadata}
end
```

Each argument has a `name` and a `kind`. Literal metadata uses `kind = "value"`
and `value`; an explicitly supplied nil uses `kind = "nil"`. A member declared
with `@ref` uses `kind = "type"` and `type`, whose integer value indexes the
same `info.types` graph as field types, so reflection carries semantic type
identity rather than a possibly aliased source name. See
[reflection.md](reflection.md#comptime-reflection) for the rest of
the `Info` surface.

Annotation names, argument values, and referenced types participate in the
descriptor fingerprint and comptime cache key, so changing serialization
metadata invalidates a reflected materialization even when no field type
changes. Reflection remains read-only, and annotations remain absent from
generated runtime Lua unless a comptime result or materializer deliberately
turns them into a runtime value.

See the [annotation declarations](../../api.md#annotations) for builtin arguments,
targets, and contracts.

## Contracts in type position

Three contracts a reader might look for on this page are written in type
position instead, because each is part of what a declaration returns rather than
metadata about it.

An owning result is written `affine(T, cleanup)`, where `cleanup` is one exact
const-function identity, and `affine(T)` is the explicit transfer-only form:

```nupp
local record File
    handle: integer
end

local function close(takes file: File): nil
    file.handle = -1
end

local function open(handle: integer): affine(File, close)
    return File(handle = handle)
end
```

Automatic lexical cleanup works over every public `affine(...)` type. The
cleanup belongs to that affine type, so different policies over the same runtime
representation remain distinct static types.

A C output states its contract the same way. A borrowed output is written
`out view: T* borrows (source)`, an owned output is written
`out value: affine(T, cleanup)*`, and `Success<T, N>` or `Failure<T, N>` on the
return says which status means the outputs hold values:

```nupp:fragment
cdef function lookup(borrows key: const char*,
    out value: voidptr* borrows (key)): int32
```

Both forms allocate and position the C output holder while presenting an
ordinary Lua multiple return.

A declaration that never comes back, because it raises, exits, or loops forever,
says so with `never` as its return type rather than with an annotation.

::: seealso
- [ownership.md](../runtime/ownership/borrowing.md) for the complete affine contract
  reference
- [c-interop.md](../runtime/c-interop/index.md) for what a C boundary adds to it
- [primitives.md](types/primitives.md#never-the-bottom-type) for
  `never` as the bottom type
:::

## Effect contracts

`@effects` is a complete, pessimistic contract. A function with a visible Nupp
body is analyzed and the checker rejects a contract that omits one of its
effects, while a bodyless declaration is a trust boundary: the annotation
records what the implementation promises, just as its type signature records
what values it accepts and returns.

```nupp
@effects(reads = {"value"}, returns = {"1=value"})
local function identity(value: table): table
    return value
end
```

```nupp
@effects(writes = {"buffer[*]"}, shapes = {"buffer"})
cdef function fill(buffer: uint8*, count: uint64): integer
```

The list members are `reads`, `writes`, `shapes`, `metatables`, `escapes`,
`calls`, and `returns`. The boolean members are `allocates`, `suspends`, `raises`,
and `external`. Every member defaults to empty or false, so `@effects()` means
the function has no observable effects; it does not mean "infer these later."

See [effects.md](effects.md) for the path vocabulary, every member's
meaning, inference and fixed-point propagation, return aliases, unknown-call
behavior, trusted declarations, optimizer interaction, current limitations, and
complete examples.

## Const declaration bindings

`const` on a bodyless declaration says that the binding keeps the same runtime
value. It is a shallow identity promise, not deep immutability: a const module
binding does not freeze the module's fields.

```nupp [clock.d.nupp]
-- clock.d.nupp: a declaration for an implementation outside this source
const monotonicNow: function(): number

return {monotonicNow = monotonicNow}
```

In visible Nupp, `const` is checked from the binding itself. In `.d.nupp` files
and similar bodyless declaration surfaces, it is the trusted statement that the
host implementation will not replace the binding. Reassigning a const binding is
an error. The standard declaration of `ipairs` is const, and that identity fact
is one part of the proof for numeric array-loop lowering.

## Compiler-registered definitions

Compiler integrations add definitions directly through the extensible
`nupp.compiler.annotations` registry. Source declarations are the normal
language-facing mechanism, and direct registration remains useful for built-ins
and compiler extensions.
