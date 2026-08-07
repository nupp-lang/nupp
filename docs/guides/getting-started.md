# Getting started

This guide builds a small Nupp program, checks it, and runs it. It assumes the
`nupp` executable is on your path. From a Nupp source checkout, use
`./bin/nupp` anywhere this guide says `nupp`.

## Create the project

Make this layout:

```text
hello/
├── nupp.lua
└── src/
    └── app/
        └── main.nupp
```

Nupp projects use camelCase for functions, methods, locals, fields, and module
names. Use PascalCase for records, structs, interfaces, and other types. Names
imported from C keep the spelling of the C API.

Put the Nupp source in `src/app/main.nupp`. The second tab shows the Lua shape
the compiler emits:

::: code-group
```nupp [Nupp]
local function greetingFor(name: string): string
   return "Hello, " .. name .. "!"
end

local recipient = "Nupp"
print(greetingFor(recipient))
```

```lua [Generated Lua]
local function greetingFor(name)
   return "Hello, " .. name .. "!"
end

local recipient = "Nupp"
print(greetingFor(recipient))
```
:::

This is ordinary Lua-shaped code with contracts where they help. The local
function and variable do not leak into `_G`, and the parameter and return type
make the function's boundary checkable.

## Add the manifest

Put this in `nupp.lua`:

```lua
return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "modules",
            entries = { "app.main" },
         },
      },
   },
}
```

`include` defines the roots where project modules live. The entry
`app.main` maps to `src/app/main.nupp`; generated Lua keeps that module path
under `build/`.

## Check before running

From the project root:

```bash
nupp check
nupp build
nupp run src/app/main.nupp
```

`check` validates the configured project without writing build output.
`build` compiles the default target and its module closure. `run` is the quick
path for executing one source file and passes any remaining arguments to it.

During normal development, check the whole project rather than only the file
you changed. That lets Nupp verify module boundaries, annotation definitions,
ownership contracts, and project lint settings together.

## Grow by modules

Put reusable code in a module table and return that table. Require it where it
is used, even when a type annotation can name the module path directly. This
keeps the runtime dependency visible alongside the type dependency.

The [modules and types guide](../modules-and-types/index.html) shows that
pattern with a complete two-file example. When the program acquires files,
sockets, or C handles, continue with
[managing resources](../managing-resources/index.html).

For every build option, see the [build system reference](../build/index.html).
