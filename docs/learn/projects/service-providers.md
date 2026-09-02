---
order: 540
title: Service Providers
---

# Service Providers

A package can advertise named capabilities without asking its consumers to copy a
driver script into their projects. Nupp reads static capability metadata first and
loads the entry module only after a build has selected it. The same discovery format
supports build-time code generators and runtime services.

Capability metadata belongs in `nupp/capabilities.json` inside an installed LuaRock:

```json
{
  "schema": 1,
  "capabilities": [
    {
      "kind": "generator",
      "name": "codegen",
      "api": 1,
      "entry": "smithy_nupp.codegen"
    },
    {
      "kind": "service",
      "service": "nupp.codec",
      "name": "json",
      "api": 1,
      "entry": "my_codec.json",
      "member": "codec"
    }
  ]
}
```

The descriptor is data, not executable discovery code. Unknown fields, unsupported
schema or API versions, and malformed entries fail the build before an entry module is
loaded. Provider names are local to their capability kind. Runtime service names are
unique within a service: two target dependencies cannot both provide
`nupp.codec/json`.

## Code generators

Declare the package once as a dependency, then select its generator by capability
name:

```lua
return {
   dependencies = {
      smithy = {
         kind = "luarocks",
         rock = "nupp-smithy",
         version = "1.2.0-1"
      }
   },
   generators = {
      api = {
         using = "smithy/codegen",
         inputs = { "model/**/*.smithy" },
         options = { namespace = "example.api" }
      }
   },
   build = {
      entries = { "example.main" }
   }
}
```

`using` is `dependency/provider`. Naming it makes that dependency a host tool; it is
not shipped in the target merely because the build ran it. Generator options are plain
JSON-shaped data so they can cross the worker boundary and participate in a stable
cache key.

The provider entry module returns a function, or a table with `generate`. It receives
this API 1 request:

```lua
local function generate(request)
   -- request.name       manifest instance name
   -- request.inputRoot  absolute project root
   -- request.outputRoot private staging directory
   -- request.inputs     sorted absolute declared input files
   -- request.options    manifest options
   local model = request.read("model/service.smithy")
   request.write("example/generated/client.nupp", render(model))
   request.diagnostic("note", "generated client")
end

return generate
```

`read` accepts only declared inputs. `write` accepts only paths below the staging
output. A successful run is published atomically at
`<outDir>/generated/<instance>/`, and that instance directory is a module root. A
failed run leaves the last successful output intact. The cache key includes the
provider installation, capability entry, generator configuration, and input content;
cached outputs are content-checked before reuse.

Generators run for `nupp build` and project `nupp check`. The language server uses the
last published output and never installs or executes a tool. Generator modules are
ordinary trusted build dependencies. The child process supplies time and memory
bounds and narrows the request API, but it is not an operating-system security
sandbox; do not install an untrusted provider.

## Runtime services

Put a service provider in the target's `dependencies`. During the build Nupp composes
their static descriptors into a deterministic registry. There is no filesystem scan
at program startup, and implementations are loaded lazily:

```lua
local services = require("nupp.services")

local codec = services.require("nupp.codec", "json")
local optional = services.lookup("nupp.codec", "messagepack")
local installed = services.list("nupp.codec")
```

The generic lookup returns `any` because unrelated services have unrelated contracts.
A service package should normally publish a typed facade—for example,
`codec.byName("json"): Codec`—which validates or casts the generic result once and
keeps application code typed.

Only target dependencies contribute runtime services. A package used as a generator
tool or compile-only declaration cannot silently register a runtime provider. Provider
entry modules must still be part of the target's normal LuaRock module surface and,
for single-file bundles, its configured bundled modules.

## Dependency roles

Dependency `kind` says how Nupp acquires something: `c`, `cargo`, `luarocks`, or
`types`. Its use site determines a separate role:

- `generators.*.using` and docs-target dependencies are host tools;
- `compileDependencies` contribute declarations while compiling, but are not packaged;
- `dependencies` on an ordinary target contribute its compile and runtime/link/package
  closure.

When the same name is both compile-only and a target dependency, the target role wins.
Roles propagate through explicit dependency edges.

For compatibility, omitting `compileDependencies` keeps every `kind = "types"`
dependency ambient. Once a target contains `compileDependencies`—even an empty
table—only the names it lists are compile-only inputs. This makes the migration
explicit without changing existing manifests.

See [build.md](build.md) for the rest of the target and dependency configuration.
