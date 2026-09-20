---
order: 540
title: SPI
---

# SPI

`nupp.spi.load(Interface)` returns a lazy iterator of implementations. A module
chooses what it needs during initialization and exports the resulting functions.
Selection is ordinary code.

Declare the interface in a module that does not initialize its consumer:

```nupp
module example.codec.spi

export interface Codec
    readonly priority: integer?
    readonly encode: function(value: string): string
end
```

An implementation exports the interface's members directly:

```nupp
module example.fastcodec

export const priority: integer = 10
export function encode(value: string): string
    return value
end
```

The fallback is another ordinary implementation module:

```nupp
module example.defaultcodec

export function encode(value: string): string
    return value
end
```

Both implementations return their input unchanged in this minimal example.

The application or provider package advertises it in `nupp/spi.json`:

```json
{
  "example.codec.spi.Codec": ["example.fastcodec"]
}
```

The interface name uses ordinary dots. Imported aliases and re-exports resolve
to the defining interface. The interface must be exported and have no type
parameters. Implementations need typed Nupp source, a `.d.nupp` declaration, or
a typed adapter; the build checks ordinary assignment compatibility, including
generic functions, borrowing, ownership, and suspension.

## Choosing an implementation

This module chooses the unique highest priority, then binds the function it uses:

Save it as `src/example/codec/init.nupp`, with the interface in
`src/example/codec/spi.nupp` and the implementation modules beside the `codec`
directory.

```nupp
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

`priority` belongs to this interface and its consumer. SPI knows nothing about
it. A different consumer can compare capabilities, use configuration, combine
implementations, or reject duplicates. Lower priority ties do not matter once a
unique higher candidate is found.

## Discovery and loading

The application descriptor comes first. Target runtime dependencies follow in
declared order, depth first, visiting each dependency once. Module arrays retain
their order; repeated interface/module pairs appear once. Tool-only and
compile-only dependencies contribute nothing.

**Discovery order assigns no preference.** The use site determines what wins.

Creating an iterator executes no provider. Each advance requires one module;
stopping early leaves later modules unloaded. Empty discovery returns an empty
iterator. A failed provider propagates its ordinary `require` error, preserving
error values and identities. Ordinary module caching preserves implementation
identity within a Lua state; each call to `load` starts a fresh iterator over that
same index.

Builds carry a data-only index and the advertised modules in their artifact.
`nupp build --json` reports them in `spi`, with `interface`, `implementation`, and
`dependency` fields. Editing a descriptor invalidates the generated index.

Module initialization selects once. Calls through the published functions do no
SPI lookup. This removes ongoing SPI overhead; initialization still takes work,
and whether a function inlines is a separate compiler decision.

## Standard-library providers

Standard-library consumers choose the unique highest `priority`, treating an
omitted priority as zero. Equal highest priorities fail initialization. Without
an external implementation they choose their built-in fallback with ordinary
target and host conditions.

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
| `nupp.io.http.spi`, `nupp.io.net.spi`, `nupp.io.tls.spi`, `nupp.io.process.spi` | `Provider` |
| `nupp.suspension.spi`, `nupp.workers.spi` | `Provider` |

Algorithm catalogs overlay their entries on the built-in catalog. Reuse the
shared resource types and cleanup identities declared by each interface module.
Storage and its integer operations must use one coherent representation;
selection cannot change the layout compiled into the program.

Workers receive the artifact's immutable index and load independent module
instances in their own Lua states. Provider objects and closures do not cross
worker boundaries.

Type checking verifies signatures. Providers still need behavioral tests for
their byte formats, ownership, cleanup, cancellation, and supported hosts.
