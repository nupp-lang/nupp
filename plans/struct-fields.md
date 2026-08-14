# Fields a struct cannot hold

> **Status: SF-S1 through SF-S3 proposed; SF-S4 onward blocked and not
> recommended on current evidence.** See §Anchoring, which is why.
>
> **Revised twice after review. Not implemented.** Nothing here is
> built. The measurements are from the compiler's own token stream, taken while
> moving trivia into an arena.
>
> The first revision claimed 32 bytes a token and made element references
> borrows. Both were wrong. The 32 bytes measured a benchmark struct missing
> `blockDepth`, `lineIdx`, `id` and `poolId`; the declared field set is 36 bytes,
> 40 with identity. And a borrow may not be stored in a table or a field
> (`docs/ownership.md`), which is exactly what the CST array part does with every
> token it holds, so the design could not have type-checked. See
> §Representation, which settles both before the stages are actionable.

## Decision

A `struct` is its C layout, and that is the point: fixed offsets, no hash
lookup, no per-field GC object. It is also why the compiler's own hottest data
cannot be one. A token is six numbers, twenty-three flags, two strings and a
dozen sparse references, and the numbers are the smallest part of it.

Nupp will let a struct declare three further kinds of field, none of which
changes what the layout is:

- **`flag`** fields, which are booleans packed into an implicit word.
- **`derived`** fields, which are computed on read and stored nowhere.
- **`associated`** fields, which are declared and typed but held beside the
  instance rather than inside it.

Instances of such a struct come from a **`pool`**, which owns the block they
live in and the shared data their derived fields read. An element reference is
borrowed from its pool, so it cannot outlive it.

Element references are ordinary values, not borrows -- an earlier revision said
borrows and could not have type-checked, because a borrow may not be stored in a
table and the CST stores every token in one.

The declarations are what make this worth doing in the language rather than by
hand. A hand-written `ffi.metatype` reaches the same layout, and every read of
`tok.kind` then goes through a metamethod the compiler knows nothing about,
returning a value it cannot type. A declared field is one the checker types and
the generator can **lower inline at the call site**, because the receiver's type
is known where the field is read. The metamethod becomes the fallback for the
sites that are not statically typed, not the mechanism.

## Why make the change

Measured on the compiler's 487,949 tokens across its own sources:

```text
representation                             MB   bytes/token    read
A  table per token (today)              126.1           264   0.005s
B  chunked storage + element pointers    34.7            73   0.004s
C  chunked storage + 8-byte handles     103.5           217   0.023s
```

B is the representation this plan assumes; §Representation says why C is not
available and what B costs.

Lexing allocates 144 MB for those tokens and is 38% of everything a build
allocates. Parsing the CST is another 23%, and a CST node has the same shape
problem the token does: a handful of numbers, a variadic child list, and about
thirty optional marks that later passes hang on it, almost all of them nil on
almost every node.

Neither can be written as a struct today. `kind: string`, `text: string`,
`definition: any` and `groupRef: any` have no place in a C layout, and dropping
them makes the type meaningless. So the choice, right now, is between a typed
token that costs 264 bytes and an untyped one that costs 32 — and the compiler
is 37 files deep in the first.

That is a bad trade to be forced into by a language whose distinguishing claim is
that its types are not always erased. The claim is worth keeping; the fields
have to move.

## Representation

Growth is the whole problem. A pool that reallocates invalidates every reference
into it, and the first revision answered that by making element references
borrows -- which cannot be stored in a table or a field, which is the only thing
the CST ever does with a token. That design could not have worked.

**Storage is chunked and never moves.** A pool is a list of fixed-size blocks;
growth appends a block and touches no existing one. An element reference is a
pointer that stays valid for the pool's lifetime, so it is an ordinary value
that may be stored anywhere a token is stored today, and no borrow is involved.

The measured alternative was a handle -- `(poolId, id)` as an eight-byte value,
storable anywhere, safe against any lifetime error by construction. It does not
survive contact with the runtime: boxed as cdata each handle costs about 200
bytes, so 500,000 of them come to 217 bytes a token against the table's 264,
and resolving one costs 6.4x a direct element read. A handle only pays unboxed,
and an unboxed handle in the CST array part is a Lua number that has lost its
type. So the language cannot offer handles as the reference type, and B is what
remains.

What B leaves open, and what the rest of this plan depends on being answered:

- **An element pointer is not traced.** If the pool is collected the pointer
  dangles, silently. Today's equivalent, `lexer.TriviaArena`, is safe only
  because the arena is a field of every token that indexes it. The language has
  to say the same thing about pools: a structure holding element references must
  hold the pool. That is a reachability rule on fields, not a borrow, and it is
  the one genuinely new piece of checking this plan needs.
- **Identity is `(poolId, id)`, not `id`.** Element 1 of two pools is one key
  otherwise. `poolId * 2^32 + id` is exact in a double for a `uint16` pool and a
  `uint32` index, so the lowered key is one arithmetic expression.
- **Pool registry lifetime is unresolved.** Strong entries leak every pool a
  long-running LSP ever opens; weak entries let a stale `poolId` resolve to a
  different pool; never reusing an id exhausts a `uint16` after 65,536 files.
  A generation counter beside the id is the usual answer and is not yet
  designed. **This is the open question that blocks SF-S4.**

## Anchoring, and why the pooled stages are blocked

An element reference does not keep its block alive. Measured, on the shape this
plan proposes:

```lua
local held
do
  local block = ffi.new("Tok[?]", 64)
  block[7].offset = 1007
  held = block[7]
end
collectgarbage("collect")            -- block is unreachable; held is not
-- allocate over the freed region
print(held.offset)                   --> 0
```

Not a crash: a read of reused memory, returning a plausible value. Chunking
fixes reallocation and does nothing about this, so §Representation's claim that
an element reference "may be stored wherever a token is stored today" is false as
written.

Three ways out, and none is good:

1. **A strong registry.** Pools are held by a module-level table, so an element is
   valid while its pool is registered, and release is a program action. Element
   validity then equals pool liveness, which is exactly Nupp's `@owned` model --
   at the pool, not the element. But use after release is undefined and
   unchecked, so element access becomes an unsafe operation wearing a typed
   field's clothes. That contradicts the reason for doing this in the language.
2. **A reference that carries its anchor.** A pool-and-index pair, which is
   §Representation's option C. Measured at 217 bytes a token against the table's
   264, because boxing an eight-byte value as cdata costs about 200. Dead.
3. **Leave tokens as tables.** No new unsafety, no saving.

A full provenance analysis -- proving that every structure storing an element
also retains its pool, through locals, returns, closures, nested nodes, calls,
unions, and containers mixing pools -- is a research-grade lifetime system, not a
stage. Until one exists, SF-S4 onward is blocked on more than the registry.

**And the trade has moved.** B saves 3.6x on lexing, which is 38% of what a build
allocates; the collector is 3-5% of build time, while the trace compiler is about
half. The escape analysis that lambda lifting and scratch reuse both want attacks
that half, costs no new unsafety, and is described as the smaller half of an
analysis that already exists. On the evidence gathered here it should come first,
and the pooled stages should wait for a reason better than allocation.

`flag`, `derived` over `self` alone, and the identity error are unaffected by any
of this. They are worth building on their own.

## Goals

1. Let a struct declare fields whose values are not part of its layout, without
   changing what the layout is.
2. Keep every such field typed, so a checker error is what a misuse produces.
3. Lower a declared field read to the code it means, rather than to a
   metamethod, wherever the receiver's type is known.
4. Give a pooled instance a stable identity, so it can key a table, unique
   across pools rather than within one.
5. Make an element reference unable to outlive the pool it points into, by a
   reachability rule on the structures that store it.
6. Leave existing structs, and their layout, exactly as they are.

## Non-goals

- Inheritance, virtual dispatch, or any form of open extension. A derived field
  is a computation named like a field, not a method table.
- Writable derived fields. A `derived` field is read-only; the thing it is
  computed from is what a caller assigns to.
- Making an arbitrary Lua value fit inside cdata. An `associated` field is
  stored beside the instance precisely because it cannot be stored inside it.
- Replacing records. A record is the right shape for data that is mostly
  references; this is for data that is mostly numbers.
- Automatic pooling. A struct that is not declared in a pool keeps allocating
  the way it does today.

## Current baseline

- `struct` lowers to FFI cdata with a fixed layout; `new Vec2(1.0, 2.0)` lowers
  to `Vec2(1.0, 2.0)` with no table at any point.
- The compiler declares ten structs across 92.5k lines, and its standard library
  none. Everything hot is a record or a plain shape.
- `lexer.TriviaArena` is the one arena that exists: a growable `uint32` block,
  five words to a record, indexed by hand through `unsafe do`. It works because
  a trivia holds no references at all. It is also the shape of the thing this
  plan is trying to make declarable, and its accessors —
  `lexer.triviaKind`, `lexer.triviaText` — are hand-written derived fields.
- Two cdata values pointing at the same address compare equal but are **distinct
  table keys**, because LuaJIT keys cdata by object identity. Nothing in the
  language says so, and a program that puts structs in a set today is quietly
  wrong.

## `flag` fields

```nupp
struct lexer.Tok
    offset: uint32
    length: uint32

    flag missing: boolean
    flag typeColon: boolean
    flag typeSeparator: boolean
end
```

Flags pack into implicit `uint32` words in declaration order, a new word every
32. Reading one is a `band`; writing one is a `bor` or a masked `band`. The word is
not addressable and not declared: adding a flag is a layout change the same way
adding a field is.

A flag is `boolean`, not `boolean?`. The absent-versus-false distinction the
optional marks currently carry is not representable in a bit, and every one of
the compiler's twenty-three boolean marks reads as "set or not" anyway. A mark
that genuinely needs three states is an `associated boolean?`, and the checker
says so rather than the author discovering it.

Reports **NUPP2213** for a `flag` field of any type but `boolean`.

## `derived` fields

```nupp
struct lexer.Tok
    kindIndex: uint16
    offset: uint32
    length: uint32

    --- The token's kind, interned once by the pool that holds it.
    derived kind: string
        return pool.kinds[self.kindIndex]
    end

    --- The exact bytes, cut from the file this token was lexed from.
    derived text: string
        return pool.source:sub(self.offset, self.offset + self.length - 1)
    end
end
```

A derived body is an expression over `self`, `pool`, and module scope. It may
not assign, may not call anything that suspends, and may not reach a global. It
is checked as a function returning the declared type; `pool` names the block the
instance came from and is available only for a pooled struct.

The lowering is the part that matters:

- Where the receiver's static type is the struct — which is every site the
  checker has already typed — `tok.kind` lowers to the body inline, with `self`
  substituted. No call, no metamethod, no upvalue. This is what a hand-written
  `ffi.metatype` cannot do, and it is why the feature belongs here.
- Where the receiver is `any`, the ctype's `__index` carries the same body as a
  fallback, so a dynamically typed site still reads the field.

Because the body is inline at typed sites, it is also recordable: no `FNEW`, no
`UCLO`, nothing for `nupp bc --check` to complain about. A derived field that
happens to allocate — `text` cuts a string — allocates exactly where the old
field read would have, and only when read. That is the whole saving in the
token case: nothing on the build path reads most tokens' text more than once,
and nothing reads whitespace text at all.

Assigning to a derived field reports **NUPP2214**.

## `associated` fields

```nupp
struct lexer.Tok
    --- Where the name this token spells was declared.
    associated definition: any

    --- The group whose breaking decision this token follows.
    associated groupRef: any
end
```

An associated field is stored in a table the pool owns, keyed by the instance's
identity, one table per field. One table per field rather than one per instance
because these are sparse: the compiler writes `definition` on 6 sites and reads
it on 259, and it is set on name tokens only. A field nobody sets costs its
pool one empty table.

Reading lowers to `pool.__assoc_definition[self.id]`, writing to the assignment.
Both are ordinary table operations on an integer key, which is faster than the
object-keyed table the same information lives in today.

The lifetime is the pool's. When the pool goes, so does every associated value —
which is what the LSP needs when a document closes, and what a build never has
to think about because the pool dies with the module.

An `associated` field may hold anything, including a reference to another
instance of the same struct. That is how `stmtLastTok` and
`functionBodyFirstTok` survive the move -- and it is also a place the
reachability rule above applies, since such a value is an element pointer like
any other.

An unset entry reads as nil, so a field declared `associated value: string` would
hand a caller nil through a type that says it cannot be. The declaration is
therefore constrained: an `associated` field is either optional or it has a
default, and a non-optional one without a default reports **NUPP2216**. Definite
initialization -- proving every instance is written before it is read -- is the
alternative, and is not worth its analysis here, because every mark this feature
exists for is genuinely absent on most instances.

## Pools and identity

```nupp
pool lexer.Tokens of lexer.Tok
    --- Shared by every element, and what `derived` bodies read as `pool`.
    source: string
    kinds: {string}
end

local tokens = new lexer.Tokens(source = source, kinds = KINDS)
local tok = tokens:append()
tok.offset = start
```

A pool owns a list of fixed-size blocks of its element type, the shared fields
the derived bodies read, and the side tables the associated fields use. It grows
by appending a block, never by reallocating one, so an element reference stays
valid for as long as the pool does and may be stored wherever a token is stored
today. §Representation says why this rather than borrows, and why not handles.

What the pool does not do is keep itself alive. An element pointer is not traced,
so a structure that stores one and drops the pool holds a dangling pointer that
reads as ordinary memory. The rule is that a structure storing element references
must also hold the pool, and it is the one new piece of checking this plan needs.
`lexer.TriviaArena` obeys it today by being a field of every token that indexes
it; the difference is that nothing checks it.

Identity is `(poolId, id)`. `id` is the element's index, assigned by `append`;
`poolId` names the pool in a module-level registry. A table keyed by an element
lowers to `poolId * 2^32 + id`, exact in a double for a `uint16` pool and a
`uint32` index. `id` alone is not identity: element 1 of two pools would be one
key, which is the bug this replaces rather than the fix for it.

Two problems this does not yet solve, both of which block SF-S3's key lowering
for pooled types:

- **The key changes with the receiver's static type.** `t[tok]` lowers to the
  composite key; `t[k]` where `k: any = tok` cannot, so it uses cdata identity
  and the two never meet -- a value stored through one is invisible to the other.
  Either a pooled reference may not erase to `any` at all, which is severe in a
  compiler whose token marks are typed `any`, or every dynamic index
  canonicalises, which means a runtime check on paths that have none today. The
  `__index` fallback has the same shape: it is where provenance disappears.
- **The key has no room left.** `poolId` and `id` fill 48 of a double's 53 exact
  bits, leaving five for the generation the registry needs, and nothing at all
  for a module or nominal discriminator -- so two pooled types in different
  modules, each with its own registry, produce the same numeric key. A wider key
  means a string or a pair, and both cost what the composite key was for.

A struct **not** in a pool has no such identity and keeps LuaJIT's, where two
cdata values at the same address are distinct keys. Using one as a table key
reports **NUPP2215** rather than quietly working for one lookup and failing for
the next.

## What this does to the compiler

The token becomes:

```text
uint16 kindIndex, uint32 offset, length, line, col, triviaFirst, triviaCount
uint32 flags        -- 23 marks
derived kind, text
associated definition, groupRef, opensGroup, stmtLastTok,
           functionBodyFirstTok, deprecationToken, deprecation,
           deprecationReported, additionalDefinitions, propertyCapability
uint16 blockDepth, lineIdx   -- ordinary fields; they were integers already
```

44 bytes an element -- 40 before `lineIdx` was widened back to 32-bit -- and 73
with the reference that reaches it, against 264. That is 3.6x, not the 8x the
first revision claimed from a benchmark struct missing four fields. Of roughly 3,200 field accesses across 37
files, the ones that change are the seven token constructions, the ten sites that
key a table by a token, and `cst.isToken`. Everything else — every `tok.kind ==
"then"`, every `tok.text`, every `tok.typeColon = true` — is written the same
way and lowers to something smaller.

The CST node is the same exercise: `kind`, `firstChild`, `childCount` as fields,
`children` derived onto a child pool, and the thirty-odd `Hints` marks
associated. That is the other 23%.

## Pooled is part of the type

A struct whose derived bodies read `pool`, or which declares any `associated`
field, is **pooled-only**: a distinct nominal from an ordinary struct, and the
difference is checked, because everything below is otherwise reachable and each
corrupts something.

- `new lexer.Tok(...)` outside a pool leaves `poolId` naming no pool. Refused.
- `ffi.new` or a cast reaching the ctype directly is `unsafe do` only, and
  reports **NUPP2217** elsewhere.
- Copying an element by value duplicates `id`, so two elements share one
  side-table entry. Assignment of a pooled element is a reference copy; a real
  copy is `pool:clone(element)`, which allocates a new id.
- Embedding a pooled struct as a field of another struct puts an element outside
  every pool. Refused.
- The same nominal in two pools. A pooled struct names its pool type in its
  declaration, so there is exactly one.

`id` and `poolId` are written once, by `append`, and are read-only to everything
else: assigning either reports **NUPP2218**. They are ordinary fields in the
layout, so they have to be closed explicitly rather than by being hidden.

## Constraints

### The stage-0 floor

This is new syntax, so it lands in two steps: a release that implements `flag`,
`derived`, `associated` and `pool` without using them in the compiler's own
source, then a bootstrap refresh, and only then may `lexer.Tok` be written this
way. See `plans/downloaded-bootstrap.md`. The token migration is therefore at
least one release behind the feature, and planning it any other way produces a
compiler that cannot compile itself.

### Inline lowering has to stay inline

The whole argument for doing this in the language is that a typed read lowers to
the body rather than to a metamethod. If the generator ever falls back to
`__index` for a typed site, the feature is a slower `ffi.metatype` with better
error messages. `nupp bc --check` should learn to say when a derived read did not
inline, and the compiler's own token stream is the regression test.

### The metatable is already occupied

`gen` emits `{__index = {}}` for every struct and stamps it with `ffi.metatype`
(`src/nupp/compiler/gen.nupp`), so the method table exists before this feature
adds anything. A derived field's fallback cannot replace `__index`; it composes
with it. Associated writes need `__newindex`, which structs do not have at all
today, and adding one turns every unknown-field write into a checked error where
it is now an FFI message. That is an improvement and it is still a behaviour
change to existing structs, so it is SF-S5's to announce.

Inline substitution must evaluate a nontrivial receiver exactly once:
`tokens[next()].kind` may not evaluate `tokens[next()]` twice because the body
mentions `self` twice. The body binds the receiver to a temporary first.

### Derived bodies are not free

`text` cuts a string. A loop that reads `tok.text` twice allocates twice, where
the old field read allocated once at lex time and shared. Most of the compiler
reads a token's text once or never, which is why this is a saving — but it is a
saving that depends on how callers behave, and a caller in a loop can lose it.
`--remarks` should say when a derived read with an allocating body is inside a
loop.

### Sparse is an assumption

One table per associated field is right for `definition` at 6 writes. It is
wrong for a field set on every instance, where a plain array in the pool would
be better and a real field better still. The compiler should report an
`associated` field it can see is written unconditionally in the same body that
creates the instance — that field wants to be in the layout.

## Stages

### SF-S1: `flag`

Packing, `band`/`bor` lowering, **NUPP2213**. Self-contained, no pool, no
identity. Lands on its own and immediately shrinks the ten structs the compiler
already has.

### SF-S2: `derived`

Bodies, checking, inline lowering at typed sites, `__index` fallback,
**NUPP2214**. Still no pool: `pool` is unavailable in a body until SF-S4, so the
first version derives from `self` alone. That is enough for a struct whose
derived field is arithmetic over its own fields, which is most of them.

### SF-S3: struct identity

**NUPP2215** for a non-pooled struct used as a table key. This is a bug fix and
does not depend on the rest; it should land as soon as it is written, because
today the failure is silent.

### SF-S4: `pool`

Chunked blocks, `append`, shared fields, `pool` in derived bodies, the
`(poolId, id)` identity, and the reachability rule that keeps a pool alive while
element references into it are stored. The largest stage.

**Blocked** until the registry lifetime is designed: strong entries leak every
pool an LSP opens, weak entries let a stale `poolId` resolve to a different pool,
and never reusing an id exhausts a `uint16` after 65,536 files. A generation
beside the id is the usual answer. Nothing after this stage is actionable until
it is settled.

### SF-S5: `associated`

Side tables keyed by `id`, which needs SF-S4 for the pool to own them.

### SF-S6: the token

Only after a release carrying SF-S1 through SF-S5 is the stage-0 compiler. Then
`lexer.Tok`, and the seventeen sites that actually change.

### SF-S7: the CST node

The same again, with the child pool. Worth doing separately, because the child
list is variadic and the token stream is not, and that difference is where this
design will first be found wanting.

### SF-S8: kind-comparison folding

Rewriting `CONST_TABLE[i] == "literal"` to `i == index`, with the immutability,
constancy and injectivity obligations above. Independent of everything else here
and testable on its own; the parser is where it pays.

## What it looks like

The declaration, with the fields grouped by where each one actually lives.

```nupp
--- One token of a lexed file.
---
--- Six numbers and a flag word are the whole layout. The kind is an index into a
--- table the language fixes; the text is a slice of the file; the marks later
--- passes hang on a token are sparse and live beside it.
struct lexer.Tok in lexer.Tokens
    --- Index into `KIND_NAMES`. The set of kinds is closed -- keywords, operators,
    --- and the five open classes -- so this needs nothing from the pool.
    kindIndex: uint16

    offset: uint32
    length: uint32
    line: uint32
    col: uint32
    triviaFirst: uint32
    triviaCount: uint32

    --- These were `integer?` marks and were always integers. `lineIdx` is an
    --- output line number and stays 32-bit: a formatted file may exceed 65,535
    --- lines, and a wrapped one breaks every line-distance comparison silently.
    blockDepth: uint16
    lineIdx: uint32

    --- Written once by `append`, read-only to everything else. Declared rather
    --- than hidden, because they are in the layout and the ABI is published.
    readonly id: uint32
    readonly poolId: uint16

    flag missing: boolean
    flag typeColon: boolean
    flag typeSeparator: boolean
    flag typeBracket: boolean
    flag typePostfix: boolean
    flag generic: boolean
    flag homogeneousPack: boolean
    flag namedVararg: boolean
    flag contextualOp: boolean
    flag constructTarget: boolean
    flag spacedTok: boolean
    flag breakOp: boolean
    flag chainStep: boolean
    flag typeOp: boolean
    flag unaryTok: boolean
    flag startsStat: boolean
    flag blankBefore: boolean
    flag blankAfter: boolean
    flag forceBreak: boolean
    flag finalFunctionReturn: boolean
    flag formatOmit: boolean
    flag _shortfnOpen: boolean
    flag _shortfnClose: boolean

    --- "name", "number", "string", "error", "eof", a keyword, or an operator.
    derived kind: string
        return KIND_NAMES[self.kindIndex]
    end

    --- The exact bytes of the token itself, trivia excluded.
    derived text: string
        return pool.source:sub(self.offset, self.offset + self.length - 1)
    end

    --- Where the name this token spells was declared, attached by the checker.
    associated definition: any

    associated groupRef: any
    associated opensGroup: any
    associated stmtLastTok: any
    associated functionBodyFirstTok: any
    associated deprecationToken: any
    associated deprecation: any
    associated deprecationReported: any
    associated additionalDefinitions: {any}?
    associated propertyCapability: string?
end

--- One file's tokens.
pool lexer.Tokens of lexer.Tok
    --- What `text` is cut from.
    source: string

    --- The file's trivia, which is the arena this replaces the hand-rolled one with.
    trivia: lexer.TriviaArena
end
```

The element names its pool -- `struct lexer.Tok in lexer.Tokens` on the
declaration line above -- which is what makes it a pooled nominal, what a derived
body resolves `pool` through, and what makes "the same nominal in two pools"
unstateable rather than merely refused. The pool type is declared after the
element type and resolved forward within the module, as a record may name a type
declared below it.

`id` and `poolId` are declared fields, not hidden ones: they are in the published
ABI, they are `readonly` so only `append` writes them, and their position in the
layout is part of the struct's declaration order like any other field.

### Lexing

Today, at the bottom of the loop:

```nupp
tokens[#tokens + 1] = {
    kind = kind,
    text = text or sub(source, start, pos - 1),
    offset = start,
    line = l,
    col = c,
    trivia = arena,
    triviaFirst = triviaFirst,
    triviaCount = triviaCount
}
```

and after:

```nupp
local tok = tokens:append()
tok.kindIndex = KIND_INDEX[kind]
tok.offset = start
tok.length = pos - start
tok.line = l
tok.col = c
tok.triviaFirst = triviaFirst
tok.triviaCount = triviaCount
```

The `text` local disappears entirely, and with it the last reason the operator
scan tracked which string it matched: `text` is now the span, and a customary
spelling keeps its own bytes for free because the span is where they are. So does
`eof`, whose length is zero, and so does a token the parser inserts to recover,
which is the same thing.

### Reading

These sites do not change. What changes is what they lower to.

```nupp
if tok.kind == "then" then          -- fmt/init.nupp:990
```

```lua
if tok.kindIndex == 47 then         -- KIND_INDEX.then, folded at compile time
```

This does **not** follow from inlining. Inlining alone produces
`KIND_NAMES[tok.kindIndex] == "then"`; turning that into an integer compare is a
separate rewrite, sound only when the table it inverts is a compile-time
constant, is never written after construction, and maps distinct indexes to
distinct strings. All three hold for `KIND_NAMES`; none is checked today. So it
is its own stage, SF-S8, with its own proof obligation and its own generated-code
and bytecode tests, and nothing else here depends on it.

With it, the most common operation in the parser -- 1,788 sites -- never reaches
`KIND_NAMES` at all. Without it, it is one array load more than today's hash
load. `tok.kind` used as a value reads the table either way:

```nupp
local spelling = tok.kind
```

```lua
local spelling = KIND_NAMES[tok.kindIndex]
```

Text costs one more indirection than it did, and pays for it by not existing
until read:

```nupp
local name = tok.text
```

```lua
local name = __pools[tok.poolId].source:sub(tok.offset, tok.offset + tok.length - 1)
```

A flag is a mask:

```nupp
colon.typeColon = true              -- parser.nupp:444
if prev.typeColon then              -- fmt/init.nupp:456
```

```lua
colon.flags0 = bor(colon.flags0, 2)
if band(prev.flags0, 2) ~= 0 then
```

And an associated field is an integer-keyed table read, where it is an
object-keyed one today:

```nupp
tok.definition = entry
```

```lua
__pools[tok.poolId].__definition[tok.id] = entry
```

### The three kinds of site that do change

Construction, above. Keying a table by a token, which today is silently wrong and
becomes right:

```nupp
kinds[tok] = kind                   -- lsp/semantic.nupp:125
```

```lua
kinds[tok.poolId * 4294967296 + tok.id] = kind
```

And the token predicate, which stops asking whether a child has trivia:

```nupp
local function isToken(x: cst.Child): x is lexer.Tok
    return x is lexer.Tok
end
```

```lua
local function isToken(x)
    return ffi.istype(NuppTok, x)
end
```

### What the pool indirection costs

`__pools` is a module-level array and `poolId` a `uint16` field, so a text read is
two array loads and a `sub` where it was one hash load. That is the price of a
token that does not know which file it came from, and it is only paid by `text`
and by the associated fields -- `kind`, the flags, and every numeric field reach
nothing outside the element.

The alternative is a pool reference inside the element, which cdata cannot hold,
or threading the pool through every function that takes a token, which is the
signature change this design exists to avoid.
