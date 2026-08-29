---
title: Portable compiler and Lua-in-Wasm host
status: Implemented
created: 2026-08-21
---

## Summary

The browser compiler is one source bundle that runs unchanged under official
Lua 5.1.5. A small Lua-in-Wasm host loads the exact native-tested bytes as a
separately cacheable asset, verifies their SHA-256 digest, and exposes a
request-and-response buffer ABI to a Worker.

Portability belongs to a compiler entry and its private providers, not to fake
LuaJIT modules or public language seams. The same checked browser API runs in
the native Lua 5.1 acceptance host and in Wasm.

## Goals

- Prove the compiler artifact under stock Lua before adding a browser host.
- Preserve direct LuaJIT operations and FFI storage in the native compiler.
- Keep portable compiler fallbacks in checked modules with isolated suites.
- Keep the Lua VM and compiler bundle separately cacheable.
- Verify the compiler bytes before Lua parses or executes them.
- Compare native LuaJIT, native Lua 5.1, and Wasm results over one corpus.

## Non-goals

- Lowering arbitrary Nupp applications to WebAssembly.
- Making compiler implementation providers part of the language seam registry.
- Discovering computed module names during a build.
- Giving the in-memory compiler a filesystem, process, C layout, or AOT host.
- Replacing third-party runtime dependencies with compiler-maintained Lua
  implementations.

## Motivation

The previous playground ran the full bootstrap through a JavaScript Lua
implementation and repaired host differences with browser shims, mixing three
questions: whether the compiler source was valid Lua 5.1, which compiler
subsystems the playground needed, and how the browser hosted Lua.

Official Lua 5.1.5 rejects that artifact at its first `goto`, and fixing the
host before the artifact would preserve an unmeasured compiler closure and make
every compiler change rebuild the Wasm payload. Proving one portable source
asset first gives the native and browser hosts the same evidence.

LuaJIT remains the fast compiler host, so selecting a portable compiler must not
put a dialect probe inside token storage, bit operations, or generated native
code.

## Overview and specification

### Compiler entry

`nupp.compiler.browser` returns a constructor for stateful in-memory sessions:

```nupp
local Browser = require("nupp.compiler.browser")
local session = Browser.new()
local response = session:check(
    "local answer: integer = 42",
    "example.nupp",
    {strict = true, dialect = "lua51"}
)
```

Each session creates one checker environment per output dialect and retains the
last successful tree for hover, and a JSON `request` method adapts this
structured surface to a Worker message without becoming the internal API.

### Compiler-private providers

The lexer depends on a private `TriviaArena` contract: the native entry selects
the FFI provider and the portable entry selects the table provider before the
first arena is constructed, and both providers are checked source passing the
same compiler-owned suite.

This contract does not enter `nupp.runtime.seam.registry`, which says which
representations and host facilities generated programs may require, where
compiler storage selection is an implementation detail.

The portable entry makes the same one-time choice for scalar bit operations and
the pinned lunajson adapter, and installs no fake `ffi`, `jit`, or LPeg
modules.

### Target source selection

A module target's `sources` selects its initial checked and packaged source set,
static dependencies extend that set, entries remain unconditional, and a
computed `require` succeeds only if another selection included its eventual
module.

The browser target uses this rule to exclude the command-line build system,
project resolver, documentation renderer, C-header parser, AOT compiler,
filesystem, process, and persistent cache. An instrumented stock-Lua test
records the modules reached by startup, checking, lowering, optimization, and
hover, and refuses forbidden host dependencies.

### Target validation

Generated source is parsed by the compiler host only when the output dialect
matches that host, because a Lua 5.1 compiler producing LuaJIT source cannot use
its own parser to reject LuaJIT `const` declarations or cdata literals. The
differential corpus parses each result with its actual target runtime instead.

### Wasm host

The browser host receives compiler bytes from the Worker and verifies their
digest before calling `luaL_loadbuffer`. It exposes ownership through handles:

```c
int32_t nupp_boot(const uint8_t *bundle, uint32_t length);
uint32_t nupp_request(const uint8_t *data, uint32_t length);
const uint8_t *nupp_response_data(uint32_t handle);
uint32_t nupp_response_size(uint32_t handle);
void nupp_response_free(uint32_t handle);
```

The Wasm binary contains Lua and the expected digest, not the compiler payload
or a virtual filesystem, and a content-hashed compiler filename lets browsers
retain the proven source when only the host changes and the host when only the
compiler changes.

### Landing gates

The portable compiler lands while the Fengari playground remains live. The
playground switches only after native Lua 5.1 acceptance, Node Wasm parity,
Chromium Worker parity, site-server verification, and the boot-latency gate
all pass.

## Risks and assumptions

- Lua 5.1 parsing a multi-megabyte source bundle may dominate startup, so the
  measured browser gate requires Wasm boot plus the first check to stay within
  twenty percent of the existing playground.
- Static closure discovery cannot see computed module names, so the exercised
  browser paths carry a runtime require inventory as evidence.
- Emscripten's ES-module Worker output and buffer ABI may change, so the host
  pins one proven Emscripten version rather than accepting ambient tool
  behavior.
- A digest proves byte identity, not publisher identity, so the Pages artifact
  and its manifest still have to be delivered by the expected site.

## Alternatives considered

**Embed the compiler in Wasm.** This verifies identity through the linked
binary but couples a stable VM to every compiler edit and prevents the two
assets from being cached independently.

**Keep the JavaScript Lua host.** This retains host-specific compatibility
patches and does not prove the artifact against the runtime its dialect names.

**Publish compiler providers as language seams.** This makes lexer storage and
other compiler internals part of the generated-program compatibility contract,
where those providers have a smaller owner and a different reason to change.

**Maintain Lua fallbacks for every runtime facility.** Hashing, UUIDs, UTF-8,
PEGs, and similar facilities already have third-party Lua implementations, and a
checked adapter plus the seam's behavioral suite establishes the required
contract without the compiler maintaining another one.

## Revisited 2026-08-28

`Landing gates` described a switch-over condition, and the switch it gated
happened: the Fengari playground it names is no longer in the tree. The five
gates did not expire with it. They became recurring jobs in the playground
workflow, so a reader finding them should take them as what continuous
integration enforces on every change rather than as work still outstanding.

Stating a sequencing condition in the present tense is what made that
ambiguous. [NEP 1](0001-nep-process.md) places tracking implementation progress
outside a proposal's job, and this section is the reason why: the reasoning
above it aged correctly, while the schedule beside it did not.
