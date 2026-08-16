# Annotations

Annotations are typed, type-erased metadata attached to language declarations
and statements. Their model is deliberately similar to Smithy traits: an
annotation is itself declared as a record or struct, its fields describe the
annotation's values, and its definition restricts where it may be applied.

Unknown annotations, invalid targets, missing values, and values of the wrong
type are errors. An annotation never becomes a silently erased comment.

File-level inner annotations use `@!name` instead. `@!nofmt` disables formatting
for one file; `@!internal` hides one file from public documentation and, when it
is placed on `init.nupp`, hides the entire module namespace beneath it. They are
compiler directives rather than user-defined annotation traits.

## Defining an annotation

Apply the built-in `@annotation` annotation to a record or struct. Its
`targets` value is a non-empty array of semantic target names:

```nupp:playground
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
record internal
end

@internal
local record CacheEntry
end
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

local record User
end

@relatesTo(User)
local record UserEvent
end
```

The value must be a bare or module-qualified type name. It is resolved in the
type namespace and checked against the member's declared type; `any` accepts
any valid type reference. Editors can navigate from the reference to the type
declaration through the language server. `@ref` is valid only on a field inside
an `@annotation` record or struct.

## Compile-time reflection

Checked user-defined annotations on records, interfaces, structs, and their
fields are available through `nupp.reflect(T)` inside comptime. Applications
retain source order, and arguments follow the annotation definition's member
order:

```nupp
return comptime do
    local info = nupp.reflect(User)
    local recordMetadata = info.annotations
    local fieldMetadata = info.fields[1].annotations
    return {recordMetadata = #recordMetadata, fieldMetadata = #fieldMetadata}
end
```

Each argument has a `name` and a `kind`. Literal metadata uses `kind = "value"`
and `value`; an explicitly supplied nil uses `kind = "nil"`. A member declared
with `@ref` uses `kind = "type"` and `type`, whose integer value indexes the
same `info.types` graph as field types. Reflection therefore carries semantic
type identity rather than preserving a possibly aliased source spelling.

Annotation names, argument values, and referenced types participate in the
descriptor fingerprint and comptime cache key. Changing serialization metadata
therefore invalidates a reflected materialization even when no field type
changes. Reflection remains read-only and annotations remain absent from
generated runtime Lua unless a comptime result or materializer deliberately
turns them into a runtime value.

## Attachment targets

Targets are semantic categories rather than parser node names. A definition
must name at least one target and may name several; the list is a union.

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

An unrecognized target makes the annotation definition invalid.

Statement annotations decorate exactly the immediately following statement.
Stacked annotations all target the innermost non-annotation statement. They do
not insert `do ... end` or extend to later sibling statements. The grammar's
terminal `return` is not an ordinary statement, so it cannot currently be
annotated directly.

## Built-in annotations

| Name | Status | Arguments | May attach to |
| --- | --- | --- | --- |
| `@annotation` | Implemented | targets = {"..."} | record, struct |
| `@annotationValue` | Implemented | None | An annotation definition field |
| `@ref` | Implemented | None | An annotation definition field |
| `@allow` | Implemented | Lint names or codes        statement |  |
| `@override` | Implemented | None | function |
| `@partition` | Implemented | Two result field names | sealed interface field |
| `@effects` | Implemented | Named effect members | function, c-function, local-binding |
| `@relax` | Implemented | Observable guarantee names | function |
| `@derive` | Implemented | Qualified comptime providers | record |
| `@json` | Implemented | JSON record or field options | record, field |
| `@debug` | Implemented | skip or redact | Field in a derived record |
| `@deprecated` | Implemented | Optional reason and replacement | declaration, field |
| `@syntax` | Implemented | One syntax name | local binding |
| `@jit` | Implemented | None | function |

`@jit` is an absence-of-known-blockers contract for the selected LuaJIT trace
profile. The visible body and statically resolved checked callees must avoid
catalogued recorder blockers; a call path to one reports `NUPP2707`. Variadic
FFI and callback boundaries remain conservative contract errors. The annotation
does not promise that the function runs, becomes hot, receives stable runtime
types, or stays compiled for every input. `jit.off(function)` is an explicit
boundary and is therefore also an error when reached from an `@jit` body.
Compile-time-only helpers use the `comptime function` declaration modifier
rather than an annotation.

The [LuaJIT trace-checking guide](tooling/jit-trace-checking.md) shows every current
blocker, risk, expected stop, warning, call-path error, bytecode verdict, editor query,
and runtime reason.

`@syntax("name")` is editor metadata for a local or const binding. It accepts
any literal syntax name and does not change the binding's type. The bundled VS
Code extension recognizes JSON, GLSL, Lua, Nupp, and PEG when the initializer
is a long string; other names remain available to tools that understand them.

The derive configuration annotations are reserved semantic names and cannot be
redefined by a project. They are visible through comptime provider `Info`.
`@derive` accepts `nupp.derive.Debug`, `.JSON`, or an
exported comptime provider and adds checked members without exposing source or
AST macros. See [Declaration derives](derives.md) for the recipe capabilities,
generated methods, JSON policies, and failure rules.

`@allow(LINT, ...)` suppresses the named [lints](lints.md) while its statement
is checked, taking either a lint name or its code. Bare `@allow` and `@allow()`
suppress every lint in that statement. It reaches a lint at any level,
including one a build would fail on, because a lint is a judgement a project
may disagree with. It does not reach a type error, which is not a judgement:
naming one is `NUPP2108` and the error stands.

`@deprecated`, `@deprecated("reason")`, or
`@deprecated(reason = "...", replacement = "new.name")` keeps an API
available while marking it for migration. It may decorate functions, methods,
bindings, type declarations, C declarations, and record/interface fields. A
use reports the suppressible `deprecated` lint; completion and semantic tokens
carry the LSP deprecated tag/modifier; hover shows the reason and replacement;
and generated documentation retains the annotation. It emits no Lua.

An owning result is written `affine(T, cleanup)`, where `cleanup` is one exact
const-function identity. `affine(T)` is the explicit transfer-only form. See
[Ownership and FFI safety](ownership.md).

C outputs state their contracts in type position. A borrowed output is written
`out view: T* borrows (source)`, and an owned output is written
`out value: affine(T, cleanup)*`. `Success<T, N>` or `Failure<T, N>` on the
return says which status means the outputs hold values. Both forms allocate and
position the C output holder while presenting an ordinary Lua multiple return.

A declaration that never comes back, because it raises, exits, or loops forever,
says so with `never` as its return type, not an annotation; see
[primitives](type-system/primitives.md#never-the-bottom-type).

Automatic lexical cleanup works over every public `affine(...)` type. The
cleanup belongs to that affine type, so different policies over the same
runtime representation remain distinct static types.

`@override` marks a member that replaces a default implementation an interface
provides. It is required there, and equally an error on a member that replaces
nothing. That catches both the misspelling that silently defines a new method
instead of overriding, and the interface that later adds a default which would
otherwise silently shadow an implementor's method. See [overloads and
overrides](type-system/overloads.md#default-implementations-and-override) for
per-entry replacement, and
[interfaces](type-system/interfaces.md#default-implementations) for interface
default behavior generally.

`@partition(left, right)` is an audited ownership assertion on a method of a
sealed interface. It states that the two named fields of the method's first
result carry sibling-disjoint regions, preserving a private implementation's
`nupp.partition` proof through the public interface signature. It may not be
attached to an unsealed or externally implementable contract, and `nupp
ownership-audit` lists every use.

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

A guarantee is a property of a running program that a reader could notice, and
Nupp keeps all six by default. `@relax` says a function may give one up, which
is what lets a rewrite that would otherwise change observable behavior apply
there.

```nupp
local m = {}

@relax("frames", "error-site")
function m.dispatch(handler: function()): nil
    handler()
end

return m
```

That says two things about `dispatch`: a traceback through it need not show the
frames it would have shown, and an error raised inside it need not report the
position it would have reported. Nothing else about it changes.

### The six guarantees

Each name is one property, and giving it up permits a specific class of
rewrite.

| Guarantee | What holding it promises | What giving it up permits |
| --- | --- | --- |
| `function-identity` | two closures built at one site are distinct values, so `a == b` answers no | caching a closure and handing the same one back |
| `load-order` | modules initialize in the order the requires run | hoisting an import, or binding a callee statically |
| `error-site` | an error reports the position that raised it | hoisting a check or a chain out of a loop |
| `frames` | a traceback shows the frames the source describes | inlining a call away |
| `gc-timing` | a value becomes collectable when it goes unreachable | keeping one alive longer, or dropping it sooner |
| `table-order` | `pairs` visits a table's keys in one order per run | rebuilding a table so iteration reaches keys differently |

### Two places to opt in

A function opts in for itself with `@relax`. A whole compilation opts in with
`--relax=GUARANTEE`, which repeats:

```bash
nupp build --relax=frames --relax=function-identity
```

A name outside the closed set is **NUPP2112**, so a typo is refused rather than
silently granting nothing.

### Recording one does not request a rewrite

`@relax` widens what a pass is allowed to do; it never asks for anything. A pass
still has to name the guarantee it would change and check that the site granted
it, and a pass that changes nothing observable needs no grant at all. The
numeric `ipairs` rewrite is one of those: it preserves the language's observable
behavior under its own proof, so it applies whether or not anything was relaxed.

Compiler integrations can still add definitions directly through the
extensible `nupp.compiler.annotations` registry. Source declarations are the
normal language-facing mechanism; direct registration remains useful for
built-ins and compiler extensions.

## Diagnostics

- **NUPP2108**: an `@allow` names a lint that does not exist, and the error it
  was meant to suppress still stands.
- **NUPP2112**: an annotation argument is outside the closed set the annotation
  accepts, which is what a misspelled `@relax` guarantee reports.
- **NUPP2113**: a reserved annotation parsed and resolved, and is not yet
  implemented.
- **NUPP2707**: an `@jit` function crosses a variadic or callback FFI boundary.
- **NUPP2119**: a declaration does not say where it lives.

## Next

- [derives.md](derives.md): the members `@derive` generates.
- [effects.md](effects.md): the contract `@effects` states.
