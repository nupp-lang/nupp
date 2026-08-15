# Porting the tecs FFI subsystem

What it costs to translate real Teal into Nupp, measured rather than guessed.

The v0.1 acceptance gate (plans/019-todo.md) is `tecs/src/tecs/internal/ffi`, 1276
lines across six files. This is a running port of the first two, kept with a
log of everything that fought back, because the friction is the point: it is the
evidence for what to build next.

Run it from this directory:

    nupp check --strict
    nupp run run.nupp

## Status

```
 file                     lines  state
 ───────────────────────  ─────  ────────────────────────────
 schema.tl                   49  ported, runs
 StableChunkedArray.tl       94  ported, runs
 init.tl                    111  not started
 EpochArena.tl              116  not started
 FFIEvents.tl               200  not started
 FFIStorage.tl              706  not started
```

143 of 1276 lines. The two done are the two least FFI-heavy, so the sample does
not yet speak to the question it was started for — see §What this does not
answer.

## What the port found

Two of these were compiler bugs, both found by **running** the port rather than
checking it — each file checked clean in a state that did not work. Both are
fixed, and each carries a regression test that runs the generated code rather
than reading it.

### 1. A record's inline method is generated with a doubled `self` — FIXED

`function name(self)` inside a record body emits `function T:name(self)` — the
`:` binds the receiver and the declared parameter then shadows it with the first
actual argument, which is `nil`. Every call crashes:

    attempt to index local 'self' (a nil value)

The spelling that works is `function name()`, with `self` implicit and
undeclared.

This is the spelling in the language reference's own worked example. `nupp
reference`, §Records, prints:

```nupp
record m.Point
    x: integer
    y: integer

    function lengthSquared(self): number
        return self.x * self.x + self.y * self.y
    end
end

local origin = new m.Point {x = 0, y = 0}
print(corner.x, origin:lengthSquared())
```

That program did not run. The reference is generated from the compiler and is
the first thing a reader or an agent is told to read, so this was worse than an
ordinary defect: it taught the broken form.

Codegen now drops a leading parameter named `self`, since the colon already
binds one, and both spellings generate the same function.
`tests/inlinemethodtest.lua` covers them by running the result.

### 2. `unused-binding` said to delete a load-bearing `require("ffi")` — FIXED

A module whose only use of `ffi` is `ffi.new(...)` is reported:

    warning: NUPP2507 unused-binding: nothing uses ffi, so requiring "ffi" does nothing here
    help: delete the require

Taking the advice does not fail to check — which is what makes it dangerous. It
changes what the code means. With the require present, `ffi.new` is recognized
and typed; without it, `ffi` is an unknown global, `ffi.new` returns `voidptr`,
and codegen passes the bare global through, so the program indexes a nil `ffi`
at run time. In a context that does not index the result, it checks clean and
fails only when it runs.

There was no machine-applicable fix attached (`fixes` was empty), so nothing
auto-applied it; the wrong instruction was advice only.

The cause: the intrinsic path recognizes `ffi.new` by the name it was written
with rather than by resolving it, which skips `lookupEntry` — the one place a
read is recorded. It now resolves the name for its own sake.
`tests/unusedtest.lua` covers it.

### 3. A table literal never infers into a tuple type

`type FieldDef = {string, string}` is idiomatic Teal and common in this corpus.
No literal reaches it, in any position:

```nupp
local annotated: Pair = {"x", "float"}          -- NUPP2001
local list: {Pair} = {{"x", "float"}}           -- NUPP2001
take({{"x", "float"}})                          -- NUPP2006
```

Even the directly annotated binding is refused. The workaround is a cast on
every literal — `{"x", "float"} as Pair` — which is what `run.nupp` does, and it
is noisy enough that a real port would probably change the type to a record
instead, losing fidelity with the original.

### 4. Integer arithmetic widens, and a checked map key notices

`zero % self.chunkSize` on two integers is `number`, so it cannot key a
`{[integer]: any}`. The rule is documented and the diagnostic is clear; it needs
an `as integer` at each site. An array `{T}` accepts the same value, so the
friction is specific to the map-with-integer-key form.

### 5. Cross-module `require` needs a manifest

Checking the files individually leaves `require("schema")` as `unknown`, and
every member access on it is an error. There is no CLI flag for an include path,
so the corpus carries its own `nupp.lua`. Not a bug, but it means a file cannot
be checked in isolation the way a single-file port suggests.

## What was NOT friction

Nothing about reification, and nothing about a struct not being a table. That is
the question this port was started to answer and the answer so far is that
neither has come up:

- no field-set or layout problem
- no `pairs`, serialization, or `type()` problem
- no place where a value had to be converted at a boundary

`reifiable-record` fired nowhere, correctly — `ChunkedArray` holds tables and a
string, so it is not a candidate, and neither is anything in `schema`.

## What this does not answer

The 143 lines ported are the two files with the least FFI in them. Everything
that would exercise reification is in the four not started: `FFIStorage.tl` (706
lines) is the schema-to-cdata layer, `FFIEvents.tl` (200) is the event storage
the metatable and prototype work was aimed at, and `EpochArena.tl` (116) is the
owned growable buffer that `plans/019-todo.md` names for bounds-carrying spans.

So the finding is only "the easy files were easy, and what made them hard was
unrelated to cdata". Whether the cdata story needs `__pairs`, a conversion, or
anything else is still open, and `FFIStorage.tl` is where it would show up.
