# Working with LuaRocks

Nupp libraries are distributed as Lua rocks. LuaRocks owns versions, dependency
resolution, servers, and publication; Nupp adds a typed module surface beside the Lua
that `require` loads.

## Start a library

```bash
nupp rock init string-tools
cd string-tools
```

The generated project has one runtime module and one declaration with the same module
path:

```text
string-tools/
├── nupp.lua
├── string-tools-dev-1.rockspec
├── src/
│   └── string_tools.nupp
├── nupp/
│   └── string_tools.d.nupp
└── tests/
    └── run.lua
```

The source builds to `build/string_tools.lua`, which LuaRocks installs as an ordinary
Lua 5.1 module. The rockspec's `copy_directories = { "nupp" }` carries the declaration
inside that rock's versioned installation. Nupp finds it there without putting it on
Lua's runtime path.

For a nested module, mirror the runtime name beneath `nupp/`:

```text
 Runtime module                 Declaration
 build/http/client.lua         nupp/http/client.d.nupp
 build/http/server/init.lua    nupp/http/server.d.nupp
```

A declaration is the public contract, not another implementation. It should contain
the exported records, types, functions, ownership effects, and return table, but no
function bodies. A rock may leave an internal Lua module undeclared; requiring it then
has the usual gradual boundary (`unknown` under strict checking).

## Build and test the rock

```bash
nupp test
nupp rock pack
nupp rock test
```

`nupp rock pack` checks the project and every declaration beneath `nupp/`, builds the
runtime Lua, and runs `luarocks make --pack-binary-rock`. Name a rockspec when the
directory contains more than one:

```bash
nupp rock pack string-tools-1.0-1.rockspec
```

`nupp rock test` packs the same artifact, installs it into a new temporary rock tree,
checks that every declaration has a runtime module, and checks a new consumer project
against the installed declarations. This catches files that happened to work from the
author's checkout but were absent from the rock.

Nupp does not publish or store LuaRocks credentials. Upload the checked rock with the
usual LuaRocks tooling:

```bash
luarocks upload string-tools-1.0-1.rockspec
```

## Consume a typed rock

Pin the rock in `nupp.lua` and put it on the target that uses it:

```lua
return {
   include = { "src" },
   dependencies = {
      string_tools = {
         kind = "luarocks",
         rock = "string-tools",
         version = "1.0-1",
      },
   },
   build = {
      entries = { "app.main" },
      dependencies = { "string_tools" },
   },
}
```

The build installs it into the project's `.rocks` tree. At run time,
`require("string_tools")` follows LuaRocks' normal `LUA_PATH`; during checking and in
the language server, the same require reads the installed `nupp/string_tools.d.nupp`.
Completion, hover, definition, and downstream interface invalidation therefore use the
published contract.

Project modules take precedence over installed declarations. This makes a local module
an intentional override and keeps dependency trees from changing what the project
itself names.

For local development, pin a rockspec and source directory instead of a server
version:

```lua
string_tools = {
   kind = "luarocks",
   rock = "string-tools",
   path = "vendor/string-tools",
   rockspec = "vendor/string-tools/string-tools-dev-1.rockspec",
}
```

Nupp reruns `luarocks make` when that directory changes. A changed declaration
invalidates the modules that require it; an unchanged installed interface remains a
warm incremental dependency.

## Native libraries

A library implemented partly in C or Rust is still published as a rock. Use Nupp's C
or Cargo dependency providers to build the native implementation, expose an ordinary
Lua module, and describe that Lua-facing module in `nupp/`. Consumers depend on the
rock, not on Cargo.

Native rocks normally need one artifact per supported platform. Pure Nupp libraries
produce platform-independent `.all.rock` files.

## Bundled applications

Publishing a library and distributing an application are separate operations. A
modules build uses the project-local rock tree. A bundle or stamped binary has no tree,
so the dependency's `bundle` globs select the Lua modules carried into
`package.preload`. See [carrying a rock into a bundle](build.md#carrying-a-rock-into-a-bundle).
