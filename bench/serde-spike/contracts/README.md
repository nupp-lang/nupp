# Open binding contracts

This separate project tests open serialization bindings and model-owned lazy
schema extensions. Its codecs and models exercise the S0 contract; production
serde and its public API remain unchanged.

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
negative fixtures. The project imports only its own public modules; its models
have no access to Nupp's private reflection or derive tables.

`example.model` and `example.other` return the same `Binding<string>` while
keeping their different member types private. A model-blind consumer uses both
without casts. `Binding.accept` passes an explicit borrowed state to a generic
consumer instead of storing a value inside the binding. Negative checks reject
widening and narrowing bindings, using another schema's extension key, and
changing the result type of a key or lookup.

The extension prototype retains results per host and key, initializes lazily,
caches nil and failures, and bounds retained entries. Clearing releases the
cache's references without invalidating values held by callers. Initialization
cannot recursively resolve the same key or clear the active cache. It has no
public preparation step or required code generation.

The compiler previously materialized the enclosing result binder of a generic
method as `any`. The concrete failure was
`Bound<T, M>.accept<S, R>` calling `Consumer<T, S, R>.apply<M>` and trying to
return `R`. The v0.0.13 bootstrap compiler reports `NUPP2002`; the corresponding
checker regression is in `tests/substitutiontest.lua`. The compiler fix must
ship and the bootstrap pin must move before standard-library source relies on
this checked dispatch.

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
attribute identities and numbered binary fields. These syntax fixtures do not
yet constitute complete model codecs. `xmlassembly.nupp` groups interleaved
flattened elements before assigning each logical member once, rejects duplicate
scalars, and keeps expanded identities on captured unknown elements and attributes.

`resources.nupp` checks an extension scope that owns managed resources, returns
aliases, and expires those aliases when closed. Ordinary data extensions constrain results to `nupp.Copyable`. The checker
refuses owned initializer results before they enter erased cache storage, and
callable result inference preserves cleanup obligations. Managed aliases remain
copyable and retain their runtime expiration checks.

These fixtures do not complete S0. Automatic declaration access, the full model acceptance fixtures, and the broader Nupp traversal
matrix remain gates in `nupp-plans/todo/open-serialization-bindings.md`.
The production API and migration gates remain open.

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
