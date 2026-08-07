# Optimization

Nupp compiles to Lua for LuaJIT, and LuaJIT has a tracing compiler that is very
good at the optimizations a compiler usually performs. Repeating its work would
buy a soundness burden in exchange for gains that disappear the moment a trace
warms up, so this compiler does not try. It optimizes the things the trace
compiler structurally cannot: costs paid before it ever sees the code, and
information only a type checker has.

The list is therefore short, deliberately, and grows only when a benchmark says
a pass earns its place with the JIT enabled. `docs/OPTIMIZATIONS.md` records the
full catalog and the reasoning behind what is and is not on it.

## Levels

    nupp build -O2
    nupp run -O2 app.nupp

`-O0` is the default, and it is a promise rather than a description: it performs
no rewrite at all. Generated Lua at `-O0` is what the language means, with types
erased and nothing else done to it. When an optimization goes wrong, `-O0` is
the way to keep working without waiting for a release.

`-O1` and `-O2` currently run the same single pass. The levels are separated now
so that the flag does not have to change later.

The level is part of the build key. Changing it rebuilds rather than leaving
half the project compiled at the old level, so switching costs a cold build and
never produces a mixture.

## What runs

| Code | Name | Level | What it does |
| --- | --- | --- | --- |
| `OPT-1` | presize | `-O1` | Creates a table at the size it is about to reach |

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

    nupp build -O2 -Zno-opt=OPT-1

That turns off one pass, named by its code, so a suspected miscompile can be
bisected without dropping to `-O0` and losing everything else. Codes are stable:
a pass may be renamed, split, or merged, and `OPT-1` still means what it meant
in the bug report you filed.

The `-Z` prefix marks the spelling as unstable. It is a debugging aid, not an
interface, and it may change or disappear.

## What optimization does not change

Nothing observable, so far.

Some optimizations trade an observable property for speed — caching a closure
changes function identity, hoisting a global changes when it is read. None of
those have landed, and when one does it will be spelled as a `--preserve=` flag
naming the guarantee you keep, rather than a pass you switch off. Until then,
`-O2` and `-O0` differ only in how fast the program runs.

The compiler's own build is the standing check on that claim: a compiler built
at `-O2` has to produce output byte-identical to one built at `-O0`, across
every module it compiles.
