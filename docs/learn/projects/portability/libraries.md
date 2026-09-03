# Portable Lua libraries

Nupp libraries can be written to take full advantage of LuaJIT's performance
features, and that same library can be compiled to work with Lua 5.1 too.

```lua
return {
   include = { "src" },
   build = {
      default = "portable",
      targets = {
         native = {
            entries = { "main" },
            dialect = "luajit",
            outDir = "build/luajit",
         },
         portable = {
            entries = { "main" },
            dialect = "lua51",
            outDir = "build/lua51",
            backends = { "portable.backend" },
         }
      }
   }
}
```

## Dialect targets

A [dialect](../build.md#dialect-selection) belongs to a build target, not to a
source file. Check and build both targets before publishing the library:

```bash
nupp check --target native
nupp check --target portable
nupp build --target native
nupp build --target portable
```

The `luajit` target is the default language path. It retains LuaJIT operators,
FFI representations, and native intrinsics without a runtime dialect test. An
explicit `dialect = "luajit"` produces the same Lua as omitting the dialect.

`luajit-compat` retains those LuaJIT runtime facilities but lowers the newer
LuaJIT spellings Nupp ordinarily passes through. Use it for an embedded LuaJIT
such as LÖVE when its FFI is available but its parser is older than Nupp's
default target floor. It is not portable Lua: FFI, `jit`, `bit`, and native
struct representations remain available.

The `lua51` target lowers syntax that Nupp can preserve across Lua 5.1 through
5.4 and LuaJIT. This includes `const`, `continue`, compound assignment,
optional access and calls, lambdas, digit separators, `table.new`,
`table.clear`, and `table.clone`. It also binds moved prelude functions such as
`unpack` and `loadstring` to the name present in the running interpreter.

Checking fails closed where syntax lowering is not enough. Authored `goto` and
labels are unavailable because Lua 5.1 cannot parse them. LuaJIT-only prelude
identities and modules, including `ffi`, `bit`, `jit`, and `string.buffer`, are
unavailable to ordinary portable source. A checked seam may still name `bit`
as its exact third-party runtime dependency.

## Backend composition

A backend is a checked module that exports one declaration: a constant name,
and the provider module that answers each seam it selects. This backend
supplies portable bit operations and table-backed struct values:

```nupp
module portable.backend

export = {
    name = "portable",
    seams = {
        ["numeric.bitops"] = "bit",
        ["representation.structvalue"] = "nupp.runtime.provider.tablestruct",
    },
}
```

Every key is a seam the compiler carries and every value is a constant module
name. A seam cannot be selected twice, because it is a key; the build rejects
two selected backends that supply the same seam, and it rejects a key that
names no known contract.

The manifest names backend modules explicitly. Nupp does not scan the source
tree, the Lua module path, or installed rocks for providers. Checking reads the
declaration as a value, without executing the module's top level or requiring
the provider it names.

Each seam has a compiler-owned name, version, structural contract, installer,
and behavioral suite. A backend may select any subset of the known seams, but
each selected seam supplies its whole contract. There is no partial seam that
inherits unspecified behavior from another backend.

### Compile-bound seams

A compile-bound seam changes how a source construct lowers when its dialect
does not have the native representation. The generated module installs the
selected backend and calls the checked provider operations:

```nupp
local struct State
    value: uint32
end

local state = new State(2166136261)
state.value = state.value ~ 16777619
```

The same source uses an FFI struct and direct bitwise operator under `luajit`.
Under `lua51`, `representation.structvalue` creates the value and
`numeric.bitops` performs the XOR. The dialect decision is made while lowering;
the artifact does not branch on the running interpreter.

### Runtime-bound seams

A runtime-bound seam adapts an exact module to a standard-library or host
contract. Installation creates a lazy binding, and the first reached member
requires and validates the selected module. A missing module or incompatible
shape reports the seam and module that failed.

The installer and every conformance suite are ordinary checked `.nupp` source
files. Provider implementations are ordinary `.nupp` or `.lua` modules.
Generated Lua contains the selected installation and calls, not fallback source
stored in compiler strings.

## Dependency-provided backends

A [LuaRock dependency](../integrations/luarocks.md#consume-a-typed-rock) may carry both a
runtime provider and the checked backend module that selects it. An HMAC rock
can install this backend source as `nupp/acme/cryptobackend.nupp`:

```nupp
module acme.cryptobackend

export = {
    name = "acme.crypto",
    seams = {["crypto.hmac_sha256"] = "acme.hmac_sha256"},
}
```

The same rock installs `acme.hmac_sha256` as a runtime Lua module. That module
may implement HMAC itself or adapt another rock; Nupp requires only the seam's
`digest` and `hex` contract. The compiler-owned suite checks published
HMAC-SHA256 vectors instead of requiring Nupp to maintain another HMAC
implementation.

Pin the rock, select it on the portable target, and name its backend from the
same target:

```lua
return {
   include = { "src" },
   dependencies = {
      crypto = {
         kind = "luarocks",
         rock = "acme-crypto",
         version = "1.0-1",
      }
   },
   build = {
      default = "portable",
      targets = {
         portable = {
            entries = { "main" },
            dialect = "lua51",
            dependencies = { "crypto" },
            backends = { "acme.cryptobackend" }
         }
      }
   }
}
```

The selected dependency's checked `nupp/` root participates in backend
resolution. Its ordinary Lua modules remain in the target's rock tree. A
target that names the backend without selecting the dependency cannot resolve
the backend source or its runtime module.

This arrangement also applies to SHA-256, UTF-8, JSON, UUID, bitsets, PEG, and
host services. A package owns the adapter for the third-party API it chose,
while Nupp owns the stable seam contract and suite.

## Backend conformance

`nupp backend test` checks the backend and runs the compiler-owned suite for
every seam it contains. Name the portable dialect and the actual interpreter
to test a stock Lua result outside the compiler's LuaJIT process:

```bash
nupp backend test acme.cryptobackend \
   --dialect lua51 \
   --runtime lua5.1
```

Use `--seam` to isolate one contract and `--json` to retain the backend digest,
runtime identity, contract version, binding kind, and result:

```bash
nupp backend test acme.cryptobackend \
   --dialect lua51 \
   --runtime lua5.4 \
   --seam crypto.hmac_sha256 \
   --json
```

The command compiles the backend, seam adapters, suites, and any checked
provider source into a temporary Lua module tree. It adds the manifest's
default target rock paths for third-party modules. Set the portable target as
`build.default` when its dependencies provide the modules under test.

Checking and building never run behavioral suites. This keeps dependency
execution out of compilation, but it means a successful build is not a
conformance result. Run the suite and a consumer smoke test on every runtime
the library supports:

```bash
for runtime in lua5.1 lua5.2 lua5.3 lua5.4 luajit; do
   nupp backend test portable.backend --dialect lua51 --runtime "$runtime"
done
```

The loop proves each provider against its seam. Run the built library's own
tests with the same interpreters to prove that the complete artifact loads and
behaves correctly.

## Artifact accounting

`nupp build --json` records the resolved dialect and every seam reached by the
target. A dependency-backed entry also records the package and pinned version:

```json
{
   "dialect": "lua51",
   "backendResolution": [
      {
         "name": "crypto.hmac_sha256",
         "version": 1,
         "binding": "runtime",
         "backend": "acme.cryptobackend",
         "runtimeModule": "acme.hmac_sha256",
         "runtimeDependency": {
            "package": "acme-crypto",
            "version": "1.0-1"
         }
      }
   ]
}
```

The record also carries the backend source digest. Changing the selected
backend, its provider module, its contract version, or the dialect invalidates
the affected build cache entries. The artifact never searches for another
provider when the recorded module is absent.

## Seam catalog

A seam is one entry in `nupp.runtime.seam.registry`, which owns its identity,
its binding, and which module a selection replaces. Its members come from the
interface declared for it in `nupp.runtime.seam.contracts`, and its behaviour is
pinned by one conformance suite named after it. Installing any of them is
`nupp.runtime.seam.module`. Backend source names the seam, not a module: there
is no per-contract factory to call.

Contract versions are 1 except where the table says otherwise.

### Compile-bound contracts

Compile-bound contracts preserve source operations through a representation
selected during lowering.

| Seam | Source surface |
| --- | --- |
| `numeric.bitops` | Integer bitwise operators |
| `numeric.int64` | Wide integers and numerals |
| `numeric.simd` | SIMD values and operations |
| `representation.structvalue` | Table-backed structs |

`text.buffer` supplies `string.buffer`, which is LuaJIT's. The standard library
builds strings by appending into one, so it is what `nupp.data.serde` and the
bundled `@derive` recipes render through; a `lua51` target that reaches either
needs a provider selected, and `nupp.runtime.provider.tablebuffer` is the carried
one. The provider implements the declared module rather than replacing it, so
signatures keep naming `string.buffer.Buffer` on both targets.

`numeric.bitops` also answers the run-time half of `nupp.math`. Most reads of
`nupp.math` are lowered to operations and never reach it, but one taken as a
value is a call into a module that is itself written in bit operations, so a
`lua51` target reaching `nupp.math` needs a provider selected for the same
reason a target performing an explicit XOR does.

### Runtime contracts

Runtime contracts project a provider module into a standard or host module
after the selected backend installs it.

| Seam | Standard or host surface |
| --- | --- |
| `data.json` | `nupp.data.json` (contract 2) |
| `data.sha256` | `nupp.data.sha256` |
| `text.buffer` | `string.buffer` |
| `data.uuid` | `nupp.data.uuid4` and `uuid7` |
| `peg` | `nupp.peg`, LPeg, and `re` |
| `suspension` | `nupp.suspension` management |
| `host.path` | The environment behind `nupp.io.path` |
| `io.uri` | `nupp.io.uri` |
| `host.http` | `nupp.io.http` |
| `host.time` | `nupp.time` |
| `host.wasm` | `nupp.wasm` |
| `host.workers` | `nupp.workers` (contract 2) |
| `host.browser_crypto` | `nupp.browser.crypto` |
| `host.browser_storage` | `nupp.browser.storage` |
| `compute.gpu` | `nupp.gpu` |

One runtime contract is an accelerator rather than a contract a program needs
filled: `crypto.hmac_sha256` names no module in the table above, because
[](nupp.data.hash) answers on every target without one, being SHA-256 and
HMAC-SHA256 written in Nupp against `numeric.bitops` alone. A backend that
installs one replaces a working implementation with a faster one, which is why
the seam is not required and does not refuse a program that selected nothing.
`nupp.data.hash` prefers an installed provider from its one-shot `hmacDigest`
and `hmacHex`; its streaming constructors have none to prefer, the seam being
one-shot.

A facility that no backend can currently supply has no seam. `nupp.io`,
[](nupp.io.files), [](nupp.io.net), [](nupp.io.tls) and [](nupp.io.process)
name a capability a `lua51` target lacks rather than a contract nobody
implements, and [](nupp.data.utf8) needs neither: it reads scalars out of
ordinary strings and is portable as written.

The other runtime contracts use existing LuaJIT or compiler-provided
implementations under `luajit` and require seams when `lua51` reaches them.

## Runtime cost

Separate artifacts keep dialect selection out of the running program. A
`luajit` target uses direct operators, FFI values, and compiler-native standard
facilities where they exist. It does not install portable seams merely because
another target in the manifest names them.

A `lua51` artifact installs a backend only in modules that reach one of its
seams. Installation is idempotent, and runtime-bound provider modules load on
first use. A backend containing several seams creates all of their lazy
bindings when installed, so use smaller backends when even that setup matters.

Compile-bound operations still pay for their selected representation. A
table-backed struct uses tables, an emulated bit operation calls its provider,
and scalar SIMD may allocate.

Conformance proves behavior, not speed. Benchmark each portable provider on the
runtime combinations the library supports. Keep a native target for callers
that want LuaJIT's direct representations and operations.

## Limits

Portable lowering preserves meaning only where the compiler has a complete
lowering or a complete seam. These boundaries remain unavailable under
`lua51`:

- `cdef`, C pointers, and other `cinterop` operations;
- C-backed storage, `nupp.data.serde`, and modules built on `nupp.mem`;
- authored labels and `goto`;
- direct use of LuaJIT-only prelude identities and VM modules; and
- standard modules with no selected seam.

The runtime check at first use is structural. It can prove that a provider
loads and exposes the required values, but only `nupp backend test` exercises
the behavioral contract. A finite suite cannot prove performance or behavior
the contract does not state.

Portable SIMD and struct providers may change representation and cost, but not
observable contract behavior. A backend cannot supply a C ABI, make a Lua table
carry a C pointer, invent a compiler capability, or replace a forbidden
capability with a value that only has the same name.

::: seealso
- [build.md](../build.md#dialect-selection) for target selection, cache behavior,
  and build output
- [LuaRocks](../integrations/luarocks.md) for packaging checked source and runtime modules
- [cli.md](../../../reference/cli.md#backend) for every backend test option
- [NEP 13](../../../neps/0013-dialects-and-capability-backends.md) for the design
  record behind dialects and seams
:::
