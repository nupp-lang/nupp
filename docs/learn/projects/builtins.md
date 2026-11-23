---
order: 515
title: Builtin libraries
---

# Builtin libraries

Some standard libraries sit on a pinned C library, or are large enough that a
program that does not use them should not pay for them. Each is registered as
a builtin, by a name such as `sqlite`. A core binary carries a builtin only
when the program reaches it, and a build can strip one by name.

## What a program carries

A core binary carries the modules its entry reaches: through `require`, a
qualified module path used as a value (`serde.json.decode`), or a `require`
of a literal name. A module nothing reaches is never checked, compiled or
carried. A builtin's C library is a separate shared library, staged beside
the bundle only when a module the bundle carries binds it, with its license
notices beside it. Nothing of a builtin is linked into the runtime itself, on
any platform. A program that never reaches a builtin carries none of its
modules, none of its libraries and none of its notices.

`nupp build --json` says what a core binary carries. `builtins` lists each
builtin the program reaches, with its modules, its staged libraries and
notices, and their bytes. `without` lists the builtins the build was asked to
strip.

## The builtins

The registry is `src/nupp/compiler/project/builtins.nupp`.

| Builtin | Modules | C library | Hosts |
| --- | --- | --- | --- |
| `sqlite` | [`sqlite`](../runtime/data/sqlite.md) and its provider | `nupp_sqlite`, the SQLite amalgamation, with its public-domain notice | native |

## Stripping a builtin

`--without` names builtins the build must not carry, separated by commas:

```bash
nupp build --without sqlite,yaml
```

A target strips them with `without`:

```lua
return {
    build = {
        targets = {
            server = {kind = "binary", stub = "nupp", entries = {"src/main.nupp"}, without = {"yaml"}},
        },
    },
}
```

The two lists are joined, and a name that is not a builtin is refused with
the nearest one that is. Changing either rebuilds the target.

A program that reaches a stripped builtin fails to build with `NUPP0006`,
which names each require on the chain from the entry to the builtin:

```text
nupp: build target "server" is built without yaml, but it reaches serde.yaml
  src/main.nupp:3        local config = require("app.config")
  src/app/config.nupp:1  local yaml = require("serde.yaml")
```

Remove the require, or stop stripping the builtin. Stripping never changes
what a program does at run time without saying so: the build fails instead.
A target whose host cannot provide a builtin, such as a browser target that
reaches a native-only library, fails the same way, naming the host.

A `require` of a computed name is not followed by the build, so it can still
ask for a builtin the build left out. It fails as a `require` of any module
the bundle does not carry: `module 'NAME' not found`.
