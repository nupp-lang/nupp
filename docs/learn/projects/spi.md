---
order: 500
title: SPI
---

# SPI

`nupp.spi.load(Interface)` iterates the implementations a package advertises.
A module chooses one while it initializes, and the choosing is ordinary code.

The interface is an exported declaration in a module that does not initialize
its consumer:

```nupp [src/example/codec/spi.nupp]
module example.codec.spi

export interface Codec
    @readonly
    priority: integer?
    @readonly
    encode: function(value: string): string
end
```

## Implementations

An implementation exports the interface's members directly:

```nupp [src/example/fastcodec.nupp]
module example.fastcodec

export const priority: integer = 10
export function encode(value: string): string
    return value
end
```

The fallback is another module of the same shape, and nothing advertises it:

```nupp [src/example/defaultcodec.nupp]
module example.defaultcodec

export function encode(value: string): string
    return value
end
```

Both return their input unchanged: the example is about the selection, not the
codec. An implementation needs typed Nupp source, a `.d.nupp` declaration, or a
typed adapter, and the build holds it to an ordinary assignment covering
generic functions, borrowing, ownership, and suspension. A plain `.lua` module
carries nothing to check:

```text
nupp: SPI implementation needs typed Nupp or a declaration: example.luacodec
```

Checking is by signature. A provider still needs behavioral tests for its byte
formats, ownership, cleanup, cancellation, and supported hosts.

## Advertising

A package lists its implementation modules in `nupp/spi.json`, under the
interface's qualified name:

```json [nupp/spi.json]
{
  "example.codec.spi.Codec": ["example.fastcodec"]
}
```

The name is the interface module and the interface it exports, in ordinary
dots. Imported aliases and re-exports resolve to the defining interface, which
must be exported and take no type parameters:

```text
nupp: SPI declaration must name a concrete exported interface: example.codec.spi.Transform
```

## Choosing an implementation

This consumer takes the unique highest priority and keeps the one function it
calls:

```nupp [src/example/codec/init.nupp]
module example.codec
local spi = require("nupp.spi")
local {type Codec} = require("example.codec.spi")

local impl: Codec = do
    local chosen: Codec?
    local tied = false
    for candidate in spi.load(Codec) do
        if chosen == nil or (candidate.priority ?? 0) > (chosen.priority ?? 0) then
            chosen = candidate
            tied = false
        elseif (candidate.priority ?? 0) == (chosen.priority ?? 0) then
            tied = true
        end
    end
    assert(not tied, "multiple codec implementations have the highest priority")
    yield chosen ?? require("example.defaultcodec")
end

export const encode = impl.encode
```

`priority` belongs to this interface and its consumer, and SPI knows nothing
about it. Another consumer can compare capabilities, read configuration,
combine implementations, or reject duplicates instead. Discovery order assigns
no preference: the use site decides what wins.

Initialization selects once, so a later call through `encode` performs no SPI
lookup.

## Discovery order

The application's own descriptor comes first, then the target's runtime
dependencies in declared order, depth first, visiting each dependency once. A
module array keeps its order, a repeated interface and module pair appears
once, and tool-only and compile-only dependencies contribute nothing.

## Lazy loading

Creating an iterator executes no provider. Each advance requires one module, so
stopping early leaves the rest unloaded, and an empty index gives an empty
iterator. A provider that fails to load propagates its ordinary `require`
error, values and identities intact, and ordinary module caching keeps an
implementation's identity within a Lua state.

## Build artifacts

A build writes a data-only index and the advertised modules into its artifact,
and reports what it found:

```json [nupp build --json, excerpt]
"spi": [
  {
    "interface": "example.codec.spi.Codec",
    "implementation": "example.fastcodec",
    "dependency": "application"
  }
]
```

`dependency` is the package the descriptor came from, or `application` for the
project's own. Editing a descriptor invalidates the generated index.

## Standard-library providers

A standard-library consumer chooses the unique highest `priority`, counts an
omitted one as zero, and fails initialization on equal highest priorities.
Without an external implementation it chooses its built-in fallback under
ordinary target and host conditions.

| Interface module | Implementation interface |
| --- | --- |
| `nupp.text.spi` | `TextBufferProvider` |
| `nupp.codec.json.spi` | `JsonProvider` |
| `nupp.random.spi` | `CryptoProvider` |
| `nupp.io.path.spi` | `PathProvider` |
| `nupp.io.uri.spi` | `UriTextProvider` |
| `nupp.time.spi` | `TimeProvider` |
| `nupp.runtime.bitops.spi` | `BitopsProvider` |
| `nupp.runtime.uuid.spi` | `UuidProvider` |
| `nupp.runtime.representation.spi` | `CstorageProvider`, `Int64Provider` |
| `nupp.digest.spi`, `nupp.checksum.spi`, `nupp.mac.spi` | `Provider` |
| `nupp.compression.spi`, `nupp.system.spi`, `nupp.gpu.spi` | `Provider` |
| `nupp.io.files.spi`, `nupp.io.http.spi`, `nupp.io.net.spi`, `nupp.io.tls.spi`, `nupp.io.process.spi` | `Provider` |
| `nupp.suspension.spi`, `nupp.workers.spi` | `Provider` |

An algorithm catalog overlays its entries on the built-in catalog, and each
interface module declares the shared resource types and cleanup identities to
reuse. Storage and its integer operations must use one coherent
representation, because selection cannot change the layout compiled into the
program.

## Workers

A worker receives the artifact's immutable index and loads its own module
instances in its own Lua state. Provider objects and closures do not cross a
worker boundary.

::: seealso
- [standard-library.md](../runtime/data/standard-library.md) for how a
  standard-library consumer picks its provider
- [libraries.md](portability/libraries.md) for which operations vary by host
:::
