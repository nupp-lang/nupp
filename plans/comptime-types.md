# Comptime type functions

## Decision

Nupp will admit compiler-only `type` and `typepack` values to `@comptime`
functions. A comptime function whose result is `type` or `typepack` may be
called in type position. It receives compile-time values and immutable handles
to resolved types, runs ordinary Nupp, and returns a validated structural type
or pack to the checker.

This replaces the type-level `match`/`infer` language. Once the proving
workloads have moved, remove:

- `match` and `match each` in type position;
- every type-pattern spelling headed by `infer`, including inferred packs and
  template segments;
- `typeerror<Message>`, whose authored failure becomes `error(message)` in a
  type function;
- guarded recursive aliases and their admission rules;
- recursive alias calls, expansion traces, and reducer budgets; and
- the static PEG example whose purpose is demonstrating a type-level
  interpreter rather than typing the production PEG API.

This replacement deliberately keeps const parameters, `keyof` and
`writekeyof`, indexed member types, mapped structural shapes, template
construction, associated-type projections, and `unpackof`. These are the
direct, readable spelling for common finite type operations. They remain
language features even when a comptime function could produce the same result;
expressive equivalence is not a reason to replace a small declarative operator
with a function and builder calls.

The simplification boundary is type-level programming, not every operation
performed while checking a type. Remove pattern binding, branching, and
recursion expressed through `match`, `match each`, `infer`, and recursive
aliases. Keep bounded structural queries and construction whose meaning is
visible locally and which do not form a second general-purpose control-flow
language.

This plan supersedes the matching, inference, and recursive-alias portions of
[`type-level-computation.md`](type-level-computation.md). Its const-parameter,
member, mapped-shape, and pack decisions remain in force until a separate
decision removes them.

Comptime type functions generate types, not declarations. They may return a
structural type, a type pack, or an existing nominal type. They do not create a
record, struct, interface, method, module member, runtime identity, or source
text. Declaration generation remains a derive or macro-system question and is
outside this plan.

## Why replace type-level inference

The current language has two ways to write a compile-time algorithm. Value
algorithms use ordinary Nupp in `comptime do` or an `@comptime` helper. Type
algorithms use a separate expression language made of `match`, `infer`,
template decomposition, tuple reconstruction, and guarded alias recursion.

The second language has its own:

- parser and CST vocabulary;
- binders and substitution rules;
- open neutral terms;
- evaluator and normal forms;
- recursion admission and cycle rules;
- step, depth, allocation, member, and visit budgets;
- diagnostics and expansion traces; and
- exhaustive handling in fingerprints, reflection, hover, and every generic
  type consumer.

It is compact for one destructuring step and poor for an algorithm. The
private `string.format` aliases are the clearest cost: a normal byte scanner is
represented as a long recursive type-state machine. Literal routes, binary
string expansion, nested-container normalization, and LPeg capture-pack
rewriting have the same shape on a smaller scale.

Nupp already has a checked, deterministic, bounded language for loops, local
state, string processing, helper calls, and authored errors: comptime. Making
types values in that language removes a language rather than adding a third
one.

This does not make comptime the only acceptable spelling for compile-time type
work. `keyof T`, `T.[K]`, a mapped structural shape, or `unpackof T` states a
small operation more clearly than opening a comptime function, reflecting a
type, and rebuilding the result. Those operators remain primitive syntax and
continue to reduce directly in the checker. Comptime is the replacement for
the exotic cases that need user-authored control flow, parsing, iteration, or
recursion.

The target model is close to a compile-time type function:

```nupp
@comptime
local function Binary(source: string): type
    local elements: {type} = {}
    for index = 1, #source do
        local digit = source:sub(index, index)
        if digit == "0" then
            elements[#elements + 1] = nupp.types.literal(0)
        elseif digit == "1" then
            elements[#elements + 1] = nupp.types.literal(1)
        else
            error("expected binary digits")
        end
    end

    return nupp.types.tuple(elements)
end

local type Digits = Binary("1101")
-- {1, 1, 0, 1}
```

No runtime function, table, or loop is emitted. `Binary("1101")` is a type
because it occurs in type position and its checked comptime callee returns
`type`.

## Goals

1. Use ordinary Nupp control flow for every recursive or iterative type
   computation now expressed with `match` and `infer`.
2. Let compile-time-known strings produce exact tuples, shapes, functions, and
   packs without compiler-specific typing at every API.
3. Let a comptime type function inspect a concrete type and construct another
   type from it without exposing mutable checker objects.
4. Preserve symbolic generic declaration checking by deferring calls whose
   arguments are not yet concrete.
5. Keep type identity, fingerprints, incremental cutoff, cancellation, worker
   isolation, and self-hosting determinism explicit.
6. Make generated types indistinguishable from written structural types to
   assignability, member access, generic inference, ownership, reflection, and
   code erasure.
7. Delete the type-pattern evaluator and recursive-alias machinery after all
   production users have moved.
8. Keep simple type errors at the application site and retain a bounded
   comptime call trace back to the generator.
9. Preserve concise finite type operators when their syntax is clearer than an
   equivalent comptime implementation.

## Non-goals

- Generating declarations, names, methods, function bodies, annotations, or
  runtime values.
- Evaluating a runtime string or specializing runtime code for a value that is
  not known while checking.
- Sending a mutable `nupp.compiler.types.Type` object to a worker.
- Returning source text and parsing it as a type.
- Symbolically executing arbitrary comptime control flow over unresolved type
  variables.
- Making normal generics monomorphize at runtime or changing their erasure
  model.
- Allowing ambient filesystem, environment, clock, random, network, or host
  FFI access during type generation.
- Preserving type-level `match` as compatibility sugar after the migration.
- Creating fresh nominal identities. A type function may receive and return an
  existing record, struct, or interface type, but may not manufacture one.
- Replacing `keyof`, indexed member types, mapped structural shapes, template
  construction, associated-type projections, const parameters, or `unpackof`
  with library calls merely because comptime can express equivalent results.

## Surface model

### Compiler-only value types

`type` is the type of a compile-time type handle. `typepack` is the type of a
compile-time function-parameter or result pack handle. Neither is inhabitable
at run time, quotable into generated Lua, storable in an ordinary runtime
table, or accepted by a non-comptime function.

They are legal in:

- parameters and results of `@comptime` functions;
- locals and tables reachable only during comptime evaluation;
- the return value of a type-position comptime call; and
- the closed `nupp.types` inspection and construction API.

They are illegal in runtime fields, runtime function signatures, module value
exports, casts, FFI declarations, and ordinary `comptime do` results that land
in value position.

The checker treats a table such as `{type}` as compile-time-only by reachability.
If a type handle escapes through a value result or an opaque materializer,
report the escape at the return. Do not silently stringify or erase it.

### Type functions

An `@comptime` function returning `type` or `typepack` is a type function:

```nupp
@comptime
local function Optional(T: type): type
    return nupp.types.union({T, nupp.types.nil_})
end

local type MaybeName = Optional(string)
```

The declaration is checked once as ordinary Nupp. Its parameter annotations
describe which call arguments are types, packs, or compile-time values. The
body may call other reachable `@comptime` helpers and uses the same step and
call-depth budgets as an ordinary comptime block.

A call in type position uses ordinary parentheses. Angle brackets remain
generic application syntax:

```nupp
Box<string>       -- instantiate a generic declaration
Optional(string)  -- execute or defer a comptime type function
```

The callee must resolve unambiguously to an `@comptime` function whose result
is `type` or `typepack`. A runtime function, an overload with an undecidable
result, or a value-producing comptime function reports at the callee. Type
functions are not implicitly invoked merely because their name appears in type
position.

For a parameter annotated `type`, a call argument is parsed and resolved as a
type. For `typepack`, it is parsed as a pack. For `string`, `boolean`, or exact
`integer`, it is a const term. This expected-parameter rule makes the following
unambiguous without putting checker objects in expression scope:

```nupp
@comptime
local function ArrayOf(T: type, count: integer): type
    return nupp.types.carray(T, count)
end

local type Buffer<const N: integer> = ArrayOf(uint8, N)
```

### Inspection and construction

Type handles are immutable and opaque. Identity comparison is available, but
their implementation fields are not. The initial API is compiler-owned and
closed:

```nupp
record nupp.types
    -- Existing types and scalar construction.
    nil_: type
    any: type
    unknown: type
    never: type
    boolean: type
    integer: type
    number: type
    string: type

    literal: function(value: string | boolean | integer): type
    optional: function(T: type): type

    -- Structural construction.
    array: function(element: type): type
    tuple: function(elements: {type}): type
    map: function(readKey: type, readValue: type, writeKey: type?, writeValue: type?): type
    shape: function(fields: {nupp.types.Field}, indexer: nupp.types.Indexer?): type
    union: function(members: {type}): type
    intersection: function(members: {type}): type
    pointer: function(element: type): type
    carray: function(element: type, count: integer?): type
    constof: function(T: type): type
    function_: function(parameters: typepack, results: typepack): type

    -- Packs are not tuples: they retain a fixed head, an optional homogeneous
    -- tail, and parameter ownership modes.
    pack: function(head: {type}, tail: type?, modes: {string}?): typepack
    parameters: function(F: type): typepack
    results: function(F: type): typepack

    -- Read-only semantic inspection.
    kind: function(T: type): string
    describe: function(T: type): TypeInfo
    elements: function(T: type): {type}
    fields: function(T: type): {nupp.types.FieldInfo}
    readKeys: function(T: type): {type}
    writeKeys: function(T: type): {type}
    readAt: function(T: type, key: type): type
    writeAt: function(T: type, key: type): type
end
```

The spelling is an API sketch, not a requirement to expose one operation for
every internal constructor. The admission requirement is semantic coverage:
every type and pack that `match`/`infer` can currently destructure or construct
must have a checked inspection or construction path before that syntax is
removed.

`nupp.types.describe` extends the existing versioned semantic reflection graph.
Edges exposed to evaluator code yield type handles, not raw integer indexes or
mutable descriptor tables. The descriptor remains target-independent. Layout
continues through `nupp.sizeof`, `nupp.alignof`, and `nupp.offsetof`.

Construction canonicalizes immediately. A union is flattened, deduplicated,
and sorted by ordinary type identity; a shape uses normal field ordering and
capability rules; a function uses normal pack modes. The API cannot construct
an invalid intermediate type and rely on a later consumer to notice.

### Authored failures

`error(message)` inside a type function fails the type application. A dedicated
`nupp.types.error(message)` may be added only if a delayed error value is needed
for composition. The initial surface prefers raising immediately once the call
is concrete.

A failure reports:

- the type-function application as the primary site;
- the message the function authored;
- the defining function and source position as related information; and
- a bounded comptime call trace when helpers were involved.

The checker must not expose worker protocol failures, type-graph node indexes,
or neutral-term names as the main user error.

## Closed and open calls

### Closed calls

A type-function call is closed when:

- every `type` argument contains no type variable, unresolved associated
  projection, or unevaluated type-function call;
- every `typepack` argument is closed by the same rule; and
- every scalar argument reduces to a literal in its declared const domain.

`any`, `unknown`, `never`, and a broad `string` type are concrete type values.
They may be inspected by a function. This matters for APIs such as
`string.format`, where a literal string produces an exact argument pack and a
broad `string` deliberately produces `...any`.

A closed call executes through the comptime type query and returns an interned
ordinary type or pack. It never reaches code generation.

### Open calls

When any argument is open, the resolver creates an interned
`ComptimeTypeCall` term containing:

- stable type-function identity;
- type, pack, and const arguments in parameter order;
- the result kind, `type` or `typepack`; and
- the generator-program semantic version.

Generic substitution rebuilds this term with rebound arguments. Normalization
executes it as soon as it becomes closed. Until then it is a legitimate open
type term in an exported generic signature, hover, fingerprint, or another
type constructor.

The checker does not partially execute the function with symbolic handles.
Doing so would recreate a second evaluator with branching, loops, unknown
values, and symbolic heap state. An operation that needs the concrete result
of an open call reports that the type function cannot yet be evaluated, unless
the existing gradual rule at that boundary explicitly answers `any`.

This is the principal difference from eager per-instantiation generic checking.
Nupp retains symbolic declaration checking and defers only the type answer.

### Recursive computation

Recursion belongs to ordinary comptime calls, not to type aliases. A type
function may use a loop, call a recursive `@comptime` helper, or call itself
with concrete arguments. The evaluator's call-depth and step limits are the
authoritative termination rule.

A type function may not return an unevaluated call to itself, construct a
symbolic type variable, or create a back edge in a structural result. Existing
nominal recursion remains legal because the returned handle refers to an
already declared nominal identity.

This removes the distinction between syntactically guarded and unguarded alias
recursion. There are no recursive aliases after the migration.

## Proving workloads

### Literal PEGs

Production PEG typing already asks the canonical grammar parser and capture
analyzer for the result shape. It must keep doing so. The generalized mechanism
lets the analyzer finalize a type or pack through the same validated type
construction boundary rather than owning a one-off inference escape.

Conceptually:

```nupp
@comptime
local function PegCaptures(grammar: string): typepack
    return nupp.peg.captureTypes(grammar)
end
```

The public spelling need not expose `PegCaptures`; a literal
`nupp.peg.compile` call may remain a compiler-recognized API. The acceptance
condition is that removing type-level `infer` does not weaken exact PEG capture
types, action checks, or materialized matcher types.

The type-level PEG interpreter example is deleted. It duplicates parsing in
types and is no longer evidence for a feature Nupp retains.

### `string.format`

Replace `__NuppFormatBuild`, `__NuppFormatError`, and
`__NuppFormatArguments` with one checked comptime scanner. It accepts a type
handle so that it can distinguish a literal-string type from broad `string`:

```nupp
@comptime
local function FormatArguments(Format: type): typepack
    local info = nupp.types.describe(Format)
    if info.kind ~= "literal" then
        return nupp.types.pack({}, nupp.types.any)
    end

    -- Scan info.value with ordinary loops and return the exact pack.
end
```

The public call remains `string.format(fmt, ...)`. Literal formats retain exact
arity and conversion diagnostics; dynamic formats retain `...any`. The new
implementation must be materially shorter than the recursive alias machine
and must not add a format-specific checker branch.

### Nested element normalization

Replace recursive `DeepElement<T>` with a loop over immutable type handles:

```nupp
@comptime
local function DeepElement(T: type): type
    while nupp.types.kind(T) == "array" do
        T = nupp.types.elements(T)[1]
    end
    return T
end
```

This proves structural inspection and returning an input-derived handle.

### Literal routes and binary strings

Replace recursive template decomposition with ordinary string operations and
shape or tuple builders. These prove scalar const arguments, authored failures,
generated field names, tuple ordering, and result-member limits.

### LPeg capture packs

Replace `__LpegOptional` and `__LpegMatch` with a comptime function that reads a
capture tuple or pack and constructs the optional result pack. This proves
heterogeneous fixed heads, homogeneous tails, optionalization, and the special
no-capture next-position result.

### Finite match users

Inventory every remaining nonrecursive `match`/`infer` alias in declarations,
tests, examples, and documentation. Port them even when the replacement is
longer. The language removal is complete only when no production or test
fixture needs the old parser.

## Type graph protocol

### Inputs

The parent serializes all type and pack arguments into a versioned,
target-independent graph. Reuse the semantic reflection vocabulary and stable
nominal identities rather than inventing a worker-private type language.

The graph contains:

- one indexed node for each structural or nominal type;
- explicit pack nodes and tails;
- stable references for nominal declarations;
- literal values and exact const terms;
- ownership and capability information needed by inspection; and
- semantic fingerprints for dependencies the generator observes.

No CST node, checker scope, diagnostic sink, mutable member table, interned
allocation address, or code-generation object crosses the worker boundary.

### Results

The evaluator finalizes the returned opaque handle into a `TypeBlueprint`
envelope. It is similar in transport shape to a materializer envelope but has a
different registry and meaning: it reconstructs erased checker semantics and
never emits a runtime expression.

The envelope contains:

- schema and builder ABI versions;
- result kind, `type` or `typepack`;
- an acyclic structural graph;
- references to permitted input and predeclared nominal nodes;
- the canonical result fingerprint;
- observed dependency fingerprints; and
- bounded diagnostic provenance.

The parent distrusts the envelope. It validates node kinds, references,
cardinalities, field capabilities, pack modes, const ranges, nominal identities,
ownership wrappers, graph acyclicity, and the claimed fingerprint before
interning anything.

A malformed envelope is a comptime failure. It cannot create a forged nominal,
an invalid layout type, a mutable checker object, or a runtime declaration.

### Limits

Type generation is subject to both evaluator and result limits:

- the existing comptime instruction, call-depth, wall-clock, memory, protocol,
  and cancellation limits;
- maximum input and output graph nodes;
- maximum tuple, union, intersection, shape, and pack members;
- maximum field-name and diagnostic-message bytes; and
- maximum transitive type-function calls in one query.

Limits are versioned compiler semantics and are documented. A result-limit
failure names the constructor and observed cardinality. It does not masquerade
as non-progressing alias recursion.

## Checker and reducer integration

### Declaration checking

Extend `@comptime` checking to admit `type` and `typepack` parameter and return
annotations. A type function is checked before it is callable. The checker
records a closed program descriptor containing its source, signature, reachable
helper sources, source locations, and dependency fingerprints.

Current `@comptime` helpers are file-private, non-generic, and non-variadic.
Those restrictions are acceptable for the first closed-call prototype. Before
an exported generic signature may contain a type-function call, its program
descriptor and helper closure must be representable in the module interface.

Cross-module type functions are part of the completed surface, not an inferred
runtime export. `@comptime function api.Name(...): type` publishes a
compiler-only function descriptor in the module interface and emits no field in
the runtime module table. A private type function captured by an exported alias
is sealed into that alias's interface dependency even when consumers cannot
name the helper directly.

Do not publish a partially checked function or capture arbitrary surrounding
locals. Inputs are explicit parameters; dependencies are explicit comptime
helpers, compiler APIs, and reflected declarations.

### Type resolution

Add a type-call primary whose callee is followed by ordinary call arguments.
Resolution proceeds in this order:

1. Resolve the callee in the comptime-function namespace.
2. Require a `type` or `typepack` result.
3. Parse each argument according to the checked parameter kind.
4. Check arity, const domains, type bounds, and pack kinds.
5. Execute a closed call or intern an open `ComptimeTypeCall`.
6. Attach definition and application metadata for tooling.

Calls are not evaluated during parser recovery, speculative overload probing,
documentation rendering, or fingerprint comparison.

### Generic normalization

Add one reducer operation for `ComptimeTypeCall`. It substitutes parameters,
normalizes argument terms, and delegates a newly closed application to a
checker-owned query service. The pure type arena does not launch workers or
read project state.

The normalization context therefore gains an explicit callback:

```text
evaluateTypeFunction(function identity, canonical arguments)
    -> type | typepack | failure
```

Every caller that may close a type function supplies the same query service:
call inference, annotation checking, member lookup, associated-type reduction,
hover, completion, and exported-interface validation. A context-free utility
may preserve an open call but may not guess its answer.

Once `match`/`infer` is removed, delete match-pattern substitution and matching,
`reduceMatch`, recursive `AliasCall` expansion, recursive-arm resolver state,
and their dedicated budgets. Retain only neutral operations still required by
the finite features that remain.

### Value comptime

Ordinary `comptime do` continues to return quotable values or materializer
envelopes. A type handle returned in value position reports that it needs a
type-position call. There is no implicit conversion from a generated type to
Lua source or runtime reflection data.

Type functions share the evaluator, allowlist, helper implementation, and
isolation boundary with value comptime. They have a separate result finalizer
and query cache because their products and invalidation rules differ.

## Worker and query design

The current comptime worker reparses one source request in a fresh process.
Launching one process for every unique format string or generic application is
not an acceptable type-checking path.

Before production type functions are used in the prelude, add a persistent
comptime worker service per compiler or LSP session:

- each request receives a fresh evaluator state and budgets;
- parsed function descriptors are cached by program fingerprint;
- type argument graphs and results are framed messages, not temporary source
  files;
- cancellation interrupts the active request;
- a timeout, crash, malformed response, or memory breach kills and replaces
  the worker; and
- no evaluator heap value survives between requests except immutable parsed
  program caches owned by the worker protocol.

Batch builds may execute safe cache hits without contacting the worker. Direct
in-process evaluation remains available to the existing embedders only if it
uses identical type protocols, validation, and limits.

The type-function query key is:

```text
compiler semantic version
+ evaluator ABI
+ type-builder ABI
+ function program fingerprint
+ reachable helper fingerprints
+ canonical type/pack/const arguments
+ observed declaration fingerprints
+ target key only when a permitted target-layout intrinsic is observed
```

Semantic reflection is target-independent. A function that does not ask for
layout must share results across targets. The query records actual observations
rather than invalidating on every declaration available in the worker request.

In-memory memoization is mandatory before the first surface milestone.
Persistent caching lands before prelude migration. A persisted blueprint is
validated again before interning, and cache corruption costs one evaluation
rather than changing an answer.

## Modules and exported interfaces

An exported type may contain an open type-function call:

```nupp
@comptime
function api.EventName(Name: type): type
    -- ...
end

type api.Event<Name> = api.EventName(Name)
```

Its interface must carry a stable function identity and a sealed comptime
program descriptor. Source offsets and local allocation identities are not
semantic identity. Fingerprints use binder position, canonical checked source
or evaluator IR, helper closure, and compiler API version.

Consumers execute the descriptor only after normal import visibility and
generic binding have succeeded. A private helper reachable from an exported
type function is embedded in the sealed descriptor but does not become a
source-visible module member.

Changing whitespace, comments, or a binder name must not invalidate consumers
when the canonical checked program is unchanged. Changing observed type
semantics, helper behavior, a returned type, or the builder ABI must invalidate
them. A body edit that produces an identical validated blueprint permits the
ordinary result-fingerprint cutoff after reevaluation.

No exported interface contains a CST pointer or requires the defining source
file to remain open in the LSP.

## Gradual typing and inference

Type functions do not weaken gradual typing. They receive `any`, `unknown`, or
other broad types as explicit handles and decide through ordinary code what to
return. The standard library functions define their fallback policy visibly.

Generic argument inference remains ordinary Nupp inference. It first binds
type, pack, and const parameters from runtime expressions. The checker then
normalizes newly closed type-function calls before checking the dependent
parameters and results.

An evaluator may not inspect a runtime value merely because its static type is
known. Only literal const arguments and type descriptors cross the boundary.
Thus a literal PEG grammar or format string can select an exact pack, while a
runtime string cannot.

Generated types participate normally in reverse generic inference only after
they are concrete. The checker does not invert an arbitrary comptime function
to infer its inputs. For example, it does not solve `F<T>() == string` for `T`.
Inputs must be inferred from ordinary covariant positions or written explicitly.

## Tooling

- Hover on a closed call shows the canonical generated type and the generating
  function.
- Hover on an open call shows the function signature and symbolic arguments,
  not a guessed result.
- Go-to-definition on the callee reaches the `@comptime` function.
- Generated members use the application as their primary provenance and the
  builder call as related information when retained by the envelope.
- Completion inside a type function includes only comptime values, helpers,
  and `nupp.types` operations.
- Rename follows source binders and function references; it never edits a
  generated field name.
- The LSP query path is cancellable and never runs evaluator code on the
  protocol loop.
- Formatting treats a type-position call as ordinary call syntax and has no
  special layout for generated output.
- Documentation renders the written call and may add a bounded generated-type
  summary when all arguments are closed.

The old `match`/`infer` semantic tokens, completions, hovers, formatter cases,
and playground highlighting are deleted with the grammar.

## Migration and compatibility

This is an intentional breaking language simplification. Implementation is
staged so the compiler can prove parity before removing syntax, but the final
language does not keep two general-purpose ways to compute a type. Direct
finite operators intentionally overlap with comptime because they are shorter,
clearer, and easier to diagnose at their use sites.

The migration order is:

1. Add type handles, builders, closed calls, and tests without changing old
   aliases.
2. Add deferred calls and exported-interface support.
3. Port private compiler and declaration users.
4. Port acceptance fixtures, examples, and docs.
5. Compare diagnostics, latency, fingerprints, and accepted programs.
6. Remove `match`/`infer` grammar and implementation in one deliberate change.

If a compatibility window is required, the old syntax reports a single
deprecation diagnostic with a link to the migration guide. Do not maintain two
reducers or lower old patterns into hidden type functions indefinitely.

The migration guide gives direct recipes:

| Old operation | Comptime replacement |
| --- | --- |
| `match T when {infer Item}` | inspect `kind(T)` and `elements(T)` |
| template `infer` segments | ordinary `string.find`, `match`, and `sub` |
| recursive alias | loop or recursive `@comptime` helper |
| tuple reconstruction | `nupp.types.tuple` or `nupp.types.pack` |
| `function(infer A...): infer R...` | `parameters(F)` and `results(F)` |
| `typeerror<Message>` in a match | `error(message)` in the type function |

There is no migration for `keyof`, `writekeyof`, `T.[K]`, `writeof T.[K]`,
mapped structural shapes, template construction, const parameters,
associated-type projections, or `unpackof`: their existing source syntax stays.
Template construction remains; only template-pattern decomposition through
`infer` moves to ordinary comptime string processing.

## Removal inventory

The final removal must be driven by an exhaustive inventory rather than a
search-and-delete pass. It includes at least:

- parser productions, contextual lookahead, CST nodes, formatter, syntax
  highlighting, and documentation tokens for type `match` and `infer`;
- match patterns, infer type and pack binders, match arms, template-pattern
  parts, `typeError` terms, recursive alias headers, and alias-call neutral nodes in
  `nupp.compiler.types`;
- pattern substitution, pattern unification, match reduction, alias expansion,
  active-alias tracking, recursive budgets, and expansion traces in
  `nupp.compiler.generics`;
- recursive-arm depth and blocked-position state in type resolution;
- alias-header creation and sealing during hoisting;
- match, alias-call, and pattern cases in fingerprints and reflection;
- NUPP2133 examples and recursive-alias documentation;
- the static PEG prototype, route, binary, deep-element, `string.format`, and
  LPeg aliases;
- LSP hover, completion, semantic-token, rename, and cancellation fixtures;
- playground and editor examples; and
- fuzzers and acceptance tests whose only target is the removed grammar.

NUPP2133 may be retired or reassigned only after `nupp explain`, reference
anchors, snapshots, and editor metadata no longer link it to recursive aliases.
Type-function limits and failures receive codes in the comptime/type-reduction
range based on whether evaluation or result validation failed.

## Milestones

### CT0: inventory and acceptance baselines

- Inventory every type-match pattern and recursive alias in production,
  declarations, tests, examples, and docs.
- Record the exact inferred types and diagnostics for PEG, `string.format`,
  LPeg, routes, binary strings, nested elements, packs, mapped fields, and
  gradual fallbacks.
- Record cold and warm check, LSP hover/completion, incremental edit, and full
  suite timings.
- Specify the initial type and pack graph schemas and cardinality limits.

Exit test: every old-syntax user has a named migration and observable parity
fixture; no removal begins from an incomplete inventory.

### CT1: compiler-only handles and builders

- Add checker-only `type` and `typepack` value types.
- Add opaque evaluator handles and the closed `nupp.types` API.
- Reuse semantic reflection for read-only inspection.
- Add `TypeBlueprint` finalization, parent validation, and canonical interning.
- Reject every value-position escape.
- Test the full current type and pack vocabulary, nominal references, malformed
  graphs, limits, and deterministic fingerprints.

Exit test: a direct evaluator test can inspect and reconstruct every type shape
used by existing `match` patterns, but source cannot yet call a type function.

### CT2: closed private type functions

- Admit `type` and `typepack` in `@comptime` signatures.
- Parse ordinary calls in type position.
- Check and seal private type-function program descriptors.
- Evaluate closed type, pack, string, boolean, and integer arguments.
- Add authored failures and application/definition traces.
- Add in-memory query memoization.

Exit test: binary strings, a closed route, and a closed nested-element example
produce canonical types with no `match`/`infer` in their replacement sources.

### CT3: deferred generic calls

- Add `ComptimeTypeCall` terms for open applications.
- Substitute and normalize them through a checker-owned query callback.
- Carry calls through generic function signatures, aliases, associated types,
  exports, hovers, and fingerprints.
- Define open-call behavior at every exhaustive type consumer.
- Preserve dynamic gradual fallbacks where the function explicitly returns
  them for a broad concrete type.

Exit test: a generic signature is checked symbolically, closes after call
inference, and uses the generated type to check later arguments and results.

### CT4: modules, persistent worker, and cache

- Seal transitive helper closures in exported function descriptors.
- Add canonical module-interface fingerprints.
- Add the persistent cancellable worker service and crash recovery.
- Add persisted type-function result caching and revalidation.
- Track reflected and layout dependencies by observation.
- Benchmark adversarial unique applications and cache hits.

Exit test: an exported open call evaluates in a consumer, survives an LSP
restart through the cache, invalidates on a semantic helper edit, cuts off on an
identical result, and cannot stall the editor past its documented budget.

### CT5: production migrations

- Replace the `string.format` recursive aliases with the comptime scanner.
- Replace LPeg capture optionalization and result-pack computation.
- Route PEG analyzer results through the validated type construction boundary.
- Replace routes, nested elements, binary strings, and all finite match users.
- Update declaration, acceptance, project, incremental, documentation, and
  playground fixtures.

Exit test: no production or documentation source requires type `match`,
`infer`, or `typeerror`; exact PEG, format, and LPeg types and diagnostics match
the CT0 baselines or have an explicitly accepted improvement.

### CT6: remove type-level inference

- Delete the grammar, CST, resolver, type representation, reducer, fingerprint,
  reflection, diagnostic, formatter, highlighter, and tooling cases in the
  removal inventory.
- Reject old syntax with the chosen migration diagnostic or remove it directly
  according to compatibility policy.
- Delete recursive-alias limits and documentation.
- Reduce the exhaustive neutral-operation inventory to the finite features that
  remain.
- Fuzz type-function calls, worker envelopes, graph validation, and open-call
  substitution.

Exit test: searches and checked inventories find no live type-pattern or
recursive-alias implementation; the replacement suite passes without a hidden
compatibility reducer.

### CT7: retained-operator consolidation

- Keep `keyof`, `writekeyof`, indexed member operators, mapped structural
  shapes, template construction, const parameters, associated-type
  projections, and `unpackof` as documented language syntax.
- Detach their finite reduction paths from the deleted pattern matcher and
  recursive-alias evaluator.
- Preserve their focused diagnostics, formatting, hover, completion,
  fingerprints, and incremental behavior.
- Document the design boundary: direct bounded operators are preferred for
  simple local transformations; comptime type functions are for algorithms.

Exit test: every retained operator works without the removed match-pattern or
recursive-alias machinery, and the language reference presents it as the
normal readable spelling rather than as legacy compatibility syntax.

## Verification

- Parser recovery and formatting for type calls and removed syntax.
- Type checking of type/typepack locals, tables, arguments, results, and escape
  attempts.
- Full structural constructor and inspector round trips.
- Parent rejection of forged nominal IDs, invalid capabilities, bad pack modes,
  cycles, oversized graphs, wrong fingerprints, and stale ABI versions.
- Closed and open calls over type, pack, string, boolean, and integer arguments.
- Generic substitution, const inference, dependent later arguments, associated
  projections, and module exports.
- `any`, `unknown`, `never`, broad string, literal string, and unresolved
  boundaries.
- Exact PEG capture and action types for literal and dynamic grammars.
- Exact `string.format` arity and conversion errors, plus dynamic fallback.
- LPeg fixed, empty, optional, and homogeneous capture packs.
- Recursive helper success, call-depth failure, step failure, timeout,
  cancellation, worker crash, and recovery.
- In-memory and persisted cache hits, corrupt-cache recovery, dependency
  invalidation, target separation only when observed, and identical-result
  cutoff.
- Hover, completion, definition, rename, semantic tokens, generated-member
  provenance, and LSP cancellation.
- Incremental project checks after function body, helper, reflected type,
  exported interface, and unrelated body edits.
- Cold and warm latency against CT0 with many unique literal applications.
- Full `./bin/nupp test`, compiler `fixpoint`, and byte-identical repeated builds.

## Completion criteria

The replacement is complete only when:

1. ordinary comptime functions can construct every type and pack shape formerly
   produced by `match`/`infer`;
2. literal PEG, format, route, binary, nested-container, and LPeg workloads keep
   exact typing;
3. exported open generic calls are deterministic, cancellable, cacheable, and
   independent of live CST state;
4. no type handle or generated graph can forge a nominal identity or escape to
   runtime code;
5. the old syntax, reducer, recursion machinery, diagnostics, and tooling paths
   are gone; and
6. the language reference teaches one compile-time programming language:
   ordinary Nupp under comptime, with types among its compiler-only values.
