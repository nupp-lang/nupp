# Optimization

Nupp compiles to Lua for LuaJIT, and LuaJIT has a tracing compiler that is very
good at the optimizations a compiler usually performs. Repeating its work would
buy a soundness burden in exchange for gains that disappear the moment a trace
warms up, so this compiler does not try. It optimizes the things the trace
compiler structurally cannot: costs paid before it ever sees the code, and
information only a type checker has.

The list is therefore short, deliberately, and grows only when a benchmark says
a pass earns its place with the JIT enabled. `plans/optimizations.md` records the
full catalog and the reasoning behind what is and is not on it.

## Levels

    nupp build -O2
    nupp run -O2 app.nupp

`-O0` is the default, and it is a promise rather than a description: it performs
no rewrite at all. Generated Lua at `-O0` is what the language means, with types
erased and nothing else done to it. When an optimization goes wrong, `-O0` is
the way to keep working without waiting for a release.

`-O1` and `-O2` currently run the same passes. The levels are separated now so
that the flag does not have to change later.

The level is part of the build key. Changing it rebuilds rather than leaving
half the project compiled at the old level, so switching costs a cold build and
never produces a mixture.

## What runs

| Code | Name | Level | What it does |
| --- | --- | --- | --- |
| `OPT-1` | presize | `-O1` | Creates a table at the size it is about to reach |
| `OPT-2` | numeric-ipairs | `-O1` | Rewrites iteration over a proved stable declared array |
| `OPT-3` | constant-fold | `-O1` | Folds exact primitive expressions and propagates `const` bindings |

### `OPT-3`, constant folding

The compiler evaluates exact primitive expressions such as integer arithmetic,
string concatenation, comparisons, and boolean selection. A `const` binding to
one of those values is propagated at each use. It deliberately leaves floating
point arithmetic, cdata, calls, allocation, and mutable bindings to LuaJIT, so
the target retains their rounding, identity, error, and lifetime semantics.
When every condition in an `if` is one of those constants, it emits only the
selected arm, retaining its block scope.

`luajit bench/constant-folding.lua` measures the intended cold-path saving:
smaller generated Lua parses and loads faster. The same benchmark also reports
a hot loop, where LuaJIT normally performs the arithmetic folding itself and no
material win is expected.

### `OPT-1`, presizing

An empty table has no hash part. Writing four fields into one grows it three
times, allocating hash parts of one, two and four entries and copying the
contents forward between them. When the compiler can see the fields coming, it
asks for the size once instead.

    local point = {}
    point.x = 1
    point.y = 2
    point.z = 3

At `-O2` the constructor becomes a sized one. `bench/presize.lua` measures 2.3x
on four hash fields, 2.7x on eight, and 7.5x on four array slots, with the JIT
on.

It does not save memory, which is worth knowing before you go looking for the
saving. The surviving table is the same size either way, because LuaJIT rounds a
hash part up to a power of two, and a hash part replaced during a rehash is
freed there and then rather than left for the collector. What is bought is the
allocations and the copying, not the heap.

The pass reads the statements after the declaration and stops as soon as the
local is used for anything other than writing one of its fields, because that is
where a count stops being a count. Both kinds of error are harmless: a table
sized for more or fewer entries than it receives behaves exactly the same, since
capacity is not something a program can observe.

### `OPT-2`, numeric `ipairs`

For a declared dense array, `ipairs(xs)` visits the raw integer slots from one
through the first nil. When a visible dense literal establishes the entry
length and the checker can also prove the table's shape cannot change, the
compiler evaluates `xs` once and emits a numeric `for` with that static bound.

```nupp
local xs: {integer} = {1, 2, 3}
for index, value in ipairs(xs) do
    use(index, value)
end
```

The proof is more than replacing the iterator with `1, #xs`. The source literal
proves the initial boundary; the alias analysis then checks structural writes
through every known local alias across the containing function. Calls use
pessimistic [effect summaries](../effects.md), including captured-table effects
and return aliases. An unknown call, an unresolved argument that may be
mutated, a yield, a metatable effect, or a possible shape change keeps the
original `ipairs` loop. The builtin itself is recognized by definition, not
spelling, and its declaration is `const`, so a shadowed or replaceable `ipairs`
is never rewritten. Neither `#t` nor the array type alone supplies the missing
boundary proof.

`bench/numeric-ipairs.lua` compares the exact generic and numeric shapes with
the JIT enabled. Using a dynamic raw length was flat and sometimes slower after
tracing, which is why the pass requires a static literal bound rather than
rewriting every typed array loop.

## Finding out what happened

    nupp build -O2 --remarks

A language whose premise is that types make code faster owes you an answer when
something did not come out fast. `--remarks` reports what each pass did, and
what it looked at and declined:

    app.nupp:1:15: note: OPT-1: presize: point is created with room for 0 array
    and 3 hash entries
     1 | local point = {}
       |               ^

    app.nupp:5:15: note: OPT-1: presize: cache is not presized, because it is
    used for something other than a field assignment before its fields are known
     5 | local cache = {}
       |               ^
    app.nupp:6:1: note: used here
     6 | register(cache)
       | ^~~~~~~~

The second form is the useful one. It names the statement that stopped the
analysis, so moving that line — or building the table with a constructor
instead — is a change you can make deliberately rather than by guessing.

A remark is a note. It is reported and stepped over, and never fails a build.

Remarks come from `nupp build` and `nupp run`. `nupp check` does not optimize,
so it does not produce them.

## When an optimization is wrong

    nupp build -O2 -Zno-opt=OPT-2

That turns off one pass, named by its code, so a suspected miscompile can be
bisected without dropping to `-O0` and losing everything else. Codes are stable:
a pass may be renamed, split, or merged, and `OPT-1` still means what it meant
in the bug report you filed.

The `-Z` prefix marks the spelling as unstable. It is a debugging aid, not an
interface, and it may change or disappear.

## What the compiler will not do for you

Some waste is better removed from the source than worked around in the output.
A function written inside a loop that does not use the iteration is built afresh
every time round and is the same function every time:

    for _, item in ipairs(items) do
        register(item, |e| -> e.kind == "click")
    end

A compiler could cache that, and it would cost a stored slot, a branch on every
evaluation, and the guarantee that two closures from one place are two objects —
a great deal of machinery to avoid moving one line. So it does not. The
`loop-invariant-closure` lint says so instead, and the fix leaves the source
faster and clearer at once:

    local isClick = |e| -> e.kind == "click"
    for _, item in ipairs(items) do
        register(item, isClick)
    end

Invariant means invariant for the innermost loop it sits in, so a function that
uses the outer loop's variable is still reported inside the inner one; lifting it
out of the inner loop is a real saving even though it cannot leave the outer.
A loop that returns runs its body once, so a function built on the way out is not
reported.

Like every lint it has a level, and a statement that disagrees writes
`@allow("loop-invariant-closure")`. See [lints](../lints.md).

## What optimization does not change

Nothing observable, so far.

Some optimizations trade an observable property for speed — caching a closure
changes function identity, hoisting a global changes when it is read. None of
those have landed. The opt-in surface is a repeatable flag such as
`--relax=function-identity`, with the same names accepted locally by `@relax`.
Until a pass explicitly checks one of those relaxations, `-O2` and `-O0` differ
only in how fast the program runs.

The compiler's own build is the standing check on that claim: a compiler built
at `-O2` has to produce output byte-identical to one built at `-O0`, across
every module it compiles.
