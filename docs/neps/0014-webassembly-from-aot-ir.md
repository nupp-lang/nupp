---
title: WebAssembly from AOT IR
status: Superseded by NEP 18
created: 2026-08-20
---

## Summary

`@aot` lowers an admitted body to IR, verifies it, and renders C. A second
renderer over the same verified kernel IR emits WebAssembly, so one pointer
kernel produces one artifact for every host satisfying the selected WebAssembly
feature contract instead of a shared library per native platform. The front
end, verifier, and safety boundary are unchanged; only the representation at the
end differs.

The existing IR also admits `lua-builder` entries that construct fresh Lua value
graphs through the Lua C API. Those are not pointer kernels, and `emit-wasm`
rejects them until a host import ABI exists; silently narrowing them is not an
option. What this proposal does not settle is how a compiled kernel is reached
from Lua. The existing wrapper loads a shared library through the FFI and hands
a span's pointer across, and WebAssembly has its own linear memory rather than
the caller's. That question decides whether the renderer is worth building, and
it is why this is a draft.

::: seealso
- [NEP 9](0009-ahead-of-time-compilation.md) for the IR, the admitted subset,
  and why generated C was the initial backend
- [NEP 13](0013-dialects-and-capability-backends.md) for the separate question
  of which Lua a build lowers for
:::

## Goals

- Produce one ahead-of-time kernel artifact consumable by every WebAssembly host
  satisfying its recorded feature contract, rather than one shared library
  built per native platform.
- Reach hosts where a C toolchain is absent, or where loading a native library
  is not permitted.
- Add no second front end, verifier, or place where safety is decided. Backend
  representability is one explicit decision over the verified entry mode.
- Render the same IR to the same bytes every time, as the C renderer already
  must for the artifact cache to key on it.

## Non-goals

- Lowering general Nupp to WebAssembly.
- Replacing generated C. `emit-c` and `require` keep their current meanings and
  remain the path a native build takes.
- Combining with the `lua51` dialect. A kernel reaches its caller through spans
  and pointers, which a runtime with no FFI does not have.
- Rendering `lua-builder` entries before a stable host import ABI exists.
- Deciding the binding. This proposal states the shapes and picks none.

## Motivation

### Seam already exists

`src/nupp/compiler/aot/` is already split the way retargeting needs: `lower`
reads checked syntax and produces IR, `verify` proves it, and `emit` renders
it. `emit.nupp` opens by saying that generated C is a backend representation
and not the safety boundary, that everything it prints was proved before it
ran, and that a rule which looks like it belongs there almost certainly belongs
in the verifier instead.

A renderer written against verified kernel IR inherits every proof.
`src/nupp/compiler/aot/admit.nupp` holds the admitted subset as data rather
than as a pass, so what a second renderer owes is a list somebody can read
rather than a body of code somebody has to trace.

`emit-c` also already exists as a policy that writes backend output without
compiling it, which means the pipeline already ends at rendered text for at
least one supported configuration.

### C toolchain is a per-platform dependency

`src/nupp/compiler/build/aot.nupp` states that choosing the `require` policy is
how a project accepts a C compiler as a dependency, and that nothing else in
Nupp makes a project depend on one. That dependency is paid once per platform a
project ships to, and every platform needs its own build, its own toolchain, and
its own shared library in the package.

One WebAssembly module is one file for all Wasm hosts with the feature contract
recorded in that module's artifact metadata. A scalar `wasm32` build is the
portable default; requesting SIMD produces a different artifact whose contract
requires SIMD128.

### Lane widths already have a tier that fits

WebAssembly SIMD is 128 bits and only 128 bits.
`src/nupp/compiler/aot/target.nupp` sets `NARROWEST_GANG = 16`, describes 16
bytes as the tier every x86-64 has, and splits vectors wider than the selected
tier rather than refusing them. A WebAssembly SIMD target is therefore an
existing width rather than a new concept in the lane lowering. It is not the
default: the scalar tier has no gangs, so an artifact meant for the broad Wasm
floor does not acquire an undeclared SIMD requirement.

### General Lua to WebAssembly is a different project

`src/nupp/compiler/gen.nupp` is syntax-directed token emission that writes each
token at its source line so a traceback needs no source map. There is no
whole-language IR under it, and the reason is that the output language is the
input language.

Rendering the whole of Nupp as WebAssembly or JavaScript means implementing Lua
semantics: metatables, coroutines, multiple returns, one-based indexing,
strings as bytes, and `pcall`. Fengari is that program, and it is an
interpreter. Reaching a browser by lowering portable Lua and running it on an
existing interpreter costs a dialect; reaching one by rendering Lua semantics
costs a language implementation.

## Overview and specification

### Second renderer over the same IR

`src/nupp/compiler/aot/emit.nupp` gains a sibling. It reads verified IR, writes
WebAssembly, and decides no safety rule: every span bound, region relationship,
conversion and lane width it relies on was proved before it ran, exactly as for
the C renderer. Its one representability check reads the verified program's
`entryMode`; it accepts `kernel` and reports the diagnostic below for
`lua-builder`.

`src/nupp/compiler/targetlayout.nupp` gains the `wasm32-unknown-unknown` memory32
layout, including four-byte pointers. `src/nupp/compiler/aot/target.nupp` reads
that same triple and offers two tiers: scalar `wasm`, the default, with no gang;
and `simd128`, whose widest register class is 16 bytes. The artifact key already
includes the triple and tier, so a SIMD module cannot be mistaken for the
portable scalar one.

### Entry mode is an explicit backend boundary

The verified IR already carries `entryMode = "kernel"` or
`entryMode = "lua-builder"`. The C emitter supports both: a kernel has a pointer
ABI, while a builder is a Lua C function that receives `lua_State *` and uses
the Lua C API to publish a fresh value graph.

`emit-wasm` accepts only `kernel`. A builder reports at the first Lua-building
operation:

```text
error[NUPP3011]: `emit-wasm` has no host ABI for a Lua-building AOT entry
  --> src/decode.nupp:18:17
   |
18 |     local out = {}
   |                 ^^ this allocation needs the Lua C API
   |
help: select `emit-c` or `require`, or keep this @aot entry pointer-only.
```

This is a backend representability diagnostic after ordinary AOT admission, not
a second parser, source subset, or verifier. The policy remains total: it never
emits some `@aot` bodies and silently leaves the rest as Lua. A later proposal
may define a versioned host import ABI and widen the renderer to builders; until
then the refusal is part of the Wasm target contract.

### Policy gains one value

| Policy | Meaning |
| --- | --- |
| `off` | `@aot` is not looked for. The default. |
| `emit-c` | verify and write C beside the build, compiling nothing |
| `emit-wasm` | verify and write a WebAssembly module beside the build |
| `require` | compile the C into the project's shared library |

`emit-wasm` writes an artifact or fails if any reached `@aot` entry has no Wasm
representation. It does not decide how that artifact is loaded, for the same
reason `emit-c` does not decide which compiler reads its output.

The policy fixes the backend target. With `emit-wasm`, an omitted `aotTarget`
means `wasm32-unknown-unknown`, and naming any other triple is an error rather
than a request to emit architecture-specific WebAssembly. An omitted
`aotFeatures` selects `wasm`; `aotFeatures = "simd128"` selects the wider feature
contract. These settings are independent of `platforms`, which still says where
the Lua host itself runs.

### Worked example

```nupp
local span = require("nupp.mem.span")

@aot
local function scaleAdd(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>,
    scale: float
): nil
    for index = 1, #output do
        output[index] = input[index] * scale
    end
end
```

Rendered as C today:

```c [Generated C, private]
void ks_scale_add(float *output, const float *input,
                  uint64_t count, float scale) {
    for (uint64_t i = 0; i < count; i++) {
        output[i] = input[i] * scale;
    }
}
```

Rendered as WebAssembly, over the same verified IR:

```wat [Generated WebAssembly, private]
(func $ks_scale_add (param $output i32) (param $input i32)
                    (param $count i64) (param $scale f32)
  (local $i i64)
  (block $done (loop $next
    (br_if $done (i64.ge_u (local.get $i) (local.get $count)))
    ...
    (br $next))))
```

The pointers are offsets into the module's own linear memory, which is the
whole of the binding problem in one line.

### A future binding must verify struct layout

`src/nupp/compiler/aot/binding.nupp` asks `layoutof` for the size and offset of
every field crossing the native boundary and compares them against what the
compiled object reports, before anything is callable, so a compiler that laid a
struct out differently is a load error rather than a silent misread.

The WebAssembly renderer emits equivalent size and offset reporter exports from
the explicit `wasm32` layout. A future binding must compare them with the host
view it actually passes or copies before exposing a call. `emit-wasm` alone has
no caller and therefore performs no load-time comparison. Nothing about a
different renderer makes the eventual boundary trusted, and a binding proposal
that omits this check is incomplete.

### Binding is not settled

Three shapes exist, and this proposal picks none.

**Host-owned linear memory.** The Lua program is itself running inside a
JavaScript or WebAssembly host, and the kernel is a module in the same
instance or imports the host's memory. The host owns the buffer and the Lua side
reaches it through whatever bridge the interpreter offers. This is the case the
browser argument wants, and it depends entirely on a bridge that differs
between wasmoon and Fengari and that Nupp does not control.

**A WebAssembly runtime reached through the FFI.** A LuaJIT program loads
wasmtime or wasmer and calls the module through it. This works, and it buys
packaging rather than portability: a project that has the FFI could have loaded
a shared library instead, so the gain is one artifact rather than one per
platform, at the cost of a new native dependency.

**Copying at the boundary.** The caller hands over a copy and takes a copy
back. [NEP 9](0009-ahead-of-time-compilation.md) already argues against this
shape, under the heading saying the kernel ABI stops where the useful work
ends: returning through a span and rebuilding pays exactly the cost the native
path existed to remove.

## Risks and assumptions

- **The binding decides whether this is worth building.** The renderer is the
  cheap half and the half that is clearly correct. If no binding is better than
  loading a shared library, a correct renderer produces artifacts nothing calls.
- **This does not combine with `lua51`.** A kernel reaches its caller through
  spans and pointers. A runtime with no FFI has neither, so the dialect that
  most wants a portable artifact is the one that cannot use this one.
- **Lua-building entries remain C-only.** They are part of the verified AOT IR,
  but their representation is a Lua C function rather than a pointer kernel.
  `emit-wasm` fails explicitly on one until a host import ABI is designed.
- **Emitting C buys the C compiler's optimizer.** A pinned toolchain does
  instruction selection, scheduling and vectorization that Nupp's IR does not
  have to describe. Rendering WebAssembly moves that work to the host runtime's
  own compiler, and moves the responsibility for emitting good input to Nupp.
- **SIMD narrows the host set.** The default scalar module uses no vector
  feature. Selecting `simd128` gets a 16-byte gang and records that requirement
  in the artifact; a host without SIMD128 must reject it rather than attempting
  a call. A project coming from a 32-byte or 64-byte native tier gets fewer lanes
  here.
- **Determinism is a requirement, not a property.** The artifact cache keys on
  rendered output, so the WebAssembly renderer owes the same rule the C
  renderer does: the same IR renders to the same bytes every time.

## Alternatives considered

**Render C and compile it to `wasm32` with clang.** This produces a
WebAssembly module with no second renderer at all, and inherits the C
compiler's optimizer. It keeps a toolchain dependency, but one toolchain rather
than one per platform. This is the strongest alternative and may well win; the
case for a native renderer rests on removing the C dependency entirely, and on
controlling what the module's imports and memory look like, neither of which
has been measured against the cost of writing and maintaining a second
renderer. Compiling a `lua-builder` still requires a Lua host import ABI, so
this alternative does not remove that boundary.

**Direct machine-code emission.** NEP 9 defers it unless measured toolchain,
latency, packaging or specialization requirements show generated C cannot meet
the release gates. Packaging is exactly the requirement this proposal raises,
so revisiting that deferral is the same conversation from the other side.

**Render the whole program as WebAssembly.** Rejected: there is no
whole-language IR, and building one means implementing Lua's object model,
coroutines and calling convention a second time.

**Run everything on an interpreter and ship no kernels.** This is the cheap
browser answer and it is a real one, reached entirely by NEP 13's `lua51`
dialect with no work here at all. It gives up native speed for the loops
`@aot` exists for, which for a program that has no such loops costs nothing.
