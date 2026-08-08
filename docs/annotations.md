# Annotations

Annotations are typed, type-erased metadata attached to language declarations
and statements. Their model is deliberately similar to Smithy traits: an
annotation is itself declared as a record or struct, its fields describe the
annotation's values, and its definition restricts where it may be applied.

Unknown annotations, invalid targets, missing values, and values of the wrong
type are errors. An annotation never becomes a silently erased comment.

## Defining an annotation

Apply the built-in `@annotation` annotation to a record or struct. Its
`targets` value is a non-empty array of semantic target names:

```nupp
@annotation(targets = {"record", "struct"})
record serializable
    format: string
    version: integer?
end
```

This defines these valid applications:

```nupp
@serializable(format = "json")
local record User
    id: uint64
end

@serializable(format = "binary", version = 2)
local struct Header
    tag: uint32
end
```

The record's fields are the annotation's members. Ordinary NUPP types apply,
and an optional field may be omitted. Annotation values are literal
compile-time constants: strings, numbers, booleans, nil, and literal tables
composed from those values. A field marked `@ref` accepts a type reference
instead, as described below.

An annotation definition is registered project-wide under its own name, which
is why it is written without a visibility: applications spell an unqualified
`@name`, so the name has to be unique across the project and there is no table
to reach it through. It is the one declaration exempt from
[NUPP2119](modules.md) for that reason. Definitions and applications may live
in different files; no runtime import is required. The definition record itself
and every application are erased from generated Lua.

A zero-field definition creates a marker annotation:

```nupp
@annotation(targets = {"record"})
record internal end

@internal
local record CacheEntry end
```

## Single-value applications

Apply `@annotationValue` to one field to designate it as the annotation's
single-value member:

```nupp
@annotation(targets = {"record", "field"})
record documentation
    @annotationValue
    text: string
end
```

The designated field may then be supplied positionally:

```nupp
@documentation("A user")
local record User
    @documentation("The stable user ID")
    id: uint64
end
```

This is exactly the same metadata as writing
`@documentation(text = "A user")`. There may be at most one
`@annotationValue` field. An annotation without one requires named members.

The formatter treats the positional form as canonical. Whenever an application
contains only the designated named member, it rewrites it to the single-value
form. This works for definitions in the same file and for definitions resolved
elsewhere in the project.

## Type-reference members

Apply `@ref` to an annotation-definition field when its value names a type
rather than an ordinary compile-time constant:

```nupp
@annotation(targets = {"record"})
record relatesTo
    @annotationValue
    @ref
    target: any
end

local record User end

@relatesTo(User)
local record UserEvent end
```

The value must be a bare or module-qualified type name. It is resolved in the
type namespace and checked against the member's declared type; `any` accepts
any valid type reference. Editors can navigate from the reference to the type
declaration through the language server. `@ref` is valid only on a field inside
an `@annotation` record or struct.

## Attachment targets

Targets are semantic categories rather than parser node names. A definition
must name at least one target and may name several; the list is a union.

| Target | Matches |
| --- | --- |
| `statement` | Every annotatable statement |
| `declaration` | Value, function, type, and C declarations |
| `binding`, `local-binding` | Local/const value bindings |
| `function` | Local, const, and named functions with bodies |
| `local-function`, `named-function` | Only the indicated function form |
| `type-declaration` | Alias, record, interface, struct, and C struct declarations |
| `alias`, `record`, `interface`, `struct` | Only that type declaration |
| `field` | A record, interface, or struct field |
| `c-declaration` | `cdef function` and `cdef struct` |
| `c-function` | Only `cdef function` |
| `block`, `loop`, `conditional`, `assignment`, `call` | The corresponding statement family |

An unrecognized target makes the annotation definition invalid.

Statement annotations decorate exactly the immediately following statement.
Stacked annotations all target the innermost non-annotation statement. They do
not insert `do ... end` or extend to later sibling statements. The grammar's
terminal `return` is not an ordinary statement, so it cannot currently be
annotated directly.

## Built-in annotations

| Name | Status | Arguments | May attach to |
| --- | --- | --- | --- |
| `@annotation` | Implemented | `targets = {"..."}` | `record`, `struct` |
| `@annotationValue` | Implemented | None | A field in an annotation definition |
| `@ref` | Implemented | None | A field in an annotation definition |
| `@allow` | Implemented | Zero or more lint names or codes | `statement` |
| `@owned` | Implemented | Cleanup/default/opaque/output contract | `function`, `c-function` |
| `@borrowed` | Implemented | Foreign output and source contract | `c-function` |
| `@dispose` | Implemented | None | `function`, `c-function`, `field` |
| `@override` | Implemented | None | `function` |
| `@effects` | Implemented | Named effect members | `function`, `c-function`, `local-binding` |
| `@relax` | Implemented | Observable guarantee names | `function` |
| `@jit` | Reserved | None | `function` |
| `@comptime` | Reserved | None | `local-function` |

A reserved annotation parses and resolves, then reports `NUPP2113` naming what
it is held for: `@jit` for the trace checker, `@comptime` for compile-time
evaluation. The names are taken so that a project does not define its own and
collide later.

`@allow(LINT, ...)` suppresses the named [lints](lints.md) while its statement
is checked, taking either a lint name or its code. Bare `@allow` and `@allow()`
suppress every lint in that statement. It reaches a lint at any level,
including one a build would fail on, because a lint is a judgement a project
may disagree with. It does not reach a type error, which is not a judgement:
naming one is `NUPP2108` and the error stands.

`@owned(cleanup, ...)` marks the first return as an affine owner. The checker
requires it to be transferred or explicitly discharged, and `dispose(value)`
invokes the named cleanup functions in source order. Bare `@owned` resolves
the result type's unique inherited `@dispose` operation;
`@owned(opaque = true)` is the explicit transfer-only form.

On a C function, `@owned(out = result, cleanup = free, success = zero)`
describes a logical owned output parameter. `@borrowed(out = view,
from = source, success = zero)` does the same for a view tied to a `borrows`
input. These contracts allocate and position the C output holder while
presenting an ordinary Lua multiple return.

A declaration that never comes back — it raises, exits, or loops forever —
says so with `never` as its return type, not an annotation; see
[primitives](type-system/primitives.md#never-the-bottom-type).

`@dispose` marks a consuming function, method, or interface field as a type's
default disposal operation. A disposal contract must take its resource, and a
bare `@owned` result is rejected unless exactly one default applies. See
[Ownership and FFI safety](ownership.md) for the complete model and examples.

`with` scopes use `@owned` producers with arbitrary return types; the returned
type does not need to implement a cleanup interface. The annotation belongs to
the producer, not the type, so different producers of the same type may carry
different cleanup contracts.

`@override` marks a member that replaces a default implementation an interface
provides. It is required there, and equally an error on a member that replaces
nothing — which catches both the misspelling that silently defines a new method
instead of overriding, and the interface that later adds a default which would
otherwise silently shadow an implementor's method. See
[interfaces](type-system/interfaces.md#default-implementations).

## Effect contracts

`@effects` is a complete, pessimistic contract. A function with a visible Nupp
body is analyzed and the checker rejects a contract that omits one of its
effects. A bodyless declaration is a trust boundary: the annotation records
what the implementation promises, just as its type signature records what
values it accepts and returns.

```nupp
@effects(reads = {"value"}, returns = {"1=value"})
local function identity(value: table): table
    return value
end

@effects(writes = {"buffer[*]"}, shapes = {"buffer"})
cdef function fill(buffer: uint8*, count: uint64): integer
```

The list members are `reads`, `writes`, `shapes`, `metatables`, `escapes`,
`calls`, and `returns`. The boolean members are `allocates`, `yields`,
`raises`, and `external`. Every member defaults to empty or false, so
`@effects()` means the function has no observable effects; it does not mean
“infer these later.”

See [Effect contracts](effects.md) for the path vocabulary, every member's
meaning, inference and fixed-point propagation, return aliases, unknown-call
behavior, trusted declarations, optimizer interaction, current limitations,
and complete examples.

## Const declaration bindings

`const` on a bodyless declaration says that the binding keeps the same runtime
value. It is a shallow identity promise, not deep immutability: a const module
binding does not freeze the module's fields.

```nupp
-- clock.d.nupp: a declaration for an implementation outside this source
const monotonicNow: function(): number

return {monotonicNow = monotonicNow}
```

In visible Nupp, `const` is checked from the binding itself. In `.d.nupp` files
and similar bodyless declaration surfaces, it is the trusted statement that the
host implementation will not replace the binding. Reassigning a const binding
is an error. The standard declaration of `ipairs` is const; that identity fact
is one part of the proof for numeric array-loop lowering.

## Relaxing observable guarantees

Some future rewrites may deliberately trade a named observable property for
speed. A function can opt in locally with `@relax`, and a compilation can opt
in with repeatable `--relax=GUARANTEE` flags:

```nupp
@relax("frames", "error-site")
local function dispatch(handler: function()): nil
    handler()
end
```

The closed set is `function-identity`, `load-order`, `error-site`, `frames`,
`gc-timing`, and `table-order`. Recording a relaxation does not itself request
a rewrite; a pass must name and check the guarantee it would change. The
current numeric `ipairs` rewrite needs no relaxation because it preserves the
language's observable behavior under its proof.

Compiler integrations can still add definitions directly through the
extensible `nupp.annotations` registry. Source declarations are the normal
language-facing mechanism; direct registration remains useful for built-ins
and compiler extensions.
