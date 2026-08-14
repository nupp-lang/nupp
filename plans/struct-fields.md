# Fields a struct cannot hold

> **Status: proposed. Not implemented.** Nothing here is built. The measurements
> are from the compiler's own token stream, taken while moving trivia into an
> arena.

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
shape                             MB   bytes/token
table per token (today)        126.1           264
struct arena + boxed pointers   30.7            64
arena alone, referred to by id  15.3            32
```

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

## Goals

1. Let a struct declare fields whose values are not part of its layout, without
   changing what the layout is.
2. Keep every such field typed, so a checker error is what a misuse produces.
3. Lower a declared field read to the code it means, rather than to a
   metamethod, wherever the receiver's type is known.
4. Give a pooled instance a stable identity, so it can key a table.
5. Make an element reference unable to outlive the block it points into.
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
`functionBodyFirstTok` survive the move.

## Pools, identity, and borrows

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

A pool owns one growable block of its element type, the shared fields the
derived bodies read, and the side tables the associated fields use. It grows by
doubling, and growth is why an element reference has to be checked rather than
free: a reallocation moves the block, and a raw pointer into the old one is a
use-after-free that no amount of care at the call site prevents.

So an element reference is `borrowed<lexer.Tok>` — the ownership system Nupp
already has, applied to the case it was built for. A borrow cannot escape the
scope that took it, cannot be stored in a structure that outlives the pool, and
cannot be held across a call that may grow the pool. The last of these is what
`retains`/`releases` already expresses for C resources, and `append` is declared
as growing.

This is the part that a Rust arena does not get. Indices into a `Vec` launder
lifetimes: the borrow checker sees an integer and says nothing, and a stale index
is a logic bug that reads a live element. A declared pool keeps the reference a
borrow, so the compiler is still watching.

`self.id` is the element's index in the block, an ordinary `uint32` field the
pool assigns on `append`. It is also the answer to the cdata-key problem: a
struct declared in a pool is keyed by `id` in any table it is used as a key of,
so two references to the same element are the same key. A struct **not** in a
pool keeps LuaJIT's object identity, and using one as a table key reports
**NUPP2215** rather than quietly working for one lookup and failing for the
next.

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

32 bytes an element, against 264. Of roughly 3,200 field accesses across 37
files, the ones that change are the seven token constructions, the ten sites that
key a table by a token, and `cst.isToken`. Everything else — every `tok.kind ==
"then"`, every `tok.text`, every `tok.typeColon = true` — is written the same
way and lowers to something smaller.

The CST node is the same exercise: `kind`, `firstChild`, `childCount` as fields,
`children` derived onto a child pool, and the thirty-odd `Hints` marks
associated. That is the other 23%.

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

The block, growth, `append`, shared fields, `pool` in derived bodies, and
`borrowed<T>` element references with the escape rules. The largest stage, and
the one that needs the ownership system rather than sitting beside it.

### SF-S5: `associated`

Side tables keyed by `id`, which needs SF-S4 for the pool to own them.

### SF-S6: the token

Only after a release carrying SF-S1 through SF-S5 is the stage-0 compiler. Then
`lexer.Tok`, and the seventeen sites that actually change.

### SF-S7: the CST node

The same again, with the child pool. Worth doing separately, because the child
list is variadic and the token stream is not, and that difference is where this
design will first be found wanting.
