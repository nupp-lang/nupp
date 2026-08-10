# Associated types

## Decision

A declaration may carry **type members**. An interface may declare one without
saying what it is, and every declaration that takes the contract has to say.
The member is projected with an ordinary dot — `T.Item` — and is erased
completely.

    interface m.Reader
        type Item

        function read(self): Item?
    end

    record m.Lines is m.Reader
        type Item = string

        handle: LuaFile

        function read(self): string?
            return self.handle:read("*l")
        end
    end

    function m.collect<T is m.Reader>(source: T): {T.Item}

This is one feature with two faces. Bound in a record, a type member is a
nested type alias — `m.Lines.Item` is `string`, reachable the way
`models.user.User` already is. Left unbound in an interface, it is an associated
type: a type the *implementor* chooses and the *user* reads back.

## Why not a type parameter

`interface Reader<T>` already expresses "a reader of T", so the question is
what associated types buy over it. Three things.

**A parameter is an input; an associated type is an output.** Nothing stops one
record from declaring `is Reader<string>` and `is Reader<integer>` both, so
`Reader<T>` cannot determine T from the implementor. `collect(source)` then has
nothing to infer T from. `type Item` makes Item a function of the implementor,
which is exactly the fact inference needs.

**Parameters propagate; associated types do not.** Every function that touches a
reader has to carry the parameter, whether or not it mentions the element type,
and each layer adds one. Nupp's compiler shows the shape of the alternative
already: `query.Q:define` types its callback `function(q: any, key: any): any`
because threading two parameters through the database, the definitions table and
every read was worse than giving up.

**They compose without arity.** An `Iterable` whose loop variables are a type
*pack* cannot be spelled as a parameter at all without fixing the arity at the
declaration.

Rust reached the same split for the same reason: `Iterator::Item` is associated,
`From<T>` is parameterized. The rule is whether the caller gets to choose.

## Syntax

**Declaring.** Inside a declaration body, a bare `type Name`. Members already
live on the declaration, so — like a field — it takes no `local`, `global` or
qualified path, and writing one is **NUPP2119**.

    interface m.Codec
        type Encoded              -- unbound: the implementor says
        type Decoded is m.Named   -- unbound, with a bound
        type Error = string       -- a default the implementor may keep
    end

**Binding.** `type Name = T` in the body of a declaration that takes the
contract. A default is inherited exactly as a default method body is: resolved
where it is written, replaced only by writing the member, and `@override` is
*not* required — a type member has no body to replace, so overriding one is
ordinary binding.

**Projecting.** `T.Item`, on a type parameter, on a concrete declaration, or on
`self`:

    m.Lines.Item                     -- string
    T.Item                           -- opaque inside a generic body
    function pos(self): self.Point   -- the receiver's binding, not the declarer's

Inside the declaring body the simple name works, the way a recursive `User?`
already does — and it means `self.Item`, not the interface's. That is the same
rebinding `self` already gets, so an implementor's inherited default method sees
its own binding.

**Constraining a projection.** Projections join the binder list, comma
separated. No new keyword:

    function joinLines<T is m.Reader, T.Item is string>(source: T): string

    function pump<R is m.Reader, W is m.Writer, W.Chunk is R.Chunk>(
        source: R, sink: W
    ): integer

The second form is why this belongs in the binder list rather than on a
per-parameter bound: the constraint relates two parameters and belongs to
neither.

**Packs.** A binder ending in `...` declares an associated *pack*, which is what
lets an interface describe Lua's generic-for without fixing the loop arity:

    interface m.Iterable
        type Values...

        function iterate(self): function(): Values...
    end

    record m.Entries is m.Iterable
        type Values... = (string, integer)
    end

## Semantics

**Resolution is second-pass.** A projection never binds a type parameter.
Ordinary unification binds the heads from the argument types; projections are
then substituted and checked. A projection whose head stays unbound substitutes
to `any`, which is what an unbound parameter already does — a partly-inferred
call stays gradual rather than wrong.

**An unresolved projection is opaque, with its bound's members.** Inside
`<T is m.Codec>`, `T.Decoded` reads exactly the members of `m.Named`, the same
way `T` itself reads the members of its bound with `self` specialized back.
Symmetric, and no new rule to learn.

**Identity interns.** Types are content-address interned, so a projection is a
deferred type interned by (head identity, member name) and two spellings of
`T.Item` are one type. Concrete projections normalize to the bound type at
intern time, so `m.Lines.Item` and `string` are the same interned type and
nothing downstream sees a projection at all.

**Bounds are checked at instantiation**, alongside the existing bound check, and
violating a projection bound is **NUPP2116** with the projection named.

**Variance is invariant.** Generic nominals are deliberately covariant in their
arguments, for compatibility with array covariance. A type member is not an
argument, and there is no compatibility story asking for the unsoundness, so
`is` on a projection is subtyping and binding is equality.

**Erasure is total.** `type Item = string` emits nothing; an interface that adds
only type members still has no runtime presence. Nothing about a type member is
observable at run time, which has one consequence worth stating outright: a
`matches` refinement cannot test one, so an interface with an unbound type
member and a refinement is refused. The refinement would claim to identify
values it cannot distinguish.

## What we would use them for

Ordered by how much they would change code that exists today.

**The query database.** `query.Q:define` takes
`fn: function(q: any, key: any): any` and `Q:get` returns `any`, so every
consumer in the incremental layer casts. A query becomes a declaration carrying
its own key and value:

    interface compiler.Query
        type Key
        type Value

        function compute(self, q: query.Q, key: Key): Value
    end

    record compiler.ParsedFile is compiler.Query
        type Key = string
        type Value = cst.Chunk
    end

`Q:get(ParsedFile, path)` then returns a `cst.Chunk`, and the early-cutoff `eq`
is typed `function(a: Value, b: Value): boolean` rather than taking two `any`.
The runtime stays a name-keyed table; only the surface gains types.

**Iteration.** `Iterable` with `type Values...` types `for` over a user
declaration once, for every arity, instead of a metamethod contract per shape.
This is the case Nupp is best positioned for, because type packs already exist
and carry list adjustment and correlation.

**Readers, writers and byte containers.** `nupp.io` has readers that produce
strings and readers that fill buffers. `type Chunk` distinguishes them, and
`transferTo` stops being a special case: `pump<R, W, W.Chunk is R.Chunk>`
connects any two whose chunks agree, and refuses the pairs that do not.

**Codecs.** `type Encoded` / `type Decoded` covers JSON (`string`, `any`), a
struct codec (`nupp.ByteView`, `T`), and the manifest and cache readers in
`build/`, which currently agree by convention.

**Lexers and passes.** A `Lexer` with `type Token`, an analysis pass with
`type Input` and `type Output`. The compiler has several of each and they are
related by comment rather than by type.

**Fallible operations.** `type Error = string` with a default is the shape that
makes a fallible interface tolerable: the common implementor says nothing, and
the one that returns a structured diagnostic says so once instead of forcing a
parameter on everyone.

**Reified element types.** A container interface with `type Element` that is a
struct lets `sizeof` and `layoutof` be written once over the interface — with
the restriction below.

## Interactions

**Structs and reification.** `ffi.new<T.Element>()`, `layoutof(T.Element)` and
`sizeof` need a ctype, and generics erase rather than monomorphize. A projection
is legal in a reified position only where its head is already concrete;
otherwise it is **NUPP2128**, which says which binder is open. Deferring this to
a runtime lookup would put a hash lookup where the whole point of a struct is
that there is not one.

**Overloads.** A resolved projection is an ordinary type and probes like one. An
unresolved projection matches candidates it should not, so probing with one is
refused rather than guessed — the existing NUPP2125 / NUPP2126 pair, with the
projection named as the reason.

**Ownership.** A projection is a type, so `takes`, `borrows` and `exclusive` on
a `self.Item` parameter mean what they always did. `@owned` sits on functions,
not types, and is untouched.

**Declaration files.** `.d.nupp` gains the ability to describe a foreign
protocol whose element type varies by implementor — which is most of them —
without inventing a parameter the foreign code does not have.

**Tooling.** `lsp inspect` on a projection should report both the projection and
what it resolved to at that site; `lsp definition` should land on the binding,
not the declaration. Rendering keeps the projection spelling in diagnostics and
shows the resolution in the `help`, because `T.Item is not string` is only
actionable next to `T.Item = integer, bound at models.nupp:12`.

## Diagnostics

- **NUPP2127** — a declaration takes a contract and leaves a type member
  unbound. Lists the members and where each was declared.
- **NUPP2128** — a projection appears where a concrete type is required
  (a reified position, an FFI intrinsic, a struct field). Names the open binder.
- **NUPP2129** — an interface carries both an unbound type member and a
  `matches` refinement. A refinement cannot test what does not exist at run
  time.

Reused: **NUPP2116** for a violated projection bound, **NUPP2119** for a type
member given a visibility keyword, **NUPP2004** for a projection of a member the
declaration does not have.

## Deliberately out of scope

**Equality constraints.** `T.Item = string` as a *constraint* (rather than a
binding) is not offered; `is` is the relation bounds already use, and adding a
second one buys precision Nupp's covariant nominals do not preserve anyway.

**Higher-kinded members.** `type Container<_>` — a type member that is itself
generic in a parameter the interface does not name. Every use we have is
first-order, and the inference cost is not first-order.

**Runtime reflection.** There is no `typememberof(T, "Item")`. Type members are
erased, and `layoutof` remains the one intrinsic that reaches through erasure,
because a struct's layout is a fact about memory rather than about the checker.
