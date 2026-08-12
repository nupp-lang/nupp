# D6 user-defined derive provider decision

## Decision

This historical rejection was superseded by
[`comptime-derive-recipes.md`](comptime-derive-recipes.md). The rejected JSON
prototype was removed after the sealed comptime provider boundary landed.

D6 did not find evidence for token, AST, or CST macros, mutable compiler
objects, arbitrary helper calls, private lowering IR, filesystem discovery, or
provider-selected member signatures. It also did not find an external workload
whose necessary result cannot be expressed by the four built-ins. Shipping an
ABI in that state would turn a test shape into a compatibility promise without
proving that it solves the first problem the public API is meant to solve.

## External proving prototype

The removed prototype used a one-shot Lua process, a JSON descriptor and a
single semantic Debug operation. It is retained here only as design history;
the current tests exercise exported Nupp `@comptime` providers directly.

The version-one prototype descriptor contains only:

- the protocol version and a fingerprint over its canonical semantic contents;
- resolved provider identity and ABI;
- resolved nominal target identity, record name and ordered fields;
- semantic field types and resolved annotation identities; and
- the single capability requested by the host.

The result may request exactly one `debug.record.v1` addition. Its generated
member and `nupp.Debug` contract are fixed by that operation. Each written field
is selected once and rendered either by the existing checked Debug operation or
as a bounded literal. The host checks closed key sets, request/provider/target
identity, operation names, field references, field/addition counts and envelope
sizes before canonicalizing and fingerprinting the result. Raw source and syntax
trees never cross the boundary.

This operation is sufficient for the prototype, deterministic over its corpus,
and line-count independent because it never constructs source. It is not a
public Nupp ABI or compatibility promise. The fixture is deliberately under
`tests/` and no annotation, declaration form, package discovery rule or compiler
loader recognizes it.

## Why the prototype does not justify a public API

The same accepted result is already written directly as `@derive(nupp.derive.Debug)` with
`@debug(redact = true)` on the sensitive field. A provider saves spelling but
adds no semantic capability. Making the Tecs example non-redundant would require
an operation such as a safe request summary: call a package-owned helper that
parses the encoded arguments and returns a bounded, redacted correlation value.
That is an arbitrary forwarding-helper operation, not one of the constrained
results proven by `Debug`, `Default`, `From`, and `JSON`.

The prototype rejects that helper request. Accepting it would require a separate
design for helper identity, type and effect checking, ownership, suspension,
runtime feature publication, cache invalidation and failure attribution. D6 has
no external differential corpus proving those rules, so widening the envelope
would imitate expression macros rather than follow evidence.

## Trust and execution model evaluated

The one-shot worker contains crashes and malformed output, and the host treats
every byte it returns as untrusted data. It is not a security boundary: an
installed provider is executable package code with the user's authority. A
future proposal must therefore name an explicit imported semantic dependency,
pin its resolved package/module identity and ABI in the module interface, run
with cancellation and hard resource limits, validate a closed result envelope,
and never discover providers by scanning the filesystem.

No stable provider ABI is accepted. The prototype's only accepted operations
are evidence about the minimum shape of a future experiment:

- immutable, versioned descriptors with nominal and annotation identities;
- host-owned generated signatures and contracts;
- closed, bounded semantic recipes; and
- deterministic fingerprints over validated results.

Reconsider a public provider only when an external consumer has a differential
corpus for a result the built-ins cannot express and the result still fits a
closed semantic recipe. A need for arbitrary source, token, AST, CST or lowering
construction is grounds to reject that provider, not to widen the derive system.

The proposed successor architecture is
[`comptime-derive-recipes.md`](comptime-derive-recipes.md). It keeps this
decision's rejection of the prototype ABI, supplies runtime forwarding as the
missing closed operation, and requires a new external proving corpus before any
public provider surface lands. More powerful parsed-source or syntax facilities
remain separate recipe capabilities rather than implicit authority granted to a
semantic derive provider.
