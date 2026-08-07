## Designed for systems work

Nupp keeps Lua's directness while adding the contracts native programs need:
nominal types, ownership, deterministic cleanup, checked C interop, and a
self-hosted toolchain.

Every valid LuaJIT program is a valid Nupp program. Annotations turn checking
on, one declaration at a time.

```nupp
local struct Vec2
    x: float
    y: float
end

@owned
local function openSession(): Session
    return Session{closed = false}
end

with session = openSession() do
    print(session.closed)
end
```

## Start here

- [Installation](start/installation.md) — requirements, a checkout, and a first
  project.
- [A tour of Nupp](start/tour.md) — the whole language in one pass.
- [Why use Nupp?](start/why.md) — what each piece is for.
- [Nupp syntax](start/syntax.md) — the syntax, and what LuaJIT 2.1 carries.

## Go deeper

- [The type system](type-system/overview.md) — gradual typing, records,
  structs, interfaces, generics, and narrowing.
- [Ownership](start/ownership.md) — resources that are hard to leak.
- [Tooling](start/tooling.md) — the checker, build system, formatter, language
  server, documentation generator, and profiler.
- [The language reference](reference.md) — every construct and the codes that
  report getting it wrong, generated from the compiler.

The generated API reference for the compiler's own modules is below.
