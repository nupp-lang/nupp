# User-defined affine types

Status: historical. The affine constructor and exact cleanup identity landed,
but [lua-ownership-capabilities.md](047-lua-ownership-capabilities.md)
superseded the proposed global `Owned`, `Transfer`, and `Drop` policy. Current
source uses `affine(T, cleanup)`, `affine(T)`, and concrete resource names.

## Decision

Nupp will make affinity a public type-system facility and define ownership policy
with ordinary Nupp declarations in the prelude. The compiler will understand the
`affine(Representation[, cleanup])` type constructor, affine introduction and consumption, and automatic
lexical destruction. It will not recognize `Owned`, `Drop`, or `Transfer` by name.

The original target prelude was:

```nupp
global interface Drop
    drop: nosuspend function(takes self: self): nil
end

local function dropDefault<T is Drop>(takes value: T): nil
    value:drop()
end

global type Owned<
    T,
    const cleanup: function = dropDefault
> = affine(T, cleanup)

global type Transfer<T> = affine(T)
```

This gives the existing useful spelling without a built-in constructor:

```nupp
local function openFile(): Owned<File>
    return new File(fd = open_fd())
end

cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)

local function allocate(): Owned<voidptr, free>
    return malloc(128)
end
```

`Owned<File>` selects the generic `dropDefault` declaration. Instantiating that
terminal for `File` proves the ordinary structural bound `File is Drop`.
`Owned<voidptr>` therefore fails, while `Owned<voidptr, free>` replaces the default
and succeeds. There is no conditional rule hidden in `Owned` and no dependent
function-parameter type.

A deliberately terminal-less owner uses the separately defined `Transfer<T>`:

```nupp
local function beginRequest(): Transfer<voidptr>
    return request_begin()
end
```

This plan supersedes the built-in-`Owned` and inherited-`@drop` decisions in
[`ownership-in-types.md`](034-ownership-in-types.md),
[`cleanup-registration.md`](035-cleanup-registration.md), and the corresponding parts
of [`automatic-destruction.md`](002-automatic-destruction.md). Const function identity,
`takes`, automatic destruction, borrow checking, pinned values, and cleanup failure
aggregation remain in force except where this plan generalizes their implementation.

## The public primitive

An affine declaration has a generic clause, one representation type, and zero or one
terminal:

```nupp
[local|global] type Name<...> = affine(Representation [, FunctionConst])
```

Module-qualified declarations use the same ownership and visibility rules as records,
interfaces, and aliases:

```nupp
type resources.Handle<T, const cleanup: function> = affine(T, cleanup)
```

Every generic facility already admitted on a type declaration is admitted here,
including type and const parameters, bounds, trailing defaults, module publication,
incremental fingerprints, and cross-module application. A terminal may name a
function declaration directly or a `const function` binder. It may not be a string,
closure value, computed expression, or unresolved name.

An affine declaration is transparent rather than nominal:

- its runtime representation is exactly `Representation`;
- declaring or instantiating it allocates no table, wrapper, tag, vtable, or cleanup
  slot;
- it introduces no runtime constructor;
- its static identity contains the canonical representation, terminal declaration
  identity when present, and intentional absence of a terminal;
- two transparent affine declarations instantiated with the same representation and
  terminal describe the same type; and
- changing only the alias name does not change assignability or the generated ABI.

Different terminals remain different types even when their function signatures are
equal. Function identity is the policy, not merely the ability to call some
structurally compatible function.

This is a general facility. A package has exactly the prelude's authority:

```nupp
type Locked<T, const unlock: function> = affine(T, unlock)

type MustForward<T> = affine(T)
```

No parser, resolver, checker, generator, documentation, or LSP path may branch on the
spelling `Owned`, `Transfer`, or `Drop` after migration.

## Compiler representation

Rename the resolved ownership qualifier from `Owned` to `Affine`. Its semantic data
is the erased representation, an optional closed or symbolic terminal identity, and
whether terminal absence was intentional. The `owned` tag, `types.Owned`, and
`types.owned` constructor become the general `affine` tag, `types.Affine`, and
`types.affine` constructor.

The declared type records one terminal identity, not a nominal default and not an
ordered list. A separate lowering cleanup plan may contain several steps for an
aggregate record or closure. Keeping these concepts separate prevents a user-declared
affine type from acquiring the field-composition behavior of a compiler cleanup plan
as part of its public identity.

Interning uses:

```text
affine(representation identity, terminal const identity | transfer-only)
```

It does not include the affine declaration's name. Generic aliases and affine
declarations substitute through the ordinary generic materializer. Relations,
unions, intersections, packs, optionality, narrowing, field projection, FFI peeling,
fingerprinting, reflection, and display must handle `Affine` as a first-class
transparent qualifier rather than asking whether a type name was `Owned`.

`ownershipKind`, raw-representation queries, automatic-owner registration, and move
state should answer from this descriptor. Once those queries are general, remove any
remaining code that uses `affineResource` as a proxy for a nominal type's declaration
history. A nominal is affine because its constructed value contains affine fields or
is wrapped in a declared affine type, not because an annotation mutated the nominal.

## Terminal contract

For a closed application, the terminal must be callable exactly once with the
representation as a consuming argument. Its required shape is:

```nupp
nosuspend function(takes Representation): nil
```

Ordinary generic inference and bounds decide whether a generic terminal is callable.
This is what makes `dropDefault<T is Drop>` enforce `Drop` only when it is selected.
There is no rule that every explicit cleanup target implement `Drop`.

The terminal may raise. Automatic cleanup retains today's failure behavior: the first
failure is primary, later cleanup failures are suppressed, and independent remaining
obligations are still attempted. `nosuspend` is required because cleanup runs at
lexical and non-yieldable boundaries; infallibility is not a type-system requirement.

The result is `nil` because automatic destruction has nowhere to deliver a result.
The terminal consumes its argument even when it raises. A terminal may compose
several operations with `nupp.attemptAll`; an affine type still records one terminal,
so failure ordering is authored by an ordinary function rather than a second type
language.

An open application retains the representation and symbolic const-function term.
Terminal validation is deferred until substitution closes enough of both sides for
ordinary call compatibility to answer. A declaration with an inherently incompatible
closed terminal reports at the `terminal` clause; a bad application reports at the
application and relates the terminal declaration.

Const-function resolution must therefore be made fully compositional. The existing
resolver accepts a named declaration at a generic application but the built-in
`Owned` path does not accept a symbolic `constVar` in its second position. Remove that
one-off path. The general affine declaration stores and substitutes the same
`ConstTerm` used by every generic declaration, and resolves a declaration key only
when the term is closed.

## `Drop` is ordinary structural policy

`Drop` is a prelude interface, not a compiler-known marker. Structural conformance
uses the existing exact member rules with `self` substitution:

```nupp
local record File
    fd: integer

    function drop(takes self): nil
        close_fd(self.fd)
    end
end

local function openFile(): Owned<File>
    return new File(fd = open_fd())
end
```

Writing `is Drop` is optional when structural conformance can already prove the exact
member. An explicit declaration remains useful as documentation and for checking the
record at its declaration rather than at its first `Owned<T>` application.

A type with a differently named canonical operation can forward once:

```nupp
local record Session
    function close(takes self): nil
        close_session(self)
    end

    function drop(takes self): nil
        self:close()
    end
end
```

A foreign pointer, shared primitive representation, or resource with several valid
terminals instead uses `Owned<T, cleanup>`. The compiler never searches a nominal for
an annotated default and never mutates a project-wide terminal list.

### Prelude source and bootstrap

The definitions above must live in checked Nupp source. `Drop`, `Owned`, and
`Transfer` are published in the prelude declaration surface, while `dropDefault` has
an ordinary Nupp body in a bundled prelude implementation unit. The compiler builds
that unit through the same parser, checker, and generator as package source and loads
or embeds its generated Lua before a user module can discharge an owner.

Do not hand-write `dropDefault` in the generator, synthesize its signature in the
resolver, or reserve a runtime key for it. Its cleanup-registry entry and stable
identity arise from compiling the function declaration exactly as they would for a
package terminal. The exported `Owned` declaration seals the private declaration
reference into its generic default, so the helper need not become a user-visible
global.

Bootstrapping may temporarily retain the old built-in while the new compiler learns
to compile this prelude source. The final fixpoint must use the source-defined
declaration and adapter on both sides; the tracked bootstrap is only a migration
compiler, not an alternate semantic implementation.

## Introduction is not an implicit coercion

Representation equality at runtime does not make `Representation` a subtype of its
affine wrapper. An unrestricted coercion would allow two obligations to be minted
from one aliased value:

```nupp
local raw = acquire_raw()
local first: Owned<Handle, close> = raw
local second: Owned<Handle, close> = raw -- must never be admitted
```

The checker applies the existing ownership-origin proof to every affine type rather
than to the `owned` tag. An affine value may be introduced only by:

- a fresh result whose declared result type is that affine application;
- a cdef result or successful cdef output whose contract is that affine application;
- construction of a record field whose supplied expression already has the same
  affine type;
- transfer from the identical affine type; or
- explicit adoption in `unsafe`.

A fresh result may be a constructor expression, a call whose declaration promises the
affine result, or another expression already proved fresh by the existing origin
rules. Merely annotating a local, assigning a shared value, casting, or returning a
borrowed/global value cannot manufacture affinity.

Unsafe adoption becomes a public operation over any affine declaration rather than
an `Owned` intrinsic. The target spelling is:

```nupp
local owner = unsafe adopt raw as Owned<voidptr, free>
```

It consumes no existing obligation and asserts that `raw` denotes a fresh unmanaged
resource. The inverse operation consumes an affine value and exposes its
representation without running the terminal:

```nupp
local raw = unsafe release owner
```

The final keywords may be settled with the parser work, but the operations must be
language-wide, require `unsafe`, preserve the target's exact representation type, and
replace the privileged type behavior of `nupp.fromRaw` and `nupp.intoRaw`. They may be
temporarily lowered from those calls during migration.

## Consumption and lexical destruction

Manual consumption is a public operator:

```nupp
drop owner
```

It consumes any affine value, resolves the terminal carried by its type, and invokes
that terminal with the erased representation. It reports an error for a terminal-less
affine type. A `Transfer<T>` must instead be passed to a consuming parameter, returned,
stored into another live affine location, or released in `unsafe`.

`drop` is syntax rather than a prelude function. Under Nupp's erased, check-once
generic model, an ordinary function cannot recover an arbitrary caller's const
terminal at runtime without monomorphization or a hidden dictionary. A public
operator states the irreducible type-directed operation honestly and gives every
affine declaration equal access to it. `nupp.drop(value)` becomes a migration spelling
and is then removed as an intrinsic-looking library call.

Automatic lexical destruction uses the same operation selected statically. Scope
exit, structured control flow, returns, errors, and cleanup-region lowering remain as
they are; they query the general affine descriptor instead of `Owned.cleanups`.

Records containing affine fields remain affine aggregates by a general composition
rule. Their synthesized terminal consumes live affine fields in reverse declaration
order and attempts all independent fields after a failure. This rule applies equally
to `Owned`, `Locked`, `MustForward`, and any other affine field type. It is not
conditional on a nominal's `affineResource` or on inherited `@drop` metadata.

Affine closures created by `takes` captures follow the same aggregate rule. Their
generated terminal is a language-generated affine descriptor, not a method named
`__drop` that receives privileges unavailable to declared affine types.

## Function identity and runtime linking

Keep the existing const-function declaration identity: origin, declaration name, and
disambiguating ordinal form the stable key used by type identity, incremental
fingerprints, hover, definition, references, and runtime linking. An affine terminal
uses that mechanism directly.

The cleanup registry may remain as a code-generation strategy for terminals declared
in another module. Registration must be driven by general references from affine
descriptors, not by `@drop`, `Owned`, or a mutation on a nominal type. A function
declaration referenced as any affine terminal is published at the declaration-token
bridge already used by `Owned<T, cleanup>`.

The prelude's private `dropDefault` needs a stable declaration identity sealed into
the exported `Owned` declaration's default argument. Consumers need not be able to
name it. Omitting the default should render as `Owned<T>` in diagnostics and tooling;
the canonical type still contains the resolved terminal identity.

Generic defaults on affine declarations use the ordinary generic-default machinery.
If generic alias defaults are generalized as part of the implementation, affine
declarations and aliases must share the same resolver rather than grow parallel
default substitution.

## Comptime construction

The declaration syntax is the primary open-generic facility. A comptime type function
whose arguments remain open cannot currently expose representation-specific affine
facts until it closes, so `Owned` itself should not be implemented as a type function.

Closed comptime construction must nevertheless have the same authority. Rename and
complete the currently undocumented unary `nupp.types.owned(T)` builder as a public
affine builder. Extend comptime parameters with the existing const-function domain:

```nupp
local comptime function MakeOwner(T: type, const cleanup: function): type
    return nupp.types.affine(T, cleanup)
end
```

Inside comptime, a function const is an opaque declaration-identity handle carrying
its checked signature and stable key. It is inspectable only through a closed,
read-only function-description API and is accepted by `nupp.types.affine`; it is not
a runtime closure and cannot be forged from a string. Open calls retain the ordinary
const term and execute when it closes.

The builder also admits deliberate terminal absence:

```nupp
nupp.types.affine(T) -- terminal-less and transfer-only
```

Blueprint validation reconstructs the same interned affine descriptor as declaration
syntax, including terminal identity and signature validation. Delete the present
behavior in which the type provider can construct an `owned` node with no terminal
metadata while the source `Owned` constructor follows a separate path.

This addition does not admit nominal generation. An affine result remains a
transparent structural type descriptor over an existing representation.

## C and ABI contracts

An affine wrapper preserves its representation's ABI. A cdef result or output may use
any affine declaration whose representation is a valid C type:

```nupp
cdef function allocate(
    size: uint64,
    out result: Owned<voidptr, free>*
): Success<int32, 0>
```

The cdef checker peels the general affine representation when emitting the prototype
and retains the affine contract for successful outputs. It must not recognize
`Owned`. A terminal used by a cdef contract is still an ordinary Nupp or cdef function
declaration with a const-function identity.

Borrowed results and pinned retention are not redefined by this plan. Their existing
special names must eventually be audited against the same principle: the compiler
should expose general lifetime and pinning facilities from which their prelude types
can be declared. That work is separate because neither is reducible to affinity plus
a terminal, and folding it into this migration would obscure the smaller ownership
decision.

## Removal of inherited `@drop`

Remove `@drop` after migrating the repository. In particular, delete:

- parsing and annotation targeting for `@drop`;
- `defaultDropOperations` and `affineResource` nominal metadata when it exists only
  to support annotated defaults;
- `addDefaultDropOperation`, `inheritedTerminals`, and project-wide nominal mutation;
- the hoisted scans that register member terminals before signatures resolve;
- method-cleanup descriptors used only to turn an annotated member into a terminal;
- multiple-default and missing-default diagnostics;
- documentation extraction and rendering special cases for `@drop`; and
- resolver branches that infer a bare `Owned<T>` terminal from a nominal.

Do not replace this machinery with a compiler-known `Drop` lookup. Bare `Owned<T>`
works solely because the prelude generic default names `dropDefault`, whose ordinary
generic bound and body use the ordinary interface.

An owning record's written cleanup method consumes its owned fields under the normal
rules for a `takes self` method. The checker no longer grants a body special field
discharge authority because it carries `@drop`; it grants authority because the
receiver is consumed. Every affine field must be moved, dropped, or transferred on
every path before the method returns, exactly as for any other consuming function.

## Migration

Migrate the repository in this order:

1. Add the affine declaration and general descriptor while retaining the old built-in
   constructor behind compatibility tests.
2. Define experimental prelude names backed by the declaration and prove they have
   identical erasure, ABI, move checking, cleanup ordering, and runtime linking.
3. Convert canonical resource types from `@drop` to an exact structural `drop` method.
   Existing `close`, `destroy`, `stop`, or `release` methods may be retained and called
   by a one-line `drop` method.
4. Convert resources without one canonical terminal to explicit
   `Owned<T, cleanup>` applications.
5. Replace `Owned<T, opaque>` with `Transfer<T>`.
6. Replace `nupp.drop`, `nupp.fromRaw`, and `nupp.intoRaw` with the public operators,
   retaining temporary diagnostics and whole-operation fixes for source migration.
7. Switch `Owned` to the prelude declaration and remove the resolver's
   `ownershipConstructors.Owned` branch.
8. Remove `@drop` registration, inherited defaults, nominal mutation, compatibility
   lowering, and obsolete diagnostics.

The source migration should be mechanical where possible. A fix for `@drop` on an
exact `takes self` method removes the annotation and renames or forwards the method to
`drop`. A fix for `Owned<T, opaque>` writes `Transfer<T>`. A free `@drop` function
causes bare applications of its resource type to name that function explicitly unless
the type gains a structural `drop` method.

There is no compatibility mode in which unresolved `Owned<T>` becomes terminal-less.
Failure to satisfy the default is an error; deliberate transfer-only ownership is
always written `Transfer<T>`.

## Tooling and documentation

The language reference and generated grammar must describe `affine(...)`, cleanup identity,
`drop`, unsafe adoption/release, `Drop`, `Owned`, and `Transfer` as separate layers:

- affinity and consumption are language semantics;
- terminal declaration identity is a const-generic facility;
- `Drop`, `Owned`, and `Transfer` are prelude source;
- automatic destruction is lowering over any affine type; and
- borrowing and pinning are related but independent lifetime facilities.

Hover and documentation show the authored affine declaration and its representation.
For a closed application they also show the selected terminal, including an omitted
default when requested by expanded detail. Go-to-definition on an explicit terminal
opens its function; on the defaulted `Owned<T>` it opens `Owned`, with a secondary
link to the sealed default terminal where that source is visible.

Rename and references treat a terminal as a semantic function reference. Renaming an
affine alias does not alter canonical type identity; renaming or replacing its terminal
does. Workspace symbols classify affine declarations as types, not constructors.

`./bin/nupp reference language` must compile examples of a default `Drop`, an explicit
C cleanup, a user-defined affine type, a transfer-only type, manual `drop`, and unsafe
adoption/release. Remove `@drop` from the annotation reference rather than retaining a
deprecated description after the migration completes.

## Verification

Focused checker tests must prove:

- users can declare and export their own generic affine types;
- the prelude `Owned` follows exactly the same resolver and checker path;
- `Owned<T>` accepts structural `Drop` and rejects a missing or inexact method;
- an explicit cleanup does not require `Drop`;
- generic cleanup functions are inferred and bounded normally;
- different function identities distinguish otherwise equal affine types;
- aliases with the same representation and terminal are interchangeable;
- terminal-less affinity is distinct from a missing or invalid terminal;
- arbitrary representation-to-affine assignment cannot mint an obligation;
- fresh results, cdef outputs, transfers, and unsafe adoption can introduce one;
- consumed, moved, overwritten, partially moved, captured, and discarded values keep
  today's affine diagnostics;
- automatic and manual destruction call the same terminal exactly once;
- terminals may raise, may not suspend, and cleanup aggregation attempts later
  obligations;
- affine aggregate fields are destroyed in reverse declaration order;
- exported defaults and explicit terminals survive module boundaries, incremental
  rechecks, cache reloads, and hot reload compatibility checks;
- cdef prototypes and generated Lua retain the representation ABI; and
- no type, table, cleanup slot, or wrapper is allocated at runtime.

Generation tests inspect the emitted Lua for direct local terminals and lazy
cross-module registry resolution. A user-defined affine type and prelude `Owned` with
the same terminal must generate equivalent cleanup paths.

Tooling tests cover parsing, formatting, semantic tokens, hover, definition,
references, rename, symbols, docs, and migration fixes. Repository-wide searches must
find no compiler branch on `Owned`, `Transfer`, or `Drop`, and no remaining `@drop`
annotation after the final phase.

Run focused ownership, type-level, cdef, generation, incremental, hot-reload, LSP, and
documentation suites during implementation. Finish with:

```sh
./bin/nupp test
./bin/nupp fixpoint
```

The fixpoint run is required because this changes parser, CST, type representation,
checker, generator, prelude declarations, and self-hosted compiler source together.

## Completion criteria

The work is complete when all of the following are true:

- `Owned`, `Drop`, and `Transfer` are written in checked prelude source;
- a package can define an affine type with the same capabilities;
- the compiler contains no name-based path for those prelude declarations;
- `@drop` and inherited terminal registration are gone;
- the only remaining ownership primitives are public affinity, consumption, origin
  proof, and lexical-destruction semantics;
- closed comptime code can construct the same affine descriptor through the public
  type API;
- manual and automatic destruction work for user-defined affine types;
- deliberate terminal absence is explicit and never inferred from failed resolution;
- generated representation and C ABI are unchanged; and
- the full suite and compiler fixpoint pass.
