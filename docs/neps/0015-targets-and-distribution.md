---
title: Targets and distribution
status: Implemented
created: 2026-08-19
---

## Summary

One machine produces binaries for every supported platform by compiling a
target-specific payload and stamping it into a pinned, prebuilt stub. Nupp does
not claim one local native toolchain can compile every host from source. A
browser target is designed and unbuilt: one statically linked WebAssembly module
carrying a stock Lua VM, the generated runtime, reified struct support, and
every required ahead-of-time translation unit.

[Distribution](../reference/distribution.md) documents what exists.

## Goals

- Make cross-platform release builds an ordinary operation on one machine.
- Keep the claim honest about what is being cross-compiled.
- Put a Nupp application, including its structs and native code, in a browser,
  with everything on one collector boundary and in one linear memory.

## Non-goals

- Cross-compiling the native host from source.
- Making a JavaScript Lua implementation the production application runtime.
- Compiling the current runtime to WebAssembly.

## Motivation

### Why the host is not cross-compiled

The payload is Nupp's own artifact, target-specific in ways Nupp knows about.
The host is a native program with a native toolchain, sysroots, and platform
SDKs behind it. Claiming to build both from one machine means owning every one
of those and being wrong about them in ways that appear at run time.

### Two heaps would turn every field access into a protocol

A JavaScript Lua implementation is useful where checking and portable code
generation need no C layout or native code — the playground is exactly that. An
application with structs and ahead-of-time code is not: putting application Lua
in JavaScript and generated C in WebAssembly creates two heaps, and every struct
field, span, rooted string, and constructed Lua value becomes a bridge protocol.

## Overview and specification

### Syntax

A binary target names its platforms; the command line selects among them,
separately from naming the build target.

```lua
dist = {
   kind = "binary",
   entries = { "app.main" },
   platforms = { "x86_64-unknown-linux-gnu", "aarch64-apple-darwin" },
   output = "build/dist/app",
}

web = {
   kind = "component",
   platforms = { "wasm32-unknown-emscripten" },
   entries = { "app.main" },
   exports = { "app.frame" },
}
```

```sh
nupp build --target dist --platform aarch64-apple-darwin
nupp build --target dist --platform all
```

### Usage

```text
build/dist/
├── app-x86_64-unknown-linux-gnu
├── app-aarch64-apple-darwin
└── app-x86_64-pc-windows-msvc.exe
```

```html
<script type="module">
  import { createNupp } from "./app.js";
  const nupp = await createNupp({ canvas: document.querySelector("canvas") });
  nupp.call("app.frame", performance.now());
</script>
```

### Lowering

Only the payload is produced locally, then stamped into a pinned prebuilt stub:

```text
 prebuilt stub (pinned, published)     target payload (compiled here)
 ────────────────────────────────      ──────────────────────────────
 native host executable            +   modules, resources, manifest
                                   ↓
                          one self-contained binary
```

A web artifact is one statically linked module, so Lua values, struct bytes,
spans, and generated C share one collector boundary and one linear memory:

```text
 app.wasm
 ├── upstream Lua VM (unmodified)
 ├── generated Nupp runtime
 ├── reified struct support
 └── AOT translation units
 app.js  — instantiates it, supplies selected browser facilities
```

Generated application Lua would use a compiler-owned portable dialect the
runtime accepts, rather than the extensions the current emitter passes through:

```lua
-- current emitter
local n = bit.band(value, 0xFF)
local t = table.new(0, 4)

-- portable dialect
local n = value & 0xFF
local t = {}
```

The dialect is not only spelling. An upstream integer subtype changes answers
rather than syntax, so the number model is ported in the emitter while the
standard library — itself written against the current runtime's extensions — is
ported in the runtime. Neither moves on its own.

### Obligations for a supported platform

Adding one means publishing and retaining its stub, teaching the compiler its
filename and executable suffix, modelling its compile-time C layout, and running
the same stamping and execution conformance tests.

**A layout model by itself does not make a platform supported.** It is the
cheapest of the four and the one that makes a platform look supported from
inside the compiler.

Platform is also not a build target: overloading one identity for both would
make "build this target for that platform" unexpressible.

## Risks and assumptions

- **Stubs must be published and retained forever.** A lost stub is a platform
  silently unsupported.
- **The supported set grows slowly by construction.** Four obligations per
  platform is deliberate friction, and genuine demand can go unmet.
- **Payload-only cross-compilation limits what can differ per platform.**
  Anything requiring a different host is out of reach.
- **The browser dialect is a second emitter target**, so every future generation
  decision has to work in both or be conditioned on the target.
- **The number model port changes answers.** A program behaving one way natively
  and another in a browser is the worst outcome available here.
- **Artifact size is unaddressed.** A statically linked VM plus runtime plus
  every translation unit is a large download.

## Alternatives considered

**Cross-compiling the host from source** on the build machine. It means owning
every target's native toolchain, sysroot, and SDK, and being wrong about them in
ways that surface at run time.

**Treating a platform as a build target.** It makes building one target for
several platforms unexpressible.

**Declaring a platform supported once its layout is modelled.** The cheapest
obligation, and the one that creates a false impression of support.

**A JavaScript Lua implementation as the application runtime.** Two heaps, and
every value crossing between them. It remains the right answer for the
playground, where there is no C layout or native code to bridge.

**Compiling the current runtime to WebAssembly.** Its tracing compiler is the
reason it exists, and is the part that does not survive the port.

**Keeping the current emitter's extensions** and requiring a runtime that
accepts them. The previous alternative wearing a different hat.
