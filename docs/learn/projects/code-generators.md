---
order: 535
title: Code Generators
---

# Code Generators

A package advertises build tools in `nupp/capabilities.json`:

```json
{"schema":2,"capabilities":[
  {"kind":"generator","name":"codegen","api":1,"entry":"smithy_nupp.codegen"}
]}
```

The descriptor is data. Runtime implementations use [SPI](spi.md).

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

