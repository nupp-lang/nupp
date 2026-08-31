---
order: 670
---

# Annotations

An annotation is typed, type-erased metadata attached to a declaration or a
statement. It is itself declared as a record or struct, whose fields are the
annotation's values and whose definition says where applications may attach.

```nupp
@annotation(targets = {"function"})
record retry
    attempts: integer
end
```

An application names the definition and supplies its fields:

```nupp
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

```nupp:playground
@annotation(targets = {"record", "struct"})
record serializable
    format: string
    version: integer?
end
```

That definition admits an application on either kind of declaration:

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
[modules.md](../learn/language/modules.md#exports-and-privacy) for the visibility rule
every other declaration holds to. Definitions and applications may live in
different files, no runtime import is required, and the definition record itself
and every application are erased from generated Lua.

::: deepdive
The model follows Smithy traits: a trait is declared with the same shape as the
data it carries, its definition restricts where it may be applied, and applying
one is checked rather than parsed out of a comment. That is what makes an
annotation a type-system object instead of a string, so an editor can navigate
a `@ref` member to the type it names and
[comptime](#compile-time-reflection) can read applications back with their
values still typed.
:::

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

That is the same metadata as writing `@documentation(text = "A user")`. There
may be at most one `@annotationValue` field, and an annotation without one
requires named members.

The formatter treats the positional form as canonical: whenever an application
contains only the designated named member, it rewrites it to the single-value
form. That works for definitions in the same file and for definitions resolved
elsewhere in the project. See [fmt.md](../learn/tooling/formatter.md#formatting-rules) for
the rest of what the formatter rewrites.

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
```

An application then writes the type's name where a literal would go:

```nupp
local record User
end

@relatesTo(User)
local record UserEvent
end
```

The value must be a bare or module-qualified type name. It is resolved in the
type namespace and checked against the member's declared type; `any` accepts any
valid type reference. Editors navigate from the reference to the type
declaration through the [language server](../learn/tooling/language-server.md). `@ref` is valid
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
entire module namespace beneath it. See
[doc.md](../learn/tooling/documentation.md#public-surface) for what the documentation generator
publishes.

## Compile-time reflection

Checked user-defined annotations on records, interfaces, structs, and their
fields are available through `nupp.reflect(T)` inside
[comptime](../learn/language/comptime.md). Applications retain source order, and
arguments follow the annotation definition's member order:

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
same `info.types` graph as field types, so reflection carries semantic type
identity rather than a possibly aliased source name. See
[reflection.md](../learn/language/reflection.md#comptime-reflection) for the rest of
the `Info` surface.

Annotation names, argument values, and referenced types participate in the
descriptor fingerprint and comptime cache key, so changing serialization
metadata invalidates a reflected materialization even when no field type
changes. Reflection remains read-only, and annotations remain absent from
generated runtime Lua unless a comptime result or materializer deliberately
turns them into a runtime value.

## Built-in annotations

These definitions are compiled into the registry, and a project cannot redefine
any of their names.

| Annotation | Arguments | Attaches to |
| --- | --- | --- |
| `@annotation` | `targets = {"..."}` | record, struct |
| `@annotationValue` | none | annotation definition field |
| `@ref` | none | annotation definition field |
| `@allow` | lint names or codes | statement |
| `@override` | none | function |
| `@partition` | two result field names | sealed interface field |
| `@effects` | named effect members | function, c-function, local-binding |
| `@relax` | guarantee names | function |
| `@derive` | qualified comptime providers | record, struct |
| `@json` | JSON record or field options | record, field |
| `@debug` | `skip` or `redact` | field in a derived record |
| `@deprecated` | optional reason and replacement | declaration, field, c-declaration |
| `@syntax` | one syntax name | local binding |
| `@jit` | none | function |
| `@aot` | `target = "cpu"` or `target = "gpu"`; `lanes = true` or `lanes = false` | function |

### `@allow`

`@allow(LINT, ...)` suppresses the named [lints](lints.md) while its statement
is checked, taking either a lint name or its code:

```nupp
@allow("unused-binding")
local pending = 1
```

Bare `@allow` and `@allow()` suppress every lint in that statement. It reaches a
lint at any level, including one a build would fail on, because a lint is a
judgement a project may disagree with. It does not reach a type error, which is
not a judgement: naming one reports `NUPP2108` and the error stands.

### `@override`

`@override` marks a member that replaces a default implementation an interface
provides. It is required there, and equally an error on a member that replaces
nothing:

```nupp
local interface Greeter
    name: string

    function greet(self): string
        return "hello, " .. self.name
    end
end

local record Shouter is Greeter
    name: string

    @override
    function greet(self): string
        return "HELLO, " .. self.name
    end
end
```

That catches both the misspelling that silently defines a new method instead of
overriding, and the interface that later adds a default which would otherwise
silently shadow an implementor's method. See
[overloads.md](../learn/language/types/overloads.md#default-implementations-and-override)
for per-entry replacement, and
[interfaces.md](../learn/language/types/interfaces.md#default-implementations) for how
interface defaults behave.

### `@partition`

`@partition(left, right)` is an audited ownership assertion on a method of a
sealed interface. It states that the two named fields of the method's first
result carry sibling-disjoint regions:

```nupp
local record Split
    left: integer
    right: integer
end

local sealed interface Splitter
    @partition(left, right)
    split: function(self: Splitter): Split
end
```

That preserves a private implementation's `nupp.partition` proof through the
public interface signature. It may not be attached to an unsealed or externally
implementable contract, and `nupp ownership-audit` lists every use. See
[ownership.md](../learn/runtime/ownership/borrowing.md#public-capability-contracts) for the
contracts a public signature is allowed to carry.

### `@derive`

`@derive` accepts `nupp.derive.Debug`, `nupp.derive.JSON`,
`nupp.derive.Serde`, or an exported comptime provider, and adds checked members
or format-neutral materialization data without exposing source or AST macros:

```nupp
@derive(nupp.derive.Debug)
local record Point
    x: integer
    y: integer
end
```

`Debug` and `Serde` admit records and structs. `JSON` admits records. A package
provider declares its result contract and decides which target it accepts.
`@json` and `@debug` configure their corresponding format and renderer; Serde
itself is format-neutral. The reserved annotations are visible through a
provider's `Info`. See [Declaration derives](derives.md) for the recipe
capabilities, generated methods, JSON policies, and failure rules.

### `@deprecated`

`@deprecated`, `@deprecated("reason")`, or
`@deprecated(reason = "...", replacement = "new.name")` keeps an API available
while marking it for migration:

```nupp
@deprecated(reason = "kept for compatibility", replacement = "current")
local function legacy(): integer
    return current()
end
```

It may decorate functions, methods, bindings, type declarations, C declarations,
and record/interface fields. A use reports the suppressible
[`deprecated`](lints.md#deprecated) lint; completion and semantic tokens carry
the LSP deprecated tag and modifier; hover shows the reason and replacement; and
generated documentation retains the annotation. It emits no Lua.

### `@syntax`

`@syntax("name")` is editor metadata for a local or const binding. It accepts
any literal syntax name and does not change the binding's type:

```nupp
@syntax("json")
local defaults = [[
{"retries": 3}
]]
```

The bundled VS Code extension recognizes JSON, GLSL, Lua, Nupp, and PEG when the
initializer is a long string; other names remain available to tools that
understand them. See [editors.md](../learn/tooling/editors.md#visual-studio-code) for
what the extension provides.

### `@jit`

`@jit` is an absence-of-known-blockers contract for the selected LuaJIT trace
profile:

```nupp
@jit
local function total(values: {number}): number
    local sum = 0
    for _, value in ipairs(values) do
        sum = sum + value
    end
    return sum
end
```

The visible body and statically resolved checked callees must avoid catalogued
recorder blockers; a call path to one reports `NUPP2707`. Variadic FFI and
callback boundaries remain conservative contract errors, and `jit.off(function)`
is an explicit boundary, so it is also an error when reached from an `@jit`
body.

The annotation does not promise that the function runs, becomes hot, receives
stable runtime types, or stays compiled for every input. Compile-time-only
helpers use the `comptime function` declaration modifier rather than an
annotation. See [jit-trace-checking.md](../learn/performance/jit-trace-checking.md) for
every current blocker, risk, expected stop, warning, call-path error, bytecode
verdict, editor query, and runtime reason.

### `@aot`

`@aot` reserves a required whole-function ahead-of-time compilation contract
on a top-level local function declaration:

```nupp
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end
```

A target's `aot` build policy says what happens with it: `off`, the default,
does nothing; `emit-c` writes the generated C beside the build; `require`
compiles that C into the project's own shared library and fails the build when
it cannot. Lua 5.1 targets use `emit-wasm` to package pointer kernels and
Lua-building entries as Wasm side modules, or `require-wasm` to replace their
bodies with checked calls into those modules. See
[wasm-aot.md](../learn/performance/ahead-of-time/wasm.md) for that host and its limits.

A closure, table, interpolated string, vararg, `goto`, dynamic call, or unsafe
operation inside the body reports `NUPP2903` at the construct. Stacking it with
`@jit` reports `NUPP2901`, and annotating a constructor or inline requirement
reports `NUPP2902`, since neither is a whole function to compile.

A body of one top-level numeric map loop over spans may also be lowered
lane-parallel, at a width the compiler decides from the arithmetic the loop does
per byte it touches. `lanes = true` and `lanes = false` override that estimate,
and neither requires the lowering to succeed. See
[build-and-artifacts.md](../learn/performance/ahead-of-time/build-and-artifacts.md)
for a full kernel,
the build policy, and what the backend does not do yet.

`target = "gpu"` records a GPU execution family in the verified IR and maps one
whole-span loop iteration to one GPU invocation. It therefore does not take a
CPU `lanes` override. With the native `aot = "require"` policy, the compiler
emits canonical SPIR-V, derives MSL with its pinned SPIRV-Cross, and replaces
the declaration with a typed kernel specification. Its
`compile(context)` method owns the shader and entrypoint, `bind(...)` accepts
resident `gpu.Buffer<T>` values in the span parameters' order and types, and
`dispatch(...)` accepts the scalar parameters and packs their uniform block.

With `aot = "require-wasm"`, the same declaration emits WGSL for a browser
WebGPU application. Browser GPU storage uses `nupp.wasm.Span` and
`nupp.wasm.WriteSpan`, not native `nupp.mem.span` values. The first browser
profile admits complete-span map kernels over `int32` and `uint32` storage and
scalar uniforms; it does not yet admit floating-point values, structs,
cursor-indexed storage, or workgroup phases. The generated binding retains the
same `compile`, `bind`, and `dispatch` shape and crosses the browser Worker
boundary through bounded Wasm-memory transfer leases. See
[gpu.md](../learn/performance/ahead-of-time/gpu.md#browser-gpu-kernels) for a complete
browser target and source example.

`aot = "off"` or `emit-c` retain the ordinary function value. `nupp aot --emit
spirv FILE` writes the canonical binary module and `--emit msl` prints its Metal
derivative.

The GPU subset has two entry shapes. A complete-span map assigns one invocation
to every element. A structured workgroup entry ends in
`gpu.workgroups(groups, size, controller)`: `controller` allocates statically
sized scratch with `phases:scratch` and divides execution into immediate
`phases:run` callbacks. On CPU each callback runs for local indices zero through
`size - 1` before the next callback begins; on GPU the boundary is a workgroup
execution-and-memory barrier.

Generated workgroups admit at most 256 lanes and 16 KiB of fixed-width scratch.
Every scratch write is exactly `shared[localIndex]`, so writes are structurally
disjoint. A later phase may read an index whose full uint32 range is statically
proved inside the allocation; a phase may only read the scratch it also writes
at its own local index. `phases:reduceSumF32(shared)` is the compiler-owned
exception: it expands into a fixed, left-before-right power-of-two tree whose
stage order is identical on CPU and GPU. There is no unordered or atomic
reduction.
`phases:inclusiveScanU32(values, temporary)` similarly expands into a
deterministic power-of-two inclusive prefix tree. Both arrays contain one
`uint32` per lane; the second is compiler-checked ping-pong scratch and the
result is left in `values`. Stable block compaction can use the resulting
prefix as each selected lane's destination without atomics.

Both shapes accept any number of proved read and write spans and up to 128 bytes
of fixed-width scalar uniforms in a local function declaration. Uploads and
downloads remain explicit, so several generated bindings can share resident
buffers without an intermediate CPU copy.

`Context:tensor(element, shape)` allocates dense row-major storage.
`gpu.bufferLayout(buffer)` returns an element-independent layout whose
`gpu.subviewLayout`,
`gpu.transposeLayout`, `gpu.broadcastLayout`, and `gpu.asStridedLayout`
operations are allocation-free;
`gpu.view(buffer, layout)` applies it while preserving the buffer's element type.
Each view retains logical dimensions separately from its bounded physical
extent. Host transfers and dispatch-indexed span accesses require dense layout;
cursor-indexed kernels may consume other inputs by passing `dimensions()` and
`strides()` as scalar uniforms. Writable views additionally need disjoint
coordinates and one complete span extent, so broadcast and overlapping writes
are refused.

Binary16 and bfloat16 storage conversions are explicit through
`nupp.math.f32.fromF16Bits`, `toF16Bits`, `fromBF16Bits`, and `toBF16Bits`.
`nupp.quant` supplies affine signed-int8 and packed signed-int4 dequantization;
the narrow integer names remain physical span/buffer element types while
accumulation uses explicit binary32. These portable paths require no optional
device feature. Native half arithmetic and cooperative matrix instructions are
separate capability-selected optimizations rather than silent changes to these
operations.

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
    return new File(handle = handle)
end
```

Automatic lexical cleanup works over every public `affine(...)` type. The
cleanup belongs to that affine type, so different policies over the same runtime
representation remain distinct static types.

A C output states its contract the same way. A borrowed output is written
`out view: T* borrows (source)`, an owned output is written
`out value: affine(T, cleanup)*`, and `Success<T, N>` or `Failure<T, N>` on the
return says which status means the outputs hold values:

```nupp
cdef function lookup(borrows key: const char*,
    out value: voidptr* borrows (key)): int32
```

Both forms allocate and position the C output holder while presenting an
ordinary Lua multiple return.

A declaration that never comes back, because it raises, exits, or loops forever,
says so with `never` as its return type rather than with an annotation.

::: seealso
- [ownership.md](../learn/runtime/ownership/borrowing.md) for the complete affine contract
  reference
- [c-interop.md](../learn/runtime/c-interop/index.md) for what a C boundary adds to it
- [primitives.md](../learn/language/types/primitives.md#never-the-bottom-type) for
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
`calls`, and `returns`. The boolean members are `allocates`, `yields`, `raises`,
and `external`. Every member defaults to empty or false, so `@effects()` means
the function has no observable effects; it does not mean "infer these later."

See [effects.md](../learn/language/effects.md) for the path vocabulary, every member's
meaning, inference and fixed-point propagation, return aliases, unknown-call
behavior, trusted declarations, optimizer interaction, current limitations, and
complete examples.

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
host implementation will not replace the binding. Reassigning a const binding is
an error. The standard declaration of `ipairs` is const, and that identity fact
is one part of the proof for numeric array-loop lowering.

## Relaxing observable guarantees

A guarantee is a property of a running program that a reader could notice, and
Nupp keeps every one of them by default. `@relax` says a function may give one
up, which is what lets a rewrite that would otherwise change observable behavior
apply there.

```nupp
@relax("frames", "error-site")
local function dispatch(handler: function()): nil
    handler()
end
```

That says two things about `dispatch`: a traceback through it need not show the
frames it would have shown, and an error raised inside it need not report the
position it would have reported. Nothing else about it changes.

### Relaxable guarantees

Each name is one property, and giving it up permits a specific class of rewrite.

| Guarantee | What holding it promises | What giving it up permits |
| --- | --- | --- |
| `function-identity` | two closures built at one site are distinct values, so `a == b` answers no | caching a closure and handing the same one back |
| `load-order` | modules initialize in the order the requires run | hoisting an import, or binding a callee statically |
| `error-site` | an error reports the position that raised it | hoisting a check or a chain out of a loop |
| `frames` | a traceback shows the frames the source describes | inlining a call away |
| `gc-timing` | a value becomes collectable when it goes unreachable | keeping one alive longer, or dropping it sooner |
| `table-order` | `pairs` visits a table's keys in one order per run | rebuilding a table so iteration reaches keys differently |

`@relax` accepts two further numeric names which are not in that table because
they are not observable in the same sense. `fp-contract` permits a multiply and
an add to fuse into one rounding, so the function answers something different
rather than reaching the same answer differently:

```nupp
@relax("fp-contract")
@aot
local function scale(a: number, b: number, c: number): number
    return a * b + c
end
```

See [Influencing
vectorization](../learn/performance/ahead-of-time/vectorization.md#influencing-vectorization)
for what
that fusion is worth on a measured kernel.

`fp-transcendentals` lets explicit fixed-width transcendental operations use
the platform's native implementation instead of Nupp's IR-owned operation
sequence. It is useful for throughput-oriented inference and simulation where
the caller validates an error bound rather than an element-exact answer:

```nupp
local span = require("nupp.mem.span")

@relax("fp-transcendentals")
@aot(target = "gpu")
local function activate(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    for i = 1, #output do
        output[i] = nupp.math.f32.exp(nupp.math.f32.narrow(input[i]))
    end
end
```

The grant is per function. It does not enable reassociation, unordered
reductions, flush-to-zero, or contraction; those guarantees remain unchanged
unless separately relaxed.

### Opting in

A function opts in for itself with `@relax`. A whole compilation opts in with
`--relax=GUARANTEE`, which repeats:

```bash
nupp build --relax=frames --relax=function-identity
```

The flag takes the six guarantees in the table above and neither numeric grant,
which stay per function because a build-wide permission to change answers is
not something a reader of any one function could see was in effect. A name
outside the accepted set reports `NUPP2112`, so a typo is refused rather than
silently granting nothing.

### Grants do not request rewrites

`@relax` widens what a pass is allowed to do; it never asks for anything. A pass
still has to name the guarantee it would change and check that the site granted
it, and a pass that changes nothing observable needs no grant at all.

The numeric `ipairs` rewrite is one of those. It preserves the language's
observable behavior under its own proof, so it applies whether or not anything
was relaxed.

## Compiler-registered definitions

Compiler integrations add definitions directly through the extensible
`nupp.compiler.annotations` registry. Source declarations are the normal
language-facing mechanism, and direct registration remains useful for built-ins
and compiler extensions.

::: seealso
- [lints.md](lints.md) for the lints `@allow` reaches and how a project moves
  their levels
- [derives.md](derives.md) for what `@derive`, `@json`, and `@debug` generate
- [effects.md](../learn/language/effects.md) for the `@effects` vocabulary in full
- [diagnostics.md](diagnostics.md) for every code an annotation can report
:::
