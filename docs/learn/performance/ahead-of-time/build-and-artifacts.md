---
order: 635
---

# AOT builds and artifacts

A target policy decides whether AOT is disabled, emitted for inspection, or
required as part of the deliverable. Required builds compile and validate the
artifact instead of retaining a silent source fallback.

A build selects one policy, and an artifact records the one it was built under:

```lua
targets = {
   game = {kind = "modules", entries = {"game"}, outDir = "build/game", aot = "emit-c"},
}
```

- `off` does nothing. It is the default, so a project that has not asked for
  native code never needs a C compiler.
- `emit-c` verifies the IR and writes the C to `<outDir>/aot/`, without
  compiling it.
- `require` does everything `emit-c` does, then compiles the result into
  `<outDir>/lib/`, and fails the build when it cannot.
- `emit-wasm` compiles admitted entries into content-addressed Wasm side modules
  while retaining their ordinary Lua bodies.
- `require-wasm` packages those modules and replaces the Lua bodies with calls
  through the Lua-in-Wasm binding.

`emit-c` adds an artifact; it does not replace one. The ordinary Lua body is
still emitted and is still what runs. A module with no `@aot` function produces
no artifact at all, and a project with no `@aot` function anywhere builds
successfully under `require` with no library. The policy says what to do with
compiled code, not that there must be some.

Under `require`, calls reach the compiled code. The build replaces each `@aot`
function with the generated wrapper where it was written, so every call in the
file and every importer gets the compiled body without naming anything new.
Kernel wrappers call FFI symbols. Builder wrappers call a cached registered Lua
C closure, so no generated FFI code fabricates or discovers a `lua_State *`.

::: deepdive
There is deliberately no mode that quietly mixes compiled functions with
ordinary fallbacks. Disabling compilation is meant to change performance and
packaging, never an answer, and a policy that silently fell back per function
would make a benchmark unattributable and a numeric contract unenforceable.
:::

## Accepting a C compiler

Selecting `require` is how a project takes on a C compiler as a dependency.
Nothing else in Nupp makes it one, which is why `off` is the default.

The build looks for `NUPP_NATIVE_CC` first, then `clang`, `cc` and `gcc` in that
order:

```bash
NUPP_NATIVE_CC=/usr/bin/clang-18 nupp build
```

Clang leads because the emitter's contraction pragma is Clang's; GCC compiles
the same C correctly and declines to contract, which is slower and never
wrong. Naming a compiler that cannot build this C is an error rather than
a reason to look elsewhere, because a build that quietly used a different
compiler than it was told to would produce an artifact nobody could account for.

The generated C needs `__attribute__((vector_size))` and
`__builtin_convertvector`: GCC 9 and later, and every Clang. **MSVC has
neither.**

That is a statement about a compiler, not about a platform. Windows is an
ordinary target: Clang and MinGW GCC both run there, both have the two
extensions, and a Windows project with either needs nothing further. The same
`aot = "require"` builds a `.dll` beside the artifact and the same wrapper loads
it. CI runs the lane-versus-scalar differential on Windows for exactly this
reason, rather than reasoning about it from the other two platforms.

A project whose only compiler is MSVC selects `emit-c` and hands the C to it,
which is what `emit-c` is for.

## Building for another machine

`aotTarget` names the machine the compiled code is for, separately from where
the Lua runs:

```lua
targets = {
   handheld = {
      kind = "modules",
      entries = {"game"},
      aot = "emit-c",
      aotTarget = "x86_64-unknown-linux-gnu",
      aotFeatures = "avx2",
   },
}
```

The triple decides the available tiers, how a shared library is produced and
what it is called, so a Windows target gets a `.dll` and no `-lm` whether or not
the build is running on Windows. A ceiling is checked against that target's
architecture, so asking aarch64 for `avx2` is refused where it is written.

`emit-c` needs nothing installed for the target: it writes one C file per
`(source, tier)`, the baseline feature detector where selection is needed, and
`aot/units.json`. The manifest names every unit's tier and required instruction
flag, which is the handoff when the compiler for a platform is somebody else's.

`aot = "require"` cross-compiles too, and then it needs the target's headers and
libraries the way any cross build does. Give them through `aotCflags`, which is
appended after the fixed flags and is part of what the library is keyed on:

```lua
aotCflags = {"--sysroot=/opt/sysroots/linux-x86_64"},
```

The build owns CPU instruction and LTO flags when it carries several tiers.
`aotCflags` therefore refuses `-march`, `-mcpu`, AVX/SSE/FMA switches, `/arch:`
and `-flto`; any of those could put optional instructions in the baseline
fallback or optimize across the object boundary.

Without one, the failure names the missing thing rather than leaving you with
the compiler's own message about a missing `math.h`.

The flags are fixed:

```text
-std=c11 -O3 -ffp-contract=off -fno-fast-math -Wall -Wextra -Werror
```

`-Werror` is deliberate. This is compiler-generated C, so a warning in it is a
defect in the backend rather than a style opinion about someone's source. The
warning that matters most is `-Wpsabi`, which is how a vector with no register
class announces itself, and silencing it would make the target model pointless.
`-ffp-contract=off` is the numeric contract's floor; a body that asked for
contraction carries its own pragma.

That pragma is Clang's. Under GCC, `@relax("fp-contract")` compiles correctly
and does not contract, so the body is as accurate as the unrelaxed one and
slower than the same body under Clang. It is correct either way, and the
difference is worth knowing about before benchmarking across compilers.

Code is linked, never mapped at run time. A shared library the loader already
brought in needs no W^X policy, no `MAP_JIT`, no executable-memory budget and no
code retirement, all of which exist only because code is mapped at run time.
They return if and when direct machine-code emission does.

## Library dispatch

The wrapper is ordinary Nupp. `nupp aot --emit binding` prints it, and what the
build splices in is the same text minus the parts the source already has:

```nupp
cdef function ks_scale_layout_Sample_size(): uint64 from"build/native/lib/libnative_aot.dylib"
const ks_scale_SampleLayout = layoutof(Sample)
if ks_scale_SampleLayout.size ~= ks_scale_layout_Sample_size() then
    error("native struct layout size mismatch", 0)
end

cdef function ks_scale(exclusive samples: voidptr, borrows source: voidptr, ...) from"..."

local function scale(exclusive samples: span.WriteSpan<Sample>, ...): nil
    if first < 1 or last > #samples or first > last + 1 then
        error("native range out of bounds", 2)
    end
    local native_samples, native_samplesCount = samples:ref()
    ...
    unsafe do
        ks_scale(native_samples as voidptr, ..., native_samplesCount)
    end
end
```

Because it is Nupp rather than generated Lua, it goes through the checker like
anything else: the ownership annotations, the range guard and the
one-statement-wide `unsafe do` are all checked, not trusted. A substitution
cannot smuggle in something the language would refuse.

It is written where the declaration was, which is necessarily after the struct
it reifies, and under the same name with the same signature. The struct layout
is compared against what the compiled object reports before the module finishes
loading, so a C compiler that laid the struct out differently is a load error
rather than a silent misread.

The module is hashed on the text that was compiled rather than the file on disk,
so a rebuild never reuses an artifact built from a different body. `nupp check`
does none of this: it answers a question about the source as written, and never
needs a C compiler.

## Shipping a shared artifact

This section describes the default `aotLinkage = "shared"` route. A static
component ships its archive to the host build rather than carrying a `lib/`
sidecar; see [Static AOT components](../../projects/build.md#static-aot-components).

The wrapper names the library with a leading `@`, which means *beside the module
that loads me* rather than *at this path*:

```lua
__nuppLib("@lib/libgame_aot.dylib")
```

VM-aware builders resolve the same `@lib/` reference before passing the path and
registrar symbol to `package.loadlib`.

At load, that is resolved against the chunk the wrapper was compiled into,
walking up until it finds the directory. Whatever path the loader used to open
the module is a path that works from wherever the program was started, so a
sibling of it does too, which makes the output tree relocatable. The walk is
also why one form serves every layout: a module named `a.b.kernel` sits two
directories down and the same module inlined at the root of a bundle sits at the
top, and the library is in one place either way.

A single-artifact target, meaning `bundle`, `binary` or `component`, gets a copy
of the library beside whatever it wrote, because that artifact is what someone
carries somewhere and the build directory is not going with it:

```text
 dist/
   app.lua
   lib/libgame_aot.dylib
```

Copy the output tree, move it, hand it to someone: it runs. Copy it without the
`lib/` directory and the load fails by name, saying what it looked for and
where, rather than with a missing symbol later on. See
[distribution.md](../../../reference/distribution.md) for the artifact kinds.

::: deepdive
A path decided at build time could not be relocatable: an absolute path pins the
program to one machine, and a relative one pins it to one directory. Resolving
against the loaded chunk is the only form that survives being copied, because
the loader has already proved that path works from wherever the program started.
:::

## Artifact cache key

Each artifact is recorded under a key covering everything that can change its
bytes: the verified IR, the version of the IR vocabulary, the numeric-contract
version, the target triple and feature tier, the backend, and the compiler's own
fingerprint. A rebuild that computes the same key leaves the file alone.

The key is over the IR rather than the source, so two sources that lower to one
program share one artifact and a comment edit is not a rebuild. The
numeric-contract version is separate from the IR version on purpose: two
compilers can agree about every field of a program and disagree about whether an
operator contracts, and an artifact built under one contract must not be reused
under another.

The key is evidence, never authority. A build compares it, then checks that the
file it describes is still on disk with the bytes it claims; a deleted or edited
artifact is written again rather than believed because a digest agreed. Losing
the record costs one rebuild and changes no answer.

The linked library gets its own key, over every tier's artifact key and compile
flags plus the detector, compiler, and final linkage. Each translation unit is
compiled to an object under its own tier flag, then those objects are linked
without a higher-tier flag. Changing compilers relinks; rebuilding an unchanged
project does not. The C itself is deliberately not keyed on the toolchain,
because the C is the same C whoever compiles it. The library is validated the same
way and is just as disposable, so deleting it costs one relink.
