## Try Nupp

This is the real compiler, running in your browser: `bootstrap/nupp.lua` in a
Lua VM, not a round-trip to a server. It re-checks on every edit, so breaking a
program is the quickest way to see what the checker actually says. Pick another
from the menu, or edit this one.

```playground
```

[Open the full playground](/playground/) for the diagnostics list and the Lua
each program compiles to.

## Start here

- [Installation](start/installation.md) — requirements, a checkout, and a first
  project.
- [A tour of Nupp](start/tour.md) — the whole language in one pass.
- [Reasons to use Nupp](start/why.md) — what each piece is for.
- [Nupp syntax](start/syntax.md) — the syntax, and what LuaJIT 2.1 carries.

## Go deeper

- [Type system](type-system/overview.md) — gradual typing, records,
  structs, interfaces, generics, and narrowing.
- [Ownership](start/ownership.md) — resources that are hard to leak.
- [Effect contracts](effects.md) — what calls may observe, change, or expose.
- [Tooling](start/tooling.md) — the checker, build system, formatter, language
  server, documentation generator, and profiler.
- [`nupp.regex`](regex.md) — compiled Rust regular expressions over Lua byte
  strings, linked only when used.
- [The language reference](reference.md) — every construct and the codes that
  report getting it wrong, generated from the compiler.

The generated API reference for the compiler's own modules is below.
