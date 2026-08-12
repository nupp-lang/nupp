# Derives

> **Status: implemented through D4, with D5 hardening ongoing.** The compiler-
> owned implementation covers `Debug`, `Default`, single-field `From`, and
> `JSON` on records, including static-factory projection and typed helper
> annotations. Associated types were not a prerequisite. User-defined derive
> providers remain deferred until the four built-ins prove the constrained
> output model in broader acceptance workloads.

## Decision

Nupp will have a declaration-augmentation phase reached by the built-in
`@derive` annotation:

```nupp
@derive(Debug, Default, JSON)
local record User
    @json(name = "user_id")
    id: integer

    @default("anonymous")
    name: string
end
```

A derive reads the declaration's resolved fields, generic binders, declared
interfaces, and checked annotations. It may add a constrained set of semantic
members and interface contracts to that declaration. It does not receive the
CST, return source text, add imports, or introduce a separately nameable type
or module.

The phase is separate from comptime:

```text
source declaration
    -> ordinary name, field-type and annotation resolution
    -> derive planning over immutable semantic TypeInfo
    -> generated-member validation and interface conformance
    -> ordinary module interface and Lua lowering
```

Comptime may be used inside a compiler-owned derive to calculate a blueprint,
and closed materialization may turn that blueprint into one runtime value.
The derive phase is still the only phase allowed to attach the resulting value
or forwarding member to a declaration. Widening `comptime` to return source or
declarations remains excluded by [comptime.md](comptime.md), and widening a
materializer to emit declarations remains excluded by
[materialization.md](materialization.md).

## Why this boundary

The four output classes stay distinct:

| Desired output | Mechanism |
| --- | --- |
| A literal table, string, number, or boolean | comptime quotation |
| One executable value with an already-declared runtime type | closed materialization |
| Members or contracts attached to one declaration | derive |
| New top-level names, declarations, imports, or modules | explicit `.g.nupp` source generator |

This gives derives enough authority for structural boilerplate without making
the meaning of a module depend on invisible arbitrary text. A reader can see
the complete augmentation request on the declaration, and tooling can describe
each generated member by the derive that owns it.

## Goals

- Generate checked instance methods, static functions, interface contracts,
  and private materialized constants for one nominal declaration.
- Reuse the canonical member view, `TypeInfo`, semantic fingerprints,
  annotation checking, comptime isolation, and materialization limits already
  in the compiler.
- Preserve declaration order, nominal identity, module-interface cutoff, and
  line-count-invariant Lua output.
- Make generated members ordinary to member lookup, completion, signature
  help, conformance, generic instantiation, and downstream modules.
- Point every failure at `@derive`, a contributing field, or one of its helper
  annotations rather than at synthetic source.
- Prove the phase with `Debug`, `Default`, single-field `From`, and `JSON`.
- Evaluate a restricted, versioned semantic provider interface after the
  built-ins prove the result model, and expose it only if an external workload
  justifies a stable contract.

## Non-goals

- Token, AST or CST macros; quoting; source parsing; or source splicing.
- Adding top-level declarations, modules, imports, globals, or arbitrary
  nested types.
- Rewriting, removing, or wrapping a declaration the user wrote.
- Function-like or attribute-like procedural macros.
- User-defined materializers or access to the private runtime-expression IR.
- Implicit monomorphization or specialization at every call site.
- Runtime reflection or an ambient derive registry loaded with `require`.
- Inferring fallible conversion policy. `TryFrom` is deliberately deferred.
- Builder generation in the first version: a builder requires a new nominal
  type and therefore crosses the initial one-declaration boundary.

## Surface syntax

`@derive` is a built-in annotation using the annotation registry's existing
`arguments = "names"` policy. Bare derive names already parse and validate the
same way as the names accepted by `@relax`; no grammar or annotation-argument
special case is required:

```nupp
@derive(Debug, Default, From, JSON)
local record UserId
    @default(0)
    value: integer
end
```

The first version recognizes exactly `Debug`, `Default`, `From`, and `JSON`.
Names are case-sensitive. A name may occur only once across all `@derive`
applications attached to a declaration:

```nupp
@derive(Debug)
@derive(JSON)
local record User
    id: integer
end
```

Stacking is equivalent to one application. Written order is retained for
display and diagnostics, but it does not affect semantics. Providers see the
same written declaration for their own target and cannot consume members
another derive generated there. Cross-declaration capabilities are resolved
through the immutable request index described below. Dependencies between
compiler-owned derives are declared in the compiler, not obtained from source
order.

`@derive` initially targets records. Applying it to an alias, interface,
function, field, or statement is an error. Struct support is staged after the
record semantics are proven: `Debug`, `Default`, and `From` have plausible
struct meanings, while JSON must first define cdata numeric and pointer rules.

The derive identifiers are reserved even before their individual providers
land. Once `@derive` itself is active, an unavailable provider name is a derive
error. D0 keeps it reserved; before D1 activates it, the existing
annotation-registry `reserved` field and NUPP2113 report that the annotation is
held for derives.

### Annotation-name reservation and migration

Annotation applications have the grammar `@name(...)`; dotted annotation
names and brace applications do not exist. The project-wide annotation
namespace is unique, and compiler built-ins win. D0 therefore reserves these
annotation names together:

| Annotation | Registry policy | Initial state |
| --- | --- | --- |
| `@derive` | `arguments = "names"`, target `record` | reserved in D0; active in D1 |
| `@default` | typed single value, target `field` | reserved until D2 |
| `@json` | typed named values, targets `record`, `field` | reserved until D4 |
| `@debug` | typed named values, target `field` | reserved until debug options land |

This is an intentional source-compatibility break for a project that already
defines one of those names. The annotation-definition path keeps NUPP2114 but
special-cases the message and help for a newly reserved built-in:

```text
NUPP2114: annotation @json is reserved by Nupp for JSON derives
  help: rename the project annotation before upgrading; annotation names
        are project-wide identifiers and cannot be qualified
```

The release notes and [annotations documentation](../docs/annotations.md) list
all newly occupied names. A collision never degrades into an unknown derive or
silently changes which annotation definition an application sees.

### Built-in typed annotation schemas

`@default`, `@json`, and `@debug` are the first compiler built-ins using the
registry's `arguments = "typed"` path. `validateTypedAnnotation` requires each
schema member to hold a real interned Nupp type and needs `singleValue` for the
positional default. Plain literal entries in `annotations.nupp` cannot provide
that by themselves, and that module deliberately has no dependency on the type
interner.

D0 keeps the registry module dependency-free and adds internal schema records
with documentation comments to the prelude for the three annotations. They
emit no runtime namespace, but remain indexed as definition/documentation
targets. After the prelude is loaded, checker environment initialization
resolves those records once and hydrates the reserved registry entries with:

- interned member types;
- optional/required flags and definition order;
- `singleValue = "value"` for `@default`;
- definition locations used by hover, definition and generated docs.

The formatter and project annotation index receive that hydrated registry.
They do not construct ad hoc string/boolean types, and checker modules do not
introduce an `annotations -> types -> annotations` require cycle. Target-
specific constraints that the shared `@json` schema cannot express — for
example `unknown` being record-only — remain provider validation after the
ordinary typed-member check.

## Written and generated members

A generated member has the same semantic shape as a checked written member:

```nupp
type DerivedMember = {
    owner: Type,
    name: string,
    namespace: "instance" | "static" | "metamethod",
    signature: Type,
    lowering: DerivedLowering,
    provider: string,
    origin: SourcePosition,
    contributingFields: {SourcePosition},
}
```

`DerivedLowering` is a private closed union of checked recipes. The initial
recipes are:

- call a compiler-owned runtime helper with field projections and constants;
- construct the owning record from a complete, typed field map;
- compare, format, encode, or decode a statically enumerated field sequence;
- call one private materialized value owned by the declaration;
- return a quoted primitive or freshly constructed table value.

It is not a CST node and it does not carry source text. Every field projection,
call, construction and result is checked against the same semantic relations
ordinary source uses. Adding a recipe is a compiler change and increments the
derive ABI version.

Generated output merges with the declaration only after all providers have
planned their additions. These are errors, never precedence rules:

- a generated instance member conflicts with a written instance or static
  member of the same name;
- a generated static member conflicts with a written or generated member of
  the same name;
- two derives generate the same member or incompatible interface contracts;
- a derive attempts to replace an inherited default without an explicit
  compiler-owned replacement rule;
- the generated signature exposes a type less visible than its owner.

Requesting an interface the declaration already names is idempotent: the one
contract remains and the generated method may satisfy it. Distinct interface
identities are never coalesced merely because their source names match.

The compiler does not silently accept a handwritten implementation beside a
derive request. The user either removes the derive or removes the member. That
keeps the declaration's source of behavior unambiguous.

## Phase ordering

Declaration checking becomes explicitly staged.

1. **Shell.** Publish the nominal identity, generic binders, written
   supertypes, nested namespace and runtime declaration table.
2. **Base declaration.** Resolve stored field types, field capabilities,
   written method signatures, and typed annotations. Check annotation values
   against their definitions.
3. **Request index.** Validate every `@derive` application and collect the
   requested provider set for every declaration before planning any of them.
   Imported declarations contribute the requested sets already published in
   their module interfaces.
4. **Derive input.** Freeze an immutable base descriptor. It contains the
   written declaration only, so `Debug` cannot change what `JSON` observes and
   a derive cannot reflect its own output. The request index is a separate,
   immutable dependency input rather than part of that descriptor.
5. **Plan.** Build each provider's cross-declaration dependency graph, resolve
   its strongly connected components under the provider's recursion policy,
   and produce semantic member and private-value plans. Planning is pure and
   memoized by provider ABI, target fingerprint, requested dependencies,
   target options, and build target where relevant.
6. **Merge.** Detect collisions, add generated signatures and requested
   interface contracts, then publish the final nominal member view.
7. **Validate.** Check written bodies, derived lowering recipes, inherited
   defaults, and final interface conformance against the merged view.
8. **Publish.** Include derive applications, provider ABI versions, generated
   signatures, private-value fingerprints, and effect requirements in the
   module interface.
9. **Lower.** Emit the record and its generated runtime setup through ordinary
   code generation without changing the source line count.

The shell is an internal checking state, not a source-visible partial type.
Once normal declaration resolution completes, every source reference sees the
same final derived surface. Recursive field types are legal because planning
walks the canonical type graph with memoized `visiting` and `complete` states
rather than recursively copying descriptors.

### Cross-declaration dependencies

The frozen base rule applies to a provider's own target; it does not pretend
other declarations have no derive requests. A provider decides a nominal
dependency from exactly two sources:

1. a compatible member written on the dependency's base declaration; or
2. the same capability in the immutable request index, provided that
   dependency's plan validates successfully.

It never probes the partly merged generated-member table. Consequently file
order and `@derive` argument order cannot change an answer.

For `Default`, a written nested route must contain exactly one callable static
entry with signature `function(): FieldType`; a field named `default` with a
different return, parameters, or an ambiguous zero-argument overload does not
count. `@derive(Default)` on `FieldType` is the other route. Direct required
cycles are illegal because no construction reaches a base case; an optional,
explicit-literal, or other parameter-independent default breaks the edge.
If the requested `Default` plan for `FieldType` fails, the dependent field
reports NUPP2804 and attaches the dependency's original failure as `related`,
rather than silently making the route disappear or duplicating its diagnostic.

For JSON, the nominal field type must request `JSON`. A written
`fieldCodec()` is not a complete route: it can produce and validate keyed Lua
tables, but it does not carry the private direct-emission entry point described
below. D4 deliberately keeps that entry point out of the public prelude rather
than pretending the existing field codec is a text codec. Handwritten nominal
JSON routes are deferred until there is a complete protocol for both text
directions. Recursive JSON strongly connected components are legal and lower
as references in one canonical schema graph. If any member of a requested
component fails, dependents report their own field as NUPP2806 with the
dependency failure attached as `related`.

`Debug` likewise accepts an exact written `nupp.Debug` implementation or a
`Debug` request on the dependency. Recursive declaration graphs are legal;
runtime value cycles are handled by the formatter's visited set. `From` has no
cross-declaration provider dependency.

NUPP2807 is therefore reserved for a cycle the named provider forbids, not for
all recursive types. The provider's section states which strongly connected
components are legal and why they terminate or lower to graph references.

## Semantic input

Derives consume the same canonical structural vocabulary as reflection. The
landed schema already carries ordered fields, typed annotations,
`staticFields`, `metamethods`, nested types and `associatedTypes`; D0 does not
design or duplicate those structures. It freezes a base projection of the
existing descriptor before generated members merge, retaining:

- nominal identity, declaration kind, visibility and generic binders;
- resolved ordered fields and their read/write capabilities;
- declaration and field annotations with typed values and type-reference
  edges;
- written supertypes, instance/static methods, constructors, metamethod
  contracts and associated-type metadata;
- recursive type edges, generic arguments and semantic fingerprints;
- source positions for the declaration, derive application and contributing
  fields.

The canonical member view remains the one answer to field enumeration.
Reflection and derives project it differently; neither reimplements record,
interface, intersection or generic-instantiation member rules. A future public
provider, if later evidence justifies one, may receive the versioned `TypeInfo`
serialization directly. The
compiler-owned providers use its semantic source view so freezing does not
round-trip through JSON inside the checker.

The first version has no user callback and therefore does not need to send a
derive request to the comptime worker. `JSON` may send its codec blueprint
through the existing closed materialization path. D6 evaluated a one-shot
external process: it received a serialized, versioned descriptor and returned a
separately versioned result envelope rather than live compiler objects. The
decision did not accept that prototype protocol as a stable ABI.

## Prelude surface

### Debug

`Debug` is an ordinary instance protocol:

```nupp
interface nupp.Debug
    debug: function(self): string
end
```

`@derive(Debug)` adds `nupp.Debug` to the declaration's contracts and adds the
method:

```nupp
function debug(self): string
```

### Static factories

Generated static functions are members of the record's existing declaration
table, whose type is `metatable<T>`. Generic consumers should be able to use
structural factory shapes:

```nupp
local type DefaultFactory<T> = {
    readonly default: function(): T,
}

local type FromFactory<T, U> = {
    readonly from: function(value: T): U,
}

function nupp.default<T>(factory: DefaultFactory<T>): T
    return factory.default()
end

function nupp.into<T, U>(value: T, factory: FromFactory<T, U>): U
    return factory.from(value)
end
```

This supports:

```nupp
local config = nupp.default(Config)
local id = nupp.into(42, UserId)
```

That does **not** type-check in the compiler today. The relation admits a shape
where `metatable<T>` is expected, but does not project a declaration table's
static members in the other direction. D1 therefore includes a prerequisite
language change before either helper is declared:

- when the source is `metatable<R>` for a nominal record, project
  `R.staticByname` and `R.staticWriteByname` as its structural read/write
  capabilities;
- check `metatable<R> -> shape` assignability field by field through that
  projection, without exposing instance methods, constructors, metamethod
  contracts, nested types, or associated types as ordinary keys;
- teach generic unification to compare a shape parameter with that same
  projection, so `U` in `FromFactory<T, U>` binds from the generated
  `function(T): R` signature;
- retain the existing prohibition on treating a record instance as its
  declaration table.

Excluding nested types is intentional even though nested nominal declarations
are runtime-reachable through the same table as submodules. Nested types remain
a separate semantic category: a structural shape asking for `Config.Inner`
does not match `metatable<Config>`. A future submodule projection, if useful,
is designed separately rather than leaking type namespaces into this relation.

Regression tests first establish that both helpers fail before the relation
change, then that `nupp.default(Config)` infers `Config` and
`nupp.into(42, UserId)` infers `UserId` afterward. This is a real structural
relation and inference extension, not a prelude-only convenience.

If nominal static contracts later earn a language surface, these structural
factory types can migrate without changing derived call sites. Associated
types remain unnecessary for this projection.

### JSON

The prelude already has `interface nupp.data.JSON` for the bundled raw JSON runtime
and `nupp.fieldcodec.KeyedCodec<T>` for the reflected keyed encoder. D4 adds no
public `nupp.JSONCodec<T>` or sibling provider. It extends the shipped
field-codec blueprint with typed decode and separately materializes a direct
JSON emitter. The two runtime products share the reflection walk, schema graph
and fingerprint inputs; the JSON encoder does not compose the keyed table
encoder with cjson.

The value-level contract remains explicit:

```nupp
interface nupp.data.JSONEncodable
    toJSON: function(self): string
end
```

`@derive(JSON)` adds this contract just as `@derive(Debug)` adds `nupp.Debug`.
Generic code over values uses `T is nupp.data.JSONEncodable`; generic code over
declaration tables uses the projected `fieldCodec()` static factory after D1.
The two paths serve different receivers and do not require a second codec type.

`KeyedCodec<T>` gains one method:

```nupp
record nupp.fieldcodec.KeyedCodec<T>
    encode: function(self, value: T): {[string]: any}
    decode: function(self, value: {[string]: any}): (T?, string?)
    fingerprint: string
end
```

`@derive(JSON)` materializes one private `KeyedCodec<User>` plus one private
direct emitter and adds one instance and two static functions:

```nupp
-- Generated instance member:
User.toJSON: function(self): string

-- Generated static members on the declaration table:
User.fromJSON: function(text: string): (User?, string?)
User.fieldCodec: function(): nupp.fieldcodec.KeyedCodec<User>
```

`fieldCodec()` returns the private keyed materialization; it does not rebuild
it. `toJSON()` allocates one `string.buffer.Buffer`, invokes the private
`encodeTo(buffer, value)` lowering, and converts that buffer to a string.
Nested derived records append through their private `encodeTo` entry point into
the same parent buffer rather than constructing a string per record.
`fromJSON()` catches the private raw decoder's text failure, requires an object
table, and passes it through keyed decode before returning `User`. The emitter
and keyed codec share one canonical bidirectional blueprint, annotations,
fingerprint and provider ABI. Reuse is at the blueprint level, not through an
intermediate encoded table, and there is no duplicate reflection walk or
third public JSON-ish codec type.

## `Debug`

```nupp
@derive(Debug)
local record User
    id: integer
    name: string
end

local user = new User {id = 42, name = "Michael"}
print(user:debug())
-- User { id = 42, name = "Michael" }
```

Formatting rules are deterministic and do not call a record's `__tostring`
metamethod implicitly:

- nil, booleans and numbers use canonical scalar spellings;
- strings use quoted escaped spelling;
- arrays, tuples, finite shapes and string-keyed maps recurse in stable order;
- a nominal field calls its declared `debug` method;
- `any` uses a bounded dynamic fallback helper and labels unsupported values;
- functions, threads, userdata, raw pointers and opaque handles are rejected
  unless their declared type implements `nupp.Debug`;
- recursive runtime tables are rendered with a stable `<cycle>` marker.

The generated formatter uses a shared output buffer and visited table rather
than repeated string concatenation. The visited table is per top-level call,
so deriving `Debug` adds no state to an instance.

Generic declarations may derive `Debug` only when every type parameter reached
through a field is already bounded by `nupp.Debug` or reaches the dynamic
`any` fallback. A derive never adds a hidden generic bound:

```nupp
@derive(Debug)
local record Box<T is nupp.Debug>
    value: T
end
```

An unconstrained `Box<T>` reports at `T` and offers the bound as help.

Field-level redaction and omission are useful, but are staged after the base
formatter. Their reserved form is `@debug(skip = true)` or
`@debug(redact = true)`; the two options are mutually exclusive.

## `Default`

```nupp
@derive(Default)
local record Config
    @default("localhost")
    host: string

    @default(8080)
    port: integer

    verbose: boolean
    label: string?
end

local config = Config.default()
```

`@default` is a built-in field annotation with one literal compile-time value.
The value is checked for assignability to the field at the annotation. A
table-valued default is freshly constructed on every call; mutable literal
state is never shared between instances.

Without `@default`, these canonical defaults apply:

| Field type | Default |
| --- | --- |
| optional | `nil` |
| boolean | `false` |
| number, integer, or sized numeric | zero of that type |
| string | `""` |
| array or map | a fresh empty table |
| tuple or finite shape | field-wise default when every member has one |
| nominal record | `FieldType.default()` only at exact `function(): FieldType` |

Functions, opaque handles, ownership-qualified values, non-null pointers and
unsupported unions have no implicit default. Every field must have exactly one
default route. A direct required recursive field is rejected; recursion
through an optional field terminates at nil.

An erased type parameter cannot be asked for a static `default()` function at
runtime: its declaration table is not carried by the value. A generic record
may therefore derive `Default` only when every parameter-dependent field has a
parameter-independent route such as optional nil or an explicit literal
`@default`. A future static-contract or factory-parameter feature may widen
that rule; the derive does not synthesize hidden runtime type arguments.

The generated static function has the exact type:

```nupp
Config.default: function(): Config
```

It constructs with `new Config {...}` and therefore passes through the same
field capability and construction checks as written code.

## `From`

The first `From` derive is deliberately the newtype case:

```nupp
@derive(From)
local record UserId
    value: integer
end

local id = UserId.from(42)
local same = nupp.into(42, UserId)
```

The target must have exactly one stored instance field and no required
constructor-only input. The generated function is:

```nupp
UserId.from: function(value: integer): UserId
```

It constructs `new UserId {value = value}` directly. Readonly fields are valid
because construction initializes them; computed, writeonly, method, static and
metamethod entries do not count as stored fields. An ownership-qualified
stored field is rejected initially; deciding whether `from` consumes, borrows,
or transfers it belongs to the later derived-effect design.

`From` does not infer structural record-to-record conversion. Matching fields
by name would silently choose policy for validation, ownership, defaults,
renames and omitted fields. Multi-field conversions remain written functions.

`From` is infallible. Range checks, parsing and validation belong to a future
`TryFrom`. That future protocol may use the in-flight associated-type feature
for an implementor-specific `Error`, but no part of `From` depends on it.

## `JSON`

```nupp
@derive(JSON)
@json(unknown = "reject")
local record User
    @json(name = "user_id")
    id: integer

    @json(omitEmpty = true)
    nickname: string?
end

local text = new User {id = 42, nickname = nil}:toJSON()
local user, err = User.fromJSON(text)
```

`@json` is a built-in typed annotation valid on records and fields. The first
version supports:

| Target | Options |
| --- | --- |
| record | `unknown = "reject" | "ignore"` |
| field | `name: string`, `omit: boolean`, `omitEmpty: boolean` |

Duplicate encoded names are a compile-time error. `omit` removes a field from
both directions and therefore requires that decoding can obtain a default for
it. `omitEmpty` affects encoding only. The default unknown-key policy is
`"reject"`; compatibility-oriented inputs opt into `"ignore"` explicitly.

The initial codec supports:

- nil, booleans, strings, numbers, and fixed-width integer types whose complete
  range is exactly representable by the JSON text runtime;
- optionals, arrays, tuples, string-keyed maps and finite shapes;
- records deriving JSON, including recursive records through graph references;
- discriminated record unions only when an existing literal field uniquely
  selects every arm.

It rejects functions, threads, userdata, ownership-qualified values, raw
pointers, opaque handles, arbitrary untagged unions, non-string map keys and
unsupported cdata. Integers decode only from integral JSON numbers in range.
A required field rejects both absence and JSON null; an optional field accepts
either as nil. Encoding a cyclic runtime value fails with a path rather than
recursing indefinitely.

### Direct emission and private decode framing

Derived encoding never uses cjson or the process-visible mutable settings on
`nupp.data`. The materialized emitter walks the statically known schema and
appends JSON directly to one `string.buffer.Buffer`. Record keys and structural
punctuation are pre-escaped literal segments. Nested records receive the same
buffer; arrays write brackets directly; finite shapes use declaration order;
and string-keyed maps sort keys by their raw UTF-8 bytes before emission. The
encoder never builds an intermediate JSON-shaped tree, calls `setmetatable`,
or mutates a caller-owned table.

The emitter policy is a versioned contract:

- integers use canonical base-10 digits and `number` values use a
  locale-independent lowercase `%.17g` spelling, preserving exact binary64
  round trips and the sign of negative zero;
- strings must contain valid UTF-8; `"`, `\\`, and U+0000 through U+001F are
  escaped, using `\b`, `\f`, `\n`, `\r`, `\t` where available and uppercase
  `\u00XX` otherwise; `/` is not escaped and valid non-ASCII UTF-8 passes
  through unchanged;
- nesting is limited to 128 containers, and an active-table identity set
  rejects cycles with the current JSON path while permitting a shared acyclic
  table after its first traversal finishes.

The number spelling, escaping table, map ordering, depth limit and cycle
algorithm participate in the codec fingerprint through the emitter-policy
version. Golden byte tests pin each choice. Changing one is a wire-format
change even if the resulting document remains semantically valid JSON.

Decode remains asymmetric on purpose. Scanning and unescaping untrusted bytes
stays in the bundled C decoder, while generated code validates and reconstructs
the declared Nupp type from the resulting table. Each materialized codec owns
one private `nupp.data.newJSON()` instance, captured by the decode helper and
not returned by `fieldCodec()`. D4 calls only settings present on the pinned
runtime:

```nupp
local framing = nupp.data.newJSON()
framing.decodeArrayWithArrayMt(false)
framing.decodeMaxDepth(128)
framing.decodeInvalidNumbers(false)
```

Those values and the raw-decoder ABI participate in the fingerprint. Mutating
the corresponding settings on `nupp.data` or a user-created codec cannot
change derived decoding. The schema, not a cjson metatable, distinguishes
arrays, objects and empty containers. Decoded arrays therefore carry no
cjson-specific metatable, while reconstructed nominal values receive the same
record metatable as directly constructed values.

The cjson boundary has explicit semantic limits:

- exponent overflow such as `1e400` can decode to infinity even when
  `decodeInvalidNumbers(false)` rejects literal `NaN` and `Infinity` tokens,
  so generated validation checks finiteness for every numeric field;
- duplicate object keys are no longer observable after decode and the last
  value wins, including when `unknown = "reject"`;
- an integral JSON number means an integral decoded value, not an integral
  token spelling, so `1`, `1.0`, and `1e0` are equivalent for integer fields;
- `unknown = "reject"` walks every decoded object with `pairs` to find extra
  keys, while `"ignore"` skips that walk and performs only known-key reads.

The strict default is consequently slower than ignore mode. It rejects unknown
names, not duplicate spellings erased by the raw decoder.

### Integer fidelity

JSON number round trips are exact only for integers in
`[-9007199254740991, 9007199254740991]`. D4 chooses rejection rather than an
implicit string representation or a separate number parser:

- fixed-width integer fields whose whole range fits that interval are
  supported;
- `int64` and `uint64` fields report NUPP2806 at derive time, even if one
  particular runtime value would be small;
- the erased Lua `integer` type is supported, but encode and decode reject a
  value outside the safe interval at runtime with its field path;
- `number` retains JSON floating-point semantics, while the direct emitter and
  generated decoder validation both reject NaN and infinities with a path.

The emitter's `%.17g` policy is separate from the integer interval: it preserves
finite binary64 values, while the interval is what makes integer-valued source
and decoded numbers exact. A future annotation may explicitly encode wide
integers as decimal strings, but D4 never changes the wire type based on
magnitude and never claims `uint64` round trips through a JSON number.

`JSON` initially rejects generic record declarations. Nupp erases a record's
type arguments, so one declaration table cannot hold a different materialized
codec for every `Box<T>` instantiation. A later surface may derive a codec
factory that accepts `nupp.fieldcodec.KeyedCodec<T>` explicitly; it will not
smuggle runtime type arguments into ordinary generics.

The compiler-owned JSON derive consumes the base `TypeInfo` and checked
`@json` annotations, asks the existing field-codec provider to finalize a
canonical bidirectional blueprint, and lowers one
`nupp.fieldcodec.KeyedCodec<User>` and one private JSON emitter through the
closed materialization layer. This synthetic boundary is internal to
`@derive(JSON)` and does not relax the ordinary rule that user-written opaque
comptime results need an explicit materializable expected type. D4 extends the
existing blueprint/provider family and runtime helpers; it does not register a
sibling public JSON provider.

The runtime implementation uses `string.buffer` for direct text emission and
the bundled JSON facility only for text tokenization on decode. Generated
validation and reconstruction retain the declared Nupp type; `decode` never
returns a raw `any` value as `T` without checking it. Runtime errors use field
paths:

```text
$.user_id: expected integer, got string
$.nickname: expected string or null, got object
$: unknown field "user_nmae"
```

The codec fingerprint includes the semantic type graph, annotation values,
bidirectional field-codec ABI, emitter-policy and helper ABI, private decode
configuration, string-buffer ABI and raw JSON decoder ABI. An annotation-only
edit therefore invalidates the codec even when the record's written field
types do not change.

## Associated types

The derive phase does not block on [associated-types.md](associated-types.md).

- `Debug` has a fixed `string` result.
- `Default` has the concrete owning record as its result.
- `From` names its source type directly from the one stored field.
- JSON uses the concrete owning record and a fixed `string` error initially.

The in-flight associated-type implementation may land before, during or after
this work. Derive merging must preserve any associated metadata already on the
nominal type, but none of the four providers projects or generates an
associated type. `TryFrom`, iterator derives, and codec protocols with
provider-specific error types are later consumers.

The two efforts do share declaration staging, generic substitution and final
interface fingerprinting. Integration tests must therefore combine a derived
generic record with an unrelated associated-type contract, proving that either
merge order retains both surfaces. This is coordination, not a prerequisite.

## Generics and recursion

A derive is installed once on a generic declaration, not rerun as arbitrary
runtime specialization. Generated signatures retain the declaration's binders
and are substituted by the existing nominal-instantiation path. This supports
`Debug` through an instance-method bound and `From` through a polymorphic
constructor recipe. `Default` is limited to parameter-independent recipes, and
`JSON` rejects generic owners as specified above.

Each provider states the capabilities required of a reached type parameter.
The written bounds must prove those capabilities. No derive silently adds or
widens a bound, because doing so would change which instantiations the source
declaration accepts.

Provider planning uses a graph keyed by nominal identity plus generic
arguments. `visiting` edges produce recursive blueprint references where the
provider supports recursion and a targeted cycle diagnostic where it does not.
Memoization and the normal type-reduction budget bound planning.

Reflection performed by ordinary code after checking sees the final semantic
type fingerprint. A derive provider itself receives the frozen base view and
cannot observe its own generated members. This removes derive-order fixed
points from the language.

## Gradual files and `any`

An explicit `@derive` request has the same semantics in `.nupp` and `.g.nupp`.
The gradual file floor suppresses missing-annotation pressure; it does not turn
an unsupported generated contract into `any` or erase a provider diagnostic.

The providers deliberately differ where their contracts differ:

- `Debug` accepts an `any` field and uses its bounded dynamic fallback.
- `Default` gives `any` no implicit default; the field needs an explicit
  assignable `@default(...)` value.
- `From` accepts a sole `any` field and generates
  `function(value: any): Owner`, because that is the source type the record
  actually declared.
- JSON rejects `any`: decoding cannot prove that an unchecked value is the
  requested runtime type.

Tests cover each rule in both strict `.nupp` and gradual `.g.nupp` files. No
provider consults the filename extension directly.

## Runtime lowering and the line-count invariant

This section describes the implemented lowering contract. Line-count-preserving
emission, closed forwarding recipes, bounded plan serialization and structural
local/upvalue proofs have landed.

Derives inherit the compiler's existing documented rule that generated code
never changes the source line count. This is a lowering constraint to retain,
not a new code-generation doctrine.

For a record, code generation already emits its runtime declaration table on
the declaration's physical line. Derived private constants and function
assignments are appended to that same logical output line after the table is
created. Large behavior lives in versioned bundled helpers or in a private
materialized expression, not in repeated source text.

Cross-declaration plans also record runtime declaration-table dependencies. If
a generated closure refers to a later local record, lowering must allocate a
hygienic forward local on an existing physical line and turn the later table
creation into assignment, or use an equivalent line-preserving delayed
binding. It must not accidentally resolve the later local name as a global.
Qualified and imported declaration tables retain their resolved runtime paths.

Generated forwarding functions are one-line closures with hygienic compiler
names. Stack traces point at the declaration line; diagnostics and editor
navigation point more precisely at `@derive` or a contributing field. A helper
failure retains its field path and derive provenance.

The implementation bounds fields, semantic plan nodes, canonical bytes,
rendered bytes and generated members. The closed recipes use at most two
generated locals and one upvalue; tests pin those structural maxima. Exceeding
a growing category reports a derive diagnostic rather than emitting a function
LuaJIT cannot load.

The runtime feature manifest records the exact helpers each derive needs.
`Debug` adds the debug formatter helper. JSON adds the bidirectional field
codec, direct string-buffer emitter and private raw-decode helper. Pure
constructor derives add no helper when direct lowering suffices.

## Incremental queries and fingerprints

This section describes the implemented D5b contract. Planning produces a
canonical semantic envelope which is interned through the `planDerives` query
by behavior fingerprint. Source provenance remains beside that envelope and
does not participate in equality.

Derive planning becomes a derived query:

```text
planDerives(
    provider ABI versions,
    base semantic type fingerprint,
    checked annotation fingerprint,
    target/runtime policy where relevant
) -> canonical DerivePlan
```

The canonical hash input is an explicit projection of the plan root: it omits
only named root envelope fields such as the runtime registration key and the
stored fingerprint. Its recursive serializer retains every nested field
without a name blacklist, including `key` when that field describes a Debug
map's key type. Source offsets occur only in diagnostic provenance. Equal plans
then intern to the same identity, providing early cutoff. The final module
interface includes:

- requested derive names and provider ABI versions;
- generated public signatures and interface contracts;
- private materialized-value fingerprints when public behavior depends on
  them;
- runtime effect requirements;
- semantic dependencies on every reached exported type.

A written function-body edit does not replan derives. A field type, relevant
annotation, generic bound, or reached type interface edit does. An annotation
irrelevant to a provider remains in the base type fingerprint today and may
conservatively replan; precise per-provider annotation dependency tracking is
an optimization, not a correctness prerequisite.

Cross-module dependencies use resolved nominal identity, never source spelling.
The separate runtime registration key derives from resolved module identity
and declaration identity, not the filename spelling passed to the compiler, so
absolute, relative and separator-normalized invocations emit identical bytes.
Changing a dependency's body stops at its unchanged interface. Changing a
field or derive contract invalidates dependents whose plans reached it.

## Diagnostics

Reserve **NUPP2801–NUPP2808** for derives:

| Code | Meaning |
| --- | --- |
| NUPP2801 | unknown or duplicate provider name in a valid `@derive(...)` |
| NUPP2802 | generated member or interface conflict |
| NUPP2803 | a field or generic bound cannot satisfy `Debug` |
| NUPP2804 | `Default` has a missing, conflicting, or ill-typed field default |
| NUPP2805 | `From` is not an unambiguous single-field conversion |
| NUPP2806 | unsupported or contradictory JSON schema |
| NUPP2807 | unsupported derive recursion or dependency cycle |
| NUPP2808 | generated plan, expression, local, upvalue, or output limit |

The annotation layer owns annotation mistakes and emits exactly one of its
existing diagnostics:

- NUPP2111 for an unknown annotation name;
- NUPP2112 for a wrong target or malformed annotation arguments;
- NUPP2113 while `@derive`, `@default`, `@json`, or `@debug` is reserved but
  not implemented;
- NUPP2114 when a project annotation definition collides with a reserved
  built-in name, using the migration wording above;
- NUPP2115 for a missing required member of a typed helper annotation.

NUPP2801 begins only after a valid, active `@derive(...)` application reaches
the derive registry. It reports an unknown provider identifier or a duplicate
identifier across stacked applications. Invalid target and unavailable
annotation are deliberately absent from NUPP2801, so one mistake cannot
produce both an annotation and derive diagnostic.

JSON schema failures are reported once as NUPP2806 at the `JSON` derive
argument, with the provider message and contributing field attached as
`related`. If D5c moves planning through the existing materialization worker,
the adapter consumes field-codec blueprint mismatches such as NUPP2415 or
NUPP2418 and remaps them to that derive diagnostic, while infrastructure or
protocol failures retain their own codes. The in-process path must provide the
same schema/infrastructure distinction without inventing worker failures. A
derive-owned generated-size limit is NUPP2808.

Diagnostics carry structured `related` entries for every contributing field
and generated-member collision. `help` gives the smallest source action: add a
bound, add `@default`, rename or omit a JSON field, remove the written member,
or remove the derive.

Examples:

```text
NUPP2804: cannot derive Default for Config
  field "logger" of type Logger has no default
  help: add @default(...), add Logger.default(), or write Config.default()
```

```text
NUPP2806: cannot derive JSON for Session
  field "callback" has type function(string): nil, which JSON cannot encode
  help: mark the field @json(omit = true) and provide a decoding default
```

```text
NUPP2802: Debug would generate member "debug", but User already declares it
  help: remove @derive(Debug) or remove the written member
```

Every code is added to `nupp explain`, the generated language reference, and
JSON diagnostic schemas with a failing and corrected program.

## Tooling

This is the implemented tooling contract. Generated identities,
provenance-aware presentation, disjoint references, rename refusal, generated
document symbols, whole derive/duplicate quick fixes and build observations
are covered by D5a–D5c fixtures.

- Completion and member inspection include generated signatures.
- Hover labels a member `generated by @derive(Debug)` and summarizes the
  contributing fields or codec fingerprint.
- Definition on a generated member navigates to its derive argument; related
  field links remain available in hover and diagnostics.
- References treat a generated member like an ordinary semantic member.
- Rename of a generated member is refused with help to change or remove the
  derive; renaming an input field simply replans the derive.
- Document symbols show generated members beneath their owner with a generated
  marker, but never invent source ranges.
- Code actions apply whole fixes: add a required bound, add `@default`, mark a
  JSON field omitted, or remove one side of a collision.
- `nupp build --json` reports provider, owner, fingerprint, generated member
  count, private-value size, runtime features, cached state and duration.

The language server never executes generated Lua. It consumes the canonical
semantic plan. JSON planning remains in-process and follows the same bounded
cancellation and recovery contract as the other providers. There is no
derive-specific worker protocol to validate.

## User-defined derives decision

The built-ins must not hard-code themselves into declaration checking. They
implement an internal provider interface equivalent to:

```nupp
type DeriveProvider = {
    name: string,
    version: string,
    targets: {string},
    plan: function(info: TypeInfo): DeriveResult,
}
```

After the four proving cases, D6 evaluated the following illustrative surface
without adding it to the language:

```nupp
@deriveProvider(name = "RedactedDebug")
@comptime
local function deriveRedactedDebug(info: TypeInfo): nupp.DeriveResult
    -- Return checked semantic additions, never source or syntax.
end

@derive(RedactedDebug)
local record Credentials
    username: string

    @redact
    password: string
end
```

The [D6 decision](derives-d6-provider-decision.md) rejects a public provider ABI
for now. The external Tecs redacted-Debug prototype passed immutable versioned
descriptors and closed semantic results through a one-shot process, but its
accepted operation duplicates `@debug(redact = true)`. The identified way to
make the example non-redundant needs a package helper call, whose identity, type,
effects, ownership, cancellation and cache contract have not been proven by an
external differential corpus. The prototype protocol is a test artifact, not a
compatibility promise.

A later proposal must settle provider import identity, package trust, isolated
worker distribution, semantic type handles in result envelopes, helper
registration, capability limits and cache ABI compatibility. It may expose only
constrained result operations proven by external workloads. It cannot expose the
compiler's CST, type objects, mutable member tables or runtime-expression IR.

Any such proposal must consume the `nupp.types` handles and type-blueprint
vocabulary defined by [`comptime-types.md`](comptime-types.md), rather than grow
a parallel signature language. It may augment its one written owner but cannot
generate a record, interface, nested nominal declaration, import, or module
member.

No plugin discovery or filesystem scanning participates in checking. Any future
proposal must make a provider an explicit imported semantic dependency and
record its resolved identity and ABI in the module interface.

## Implementation stages

### D0: phase skeleton and observation-only provider

- Register `@derive`, `@default`, `@json`, and `@debug` through the existing
  annotation registry, using its `names`, typed and `reserved` policies; make
  no parser change.
- Add hidden prelude schema records for the three typed built-ins and hydrate
  registry members with interned types and definition locations after prelude
  loading, without adding type construction to `annotations.nupp`.
- Add the NUPP2114 migration diagnostic for a project definition that collides
  with one of the newly reserved names.
- Split declaration checking into base, derive-merge and final-conformance
  stages without changing programs that use no derives.
- Freeze a pre-merge projection of the landed `TypeInfo`/member view and add the
  canonical `DerivePlan` envelope; do not add a second descriptor vocabulary.
- Collect the module-wide request index and run an internal test provider that
  reports observations but generates no members. Public `@derive` remains
  reserved and reports NUPP2113 through this stage.
- Add query counters, plan fingerprints and JSON build observations.

Exit test: an unannotated compiler rebuild is byte-identical; derive planning
sees the landed ordered fields, annotations, static fields and associated-type
metadata; built-in typed schemas drive validation, hover and definition;
body-only edits do not recompute the plan; reserved applications and name
collisions use the existing annotation diagnostics; no generated runtime code
exists.

### D1: generated members and `Debug`

- Add derived instance/static member storage to nominal types and generic
  instantiation.
- Project a nominal `metatable<R>` declaration table's static read/write
  members into structural shape assignability, and teach generic unification
  to bind through the same projection.
- Merge signatures before final conformance and report every collision.
- Add the private closed lowering recipes to the existing line-count-preserving
  emitter and retain its invariant tests.
- Activate `@derive`, add `nupp.Debug`, the bounded runtime formatter and the
  `Debug` provider.
- Integrate completion, hover, definition, symbols and references.

Exit test: nested, generic and recursive records format deterministically;
unsupported fields and missing bounds fail at their fields; generated code
loads on LuaJIT and retains exact source line count; independent fixtures prove
`metatable<R>` fits only a shape satisfied by its static members and generic
result inference binds through those signatures.

### D2: `Default`

- Activate the reserved typed `@default` field annotation.
- Implement the canonical default table and recursive availability analysis.
- Generate direct, checked record construction with fresh mutable values.
- Add structural `DefaultFactory<T>` and `nupp.default` declarations.

Exit test: every supported field category constructs correctly; missing and
ill-typed defaults report NUPP2804; two calls share no mutable default state;
direct required recursion is rejected and optional recursion terminates.
`nupp.default(Config)` type-checks through D1's declaration-table projection
and infers `Config`.

### D3: `From`

- Identify the one stored field through the canonical member view.
- Generate the exact static `from` signature and direct construction recipe.
- Add structural `FromFactory<T, U>` and `nupp.into` declarations.
- Reject computed, ambiguous and multi-field targets with NUPP2805.

Exit test: `UserId.from(42)` and `nupp.into(42, UserId)` infer `UserId`; a
wrong source type fails at the call; multi-field and constructor-dependent
records fail at the derive; the `U` result is inferred through D1's projected
static `from` signature rather than from an `any` fallback.

### D4: typed JSON from shared field blueprints

- Activate the reserved typed `@json` annotation schemas and contradiction
  checking.
- Extend `nupp.fieldcodec.KeyedCodec<T>` and its existing provider/runtime with
  typed object decode; do not add a sibling JSON codec type or provider.
- Reuse the reflection graph, annotation edges, worker envelope,
  materialization relation, private expression IR and runtime effect manifest,
  and finalize one canonical bidirectional field blueprint.
- Materialize a direct `string.buffer` emitter from that blueprint, with nested
  `encodeTo` calls sharing one buffer and with the versioned number, escaping,
  ordering, depth and cycle policies above.
- Keep cjson only for raw decode, capture a privately configured `newJSON()` per
  materialized codec, disable decoded array metatables, and validate the raw
  table against the same blueprint.
- Reject fixed-width integer schemas wider than the safe JSON-number interval
  and enforce that interval dynamically for erased `integer` fields.
- Reject non-finite decoded values explicitly, document last-wins duplicate
  keys and integral-value semantics, and make the strict unknown-key walk part
  of the contract.
- Remap field-codec schema failures to one NUPP2806 at the derive site.
- Add `nupp.data.JSONEncodable` conformance to each JSON-derived record.
- Generate `toJSON`, `fromJSON`, and `fieldCodec` forwarders.
- Differential-test encode/decode against a direct reference implementation
  and fuzz small supported schemas and values.

Exit test: nested and recursive records round-trip; invalid decoded shapes
never escape as `T`; annotation-only edits change the codec fingerprint;
encoding performs no intermediate-tree allocation or caller-table mutation;
golden bytes pin number and string spellings; mutating global decode settings
does not change derived decoding; decoded arrays carry no cjson metatable;
`1e400` is rejected as non-finite; duplicate keys are last-wins; `1.0` and
`1e0` satisfy an integer field; `int64`/`uint64` report NUPP2806 and unsafe
`integer` values fail with a path; runtime failures carry deterministic JSON
paths; pure bundled output runs with no compiler present.

### D5: incremental, tooling and hardening closure

The D5a–D5d implementation is complete: derives are present in source,
generated reference and ejected skill output; generated members have distinct
editor identities and provenance; canonical fingerprints retain nested map
keys and exclude source spelling; plans are interned by a memoized query;
bounded cancellation and recovery publish no partial state; internal plus
external acceptance corpora exercise all four providers; and the cross-surface
closure gates plus post-adoption fixpoint pass.

#### D5a: generated-member semantic and editor model

- Give every generated member its own stable semantic identity. It records the
  owner, namespace, member name, signature, provider, derive-argument origin,
  contributing fields and plan fingerprint. Several members produced by one
  provider must not share the same definition key.
- Retain the derive argument as the navigation origin without pretending that
  its token spells the generated member. Definition goes to that origin;
  related field locations remain separate structured links.
- Make completion, hover, signature/inspection, definition and references read
  the canonical generated-member record. Hover names the provider and owner;
  references for `toJSON`, `fromJSON` and `fieldCodec` remain disjoint.
- Refuse prepare-rename and rename for a generated member with help to change
  or remove the derive. Renaming an input field remains an ordinary semantic
  rename followed by replanning.
- Add generated children to document symbols with a generated marker and no
  invented source range. Keep source-only outline behavior available while a
  declaration is incomplete.
- Add whole quick fixes for the errors where one source action is unambiguous:
  remove a conflicting derive or member, add a literal default, omit a JSON
  field, or remove a duplicate provider. A fix is one titled edit set, never a
  selection of synthetic-member edits.

Exit test: completion, hover, inspect, definition, references, rename, symbols
and actions have local, qualified and cross-module derive fixtures. Each JSON
member keeps a distinct identity; generated-member rename is refused; no
request navigates to or edits a token merely because it carries a shared
provider name.

#### D5b: incremental query and published interface

- Extract `planDerives` as a pure memoized query over provider and helper ABI
  versions, the frozen written declaration, relevant checked annotations,
  reached semantic type dependencies and target/runtime policy. Diagnostic
  source locations travel beside the canonical result and do not participate
  in equality.
- Define fingerprint input by an explicit projection of root envelope fields,
  then serialize the projected value recursively without excluding names at
  deeper levels. In particular, a Debug `{string: string}` map and
  `{integer: string}` map have different behavior fingerprints. Never use a
  recursive `key`/`fingerprint` name blacklist as the projection.
- Separate a hygienic runtime registration key from semantic identity. The
  canonical plan and every nested record reference use resolved nominal
  identity that is stable across line moves and workspace relocation; filename
  and source line never enter a semantic or behavior fingerprint. Derive the
  runtime key from resolved module identity and declaration identity rather
  than the path spelling supplied at invocation.
- Intern equal plans or compare their canonical serialized envelopes so an
  unchanged result supplies early cutoff even when an irrelevant input caused
  the query to run.
- Publish requested providers and ABI versions, generated public signatures,
  interface contracts, effects, behavior/private-value fingerprints and
  reached exported-type dependencies in the module interface. Consumers do
  not infer these facts from mutable nominal tables or source spelling.
- Record counters for plan executions, cache hits, equal-plan cutoffs and
  downstream module checks. Test body, field, relevant and irrelevant
  annotation, generic-bound, dependency-interface, provider-ABI and helper-ABI
  edits separately.

Exit test: moving a declaration or relocating the project leaves semantic and
behavior fingerprints unchanged; absolute, relative and normalized spellings
of one input emit identical bytes; Debug maps with different key types have
different fingerprints; a body-only or irrelevant-annotation edit does not
replan; an equal public plan cuts off consumers; a changed generated signature,
contract, effect or behavior fingerprint invalidates exactly the modules that
observed it; cached and cold output remain byte-identical.

#### D5c: bounded work, cancellation and observations

- Retain the field and semantic-node caps and add direct NUPP2808 fixtures at
  and beyond each boundary.
- Bound rendered plan/output bytes before lowering. Add explicit generated
  member, local and upvalue counters where a provider can grow them. Where the
  closed built-ins make a category constant, document that structural bound
  and test the maximum recipe instead of adding a ceremonial counter.
- Thread a cooperative budget/cancellation probe through declaration walking,
  recursive type planning, dependency validation and canonical serialization.
  Cancellation returns one ordinary cancelled result, publishes no partial
  plan or generated members, and leaves the next request able to recompute.
- If JSON planning moves through an isolated worker, validate and bound its
  envelope before merge and test cancel, crash, malformed response and retry.
  If it remains in-process, delete the worker-specific promise and test the
  equivalent in-process cancellation and recovery contract explicitly.
- Add build observations containing provider, owner, semantic fingerprint,
  generated member count, canonical/private-value sizes, runtime effects,
  cached state and duration. Observations are reporting data and do not alter
  a module interface or cache key.

Exit test: adversarial fields, shapes, unions, recursion and annotation values
terminate with a deterministic diagnostic or cancellation; no over-limit Lua
is emitted; a cancelled or failed request poisons no later check; cold and warm
observations describe the same semantic product.

#### D5d: internal and external acceptance

- Derive `Debug` and `Default` on compiler-owned configuration or diagnostic
  records whose handwritten behavior can be compared byte-for-byte or
  value-for-value before duplication is removed.
- Replace one handwritten scalar/newtype constructor with `From` and exercise
  it through `nupp.into` in generic code.
- Put derived JSON beside the existing manifest/build-cache codecs, run their
  real corpora and compare bytes, accepted values and failure paths before
  deleting any reference validation.
- Apply JSON to one external tecs configuration or protocol model and run the
  complete consumer corpus. Record every operation the constrained result
  model needed and every requested operation it deliberately refused.

Exit test: all four providers replace real boilerplate without compatibility
regressions; the internal and external differential corpora pass; the proving
case leaves enough evidence to evaluate D6 without designing from examples
invented for the provider API.

#### D5e: closure verification

- Add check/build/LSP agreement and cached/cold byte-identity fixtures for the
  accepted workloads.
- Pin exact source/output line counts, LuaJIT loadability, runtime feature
  manifests and every generation boundary.
- Change a derived Debug field between `{string: string}` and
  `{integer: string}` and prove that its behavior fingerprint, cached plan and
  emitted plan all change, while changing only invocation path spelling leaves
  emitted bytes unchanged.
- Run the full suite and the stage-one/stage-two compiler fixpoint after the
  compiler adoption, not only before derived records enter the compiler.

Exit test: every D5a–D5d exit test passes; cached and cold builds are
byte-identical; unchanged public plans cut off downstream work; adversarial
types cannot hang or overflow the compiler or LSP; the compiler using accepted
derives rebuilds itself byte-identically.

### D6: evaluate user-defined providers

- Completed after D5: one provider outside the compiler consumes a versioned
  serialized descriptor and returns a closed, bounded semantic Debug result.
- The Tecs request corpus proves deterministic redaction, descriptor/result
  identity checks and refusal of raw source, syntax trees, arbitrary helpers and
  over-limit results.
- The public proposal is rejected for now because the accepted operation
  duplicates the built-in field-redaction policy and the first unmet operation,
  a package helper call, has no proven semantic or trust contract. See the
  [decision](derives-d6-provider-decision.md).
- Any reconsideration must use CT1's semantic type handles and CT4's sealed
  worker, module identity and cache protocol; it must not invent a second
  envelope or execution path.

Exit test: passed. The decision records the real workload, prototype operations,
trust model, explicitly unstable ABI and the evidence required to reconsider;
derive execution remains compiler-owned.

## Test matrix

The shared suite covers:

- parser and formatter behavior for one, stacked, duplicate and malformed
  derive applications;
- reservation migration and typed-schema hover/definition for `@default`,
  `@json`, and `@debug`;
- every valid and invalid target kind;
- written/generated and generated/generated member collisions;
- interaction with written supertypes, inherited defaults, overloads,
  constructors, metamethods, readonly/writeonly fields and nested declarations;
- generic records with sufficient, insufficient and irrelevant bounds;
- declaration-table projection and inference for static members, including the
  intentional refusal to project nested types;
- recursive records, mutually recursive records and unsupported cycles;
- local, module-qualified and global declarations;
- same-module and cross-module member lookup and interface cutoff;
- semantic fingerprints across declaration order, annotation order and worker
  processes;
- body, field, annotation, bound, provider ABI and helper ABI edit counters;
- emitted source line count, LuaJIT loadability, runtime feature manifests and
  generated-size limits;
- check/build/LSP agreement and cached/cold byte identity;
- `nupp reference language` and `--format skill` contain the same derive
  surface, examples and diagnostic codes as the source reference;
- coexistence with associated-type metadata regardless of landing order;
- stage-one/stage-two compiler fixpoint.

Provider suites add:

- `Debug`: all scalar/container spellings, escaping, stable map ordering,
  nested nominal protocols, dynamic fallback and runtime cycles;
- `Default`: every default category, fresh tables, annotation assignability,
  nested defaults, dependent-plan failure propagation, and direct/optional
  recursion;
- `From`: exact source inference, readonly stored fields, wrong source types,
  multi-field ambiguity and generic newtypes;
- `JSON`: supported schema products, renamed/omitted/empty fields, unknown-key
  policy and strict-walk behavior, direct-emitter golden bytes, string escaping
  and UTF-8 rejection, stable map keys, no input mutation, private decode
  configuration, unmarked decoded arrays, duplicate-key last-wins behavior,
  exponent overflow, integral-value spellings, safe and rejected integer
  widths, numeric range checks, null/absence, discriminants, invalid paths,
  runtime cycles and differential/fuzz round trips.

## Acceptance workloads

The feature is not complete merely because four fixtures compile.

- Derive `Debug` and `Default` on compiler-owned configuration and diagnostic
  records, deleting handwritten boilerplate where the generated output is
  identical.
- Replace at least one handwritten scalar/newtype constructor with `From` and
  use it through `nupp.into` in generic code.
- Implement JSON codecs for the manifest/build-cache records currently passing
  through `cjson`, then compare behavior and failure paths against the existing
  validation code before deleting duplication.
- Apply the JSON derive to one external tecs configuration or protocol model
  and run the real corpus, not only a reduced fixture.

Only code made redundant by an accepted derive is removed. The reference
implementation remains through differential testing until the generated path
has covered the acceptance corpus.

## Deferred questions

- Struct support and the JSON meaning of cdata numeric, pointer and array
  fields.
- `Eq`, `Hash`, cloning, ECS/component and schema derives.
- `TryFrom` and whether its error is an associated type or an explicit generic
  parameter.
- Builder and visitor generation, which may require separately nameable nested
  declarations.
- Whether derived methods may opt into ownership or effect annotations.
- Whether a public provider can request a checked forwarding helper from its
  own module without opening arbitrary expression generation.
- Which external workload, if any, justifies reconsidering the rejected stable
  semantic provider ABI.
- Whether the bundled decoder should expose a pull or SAX interface so derived
  decode can validate while scanning without allocating an intermediate table.

None of those questions requires comptime to become a token or AST macro
system.
