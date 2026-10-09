# Open binding contracts

This separate project tests the compiler contract needed by open serialization
bindings and model-owned lazy schema extensions. It is an S0 prerequisite,
not the replacement serde implementation or a performance benchmark.

```sh
cd bench/serde-spike/contracts
../../../bin/nupp run erasure.nupp
../../../bin/nupp run extensions.nupp
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

These small fixtures do not complete S0. They do not establish a complete
access/construction API, scoped unknown readers, rich documents, recursive
serializer publication, resource-bearing extension ownership, protocol
compatibility, or traversal performance. Those gates remain in
`nupp-plans/todo/open-serialization-bindings.md`; no production API is frozen
by this package. The original serde API remains in place until its replacement
passes the plan's compatibility and migration gates.

`evidence/baseline.json` records the starting revision, focused baseline
results, and an initial reference inventory. It is not the complete S0
inventory or a throughput result.
