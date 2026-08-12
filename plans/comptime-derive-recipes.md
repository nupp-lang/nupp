# Comptime derive recipes and runtime forwarding

## Status and decision

This is the proposed successor design to the D6 user-defined-provider
experiment. D6 was right not to publish its one-operation JSON prototype as an
ABI. This design supplies the missing semantic boundary: a user-defined derive
is an exported `@comptime` function which inspects one written declaration and
returns a closed, versioned recipe. The compiler validates and applies that
recipe. Complicated runtime behavior stays in ordinary exported Nupp functions;
the recipe generates only checked forwarding members.

The first public surface is deliberately about implementing an existing
interface. A provider does not choose arbitrary member signatures. It names an
interface, fills its named requirements, and lets the compiler take the member
signatures, ownership modes and effects from that contract. It may augment only
the declaration carrying `@derive`.

This is not a commitment against future macros. Recipe kinds form a capability
ladder. Parsed Nupp fragments, a stable public syntax model, layout generation,
or a full macro system may be designed later as separate, explicitly powerful
recipes. Adding one does not widen existing providers or expose the compiler's
private AST and CST to recipes which do not request it.

No public provider ABI lands solely because this document exists. DR0 must
first prove runtime forwarding on an external workload whose result the four
built-ins cannot express. The design fixes the intended boundary so that the
experiment tests a candidate architecture rather than inventing one around the
fixture.

## The invariant

There are three distinct programs:

1. the written owner declaration;
2. an ordinary Nupp comptime provider which decides what the owner should gain;
3. ordinary Nupp runtime helpers which contain the resulting behavior.

The provider returns data between the second and third steps. It never returns
source, private syntax nodes, mutable compiler objects, or lowering IR.

```text
written declaration
        |
        v
immutable semantic TypeInfo
        |
        v
@comptime provider ---------------------+
        |                               |
        v                               |
closed DeriveResult                     | compile time
        |                               |
--------+-------------------------------+
        |
        v
validate, merge, check conformance
        |
        v
small forwarding member
        |
        v
ordinary Nupp runtime helper
```

Comptime owns reflection, selection, branching, loops, validation decisions,
type construction and frozen configuration. Ordinary Nupp owns arbitrary
runtime control flow. The compiler alone owns declaration mutation and code
emission.

## Goals

- Let packages define useful derives without receiving source or compiler
  internals.
- Make the common spelling exactly a comptime function applied to an existing
  declaration and interface.
- Keep arbitrary runtime algorithms in ordinary Nupp, where effects,
  ownership, suspension, generics, diagnostics and optimization already work.
- Reuse `nupp.types` handles and the versioned semantic reflection graph.
- Give every generated member a compiler-known signature, origin, helper
  dependency and deterministic fingerprint.
- Keep providers order-independent, bounded, cancellable and cacheable.
- Preserve freedom to replace the compiler's private AST, CST, checker graph
  and lowering pipeline.
- Allow later recipe kinds to add power deliberately without weakening the
  guarantees or authority of earlier kinds.

## Non-goals for the first version

- Generating a record, struct, interface, nested nominal declaration, import,
  module member or source file.
- Returning source, tokens, AST, CST, arbitrary expression IR or backend IR.
- Adding members which do not satisfy a named requirement of the provider's
  declared interface.
- Mutating stored layout, field order, visibility, written annotations,
  constructors or supertypes.
- Discovering providers or helpers by scanning the filesystem.
- Executing runtime helpers during checking or executing generated Lua in the
  language server.
- Running a provider once per generic instantiation.
- Treating a provider worker as a security sandbox. Installed provider code has
  the user's authority even though every returned byte remains untrusted.

## Proposed surface

The exact names may change during DR0. Their roles and boundaries may not.

### Provider and consumer

```nupp
-- inspect.nupp
local M = {}

interface M.Inspect
    inspect: function(self): string
end

-- Ordinary runtime Nupp. It can be as complicated as the package needs.
function M.renderRecord(value: any, fields: {string}): string
    local parts = {}
    for _, name in ipairs(fields) do
        parts[#parts + 1] = name .. "=" .. tostring(value.[name])
    end
    return "{" .. table.concat(parts, ", ") .. "}"
end

@comptime
function M.derive(info: nupp.derive.TypeInfo): nupp.derive.Result<M.Inspect>
    if info.kind ~= "record" then
        return nupp.derive.error("Inspect can be derived only for records")
    end

    local fields = {}
    for _, field in ipairs(info.fields) do
        if field.readType == nil then
            return nupp.derive.error(
                "Inspect cannot read field " .. field.name,
                field.location
            )
        end
        fields[#fields + 1] = field.name
    end

    return nupp.derive.implement {
        methods = {
            inspect = nupp.derive.forward {
                helper = nupp.derive.helper(M, "renderRecord"),
                arguments = {
                    nupp.derive.receiver(),
                    nupp.derive.constant(fields),
                },
            },
        },
    }
end

return M
```

```nupp
-- application.nupp
local inspect = require("inspect")

@derive(inspect.derive)
local record Credentials
    username: string
    password: string
end

local credentials = new Credentials(
    username = "michael",
    password = "secret"
)

print(credentials:inspect())
```

The generated semantic member is equivalent to this written code:

```nupp
function Credentials:inspect(): string
    return inspect.renderRecord(self, {"username", "password"})
end
```

No source containing that function is produced or reparsed. The compiler may
lower the semantic forwarding member directly, synthesize a private typed node,
or use another internal representation. Those choices are not observable.

### `@derive` arguments

Existing built-in names remain accepted:

```nupp
@derive(Debug, Default)
```

A user-defined argument is a resolved exported `@comptime` provider symbol:

```nupp
@derive(inspect.derive)
```

It is not a runtime function value or an arbitrary annotation expression. The
checker resolves the symbol, verifies the provider signature, and seals its
module identity, exported name, signature, reachable comptime helper closure
and semantic body fingerprint into the request. Aliases resolve to the same
provider identity. Two spellings of one identity are a duplicate derive.

The provider signature is initially exact apart from the interface `I` it
implements:

```nupp
function(info: nupp.derive.TypeInfo): nupp.derive.Result<I>
```

`I` must resolve to one existing interface when the provider is declared. It is
part of the exported provider identity and does not arrive as a forgeable result
field. One provider implements one interface; an owner may request multiple
providers. A later result form may admit an explicit interface intersection if
a real provider needs one atomic implementation spanning several contracts.

Generic, variadic, overloaded and effectful provider signatures are rejected.
Providers execute through the existing comptime worker and limits. A provider
is erased from runtime output unless an ordinary runtime export from the same
module is independently required by a forwarding recipe.

### Helper references

`nupp.derive.helper(module, name)` is a compiler intrinsic admitted only while
checking and sealing a derive provider. It does not capture the module's runtime
table. It resolves one exported ordinary function and returns an opaque
`RuntimeHelper` handle containing:

- resolved package, module and export identity;
- the helper's generic function signature;
- ownership, effects, suspension and runtime-feature contracts;
- definition provenance for diagnostics and navigation; and
- the public-interface fingerprint on which callers depend.

The module argument must be an explicit imported dependency or the provider's
own module. The name must be a literal exported member. No string is looked up
on the filesystem or global package registry. Re-exported helpers resolve to
their canonical definition identity.

The intrinsic is intercepted before comptime evaluation in the same spirit as
`nupp.types.reflect`. The worker receives only the opaque, provenance-checked
handle. It cannot call the runtime helper or inspect its body.

## Semantic model

### Input descriptor

`nupp.derive.TypeInfo` is the immutable, pre-merge projection already used by
compiler-owned derives, extended with `nupp.types` handles rather than a second
type vocabulary. It contains only semantic information:

- request, provider and owner identities;
- owner kind, visibility, generic parameters and declared bounds;
- the existing nominal owner type handle;
- written supertypes and interface requirements;
- ordered stored fields with read/write type handles and capabilities;
- written methods, constructors, properties and metamethod contracts;
- resolved annotation identities and typed constant arguments;
- stable declaration and contributing-field locations for diagnostics; and
- schema version and canonical fingerprint.

It does not contain comments, trivia, tokens, CST nodes, mutable member tables,
backend names or generated results from another provider.

Every provider on one owner sees the same frozen written declaration. Providers
do not observe one another's additions. This makes execution order irrelevant;
the compiler validates and merges all canonical results together, reporting
generated/generated conflicts with both provider origins.

### Result envelope

The serialized result is a closed tagged union. An illustrative first schema is:

```nupp
type Result = {
    version: "nupp.derive.result.v1",
    requestFingerprint: string,
    providerIdentity: string,
    ownerIdentity: string,
    interface: type,
    methods: {[string]: Forward},
}

type Forward = {
    operation: "forward.v1",
    helper: RuntimeHelper,
    arguments: {Argument},
}

type Argument = Receiver | MethodArgument | FieldValue | Constant
```

These are explanatory shapes, not runtime records and not permission for a
provider to construct arbitrary tables. `nupp.derive` builders create opaque
blueprints. Finalization rejects forged tags, unknown keys, foreign handles,
wrong parents, duplicate methods, cycles and over-limit graphs before an
internal derive plan exists.

### First recipe algebra

The first public recipe has one member-body operation:

```text
forward.v1(helper, arguments)
```

Its argument vocabulary is closed:

- `receiver()` passes the generated method's receiver;
- `argument(name)` passes one parameter from the interface requirement;
- `field(fieldInfo)` reads one admitted field from the receiver;
- `constant(value)` embeds one bounded quotable comptime value.

There are no calls nested inside arguments, operators, branches, assignments,
loops, locals, returns or arbitrary member accesses. Runtime control flow stays
in the helper.

A scalar `constant` lowers directly. A table-shaped constant is a canonical
blueprint which materializes a fresh ordinary table for each generated call,
matching a written table constructor; mutation by one helper invocation cannot
alter a later call or compiler-owned cache data. The optimizer may scalarize or
erase that allocation only when ordinary escape and mutation analysis proves it
unobservable. A shared mutable constant is not a v1 operation.

`field` is preferable to making a helper dynamically index an `any` receiver:
it preserves field visibility, exact field types, ownership and direct lowering.
A provider may still deliberately pass the receiver when the helper's checked
signature accepts it. The compiler does not grant private access the written
program would not have.

The v1 result may fill bodyless callable instance requirements of its one
declared interface. It cannot replace a written member or override an interface
default. Constructors, static factories, properties, setters and
metamethods require later named recipe versions after their receiver and
conformance rules are proven. The four built-ins remain compiler-owned and do
not force all of their current operations into public v1.

### Interface-owned signatures

For each result method the compiler finds the named requirement on the
provider's declared result interface and instantiates it for the owner. That
requirement owns:

- the member name and overload slot;
- parameter and return packs;
- parameter ownership modes;
- effects and suspension;
- visibility and method/static classification; and
- any associated-type constraints.

The provider supplies an implementation recipe, not a replacement signature.
The helper call is checked as the generated method body would be checked. The
argument recipes must supply its parameters, its results must satisfy the
interface result pack, and its observable contracts may not exceed the
requirement. Ordinary gradual rules still apply, but using `any` does not erase
an ownership, effect or suspension violation.

The owner must satisfy every remaining interface requirement after all written,
inherited and generated members merge. `implements` is a checked claim and does
not introduce a new nominal identity or globally register an implementation.

### Generic owners

A provider runs once for the generic declaration, never once per
instantiation. Its input graph may contain type-variable handles. Inspection of
a type variable exposes only its declared bound. A provider which needs a
stronger fact returns a diagnostic asking the declaration to add that bound.

The generated forwarding member remains generic with the owner. Helper checking
is symbolic over those same parameters, and the canonical recipe contains
parameter identities rather than one result per instantiation. DR0 may narrow
the first prototype to nongeneric owners, but accepting the ABI requires at
least one bounded generic fixture so the serialized model does not accidentally
make monomorphization part of provider semantics.

## Phase ordering

For one declaration the checker performs:

1. Parse and bind the written declaration and annotations.
2. Build its base member view and recursive nominal shell.
3. Resolve all built-in and user-defined provider identities.
4. Freeze one pre-merge semantic `TypeInfo` and its fingerprint.
5. Execute or reuse every provider result independently.
6. Validate each result envelope, handles, limits and helper identities.
7. Sort results by canonical provider identity and merge their additions.
8. Report written/generated and generated/generated conflicts.
9. Run ordinary final interface, ownership, effect and associated-type checks.
10. Publish the generated semantic members and module-interface fingerprint.
11. Lower forwarding members and record their runtime dependency closure.

A provider cannot observe the result of an earlier provider, request another
provider dynamically, or trigger a second derive round. Derived output therefore
cannot form an order-sensitive macro expansion loop.

## Runtime forwarding

Runtime forwarding is the long-term escape hatch, not a temporary substitute
for expression generation. A package can put arbitrary maintainable behavior in
an ordinary helper:

```nupp
function runtime.render(
    value: Credentials,
    username: string,
    password: string,
    policy: RenderPolicy
): string
    -- Ordinary branches, loops, calls, errors and data structures.
end
```

The provider only connects semantic inputs to it:

```nupp
nupp.derive.forward {
    helper = nupp.derive.helper(runtime, "render"),
    arguments = {
        nupp.derive.receiver(),
        nupp.derive.field(info:field("username")),
        nupp.derive.field(info:field("password")),
        nupp.derive.constant(policy),
    },
}
```

Changing the helper body is an ordinary runtime-module rebuild and does not
change the owner's public interface. Changing the helper signature, effects,
ownership or exported identity invalidates the derive plan. If cross-module
optimization later consumes helper bodies, its private optimization cache must
also depend on the body fingerprint; that does not make the body part of the
language-level provider ABI.

### Optimization and sinking

The semantic forwarding node may survive until typed lowering. The optimizer
may, when ordinary Nupp semantics permit:

- inline the forwarding wrapper;
- inline or specialize its runtime helper;
- replace `field` arguments with direct field reads;
- sink frozen constants into the helper;
- scalar-replace or erase frozen descriptor tables;
- constant-fold annotation policies;
- deduplicate equal frozen plans; and
- fuse a call through the generated member with its helper call.

Optimization must preserve function identity where the generated member is
observed as a value, evaluation order, errors, ownership, effects, suspension,
debug provenance and separate-compilation boundaries. The recipe specifies
meaning, not an optimization guarantee.

## Determinism, caching and incrementality

The canonical provider-query key includes:

- compiler and recipe schema versions;
- target-independent semantic reflection version;
- canonical provider identity and sealed comptime-program fingerprint;
- owner descriptor fingerprint;
- observed annotation and type identities;
- helper public-interface fingerprints; and
- declared capability set and evaluator limits.

The cached answer is the validated canonical recipe plus diagnostics and
observations. A cache hit still checks that all referenced identities exist in
the current module graph. Corrupt, stale or unknown-version entries are misses,
never authority.

Map iteration, allocator identity, process order, filesystem order, locale,
clock, randomness and environment variables cannot affect a result. Descriptor
members have defined semantic order. Every unordered result collection is
canonicalized before collision checking and hashing.

An unchanged helper body with an unchanged public contract does not recheck a
consumer. An interface or helper signature change invalidates the owner and its
dependents. A provider-body change invalidates its requests even if its exported
function signature stays equal. If the new canonical result equals the old one,
the owner's published interface cuts off downstream type checking.

## Limits and failure containment

The provider uses the existing persistent comptime worker, cancellation path
and resource accounting. The derive layer adds limits for:

- providers per owner;
- interface requirements and methods per result;
- argument recipes per forwarding member;
- referenced fields and helpers;
- frozen constant graph items and bytes;
- serialized request and result bytes; and
- diagnostics and related locations returned by one provider.

Timeout, cancellation, worker crash, malformed output, unknown operation,
foreign handle, stale request identity and over-limit output fail the one derive
request with a deterministic diagnostic. No partial member merge occurs. A
failed request poisons neither the persistent worker nor later cache entries.

Provider code is trusted installed code and may consume the user's authority
while it runs. Isolation limits crashes and resource use; it is not a promise
that malicious package code cannot access the machine. Package policy may later
distinguish providers from ordinary dependencies, but that is not delegated to
the recipe validator.

## Diagnostics and tooling

Every generated member records:

- owner and interface requirement;
- provider identity and `@derive` application;
- helper definition identity;
- contributing fields, annotations and frozen constants;
- canonical recipe fingerprint; and
- its generated signature and runtime feature closure.

Hover labels the member as generated, names the provider, interface and helper,
and summarizes its inputs. Definition navigates first to the `@derive`
application, with secondary links to the provider, interface requirement,
helper and contributing fields. References are ordinary semantic references.
Rename of a generated member is refused with help to change the interface or
provider. Rename of a field, provider or helper follows resolved identities and
replans the derive.

Diagnostics point at the narrowest written origin available:

- invalid application or provider failure: the provider argument in `@derive`;
- missing bound or unreadable field: the contributing declaration or field;
- missing interface method: its requirement and the derive application;
- helper signature/effect/ownership mismatch: helper definition and generated
  method requirement;
- member collision: written member or both provider applications; and
- malformed worker result: provider application, with no invented source range.

`nupp build --json` reports provider identity, owner, interface, generated
members, helper dependencies, capabilities, fingerprints, cache state,
duration and private frozen-value size. The LSP reads cached canonical recipes;
it never executes emitted runtime helpers.

## Capability ladder and future recipes

The result envelope is extensible by versioned operation tags, not by adding an
untyped escape field. Each provider declares the recipe capabilities it may
return; validation rejects an undeclared or unknown tag. Adding a capability
does not grant it to existing providers.

The expected ladder is:

| Capability | Result power | Public representation |
| --- | --- | --- |
| Semantic built-in | fixed compiler operation | semantic identities and options |
| Runtime forwarding | fill an interface requirement by a checked helper call | helpers and closed argument recipes |
| Checked expression | construct a deliberately small typed expression | separately versioned expression algebra |
| Parsed members | parse hygienic Nupp fragments in an owner context | source plus explicit semantic captures |
| Syntax macro | transform a stable public syntax model | versioned public syntax handles or graph |
| Layout/codegen macro | affect storage or backend behavior | separate privileged compiler-extension ABI |

The first two remain useful if later levels ship. They are more legible,
analyzable, cacheable, optimizable and safe to admit in dependencies. A package
should use the least powerful recipe which expresses its result.

### Parsed Nupp is a separate capability

A future recipe may deliberately accept something like:

```nupp
nupp.derive.parsedMembers {
    language = "nupp.v1",
    source = "function inspect(self): string ... end",
    captures = {
        helper = nupp.derive.helper(runtime, "render"),
    },
}
```

That feature must specify hygiene, capture identity, declaration ordering,
grammar version, source mapping, diagnostics, formatting, visibility and phase
interaction. The compiler parses and type-checks the fragment; the provider
still receives no private AST or CST. The public contract is the named source
language and capture protocol, not the current parser's internal nodes.

### A syntax API creates a contract deliberately

If Nupp later exposes `nupp.syntax.Node`, that public graph or handle API becomes
a compatibility contract. The compiler may translate between it and any private
AST/CST, but cannot pretend no contract exists. It must be separately versioned,
immutable, capability-scoped and explicit about trivia, locations and hygiene.

This recipe architecture preserves the freedom to make that decision later. It
does not make the cost disappear. Providers using only semantic or forwarding
recipes remain independent of the syntax contract and continue working across
private parser rewrites.

## Rejected alternatives

### Return generated source from every provider

This makes grammar version, hygiene, locations, declaration ordering and
formatting part of the first ABI; weakens semantic diagnostics; and makes simple
derives depend on the most powerful mechanism. Parsed source may be added later
as one explicit capability, not as the foundation.

### Expose the compiler's current CST or type objects

This freezes internal representation, admits forged or stale identities, makes
caches pointer-sensitive and prevents independent compiler evolution. Public
syntax, if accepted later, is a translated versioned model. Types use existing
opaque `nupp.types` handles.

### Add a complete generated-expression builder now

Branches, loops, locals, calls, assignments and returns would form a second
runtime programming language embedded in builders. Ordinary helpers already
provide that language with better checking and tooling. Add individual semantic
operations only when forwarding cannot express a proven workload.

### Let the provider choose arbitrary signatures

This immediately expands collision, overload, generic, ownership, effect and
coherence rules without a contract to check against. V1 fills requirements of
an existing interface. A later `addMember` recipe needs its own evidence and
rules.

### Run providers in merge order

Letting one provider observe another makes source order semantic, introduces
derive expansion rounds and complicates caching. Every provider reads the same
written base view and results merge once.

### Make runtime forwarding an interim implementation detail

That invites pressure to replace ordinary Nupp with generated expression IR.
Forwarding is the intended durable boundary. Optimizers may erase its overhead,
but helper code remains the source-owned place for complicated runtime behavior.

## Implementation plan

### DR0: external forwarding spike

- Choose one external workload which built-in derives cannot express and whose
  behavior has a differential corpus.
- Implement it with an ordinary runtime helper and a handwritten adapter
  equivalent to the proposed forwarding member.
- Record required receiver, method-argument, field and frozen-constant argument
  forms; helper ownership, effects and suspension; runtime features; generated
  member count; and diagnostics.
- Compare wrapper and helper performance before and after ordinary optimizer
  passes. Record which forwarding allocations or dynamic accesses remain.
- Reject or narrow this design if the first real workload requires arbitrary
  source, syntax mutation or provider-chosen signatures merely to be useful.

Exit test: the workload replaces real handwritten adapters, matches its corpus,
and fits `forward.v1` without adding a general expression language.

### DR1: internal semantic forwarding

- Add `RuntimeHelper`, argument blueprints and canonical `forward.v1` to the
  internal derive plan.
- Run a compiler-owned test provider through the same validation and lowering
  path, while exposing no public annotation surface.
- Check exact helper signatures, interface requirements, ownership, effects,
  suspension, fields and frozen constants.
- Lower direct field arguments and preserve generated provenance.
- Add corrupt, foreign, cyclic and over-limit blueprint fixtures.

Exit test: an internal provider implements a non-built-in interface through an
ordinary helper; cold/cached check, build and LSP answers are identical.

### DR2: sealed provider modules

- Extend module interfaces with exported provider descriptors and identities.
- Admit `nupp.derive.helper` only during provider sealing and serialize resolved
  helper handles into the sealed comptime program.
- Track provider bodies, observed types/annotations, helper interfaces and
  runtime feature closure independently.
- Reuse the persistent comptime worker and store validated results in the
  existing compiler cache.
- Prove alias/re-export identity, private helper refusal, missing dependencies,
  cancellation and worker recovery.

Exit test: a provider imported from another module plans deterministically with
no live CST pointers or runtime tables in its module interface.

### DR3: public `@derive(provider)`

- Extend `@derive` resolution from built-in names to exported provider symbols.
- Publish the minimal `nupp.derive` TypeInfo, builder and diagnostic surface.
- Run providers from the same frozen pre-merge view and merge canonical results
  once.
- Implement generated-member hover, definition, references, rename refusal,
  symbols, code actions and JSON build observations.
- Document provider trust, explicit dependencies, limits and generated
  provenance.

Exit test: the DR0 external package uses the public surface without a compiler
patch and its complete differential corpus passes.

### DR4: generic and incremental closure

- Add bounded generic owners and helpers; keep one recipe per declaration.
- Pin interface and helper changes, provider-body changes, equal-result cutoff,
  annotation observations, cached/cold identity and target independence.
- Run adversarial size, depth, timeout, cancellation and corruption tests.
- Measure full build, warm check and LSP latency against the pre-provider
  baseline.
- Run full suite and compiler fixpoint.

Exit test: generic and nongeneric results are deterministic and byte-identical;
unchanged public recipes cut off downstream checking; the compiler rebuilds
itself byte-identically.

### DR5: capability review

- Inventory real provider requests refused by `forward.v1`.
- Prefer a new closed semantic argument or operation when it has a stable
  meaning across compiler implementations.
- Consider checked expressions or parsed members only with an external corpus
  which forwarding cannot reasonably express.
- Version every accepted capability independently and leave existing providers
  at their declared authority.

Exit test: each new operation has a proving workload, explicit contract and
compatibility boundary; absence of such evidence leaves v1 unchanged.

## Test matrix

- valid local and imported provider identities, aliases, re-exports and
  duplicates;
- invalid runtime functions used as providers and invalid comptime functions
  used as helpers;
- record, struct, interface, local, nested and otherwise invalid owner targets;
- one interface per provider, multiple providers per owner, defaults, overloads
  and associated requirements;
- written/generated and generated/generated conflicts independent of provider
  order;
- receiver, named method argument, readable field and frozen constant recipes;
- missing, private, renamed, re-exported and signature-changed helpers;
- exact parameter/result packs, generics, ownership, effects and suspension;
- annotation identity and typed-argument observations;
- generic owners with sufficient and insufficient bounds;
- deterministic provider and result fingerprints across process order and
  targets;
- provider-body, helper-interface, helper-body, owner-field and annotation
  edits with the intended incremental cutoff;
- timeout, cancellation, worker crash, malformed envelope, unknown tag,
  foreign handle, cycle, oversize and corrupt cache recovery;
- check/build/LSP agreement and no runtime helper execution in the LSP;
- hover, definition, references, symbols, rename refusal and whole-result code
  actions;
- direct lowering and optional sinking without changed runtime behavior or
  debug provenance; and
- self-hosting fixpoint after any compiler adoption.

## Completion criteria

The first public comptime derive surface is complete only when:

1. a real external derive not expressible by built-ins uses an exported
   comptime provider and ordinary runtime helper without generated source;
2. every generated member fills an existing interface requirement and passes
   normal type, ownership, effect and suspension checking;
3. providers receive immutable semantic descriptors and return only validated,
   closed, bounded recipes;
4. provider, owner, interface, helper and field identities are explicit,
   deterministic and represented in module and cache fingerprints;
5. providers on one owner are order-independent and cannot observe or derive
   from generated output;
6. no provider can create a nominal declaration, import, module member, layout
   mutation, private AST/CST node or arbitrary runtime IR;
7. tooling explains generated provenance without inventing source;
8. forwarding overhead is measurable and optimizable without making optimizer
   behavior part of the recipe contract;
9. cached, cold, build and LSP semantics agree under failure and cancellation;
   and
10. future syntax or macro capabilities can be added as separate versioned
    recipes without widening or invalidating forwarding-only providers.

## Open questions for DR0

- Which external workload first proves behavior beyond `Debug`, `Default`,
  `From` and `JSON`?
- Must v1 accept only methods whose first argument is the owner, or every
  callable instance field an interface can state?
- Are `field` arguments sufficient, or does the first workload need a frozen
  descriptor interpreted by a helper receiving the whole owner?
- May a forwarding helper consume the receiver when the interface explicitly
  owns it, or should v1 begin with borrowed/read-only receivers?
- How should a provider name an interface imported only for type checking while
  preserving its canonical module identity?
- Should provider imports remain in emitted Lua when every generated forwarding
  helper comes from another explicit runtime module?
- Which generated forwarding calls may the current optimizer already sink, and
  which need a semantic forwarding node to avoid allocating frozen plans?
- Does the first public release permit bounded generic owners, or prototype them
  internally and reject them at the annotation until DR4?
