---
order: 540
title: Service Providers
---

# Service Providers

A package can advertise named capabilities without asking its consumers to copy a
driver script into their projects. Nupp reads static capability metadata first and
checks the declared provider exports without executing them. The same discovery format
supports build-time code generators and runtime services.

Capability metadata belongs in `nupp/capabilities.json` inside an installed LuaRock:

```json
{
  "schema": 2,
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
      "contract": "mycodec.contract",
      "export": "service",
      "entry": "mycodec.json",
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

Declare one canonical interface and typed handle in a module that loads no
implementations:

```nupp
module mycodec.contract
local services = require("nupp.services")
export interface Codec
    readonly encode: function(value: any): string
    readonly decode: function(text: string): any
end
export const service: services.Service<Codec> = services.define("nupp.codec", 1)
```

The annotation supplies generic inference. `Service<T>` is invariant: a handle for
one interface cannot be assigned to a handle for another.

| Method | Result |
| --- | --- |
| `register(name, loader)` | Registers a checked `function(): T` without loading it |
| `select(name)` | Chooses the default before it resolves |
| `lookup(name?)` | Loads and caches the implementation, or returns `nil` if absent |
| `require(name?)` | Loads and caches the implementation, or raises if absent |
| `list()` | Returns registered names in sorted order without loading them |

Duplicate names fail. Successful named loads retain identity. Failed loads and
cycles report the service and provider involved. Instances and registrations
belong to the current Lua state.

A facade resolves during its top-level initialization:

```nupp
module mycodec
local contract = require("mycodec.contract")
export = contract.service:assemble(function(): contract.Codec
    return contract.service:require("json")
end)
```

`assemble(defaultLoader, validator?)` resolves an explicit selection or calls the
facade's default loader. `assembleOptional` permits a missing default. Both freeze
the loaded facade's default selection; later `select` calls fail. Optional absence
is also fixed for that facade. Validators run before an implementation is published.
The module returns the actual provider operations, and normal `require` caching
retains them. Store the module or its methods in locals and call them directly.

A setup entry selects providers before it imports consumers:

```nupp
module setup
local contract = require("mycodec.contract")
contract.service:select("json")
return require("application")
```

Put provider packages in the target's `dependencies`. The build validates the
service identity, API version, canonical handle, and implementation export together.
Provider exports may have additional members. Generic parameters, optional members,
ownership, and suspension guarantees must satisfy the canonical interface. External
Lua providers supply `.d.nupp` declarations or typed adapters. Runtime shape checks
come from the declared contract; behavioral tests remain necessary.

Only target dependencies contribute runtime providers. Generator and compile-only
packages do not register them. Discovery order never selects a third-party default.
The artifact catalog contains compatible provider declarations without executing
their modules. `nupp build --json` reports these declarations in `services`,
including their canonical contract, API version, entry, and exporting dependency.

Worker lanes load fresh instances. `services.setupWorkers("workersetup")` registers
an ordinary setup module for child initialization; include it in the artifact's
entries. Catalog-backed named selections are replayed before child consumers load.
Runtime-only registrations require setup in the destination state.

The GPU service exports the complete provider protocol from
`nupp.runtime.services.gpu`. Providers implement its shared buffer, kernel, binding,
and context interfaces with their own records. Applications use `nupp.gpu`'s context
interface, which exposes device operations without provider state or generated-kernel
hooks. Context cleanup uses the canonical `destroyContext` contract.

Portable 64-bit arithmetic uses `numeric.int64`. A stock Lua target may select an
integer provider without physical storage. When a storage provider supplies integer
operations, the integer facade uses that same instance; selecting an incompatible
instance fails initialization. Provider selection cannot change the target's pointer
or machine layout.

## Implementing a runtime contract

Import the canonical declaration module in both the provider and setup. Give the
provider export an explicit interface annotation so its entire shape is checked:

```nupp
module mycodec.text
local {type Codec} = require("mycodec.contract")

local codec: Codec = {
    encode = function(value: any): string
        return tostring(value)
    end,
    decode = function(text: string): any
        return text
    end,
}

export = codec
```

For a runtime registration, supply a typed loader in setup:

```nupp
module setup
local contract = require("mycodec.contract")

contract.service:register("text", function(): contract.Codec
    return require("mycodec.text")
end)
contract.service:select("text")
return require("application")
```

A packaged provider uses the descriptor's `contract` and `export` fields to name
that same handle. `entry` names the implementation module; omit `member` when the
module itself returns the provider. The declared API must match the handle. An
implementation can mark its module `@!internal` while keeping its canonical
contract public. Built-in implementation modules are internal; applications use
facades, and third-party implementers depend on the contract declarations.

The interface is also a behavioral protocol. Respect its receiver arguments,
pending and EOF results, byte encodings, cleanup rules, and callback lifetimes.
A signature containing `self` requires the retained provider or resource as that
argument. A receiver-free function can be assigned directly to the facade. Generic
methods must work for every permitted type, and an affine result must preserve
the canonical cleanup identity. Extra fields cannot weaken these requirements.

Keep host-dependent initialization inside the provider loader or facade assembly.
Declaration imports and catalog discovery must not open devices, create clients,
or load resolving facades. If two providers depend on each other, restructure
their initialization so a loader does not require a facade already resolving.
The diagnostic reports the dependency cycle.

Successful named loads are cached independently. Named `lookup` and `require`
do not select the default. An unnamed lookup freezes its result, even if it is
`nil`; later registration cannot change that loaded facade. An explicitly selected
but missing name raises instead of falling back. Failed loads clear their loading
state and may be retried, but a successfully resolved default cannot be reselected.

## Built-in contract declarations

These are the public extension points. Import the listed declaration and use its
handle before loading the consuming facade. The module API documentation specifies
member behavior and shared types.

| Declaration module | Handle | Service ID | API |
| --- | --- | --- | --- |
| [](nupp.runtime.services.contracts) | `bitops` | `numeric.bitops` | 1 |
| [](nupp.runtime.services.contracts) | `buffer` | `text.buffer` | 1 |
| [](nupp.runtime.services.contracts) | `crypto` | `host.crypto` | 1 |
| [](nupp.runtime.services.contracts) | `cstorage` | `representation.cstorage` | 1 |
| [](nupp.runtime.services.contracts) | `int64` | `numeric.int64` | 1 |
| [](nupp.runtime.services.contracts) | `json` | `data.json` | 2 |
| [](nupp.runtime.services.contracts) | `path` | `host.path` | 1 |
| [](nupp.runtime.services.contracts) | `storage` | `host.storage` | 1 |
| [](nupp.runtime.services.contracts) | `time` | `host.time` | 1 |
| [](nupp.runtime.services.contracts) | `uri` | `host.uri` | 1 |
| [](nupp.runtime.services.contracts) | `uuid` | `data.uuid` | 1 |
| [](nupp.runtime.services.digest) | `service` | `nupp.digest` | 1 |
| [](nupp.runtime.services.checksum) | `service` | `nupp.checksum` | 1 |
| [](nupp.runtime.services.mac) | `service` | `nupp.mac` | 1 |
| [](nupp.runtime.services.system) | `service` | `host.system` | 1 |
| [](nupp.runtime.services.gpu) | `service` | `host.gpu` | 1 |
| [](nupp.runtime.services.http) | `service` | `host.http` | 1 |
| [](nupp.runtime.services.net) | `service` | `host.net` | 1 |
| [](nupp.runtime.services.process) | `service` | `host.process` | 1 |
| [](nupp.runtime.services.suspension) | `service` | `suspension` | 1 |
| [](nupp.runtime.services.tls) | `service` | `host.tls` | 1 |
| [](nupp.runtime.services.workers) | `service` | `host.workers` | 1 |

SPI covers facilities whose implementation varies. Fixed runtime libraries remain
ordinary modules. Struct-value and Wasm memory protocols are parts of a coherent
storage family and have no independent selection handles.

The digest, checksum, and MAC extension points select algorithm catalogs.
Implementation names are distinct from algorithm names. A selected catalog can
override matching built-ins or add algorithms; the facade retains its descriptors
at require time. See [Digests and checksums](../runtime/data/digests.md) for catalog
shape, state ownership, and standard algorithm requirements.

Use [](nupp.runtime.services.cancellation) when a provider constructs or recognizes
task cancellation. Use the shared Buffer, URI, process Exit, worker scope, and GPU
types referenced by the interfaces. Recreating an equivalent-looking record does
not recreate its nominal identity or ownership guarantees.

Test an implementation in an isolated Lua state with its setup loaded first.
Check the contract's success, failure, cancellation, and cleanup behavior, then
verify that repeated operations leave the SPI resolution count unchanged. Test
different selections in separate states because a loaded facade's default is fixed.

## Dependency roles

Dependency `kind` says how Nupp acquires something: `c`, `cargo`, `luarocks`, or
`types`. Its use site determines a separate role:

- `generators.*.using` and docs-target dependencies are host tools;
- `compileDependencies` contribute declarations while compiling, but are not packaged;
- `dependencies` on an ordinary target contribute its compile and runtime/link/package
  closure.

When the same name is both compile-only and a target dependency, the target role wins.
Roles propagate through explicit dependency edges.

Omitting `compileDependencies` makes `kind = "types"` dependencies ambient. When
`compileDependencies` is present, only its listed dependencies contribute those
compile-only declarations.

See [build.md](build.md) for the rest of the target and dependency configuration.
