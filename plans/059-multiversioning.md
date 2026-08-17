# Ahead-of-time multiversioning

Status: scoped, not implemented — follows `plans/038-aot-functions.md`

## Decision

A build that wants several CPU feature tiers emits one translation unit per
`(source, tier)`, compiles each with that tier's flag, links all of them into
the one library it already produces, and gives each exported symbol a tier
suffix. The generated wrapper asks the compiled object once, at load, which
tiers this machine can run, and binds each `@aot` function to the widest symbol
the machine supports and the build carried.

Feature detection is a function the emitter writes in C and the build compiles
at the architecture baseline, not machinery in the runtime, the native provider
or the FFI layer. The wrapper calls it exactly the way it already calls the
layout reporters.

A build that names one tier emits exactly what it emits today: one symbol per
function, no detection, no suffix. Multiversioning is something a project asks
for.

## Why this is worth doing

`target.DEFAULT_TIERS` pins x86-64 to `baseline`, and it has to: a binary
compiled for AVX2 does not run on a machine without AVX2, and the failure is an
illegal instruction rather than a diagnostic. So the most common target gets the
16-byte gangs — two binary64 lanes or four 32-bit ones — while most machines
running that artifact have a 32-byte register class sitting idle.

What this buys is lane density, not cheaper arithmetic, and the closest thing to
a measurement of it is a different experiment on a different machine:
`bench/kernel-subset-spike/mixedwidth.sh` doubled a gang's lanes on arm64 and
that half of the change was worth 1.9x. So the estimate for x86-64 is "about
that", and nothing here should be claimed until the same kernel has been run at
both tiers on one AVX2 machine. That measurement is step 5, and it is a step
rather than a footnote because a doubling that does not show up is a reason not
to carry the second tier at all.

## Why one library and one translation unit per tier

The tier is already a whole-translation-unit flag. `aot.TIER_FLAGS` maps `avx2`
to `-mavx2`, `aot.compileFlags` appends it to the command line for the whole
compilation, and `aot.libraryKey` keys the library on those flags. Compiling
each tier as its own translation unit is therefore the shape that needs no new
mechanism: the flag path, the artifact key, which already carries `tier`, and
the link step all work as written, once per tier instead of once.

One library rather than one per tier, because a library is a thing that travels.
`aot.libraryReference` names it `@lib/lib<name>_aot.<suffix>`, resolved against
the module that loads it, and a `bundle`, `binary` or `component` target copies
it beside the artifact so a single file carries its compiled code. All of that
is per library. Two libraries is two of it, in every one of those places, to
avoid a suffix on a symbol name.

Loading AVX2 code onto a machine that cannot execute it is not a hazard. A
shared library is mapped, not run; what would fault is a call, and the whole
point of the selection is that the call never happens.

The symbol suffix goes through `scalarIR.privateSymbol`, which exists precisely
so that the generated C, the foreign declaration and the layout reporters cannot
disagree about a name. It takes the tier as a second argument and everything
downstream keeps agreeing by construction.

The layout reporters stay single. A struct's layout does not depend on `-mavx2`,
so emitting the reporters from the baseline unit only keeps the load-time layout
check one check rather than one per tier, and keeps it saying what it says now.

## Feature detection

The emitter writes one function into the baseline unit:

```c
KS_API bool ks_cpu_has_avx2(void) {
#if defined(__x86_64__) || defined(__i386__)
    return __builtin_cpu_supports("avx2");
#else
    return false;
#endif
}
```

This is the whole of the new run-time machinery, and it is deliberately in the
compiled object rather than anywhere else. The compiler that produced the code
is the one that answers whether the machine can run it; the answer is computed
on the machine that will run it, which a build-time probe cannot do; and nothing
new has to travel, because the object already travels. Putting it in the native
provider instead would mean every program that never uses `@aot` carries CPU
detection, and a second place for the question to be answered differently.

It compiles at the baseline tier — the builtin needs no feature flag — and under
a cross build: `clang -target x86_64-apple-darwin` accepts it on an arm64 host,
which is what `nupp aot --target` already does under `-Werror`.

One portability item has to be settled before this lands rather than after. On
GCC, `__builtin_cpu_supports` resolves through libgcc's `__cpu_model`; the
Windows job is the one that has to prove it links, and the fallback if it does
not is an inline `cpuid`, which is a dozen lines and no library dependency.

aarch64 has one tier. NEON is mandatory rather than optional, so there is
nothing to detect and nothing to dispatch between, and the feature is x86-64's
until an architecture with a second tier arrives. An `avx512f` tier, when there
is hardware in CI to execute it, is another entry in this same mechanism rather
than a change to it.

## Where the choice is made

At load, once, in the generated wrapper, which already declares foreign symbols
and already calls one at load to check a struct layout:

```nupp
cdef function ks_cpu_has_avx2(): boolean from "@lib/libkernel_aot.dylib"
cdef function ks_scale__baseline(...) from "@lib/libkernel_aot.dylib"
cdef function ks_scale__avx2(...) from "@lib/libkernel_aot.dylib"

local compiled = ks_cpu_has_avx2() and ks_scale__avx2 or ks_scale__baseline
```

Bound once means a call reaches a constant upvalue, and the branch is not in the
loop, not in the call, and not anywhere a trace has to see it. Choosing per call
would put a test in front of every call to buy nothing.

The tier the wrapper selects is the widest one this machine reports and this
build carried. `NUPP_AOT_TIER` overrides it, which is not a tuning knob but the
thing that makes the dispatch testable: a machine with AVX2 can then run the
baseline symbol too, and prove both answer the same.

## What changes in the build

`aotFeatures` and `--features` take a list as well as a string. A string means
one tier and is what everything means today.

`aot.key` keys each artifact on its tier, which it already does. What is new is
that one source produces several artifacts, so the emitted-artifact map is keyed
by `(source, tier)` rather than by source, and `aot.libraryKey` takes each
tier's flags rather than one set.

`nupp aot --check` exits 1 for a map loop that lowered scalar. With several
tiers, lowering scalar becomes a per-tier fact: a loop that lanes under `avx2`
and not under `baseline` is the mechanism working, not a failure. The check
reports the tier and fails only when a loop lowered scalar under every tier the
build carried.

Artifact size grows by roughly the `@aot` code once per additional tier, and by
nothing else. That is a reason for the default to stay one tier, not a reason
against the feature.

## Testing

The differential that exists compares a lane body against the forced-scalar body
in the same artifact. It extends to tiers directly: for each tier the build
carried, the same inputs through the tier's symbol and through its own scalar
body have to agree bit for bit.

What a machine cannot do is execute a tier it does not have. So the matrix is:
build every tier everywhere, since compiling and inspecting an AVX2 artifact
needs no AVX2; run the tiers the host supports; and use `NUPP_AOT_TIER` on a
host that supports several to run each of them in turn against the same inputs.
The native x86-64 job is the one that matters here, because it is where both
x86-64 tiers exist at once — and it is already the job that found the `-Wpsabi`
mask type nobody had given a C spelling.

`crosscheck.sh` cross-compiles and runs the result under an emulator, which is
how an arm64 machine exercises x86-64 today. Whether that emulator reports AVX2,
and whether it executes it correctly if it does, is a thing to establish before
relying on it: an emulator that says yes and lowers badly would make the local
run disagree with the native one for a reason that is nobody's bug. Until it is
established, the local run pins `NUPP_AOT_TIER` to what it can verify.

A build carrying several tiers, copied to another directory and run there, is
the same relocatability test the single-tier library already has.

## Non-goals

Raising the x86-64 default to a multiversioned build. That changes what every
existing x86-64 project produces and doubles its `@aot` code, so it is a
decision to make with the feature working and measured, not as part of shipping
it.

Function-level dispatch chosen by anything other than CPU features. Selecting on
input size, cache residency or measured throughput is a different feature with a
different justification, and none of this machinery assumes it away.

`ifunc` and `target_clones`. They hand the whole problem to the loader, and the
loader that implements them is glibc's. This project builds for darwin, linux
and windows.

## Order

1. **A tier list in the manifest and on the command line**, defaulting to the
   single tier that is there now. Nothing downstream changes yet, so a wrong
   answer here is visible before it can be built on.
2. **Emit per tier**: lane lowering runs once per tier, exported symbols carry
   the tier, layout reporters come from the baseline unit only, and each
   artifact keys on its tier. Verifiable with `aot = "emit-c"` and no toolchain
   in play — the C is a text file at this stage.
3. **Detection and selection**: the baseline unit exports the query, the wrapper
   binds one symbol per function at load, `NUPP_AOT_TIER` forces one. This is
   the step that needs the Windows link question answered first.
4. **The differential across tiers**, and the native x86-64 job running both.
5. **Measure it** on an AVX2 machine against the same kernel at `baseline`, and
   record what the lane count was actually worth there.

Steps 1 through 3 are each independently checkable, which is the property worth
having: this feature's failure mode is an illegal instruction on someone else's
machine, and that is not a thing to discover at step 5.

## Rejected alternatives

**One translation unit, `__attribute__((target("avx2")))` per function.** This
works, which is worth stating precisely because the obvious objection to it does
not hold up on inspection: with the attribute on the generated function *and* on
every helper it calls, Clang compiles the file clean under `-Werror`. Without it
on the helpers it does not, and the error is the familiar one —

```
AVX vector return of type 'ks_f32x8' (vector of 8 'float' values)
without 'avx' enabled changes the ABI
```

— reported at the call site of a `static inline` helper, which is the same shape
of failure the 64-byte gang ran into. So the cost of this route is an attribute
on every emitted helper and every gang prelude, correct in two compiler
dialects, to save one object file per tier. The flag route gets the identical
guarantee from a flag the build already passes, and gets it wrong loudly at the
whole-unit level rather than quietly at one helper somebody forgot. Reconsider
only if per-unit compilation turns out to cost something measurable.

**One library per tier, selected by which one the wrapper loads.** Attractive
because it needs no symbol suffix and never maps unrunnable code. Rejected
because a library is the unit that travels: the `@` reference, the copy beside a
single-artifact target, and the state that remembers what a target produced are
all per library, and this multiplies each of them to avoid a suffix.

**Detection in the runtime or the native provider.** It would put CPU feature
detection into every program that never compiles an `@aot` function, and give
the question two places to be answered from. The object that holds the code is
the right place to hold the test for whether the code can run.
