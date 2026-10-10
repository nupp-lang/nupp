---
order: 135
title: Serialization bindings
---

# Serialization bindings

A binding defines how a value is read and constructed, and a codec chooses its
wire representation. Select the binding at the call site:

```nupp:playground
local serde = require("nupp.serde")
local json = require("nupp.serde.json")
local record User
    id: uint32
    name: string?
end
local users = serde.binding(User)
local bytes = json.encode(users, new User(id = 41, name = "Ada"))
local restored = json.decode(users, bytes)
assert(restored.id == 41 and restored.name == "Ada")
```

## Declaration bindings

`serde.binding(T)` uses the declaration's field access and construction rules.
It supports records, structs, defaults, and recursive types without a derive.
Missing required fields and unsupported construction fail explicitly; a custom
binding supplies different construction rules when needed.

Nullable values and homogeneous literal unions use their declared carriers.
Record unions need an explicit adapter that chooses their discriminator and
wire representation; the declaration binding does not infer a protocol.

Structs are read field by field. Pointer fields need an explicit adapter that
establishes their ownership and extent.

A declaration can have several bindings. The binding selected for a saved game
can differ from the one selected by a service model, even when both use the
same Nupp record.

## JSON mappings

Mapping options belong to a binding. A field mapping is a whitelist:

```nupp
local serde = require("nupp.serde")
local json = require("nupp.serde.json")
local record User
    name: string
    token: string?
end
local publicUser = serde.binding(User, new serde.Options(
    fields = {name = new serde.FieldOptions(name = "displayName")},
    unknownMembers = "ignore"
))
assert(json.encode(publicUser, new User(name = "Ada")) == '{"displayName":"Ada"}')
assert(json.decode(publicUser, '{"displayName":"Ada"}').token == nil)
```

Omitted fields must have a default or compatible construction mapping before
decoding is selected. An encode-only mapping can omit required fields.
`serde.iso8601Seconds` maps an integer epoch-seconds field to a timestamp;
other conversions use an explicit adapter.

`json.encodeInto(binding, value, buffer)` appends to a caller-owned Buffer and
restores its previous contents if serialization fails. `json.codec(policy)`
makes a codec with a model-owned policy and its own bounded cache.

## Model-owned bindings

A model library owns its member identities, schemas, traits, and registry.
Its adapter implements the shared Reader/Writer contract, while its codec
policy interprets protocol traits such as names, timestamp representations,
XML namespaces, and numbered binary fields.

The erased `Binding<T>` keeps the value type invariant and hides the model's
member type. Generic consumers can use it without importing that model or
turning its schema into a standard-library schema first. `serde.access(T)`
exposes a declaration's fields and constructor to a model that maps an existing
record.

[](nupp.serde.adapters) builds scalar, list, and structure adapters over the
model's own member type:

```nupp
local serde = require("nupp.serde")
local adapters = require("nupp.serde.adapters")
local json = require("nupp.serde.json")
local record Member is serde.Member
    @readonly name: string
    @readonly index: integer?
    @readonly shapeId: string
end
local function textBinding(member: Member): serde.Binding<string>
    return new serde.Bound<string, Member>(adapter = adapters.text(member))
end
local binding = textBinding(new Member(name = "title", shapeId = "example#Title"))
assert(json.codec(json.memberNamePolicy):encode(binding, "Dune") == '"Dune"')
```

A new codec implements `serde.Writer` and `serde.Reader`;
[](nupp.serde.codec) supplies the number, timestamp, error-path, and context
rules the built-in codecs follow.

The model's JSON policy interprets those handles. Callers pass that policy to
`json.codec(policy)`; the default JSON policy only selects standard declaration
and document conventions, and refuses other members rather than guess at their
traits. `json.memberNamePolicy` writes a model's members under their own names.

Operation routing remains with the model library. A Smithy request can select
separate header, query, and body writers, with streaming members handled by
the transport.

## Documents

Documents retain semantic values, schema context, and their source codec and
profile. They distinguish a document boundary from its contents, so a protocol
can interpret a document-valued member separately from the value inside it.

```nupp
local document = require("nupp.serde.document")
local json = require("nupp.serde.json")
local adapter = document.adapter()
local value = document.object({
    new document.Entry(name = "count", value = document.numberToken("18446744073709551615")),
    new document.Entry(name = "payload", value = document.null())
})
assert(json.encodeDocument(adapter, value) == '{"count":18446744073709551615,"payload":null}')
```

The value vocabulary includes exact integers, numeric tokens, decimals,
width-preserving floats, bytes, timestamps, lists, tuples, maps, structures,
unions, and model-defined atoms. A codec rejects values it cannot represent.
Absent members, explicit null, and present values remain distinct.
`json.decodeDocument(adapter, bytes)` reads contents and attaches source
context.

Context values are keyed by [](nupp.util.Key)s. Child documents retain
inherited model and member context after the input reader is dropped; borrowed
reader handles expire when the callback returns. Unknown content can be retained as an owned value with
its original identity and profile, and an incompatible target protocol can
refuse replay.

## Typed views

A typed view retains its value and explicit binding without building a document
tree. Serialization reads the current value through that binding:

```nupp
local serde = require("nupp.serde")
local document = require("nupp.serde.document")
local json = require("nupp.serde.json")
local record Counter
    count: integer
end
local binding = serde.binding(Counter)
local owner = new Counter(count = 1)
local view = document.view(binding, owner)
local snapshot = view:snapshot()
owner.count = 2
local adapter = document.viewAdapter(binding)
assert(json.encodeDocument(adapter, view) == '{"count":2}')
assert(json.encodeDocument(adapter, snapshot) == '{"count":1}')
```

Views require Copyable values and retain their binding and optional context.
`view:document()` materializes logical contents for exploration. `snapshot()`
reconstructs a detached value through the same binding, retaining its model and
context; it requires that binding to support reconstruction. Model libraries
can provide their own document adapters for other snapshot semantics.

Use `codec:decode(adapter:contents(), bytes)` when reading a typed view through
its model's wire policy. `decodeDocument` reads logical document contents; a
model-specific document adapter owns any additional interpretation of those
contents.

## Caching

A codec works out what a binding needs the first time it sees it: names, field
dispatch, construction, and conversions, or a compiled decoder on native AOT.
It keeps that work per binding, so later calls skip it. A failed selection is
kept too, so a bad binding fails the same way each time without being retried.

Caches are bounded at 256 bindings by default and retain no serialized values
or borrowed reader handles. `json.codec(policy, capacity)` and
`native.codec(capacity)` make a codec with a cache of its own, which
`codec:clear()` empties; `document.clear()` empties the cache behind
`document.into`. Decoders already handed out keep working after a clear.

## Owned results

A successful decode transfers an owning result to its caller. An owning
binding provides a typed consuming `drop` function, so a codec can drop a result
it rejects after an adapter returns, such as when the adapter leaves its reader
unconsumed.

`serde.Bound<T, Member>` requires Copyable values. `serde.OwnedBound<T, Member>`
also takes the `drop` function, and document adapters carry the same contract.
A construction failure drops the partial draft. A failure raised while dropping
is kept in the error's `suppressed` list, beside the original cause.

## Native persistence

`nupp.serde.native` reads and writes a versioned LuaJIT-local frame through the
same bindings. It preserves rich scalar values and document boundaries, and
refuses unsupported hosts before selecting a binding.

```nupp
local serde = require("nupp.serde")
local native = require("nupp.serde.native")
local record Save
    level: integer
    inventory: {string}
end
local saves = serde.binding(Save)
local bytes = native.encode(saves, new Save(level = 12, inventory = {"key"}))
assert(native.decode(saves, bytes).inventory[1] == "key")
```

Native persistence stores finite value trees. It does not preserve shared
object identity, execute code from the input, or save process handles.
`document.storeRegistry()` saves a [](nupp.util.Store) through an explicit
registry of entry names, bindings, versions, and migrations, and any codec
carries the snapshot through `document.storeBinding()`.

The frame is not compatible with the previous JSON store snapshot format.
Read old snapshots with the previous codec and write them through an explicit
binding and registry before changing the reader. Native frames reject unknown
versions rather than guessing a layout.

## Runtime support

JSON uses a portable provider on native and browser LuaJIT hosts. Native AOT
can select checked decoding operations for supported carriers; custom adapters
retain the visitor path. Native persistence requires a native LuaJIT host.

The stock Lua 5.1 source profile rejects these standard-library dependencies.
That profile checks source compatibility and does not supply another lowering
backend. See [Portable Lua libraries](../../projects/portability/libraries.md)
for the supported runtime and source boundaries.

## Migration

Use `serde.binding(T)` in place of `serde.of(T)` and pass the binding to a
codec. Type-level JSON methods and serialization derives are replaced by
explicit mappings; declaration defaults and custom construction remain part
of the selected binding.

Run `nupp migrate path/to/model.nupp` to migrate local declarations and
their JSON calls. The command checks the replacement before changing the file.
It removes JSON annotations, creates explicit field mappings, and preserves
`fromJSON`'s old value/error convention with a local `pcall` helper.

Generic declarations, imported callers, record unions, and nested declarations
with distinct JSON policies need explicit binding selection. Migration refuses
ambiguous rewrites instead of dropping their policies. Handwritten methods named
`writeJSON` or `fromJSON` remain ordinary methods.

| Previous API | Explicit binding API |
| --- | --- |
| `serde.of(User)` | `serde.binding(User)` |
| `codec:prepare(binding):encode(value)` | `codec:encode(binding, value)` |
| `User.fromJSON(bytes)` | `json.decode(binding, bytes)` |
| `value:writeJSON(writer)` | `json.writeValue(binding, value, writer)` |
| `@json(name = "id")` | `new serde.FieldOptions(name = "id")` |
| `@json(omit = true)` | Leave the field out of the mapping whitelist |

Serialization errors are raised with their logical path and original cause.
Use `pcall` when the surrounding API returns errors as values. There is no
public preparation step or serialization derive to add to the declaration.
