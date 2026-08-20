---
title: WebAssembly application runtime
status: Draft
created: 2026-08-19
---

## Summary

A browser application target whose artifact contains a stock Lua VM, the
generated runtime, reified struct support, and every required ahead-of-time
translation unit in one statically linked WebAssembly module, instantiated by a
small JavaScript loader. It would use an unmodified upstream Lua rather than
compiling the current runtime to WebAssembly, and generated application Lua
would use a compiler-owned portable dialect.

Nothing below exists.

## Goals

- Put a Nupp application, including its structs and native code, in a browser.
- Keep Lua values, struct bytes, spans, and generated C on one collector
  boundary and in one linear memory.

## Non-goals

- Making a JavaScript Lua implementation the production application runtime.
- Compiling the current runtime to WebAssembly.

## Motivation

### Two heaps would turn every field access into a protocol

A JavaScript Lua implementation is useful where checking and portable code
generation need no C layout or native code — the playground is exactly that. An
application with structs and ahead-of-time code is not: putting application Lua
in JavaScript and generated C in WebAssembly creates two heaps, and every struct
field, span, rooted string, and constructed Lua value becomes a bridge protocol.

### The runtime change is not a syntax change

An upstream Lua release differs from the current runtime in ways that change
answers rather than spellings — an integer subtype is the clearest — and the
standard library the payload links is itself written against the current
runtime's own extensions.

So this is two ports, not one: the number model in the emitter, and the library
in the runtime. Neither moves on its own, which is the main reason this is a
larger piece of work than "add a target".

## Overview and specification

### Syntax

A build target and a loader; no language surface.

```lua
web = {
   kind = "component",
   platforms = { "wasm32-unknown-emscripten" },
   entries = { "app.main" },
   exports = { "app.frame" },
}
```

```html
<script type="module">
  import { createNupp } from "./app.js";
  const nupp = await createNupp({ canvas: document.querySelector("canvas") });
  nupp.call("app.frame", performance.now());
</script>
```

### Usage

Ordinary Nupp, including structs and ahead-of-time functions, with the browser
facilities the application selected supplied by the loader.

### Lowering

One statically linked module holds the VM, the generated runtime, reified
struct support, and every required translation unit, so Lua values, struct
bytes, spans, and generated C share one collector boundary and one linear
memory:

```text
 app.wasm
 ├── upstream Lua VM (unmodified)
 ├── generated Nupp runtime
 ├── reified struct support
 └── AOT translation units
 app.js  — instantiates it, supplies selected browser facilities
```

Generated application Lua uses a compiler-owned portable dialect the runtime
accepts, rather than the extensions the current emitter passes through:

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
standard library — itself written against the current runtime's own extensions
— is ported in the runtime. Neither moves on its own.

One statically linked module containing the VM, the runtime, struct support, and
the required translation units. A small loader instantiates it and supplies the
browser facilities the application selected.

Generated application Lua uses a compiler-owned portable dialect the runtime
accepts, rather than the extensions the current emitter passes through.

## Risks and assumptions

- **The dialect is a second emitter target.** Every future generation decision
  has to work in both, or be conditioned on the target.
- **The number model port changes answers.** A program that behaves one way on
  the current runtime and another in a browser is the worst outcome available
  here, and preventing it is most of the work.
- **A pinned toolchain becomes a browser-target dependency**, on top of the one
  ahead-of-time compilation already needs.
- **Artifact size is unaddressed.** A statically linked VM plus runtime plus
  every translation unit is a large download, and nothing above bounds it.

## Alternatives considered

**A JavaScript Lua implementation as the application runtime.** Rejected: two
heaps, and every value crossing between them. It remains the right answer for
the playground, where there is no C layout or native code to bridge.

**Compiling the current runtime to WebAssembly.** Rejected in favour of an
unmodified upstream Lua — the current runtime's tracing compiler is the reason
it exists, and it is the part that does not survive the port.

**Keeping the current emitter's extensions** and requiring a runtime that
accepts them. Rejected: that is the previous alternative wearing a different
hat.
