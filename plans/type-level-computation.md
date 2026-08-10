# Type-level computation

> **Status: proposed. Not implemented.** This is a checker feature, not an
> extension of `comptime`. The finite structural stages are specified for
> implementation; recursive reduction has a separate admission gate and is not
> implied by landing the earlier stages.

## Decision

Nupp will admit a small, explicitly staged language for deriving a type from
other types and compile-time-known generic values. It begins with terminating
structural operators: member keys, indexed member types, mapped structural
shapes, type pattern matching, and string-template types. Recursive generic
aliases remain forbidden until those operators have proved useful on real APIs
and a synchronous reduction budget has proved responsive in the checker and
language server.

The feature exists for a relationship ordinary parametric generics cannot
state: one input type determines the fields or callback types of another. An
event adapter derived from a record is the proving case delivered by the finite
stages:

```nupp
local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]:
        function(callback: function(value: T.[K]): nil): nil
}

local type Person = {name: string, age: integer}
local events: Events<Person> = nil as any
events.nameChanged(function(value) print(value) end)
events.ageChanged(function(value) print(value) end)
local missing = events.heightChanged -- unknown field
```

A literal route determining a handler shape is the motivating case for the
conditional recursive stage. It is deliberately not the headline promise:
T1--T4 are useful and complete if recursive aliases never earn admission.

`comptime` cannot express that relation and will not be widened to do so. It
runs after normal name and type resolution and requires a closed request. A
type reducer runs during that resolution. They are separate evaluators on
opposite sides of the phase boundary.

The full phase table is:

| Direction | Mechanism | Status |
| --- | --- | --- |
| value -> value | comptime evaluator | C1 landed |
| type -> value | `reflect(T)` descriptor | C2a landed |
| value -> type | no general mechanism | closed deliberately |
| type -> type | checker-native type reducer | T1--T4 landed |

Compile-time value parameters are a narrow extension to the generic system,
not a general value-to-type escape. Only values admitted by the const-argument
grammar and proven known while checking may bind one. Runtime results,
`comptime` blocks, globals, I/O, and arbitrary expressions cannot.

## Why this is not comptime

The boundary in [the comptime plan](comptime.md#generic-system-interaction) is
the governing rule:

> A comptime request must be closed after normal name and type resolution. It
> cannot depend on an unresolved type parameter or on a runtime generic
> argument.

Comptime therefore cannot implement any part of this feature:

- `reflect(T)` serializes facts the checker has already established into a
  comptime-only value. `keyof T` must establish a type while the checker is
  still resolving one.
- `@comptime` helpers run ordinary checked functions over closed values. A
  type-level `match` reduces open terms containing symbolic binders.
- C4 moves comptime behind a cancellable worker. A type reducer is synchronous
  inside assignability, inference, member lookup, hover, and completion; it
  cannot use that worker without turning every checker query into an
  asynchronous protocol.
- Materialization emits one runtime expression of an already declared type. It
  cannot add a declaration or change a handler parameter's type.

The two systems share no evaluator, bytecode, environment, recursion budget,
or result protocol. They do share the checker's semantic member vocabulary and
type fingerprints. Sharing those facts is necessary for consistency, not an
implementation path from one evaluator to the other.

## Goals

1. Express dependent library surfaces where a literal or input type determines
   another argument or result type.
2. Derive readable and writable structural views without repeating field names
   and types.
3. Parse small, compile-time-known string languages such as routes, event names,
   and format strings into types.
4. Keep every pre-recursion stage terminating by construction and bounded in
   output size.
5. Give reflection, mapped types, `keyof`, derives, and documentation one
   semantic answer for a type's members and capabilities.
6. Preserve content-addressed type identity, module invalidation, incremental
   cutoff, fixpoint builds, and responsive LSP operations.
7. Make the distinction between a type parameter and a compile-time value
   parameter visible at its binder.
8. Report reduction failures at the operator or alias that caused them, with a
   bounded expansion trace when recursion eventually lands.

## Non-goals

- Executing a runtime parser in the type checker.
- Replacing LPeg or the planned materialized PEG matcher.
- Parsing runtime strings. A value typed merely `string` contains no text for a
  type-level parser to inspect.
- General value-to-type conversion, dependent runtime values, macros, source
  generation, AST access, or declaration generation.
- User-defined type reflection callbacks or user-defined reducer intrinsics.
- Higher-kinded types or abstracting over a type constructor.
- General arithmetic theorem proving, Peano encodings, Fibonacci, Collatz, or a
  goal of Turing completeness.
- Implicit specialization or monomorphized runtime functions. Const parameters
  erase with ordinary generics.
- Inferring const values from arbitrary function bodies or optimizer results.
- General type-level computation over packs in the first stage. One narrowly
  specified pack concatenation may be proposed independently for typed parser
  combinators.
- Reopening the withdrawn associated-type design. A future projection feature
  may consume the same reducer, but is not a prerequisite or part of this plan.

## Proving cases

### Event adapters

Member enumeration and template construction derive an adapter surface without
recursion:

```nupp
local type Events<T> = {
    readonly [K in keyof T as `${K}Changed`]:
        function(callback: function(value: T.[K]): nil): nil
}

local type Person = {
    name: string,
    age: integer
}

local events: Events<Person>
events.nameChanged(function(value) print(value) end)
events.ageChanged(function(value) print(value) end)
local missing = events.heightChanged -- unknown field
```

This is a structural type only. It does not manufacture a record, table,
method body, metatable, dispatcher, or event registration at run time.

This is the T3 headline. It delivers a dependent API surface even if T5 is
declined permanently.

### Recursive literal routes

The route path is the candidate proving case for T5, not for the finite
feature. It requires a recursive alias to collect an arbitrary number of
segments:

```nupp
local type RouteNames<const Path: string> =
    match Path
    when `${infer _}:${infer Name}/${infer Rest}` then
        Name | RouteNames<Rest>
    when `${infer _}:${infer Name}` then
        Name
    else
        never
    end

local type RouteArguments<const Path: string> = {
    readonly [Name in RouteNames<Path>]: string
}
```

For `"/users/:user/posts/:post"`, `RouteNames` reduces to `"user" |
"post"`, and `RouteArguments` reduces to:

```nupp
{
    readonly post: string,
    readonly user: string
}
```

Structural fields retain Nupp's canonical name order even though the parser
encountered `user` first. Source-facing diagnostics may show encounter order;
type identity and fingerprints use canonical order.

### Read and write views

Nupp properties carry independent capabilities, so the surface must not copy
TypeScript's one-directional field model:

```nupp
local record Cell
    readonly value: string
    writeonly value: string | integer
end

local type ReadKey = keyof Cell                 -- "value"
local type WriteKey = writekeyof Cell           -- "value"
local type ReadValue = Cell.["value"]            -- string
local type WriteValue = writeof Cell.["value"]   -- string | integer
```

The first mapped-type stage requires an explicit output capability:

```nupp
local type ReadonlyView<T> = {
    readonly [K in keyof T]: T.[K]
}

local type WriteSink<T> = {
    writeonly [K in writekeyof T]: writeof T.[K]
}
```

A bare mapped field is rejected initially. Capability preservation and a
`readwrite` mapped modifier may be designed after real examples establish what
they should mean for a source with different read and write types.

### Typed PEG is adjacent, not an implementation case

Ordinary generics can type the result of parser combinators without evaluating
the grammar in the type system:

```nupp
local type Pattern<Result> = any

local function capture(pattern: Pattern<nil>): Pattern<string>
local function action<A, B>(
    pattern: Pattern<A>,
    transform: function(A): B
): Pattern<B>
```

The planned PEG materializer threads `Blueprint<R> -> Matcher<R>` through
ordinary generic types. A type-level reducer does not inspect the opaque graph
to discover `R`, and materialization does not invoke the reducer to generate a
type.

A complete LPeg-style multiple-capture algebra wants concatenation of two
symbolic packs:

```nupp
local function sequence<A..., B...>(
    left: Pattern<A...>,
    right: Pattern<B...>
): Pattern<pack.concat<A..., B...>>
```

That operation is useful and finite, but first-class packs deliberately exclude
concatenation today. It needs its own representation and ownership proof; it is
not smuggled into this plan as a reason for general recursion.

A PEG interpreter encoded entirely as types would be possible only after
recursive matching and string decomposition land. It would accept only a
literal input and produce a type-level result, not executable Lua. It is an
explicit non-goal and no acceptance test asks for one.

## Surface syntax

Every spelling below is contextual in type or generic-binder position. The
parser recognizes an operator only from a complete lookahead that existing
type syntax cannot satisfy:

- `keyof` and `writekeyof` are operators only when another type primary follows
  on the same line; a terminal type named `keyof` remains a name;
- `writeof` is an operator only before a complete `T.[K]` indexed member type;
- `match` is an operator only when a scrutinee is followed by `when` or `else`
  at the same nesting depth;
- `infer` is special only in a `when` pattern and only before a pattern binder;
  and
- a mapped field is recognized only by `[Name in` after a property capability.

These are context-sensitive additions of the same kind as the existing typed
operators, not reserved words. The grammar notes must record the exact
lookahead and same-line rules rather than claiming the names cannot conflict.

### Compile-time value parameters

`const` before a generic binder declares a value parameter:

```nupp
local record Matrix<T, const Rows: integer, const Columns: integer>
    values: T[Rows * Columns]
end

local type Header<const Name: string, const Value: string> =
    `${Name}: ${Value}`
```

The colon takes a const-value domain, initially `string`, `boolean`, or
`integer`. It is not an ordinary upper bound and does not use `is`.

At a type application, the declaration's binder kinds interpret arguments:

```nupp
local type M = Matrix<float, 4, 4>
local type H = Header<"content-type", "application/json">
```

At a function call, inference binds a const parameter only from an expression
the checker already records as compile-time-known:

```nupp
local record Field<const Name: string> end

local function field<const Name: string>(name: Name): Field<Name>

const id = "user_id"
field("name") -- Name = "name"
field(id)     -- Name = "user_id"

local dynamic: string = readName()
field(dynamic) -- const parameter Name cannot be inferred from a runtime string
```

There is no explicit type-argument syntax on calls; this preserves Nupp's
existing rule. An annotation or a literal argument supplies context.

Const inference is not ordinary literal-preserving type inference. `<T is
string>` binds a type and follows the ordinary widening and unification rules;
`<const S: string>` binds a known value. Library authors choose deliberately.

The initial const-argument grammar admits:

- string, boolean, and integral numeric literals;
- a const parameter of the matching domain;
- a `const` binding or immutable named field whose initializer is already a
  known admitted value;
- the closed const operators implemented for that domain; and
- parenthesized forms of the above.

It excludes calls, table constructors, indexing a mutable path, `comptime do`,
runtime locals, and every operation whose result needs optimizer analysis.

### Constant expressions in type position

The const expression grammar is closed and separate from runtime `exp`. The
first string stage contains literal concatenation through templates. The first
integer stage, needed before value-sized generic arrays, contains `+`, `-`,
`*`, `//`, `%`, and comparisons over exact integers with checked overflow.

An operation returns a const value, not a runtime expression and not a general
type. Where a type is required, a string or boolean const value denotes its
singleton literal type. Numeric literal types become legal in type syntax when
integer const parameters land; today the internal type algebra can carry one
but the type grammar cannot spell one.

Target-sized cdata arithmetic is excluded. `int32`, `uint64`, floating point,
pointer sizes, `sizeof`, and ABI layout remain outside this target-independent
generic system.

### Type matching and inference

`match` is an expression in the type grammar:

```nupp
local type Element<T> =
    match T
    when {infer Item} then Item
    else T
    end
```

The recursive stage may later spell `DeepElement<Item>` in the first arm; the
nonrecursive stage rejects that reference under the existing NUPP2115 rule.
Initial patterns are:

| Pattern | Examples |
| --- | --- |
| literal | `"ready"`, `true`, `3` |
| ordinary type | `string`, `Named`, `T` |
| array | `{infer Item}` |
| tuple | `{infer First, infer Second}` |
| map | `{[infer Key]: infer Value}` |
| function | `function(infer A...): infer R...` |
| pointer | `infer Item*` |
| C array | `infer Item[?]`, `infer Item[16]` |
| read-only view | `const infer T` |
| generic nominal application | `Box<infer Item>` |
| template string | `` `${infer Head}:${infer Tail}` `` |

Only forms already expressible in Nupp's public type syntax are
pattern-matchable. Internal ownership, borrow provenance, cleanup identity,
nominal runtime metadata, and inferred effects are never decomposed by a
user-written pattern.

`infer` is scoped to its `then` arm. Repeating a name requires the matched
parts to be the same type or const value; it does not union them. `_` is an
anonymous binding and may repeat.

Arms are tried in source order. The first pattern that provably matches wins.
An ordinary type pattern succeeds when the scrutinee fits it under the normal
type relation; an `infer` pattern structurally unifies and binds the named
parts. For a concrete scrutinee, overlap is therefore visible and intentional.
An open scrutinee stays as a neutral match term until substitution makes the
choice decidable. Omitting `else` means `else never`.

Normal matching treats a union as one type. Distribution is explicit:

```nupp
local type NonNil<T> =
    match each T
    when nil then never
    else T
    end
```

`match each never` is `never`; otherwise each union member is reduced and the
results are united canonically. There is no TypeScript-style rule where a
syntactic accident involving a bare binder silently selects distribution.

### Template literal types

Backticks keep the spelling Nupp already uses for runtime interpolation, but
their holes contain const or type-level string terms in type position:

```nupp
local type Event<const Name: string> = `${Name}Changed`
local type Qualified<const Module: string, const Name: string> =
    `${Module}.${Name}`
```

A union in a construction hole produces the Cartesian product:

```nupp
local type Side = "left" | "right"
local type Event = `${Side}Down` | `${Side}Up`
```

The reducer enforces a fixed product/member limit before allocating the output.
The diagnostic reports each hole's cardinality and recommends an ordinary
`string`, a smaller union, or generated data when the product is too large.

In a match pattern, a template decomposes a concrete string literal and binds
its `infer` holes as const strings. Greedy/non-greedy ambiguity is not left to
implementation accident: literal separators delimit from left to right, and
adjacent inferred holes are rejected because they have no unique split.

```nupp
when `${infer Name}Changed` then Name       -- unique suffix delimiter
when `${infer A}${infer B}` then ...        -- rejected as ambiguous
```

Unicode operations are byte-preserving initially. The templates concatenate
and split source strings; case conversion, character classes, locale, and
normalization are not built-in type operations.

### Member keys and indexed member types

```nupp
keyof T                 -- keys granting read capability
writekeyof T            -- keys granting write capability
T.[K]                   -- type read through K
writeof T.[K]           -- type accepted when writing through K
```

The dot before `[` is mandatory. `T[N]` already means a fixed C array and T2
extends `N` from a written numeral to an exact integer const expression, so
reusing bare brackets for member indexing would become ambiguous precisely when
const parameters landed:

```nupp
T[16]                   -- C array of 16 T values
T[Rows * Columns]       -- C array with a const-expression length
T.[16]                  -- member type at numeric key 16
T.[K]                   -- member type at key type K
```

This is a settled surface distinction, not parser lookahead based on whether a
name later resolves to a const parameter. C-array count expressions have the
closed integer const grammar; indexed member brackets contain a type.

For a finite set of named members, the key operators return a union of string
literal types. Instance methods are readable value members and participate;
static members, nested type names, annotations, metamethod contracts, and
constructor entries do not.

Indexers participate in key lookup. A broad readable string indexer makes
`keyof T` include `string`; a broad writable one does the same for
`writekeyof`. Numeric table keys require numeric literal types and the integer
const stage. C-array indexing is not member lookup and does not participate.

`T.[K1 | K2]` is the union of the readable member types. `writeof T.[K1 | K2]`
is their intersection, because a value written through an unknown union key
must be accepted by every possible destination. A missing capability reports
at the indexed type operator rather than quietly producing `never`.

### Mapped structural shapes

The first mapped form iterates a finite union of literal keys:

```nupp
{
    readonly [K in Keys]: Value
}
```

It may remap or drop a key:

```nupp
{
    readonly [K in keyof T as `${K}Changed`]:
        function(value: T.[K]): nil
}

{
    readonly [K in keyof T as
        match K
        when "password" then never
        else K
        end
    ]: T.[K]
}
```

The iteration binder is a singleton literal in the key and value expressions.
`never` as the remapped key drops the member. Two source keys remapped to one
name are rejected initially rather than silently unioning read types or
intersecting write types.

The first stage requires `readonly` or `writeonly` before the mapped field. A
key term blocked only on a declared generic binder remains a neutral mapped
shape and may cross an open generic interface. Once its binders are supplied,
the iterated key type must reduce to a finite literal union. A closed mapping
over broad `string`, `integer`, `any`, `unknown`, or another irreducible key
term is a local diagnostic. Mapped indexers and capability-preserving
transforms are deferred.

The result is an ordinary interned structural shape. It carries no trace of the
mapping operation after closed reduction and receives no nominal identity or
runtime artifact.

## Shared semantic type vocabulary

Reflection and the finite structural operators must not independently decide
what a member is. They use one checker-owned, immutable semantic view:

```text
members(T) -> {
    ordered: [
        {
            name,
            readType?,
            writeType?,
            declarationKind,
            definition?,
            annotations
        }, ...
    ],
    readIndexer?:  {keyType, valueType},
    writeIndexer?: {keyType, valueType}
}
```

The view is internal semantic data, not the mutable tables on `types.Nominal`
and not the public `TypeInfo` schema. Its rules cover shapes, records,
interfaces, structs, generic nominal applications, intersections, const views,
and gradual table types exactly once.

Consumers project it differently:

- member access asks for one read or write capability;
- `keyof` and `writekeyof` project key types;
- indexed member types project value types;
- mapped shapes enumerate finite entries;
- reflection serializes the public descriptor subset;
- documentation and future derives may retain declaration order and
  annotations.

Metamethods, static members, nested types, associated-type requirements, and
constructors remain separate semantic categories even if a future `TypeInfo`
descriptor exposes them. They never become ordinary `keyof` results merely
because reflection can see them.

The member view owns no evaluator and performs no user-defined computation. It
is a total structural query over a type the checker already resolved.

## Type terms and reduction

### Current baseline

- Structural types are content-addressed and compare by object identity.
- A generic alias stores an interned `body: Type` containing its symbolic type
  and pack binders.
- `generics.rebind` replaces named binders and preserves unmapped ones.
- `generics.materialize` replaces named binders and fills unmapped ones with
  `any` at an inference boundary.
- Applying a generic alias materializes its body directly.
- Recursive aliases are rejected as NUPP2115.
- Module type fingerprints number binders by encounter position rather than
  name.
- String and boolean literal types are source-spellable; numeric singleton
  types exist internally but are not accepted by the type grammar.

### Representation

Introduce two immutable, interned term sorts. A **const term** is a value from
one of the closed const domains:

```text
ConstLiteral(domain, value)
ConstVar(domain, identity)
ConstOp(operation, operands)
```

A **type term** is an ordinary interned type or one `types.Neutral` variant
whose `op` names the type-level operation blocked on an unresolved binder:

```text
Singleton(constTerm)
KeyOf(type, capability)
MemberAt(type, key, capability)
TypeMatch(scrutinee, distribution, arms)
Template(parts)
MappedShape(capability, keys, keyTerm, valueTerm)
AliasCall(aliasIdentity, typeArgs, constArgs, packArgs)
```

These are seven operations, not seven new `Type.tag` values. The ordinary type
algebra gains one `tag = "neutral"`; the reducer owns the exhaustive `op`
dispatch. This limits the change to consumers that must distinguish an
ordinary type from an unreduced term, while still requiring the explicit
consumer audit in T1.

Templates and const match patterns consume const terms and produce type terms.
Const terms never enter `types.Type`, ordinary assignability, or runtime value
packs merely because both sorts can ultimately mention a string literal.

Patterns and match arms use immutable interned records with binder-position
identity. They are semantic terms, not CST nodes: they contain resolved nominal
identities and interned child types, never source tokens or scope tables.
Source locations live in checker metadata for diagnostics.

Closed constructors reduce immediately. An open constructor interns a neutral
term. The same open term with the same binder identities is the same object.
Closed reduction returns an existing ordinary `Type` whenever possible, so
relations and member access do not grow alternate representations of a shape,
union, or function.

Do not make reduction a flag on substitution. It is a third named operation:

```text
rebind(type, bindings)       preserve every unnamed binder
materialize(type, bindings)  fill every unnamed binder with any
reduce(type, bindings)       rebind, then normalize decidable neutral terms
reduceConst(term, bindings)  normalize one closed const-domain expression
```

Rebinding walks neutral children without choosing an arm prematurely.
Materialization is still the call-inference policy and does not acquire
reducer semantics by accident. Generic alias application invokes `reduce`
after binding all supplied type, const, and pack arguments.

### Normal forms

Before a type participates in assignability, member lookup, hover display, or a
closed exported interface, it is reduced to weak-head normal form: the outer
operator is either an ordinary type constructor or a neutral blocked on an
open binder. A relation asks for deeper normalization only where it descends.

Two identical open neutral terms relate by identity. Different blocked terms
do not become compatible merely because neither can reduce yet; the relation
may use a declared generic bound when that proves the answer and otherwise
reports the same unsatisfied relation it would for two unresolved structural
types.

This avoids eagerly expanding every mapped field or recursive arm when a
shallow question can answer first. Closed mapped shapes, key unions, indexed
types, and templates nevertheless normalize fully before crossing a module
boundary.

The reducer is pure, but its memo key cannot contain dependencies learned only
by running it. Lookup has two levels:

```text
key = interned term identity
    + canonical binding identities
    + reducer semantic version

entry = reduced normal form
      + [{semantic dependency identity, fingerprint}, ...]
```

Reduction records every nominal member view it inspects and stores those
fingerprints beside the result. A lookup validates the recorded fingerprints
against the current project environment before returning the normal form; a
changed or missing dependency recomputes and replaces the entry. The query
engine records the same identities as dependency edges for ordinary
invalidation and observations.

Neutral term interning may use the process-global type arena because the term
is immutable structure. Dependency-sensitive reduction results may not: their
memo belongs to the checker/project environment or a revisioned query cache.
This distinction prevents a long-lived LSP from returning a stale hover merely
because a structurally identical neutral survived in the global arena. No
cache entry contains a CST node, scope, source offset, diagnostic sink, or
mutable nominal member table.

### Open exported types

A generic exported alias may necessarily contain neutral terms:

```nupp
type api.Events<T> = {
    readonly [K in keyof T as `${K}Changed`]:
        function(value: T.[K]): nil
}
```

Its interface stores the canonical symbolic term, with binders numbered by
position. A closed application stores or fingerprints its reduced result. The
written spelling is retained for documentation but is never the semantic cache
key.

Changing a dependency whose members an open term may inspect changes the term's
dependency fingerprint. Changing a dependency and obtaining the same reduced
closed result permits the normal incremental cutoff. A body-only edit remains
irrelevant.

### Alias hoisting and guarded self-reference

The current resolver hoists an alias name but waits to resolve its body. A
second lookup while `resolvePendingAlias` is resolving that body reports the
recursive-alias case of NUPP2115 and installs `any`. Reducer-side cycle checks
cannot make recursion legal while that name-level guard discards the reference
first.

T1--T4 leave this behavior unchanged. T5 changes alias declaration and
resolution in a controlled order:

1. Hoisting creates a stable alias header containing declaration identity,
   visibility, and type/const/pack binder signatures before resolving the body.
   It contains no partially resolved body and is not an inhabitable `Type`.
2. The type resolver tracks whether it is resolving a result beneath a
   `match` arm. Merely appearing in the scrutinee, pattern, mapped key, or an
   unconditional child does not qualify.
3. A reference from a qualifying arm to the alias currently being resolved
   becomes `AliasCall(headerIdentity, arguments)` instead of recursively asking
   for its unfinished body.
4. Any other self-reference receives the new recursion-specific diagnostic.
   It is never replaced silently by a neutral call.
5. Successful body resolution seals the header with its canonical term and
   fingerprint. A failed body poisons outstanding calls for that check and
   reports at their use sites without publishing a partial interface.
6. The first recursive stage permits direct self-recursion only. Mutually
   recursive alias headers remain illegal until a separate need and cycle model
   are specified.

The alias header identity, not body object identity, keys `AliasCall` and the
active reduction set. The exported interface fingerprints the sealed body, so
changing an arm invalidates users even though the declaration identity remains
stable.

## Semantics at gradual boundaries

The reducer must not inherit TypeScript's historical edge behavior by accident.
The initial rules are:

| Operation | `any` | `unknown` | `never` |
| --- | --- | --- | --- |
| `keyof`/read index | `any` | no known key/error | `never` |
| write key/index | `any` | no known key/error | `never` |
| ordinary match | `any` | match if provable | normal matching |
| `match each` | `any` | match if provable | `never` |
| mapped keys | rejected as broad | rejected as broad | empty shape |
| template construction | `string` | blocked/error | `never` |

`any` stays gradual; an operation depending on its structure normally answers
`any` rather than selecting an arbitrary arm. `unknown` reveals nothing until
constrained or matched by a pattern that is provably valid for all unknown
values. `never` distributes to no cases and contributes no key.

A type parameter's bound may answer a finite structural query inside its body,
as existing member access uses a bound. The result remains expressed in the
parameter where necessary: `T.[K]` does not become the bound's field type if the
actual argument may refine it covariantly.

These rules receive focused tests before public utility aliases are added to
the prelude.

## Termination and resource limits

### Finite stages

Stages before recursive aliases are terminating by construction. They still
need size limits because Cartesian products and mapped unions can allocate
large results:

- maximum union members produced by one reduction;
- maximum fields in one mapped shape;
- maximum template Cartesian product;
- maximum nested finite reducer nodes visited for one requested normal form;
  and
- maximum diagnostic rendering depth.

These are documented compiler constants, participate in the reducer semantic
version where they affect accepted programs, and are not source-level knobs.
A limit diagnostic identifies the operator and its input cardinalities.

### Recursive stage

Recursive aliases remain NUPP2115 through the finite milestones. Their later
admission requires all of:

1. A T5 proposal names at least two real dependent API workloads that finite
   matching cannot express. Multi-segment routes may count as one; the second
   must be named and characterized before T5 starts. A type-level PEG
   interpreter does not count.
2. A memo key of alias identity plus canonical type, const, and pack arguments
   and reducer semantic version, with post-reduction dependency fingerprints
   stored and validated as specified above.
3. Detection of an identical active key as non-progressing recursion.
4. Separate depth, total-reduction-step, result-member, and term-allocation
   budgets.
5. Cancellation polling inside the synchronous reducer for LSP requests.
6. A bounded expansion trace showing alias definitions and instantiated
   arguments.
7. Benchmarks for check, completion, hover, and edit invalidation on worst-case
   accepted and rejected inputs.
8. No regression in comptime C4 work; the two evaluators retain separate limits
   and observations.

Only a recursive reference reached beneath a `match` arm is considered in the
first recursive proposal. At T5, every recursive-alias case moves out of the
NUPP2115 family and receives a dedicated code in the type-reduction subrange:
unguarded self-reference, unsupported mutual recursion, an identical active
key, and an exhausted budget are facets of that stated rule. A proof of
syntactic structural decrease is not required—the budget is authoritative—but
obvious same-argument recursion is diagnosed immediately.

The reducer remains in process. Exceeding a limit is an ordinary deterministic
type diagnostic, not a worker failure and not a reason to invoke comptime.

## Const inference and runtime erasure

A const parameter is universally checked like a type parameter. The function
body is checked once with a symbolic `ConstVar`; calls do not compile or cache a
specialized body.

At a call, a const binder collects candidates only from parameter positions
whose declared type contains that binder. All candidates must be the identical
known value. Unlike ordinary type unification, two different values do not
union:

```nupp
local function same<const S: string>(left: S, right: S): nil

same("x", "x") -- S = "x"
same("x", "y") -- conflicting const inferences for S
```

An unbound const parameter is an error, not `any`: there is no unknown value to
substitute while preserving the promise that it was compile-time-known.

The runtime signature remains the ordinary Lua parameter list. Generic and
const binders erase. A const parameter may influence checking and generated
static constructs already represented in the type, such as a fixed C-array
length, but it does not authorize constant-folding the runtime argument or
cloning the function body.

## Diagnostics and tooling

Reserve a new diagnostic subrange when implementation begins; do not reuse
NUPP24xx, which belongs to comptime. Required diagnostic classes are:

- a const argument or inference candidate is not compile-time-known;
- const candidates conflict;
- a const operation is outside its domain or overflows;
- no type-match arm is decidable for a required closed term;
- a template match has adjacent or otherwise ambiguous inferred segments;
- a member key lacks the requested read or write capability;
- a mapped key is broad, nonliteral, duplicated after remapping, or over limit;
- finite reduction exceeds a size/visit limit;
- recursive reduction is unguarded, mutually recursive, cycles, or exceeds
  depth/step/allocation limits;
- an open neutral term reaches a boundary that requires a closed type.

T1--T4 retain the current NUPP2115 recursive-alias diagnostic because all
recursion is still forbidden. T5 migrates that case to the new dedicated code
and adds a `nupp explain` rule with worked guarded, unguarded, cycling, and
budgeted examples. NUPP2115 remains available to the other annotation/type
family cases that already share it.

Hover shows the written alias and a shortened reduced form. A separate verbose
view may show a bounded reduction trace; ordinary hover must not eagerly reduce
an expensive recursive term merely to decorate it.

Go-to-definition on `T.[K]` reaches the concrete member when both operands are
closed and unique. References and rename operate on source declarations and
literal member names, never on generated mapped-field tokens. Completion on a
closed mapped shape exposes its reduced fields; completion on an open term uses
the bound's known members without forcing a speculative instantiation.

`--json` diagnostics include the operator, normalized inputs, budget consumed,
and bounded expansion frames where present. Formatter and syntax tooling only
need the CST spellings; they never receive synthetic source for a reduced type.

## Incremental and fingerprint requirements

Type-level computation makes exported type meaning a reduction result, so
interface identity must include semantics rather than spelling:

1. Add canonical fingerprints for const binders by binder position and domain.
2. Fingerprint open neutral terms structurally, including arm order, patterns,
   capabilities, and reducer semantic version.
3. Fingerprint closed terms by their reduced ordinary type.
4. Record every nominal member view inspected while reducing a term.
5. Include exported nominal semantic member fingerprints rather than relying
   only on declaration names when a reducer can enumerate their members.
6. Preserve early cutoff when reevaluation after a dependency edit produces
   the identical normal form.
7. Count reductions, memo hits, limit failures, and invalidated dependent
   interfaces in the existing query observation machinery.

This work shares reflection's semantic type fingerprints. It is implemented
once under the semantic member view and consumed by both features. Neither
consumer defines the other's cache format.

## Grammar work

The type grammar gains, in dependency order:

```text
genericparam  = Name ["..."] ["is" type]
              / "const" Name ":" constdomain

typeprimary   = ... existing forms ...
              / "keyof" typeprimary
              / "writekeyof" typeprimary
              / "writeof" indexedtype
              / typematch
              / templatetype
              / mappedshape

posttype      = typeprimary *postfix
postfix       = "?" / "*" / carraysuffix / memberindex
carraysuffix  = "[" ("?" / constintexp) "]"
memberindex   = ".[" type "]"
indexedtype   = typeprimary *postfix memberindex

typematch     = "match" ["each"] type-or-const
                1*("when" typepattern "then" type)
                ["else" type] "end"

mappedfield   = ("readonly" / "writeonly")
                "[" Name "in" type ["as" type] "]" ":" type
```

This is illustrative ABNF, not a patch to `docs/grammar.abnf`. Its decided
precedence and disambiguation rules are:

- optional, pointer, C-array, and member-index postfixes apply left to right in
  one chain, preserving Nupp's existing postfix rule;
- `T[constintexp]` is always a C-array suffix, while only `T.[type]` is an
  indexed member type;
- `writeof T.[K]` binds to the complete indexed member type;
- `keyof`/`writekeyof` bind tighter than `&` and `|`;
- a mapped field is recognized by `Name in` after `[`, while an existing
  indexer contains a type followed by `]` and `:`; and
- a backtick token in type position selects template-type parsing, leaving the
  runtime interpolated-string grammar unchanged.

T2 updates the public C-array grammar from a written `Numeral` to
`constintexp`; it does not rely on semantic binder lookup to decide which
bracket form was parsed. C-array patterns initially match `?` or an exact
written const count and infer only the element. Inferring a count from
`infer Item[infer N]` is deferred until it has a concrete use and its own
unambiguous pattern grammar.

## Implementation stages

### T0: semantic vocabulary and baselines

- Specify and implement the immutable semantic member view.
- Move existing read/write member lookup to it without changing behavior.
- Add semantic member fingerprints suitable for reflection and reducer dependencies.
- Commit route, event, capability, template-product, and invalidation fixtures
  as rejected/pending acceptance cases.
- Measure current check, hover, completion, and one exported-type edit.

Exit test: existing member access, relations, module hashes, and fixpoint are
unchanged; reflection consumes the view without learning reducer concepts.

### T1: finite structural operators

- Add `keyof`, `writekeyof`, indexed member types, and `writeof`.
- Add explicit-capability finite mapped shapes without remapping.
- Add neutral term interning, weak-head reduction, memoization, and
  fingerprints.
- Inventory every `Type.tag` consumer and record one policy for `neutral`:
  reduce, preserve structurally, or reject as an internal leak. Cover at least
  relations, generic rebinding/materialization, rendering, fingerprints,
  ownership/affinity, narrowing, method slots, documentation, LSP semantic
  queries, optimization, and code generation. Put the inventory in a focused
  test or checked table so a later consumer cannot silently omit the tag.
- Reject broad mapped keys and enforce output limits.

Exit test: readonly and writeonly views reduce correctly across shapes,
records, interfaces, intersections, indexers, bounds, and module boundaries;
no recursive alias is accepted; every exhaustive type consumer has an asserted
neutral policy; and no neutral reaches ownership, optimization, or codegen at a
boundary requiring a closed type.

### T2: const parameters and literal domains

- Add const binder identity, generic application arguments, and call inference.
- Add source-spellable numeric literal types and the closed exact-integer const
  expression floor.
- Extend C-array suffix counts from a written numeral to `constintexp`; preserve
  bare `T[N]` for C arrays and require the decided `T.[K]` spelling for every
  indexed member type, numeric keys included.
- Carry const arguments in nominal and alias instantiation identity.
- Prove erasure and no runtime specialization.

Exit test: `Matrix<float, 4, 4>` and literal function inference work; dynamic
arguments, conflicts, overflow, and unbound const parameters fail locally;
module fingerprints distinguish values but not binder renames; and `T[16]`,
`T[Rows * Columns]`, and `T.[16]` parse and resolve to their three specified
forms without semantic lookahead.

### T3: nonrecursive match and templates

- Add `match`, `infer`, explicit `match each`, and open neutral matches.
- Add template construction and unambiguous pattern decomposition.
- Add key remapping and dropping through `never`.
- Keep NUPP2115 unchanged for every recursive alias.

Exit test: finite event-name adapters and one-segment route extraction work;
ambiguous templates, accidental distribution, remap collisions, and product
limits have focused diagnostics.

### T4: dependent API acceptance

- Add the recursive-looking route workload in an explicitly bounded,
  hand-unrolled form first and measure its useful ceiling.
- Port two real library APIs that currently duplicate field or literal names.
- Record interface invalidation and LSP latency against T0.
- Decide whether finite unrolling is sufficient or recursive aliases have
  earned a proposal.

Exit test: at least two APIs remove duplicated type declarations, their error
messages name source concepts rather than reducer internals, and normal edits
remain within the recorded latency budget.

### T5: recursive aliases, conditional

This milestone does not follow automatically. It exists only after T4 records
a keep decision satisfying §Recursive stage.

- Predeclare alias headers and teach `resolvePendingAlias` to produce an
  `AliasCall` only for a direct self-reference beneath a match arm; keep
  unconditional and mutual references out as specified in §Alias hoisting and
  guarded self-reference.
- Add active-key cycle detection, budgets, cancellation checks, observations,
  and expansion traces.
- Move recursive aliases from NUPP2115 to the dedicated reduction diagnostic
  and add its `nupp explain` examples.
- Land the complete multi-segment route example.
- Fuzz recursive terms and adversarial union/template growth.

Exit test: accepted routes reduce predictably; exact cycles fail immediately;
large progressive reductions stop at deterministic budgets; cancellation keeps
the LSP responsive; no type-level PEG interpreter or arithmetic stunt is added
as a success case.

## Verification

Every stage runs:

- parser/CST round-trip and formatter fixtures for new syntax;
- unit tests for interned identity, rebinding, materialization, and reduction;
- relation tests proving no neutral leaks into closed comparisons;
- capability tests for readonly, writeonly, const, intersections, and indexers;
- generic inference tests separating type and const binders;
- module-interface and incremental invalidation tests;
- LSP hover, completion, definition, rename, and cancellation tests;
- JSON diagnostic schema fixtures;
- the complete `./bin/nupp test`; and
- `./bin/nupp fixpoint`.

Performance gates record cold and warm checks, one body-only edit, one exported
type-body edit, hover over an open alias, completion on a closed mapped shape,
and the largest accepted reduction. A feature stage does not land by raising a
limit until its benchmark passes.

## Open questions

- Whether the public names should be `keyof`/`writekeyof` and `writeof T.[K]`,
  or a more symmetric capability syntax. The semantics above are fixed before
  spelling bikeshedding.
- Whether mapped fields should eventually preserve source capabilities, and how
  a remapped key with separate read/write types states that intention.
- Whether broad-key mapped types should later lower to indexers.
- Whether const generic arguments may read immutable exported fields across a
  module boundary, or begin with literals and local consts only.
- Whether exact integer arithmetic belongs in T2 or should wait for a concrete
  value-sized generic other than `Matrix`.
- Whether one finite `pack.concat` operator earns a separate proposal for typed
  parser combinators and ownership-preserving adapters.
- Which second recursive workload must join multi-segment routes before T5 can
  be proposed. T1--T4 do not depend on answering this.

None of these changes the phase decision: type-to-type reduction is a
checker-native feature, and comptime remains downstream, closed, and separate.
