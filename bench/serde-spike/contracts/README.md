# Open binding contracts

This separate project tests the standard serialization contracts through
independently owned model libraries and codecs. The fixtures import
`nupp.serde` through the same public interfaces used by application packages.

```sh
cd bench/serde-spike/contracts
../../../bin/nupp run erasure.nupp
../../../bin/nupp run extensions.nupp
../../../bin/nupp run rich.nupp
../../../bin/nupp run resources.nupp
../../../bin/nupp run context.nupp
../../../bin/nupp run protocolsyntax.nupp
../../../bin/nupp run model_document.nupp
../../../bin/nupp run documents.nupp
../../../bin/nupp run buffer_output.nupp
../../../bin/nupp run errors.nupp
```

From the repository root, `./bin/nupp test serdecontracttest` also checks the
negative fixtures. Model libraries use public standard-library contracts and
have no access to Nupp's private reflection or derive tables. The Lua backend
harness separately checks the internal native lowering against a forced visitor
execution.

`example.model` and `example.other` return the same `Binding<string>` while
keeping their different member types private. A model-blind consumer uses both
without casts. `Binding.accept` passes an explicit borrowed state to a generic
consumer instead of storing a value inside the binding. Negative checks reject
widening and narrowing bindings, using another schema's extension key, and
changing the result type of a key or lookup.

The data extension cache retains results per host and key, initializes lazily,
caches nil and failures, and bounds retained entries. Clearing releases the
cache's references without invalidating values held by callers. Initialization
cannot recursively resolve the same key or clear the active cache. It has no
public preparation step or required code generation.

The compiler previously materialized the enclosing result binder of a generic
method as `any`. The concrete failure was
`Bound<T, M>.accept<S, R>` calling `Consumer<T, S, R>.apply<M>` and trying to
return `R`. The v0.0.13 bootstrap compiler reports `NUPP2002`; the corresponding
checker regression is in `tests/substitutiontest.lua`. The dispatch prerequisites shipped in v0.0.14.

`rich.nupp` exercises record and indexed storage through the same external
model. Two JSON policies choose different names and timestamp representations.
The fixture covers integer map keys, recursion, absent optionals, exact numeric
tokens, unknown union capture, duplicate logical keys, and name collisions. A
model-blind renderer uses the same bindings. Documents have their own binding
and member type; `context.nupp` checks typed schema and member context after
decoding and child access.

The JSON reader validates skipped syntax and scopes every aggregate callback.
`reader_scope.lua` also tests untyped callers that retain a reader, underconsume,
overconsume, or throw. `protocolsyntax.nupp` reads actual XML namespace and
attribute identities and numbered binary fields. The syntax checks are separate from the model codec checks. `xmlassembly.nupp` groups interleaved
flattened elements before assigning each logical member once, rejects duplicate
scalars, and keeps expanded identities on captured unknown elements and attributes.

`resources.nupp` checks an extension scope that owns managed resources, returns
aliases, and expires those aliases when closed. Ordinary data extensions constrain results to `nupp.Copyable`. The checker
refuses owned initializer results before they enter erased cache storage, and
callable result inference preserves cleanup obligations. Managed aliases remain
copyable and retain their runtime expiration checks.

The [performance report](performance.md) records the final model/provider
measurements, traversal controls, and explicit limits on throughput claims.
These fixtures separately provide semantic acceptance.

`evidence/baseline.json` records the starting revision, focused baseline
results, and an initial reference inventory. It is not the complete S0
inventory or a throughput result.

`model_document.nupp` reads schema-backed documents using logical member names,
retains typed schema/member context, and writes exact timestamps under another
profile after decoding has finished. Dynamic documents and indexed values retain
explicit null separately from absence. `documents.nupp` snapshots rich values
through scoped in-memory readers, including typed map keys, exact integers and
decimals, float width, bytes, timestamps, unions, tuples, nulls, and immutable
fixture atoms. These snapshots do not serialize to bytes.

`selection.lua` proves that omitted and redacted function fields bypass child
preparation and value access. Their input is still syntax-validated, and the
constructor supplies defaults. `buffer_output.nupp` appends directly to a caller's
Buffer and restores its prefix when a later field fails. The failure path alone
copies that prefix. `errors.nupp` checks structured error codes, logical member
paths, byte positions, causes, and input/token/aggregate limits.

`structure.nupp` uses typed field getters, assignments, and a checked factory as
one operation description. Generic execution and an inspecting backend see the
same operations. Omitted and redacted fields bypass their getters and child
adapters. Construction state closes on malformed syntax, missing required
fields, and constructor validation failure. The field helper accepts copyable
values; resource-producing custom adapters keep their explicit ownership
contract.

`openapi.nupp` uses an independent model and member type. Its request and response
views omit different fields, preserve additional JSON properties, and interpret
an untagged alternative using model-owned rules. Overlapping alternatives and
out-of-range integers are refused. It shares the JSON engine with the Smithy
fixture without changing the substrate for either model. This is a contract
fixture, not a complete OpenAPI implementation.

`smithy_access.nupp` loads one model and uses its member handles in typed,
indexed, and document bindings. The same JSON profiles change timestamp and
name rules in all three representations. Direct reconstruction retains document
boundaries, including null contents. An explicit typed registry reconstructs
records from documents; unknown discriminators fail and destination registries
own their names. No discriminator causes an executable module to load.

`routing.nupp` and `streaming.nupp` split members across query, header, body,
and stream locations. Header and query visitors cache decisions independently
from JSON, validate names and collisions, and escape query components. The
finite codecs refuse streams; protocol routing leaves them unread for the
transport. OpenAPI records and documents share body and parameter policies.
These parameter fixtures support scalar values; list styles, timestamps, and
blob parameters require explicit protocol conversions.

`indexed.nupp` exercises typed slot handles, absent versus null values, exact
64-bit integers, blob bytes, validating conversions, and fresh default factories.
Layouts seal when their binding is requested. Inspectable fields expose presence,
borrowed or copied access, assignment, and an optional default factory, so an optimizing
backend sees the same choices as generic traversal. Foreign slots are refused.

`binarycodec.nupp` runs the common Reader/Writer contract over the NB1 fixture
format. Structures contain numbered fields with a wire kind and byte length.
Strings are UTF-8, blobs are uninterpreted bytes, and integers use big-endian
two's complement with width and signedness supplied by the schema. Tuples have
no tags: integer widths come from the layout and variable slots have u32 byte
lengths. Unexplained tuple suffixes are refused. The fixture supports structures,
these scalars, and scalar tuples; other kinds fail before data traversal.

Record and indexed bindings share the binary codec. Tests cover field
reordering, exact integers, blob bytes, truncation, duplicate known members,
wire mismatches, and owned unknown-field replay after reader closure. Unknown
fields retain numeric identity and opaque payloads under their original profile;
they are never converted to JSON or guessed from their bytes. This specified
fixture is not Protobuf, CBOR, or the native persistence format.

`xmlcodec.nupp` runs the same Reader/Writer contract over XML with Smithy-owned
XML trait policy. Records and schema-backed documents share expanded names,
attributes, scalar values, structures, and wrapped or flattened lists. The
fixture assembles interleaved flattened occurrences before assigning a member.
Empty text remains a value; an absent element stays absent. Unknown subtrees
retain namespace/role identities and owned values in model context, without
inventing string field names. They can be replayed after reader closure under
their original profile. Writers choose namespace prefixes, so tests compare
expanded names and values rather than byte identity.

The XML subset accepts UTF-8 text with ASCII qualified names and rejects DTDs,
processing instructions, scalar mixed content, duplicate scalar members, nulls,
and unsupported schema kinds. These limits belong to the fixture codec, not to
the binding contract. `protocol_scope.lua` checks both XML and binary reader
expiration on success, underconsumption, overconsumption, and exceptions; it also
checks failure caching before malformed input is read.

`mapping.nupp` selects an explicit field whitelist, validates field names, freezes
mapping options, changes wire names, and chooses unknown-property behavior.
Decode rejects omitted required construction parameters before reading input;
optional parameters keep their declared defaults, including fresh mutable tables.
The ISO epoch-seconds conversion accepts integer carriers, handles nullable fields,
and rejects invalid dates or fractional seconds that the carrier cannot retain.

`debug.nupp` exercises the value writer with an independent rendering policy.
Skipped and redacted fields bypass their getters and child selection, including
function fields. Custom Debug methods work on records, interface fields, and
reflected generic bounds. Maps keep deterministic key order, exact 64-bit values
keep their suffixes, and cycles do not confuse shared siblings. Renderer-owned
schema extensions initialize lazily, cache failures, evict old entries, and clear
without retaining rendered values or borrowed identity keys.

`native.nupp` and `native_scope.lua` exercise the framed LuaJIT-local format in
[native-format.md](native-format.md). They preserve exact rich values and document
boundaries, reconstruct through explicit bindings, and restore named store entries
transactionally with explicit version migrations. Other targets are refused before
binding selection. The writer emits wire arrays directly; decoding currently
validates through semantic documents. Native codec instances cache both capability
checks and reconstruction operations, with independent read/write slots and bounded
eviction. The same modules provide the production persistence implementation.

Owning bindings use `OwnedBound<T, Member>` with a typed consuming disposal
function. `Bound` requires Copyable values. JSON, native, XML, binary, and
cross-binding reconstruction dispose returned values if the adapter fails its
consumption check, while successful reads transfer ownership to the caller.
Cleanup failures retain the original error and a separate suppressed cause.
Document adapters carry the same disposal contract. Context values and ordinary
projection intermediates must be Copyable; owning conversions use explicit
reader/writer hooks with concrete resource lifetimes.

`transport_scope.lua` exercises transport backpressure and cancellation after a
finite codec publishes owned bytes. It verifies partial output, cleanup, cache
reuse while publication is suspended, and expired serializer handles. Transport
owns the suspended operation; the synchronous value traversal finishes first.


`view.nupp` checks copyable typed views that retain an explicit binding and
source context, observe mutations, and snapshot into independent nested values.
Serialization traverses the original adapter directly. `document_cache_scope.lua`
checks lazy reconstruction selection, bounded eviction, failure caching,
reentrant initialization refusal, and release without invalidating held decoders.

`matrix.lua` compares the old public API at v0.0.14 with the replacement using
paired independent processes and the same native syntax provider. `breadth.lua`
measures nominal, indexed, document, typed-view, Smithy, and OpenAPI paths under
both portable LuaJIT and native syntax providers. Its allocation measurement is
Lua heap growth with collection paused, not native allocation or process RSS.
The browser conformance record comes from the real i386 LuaJIT guest in Chrome.
