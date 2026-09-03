---
title: Seams as declared contracts
status: Implemented
created: 2026-09-03
---

## Summary

A seam is one entry in a registry, one declared interface, and one conformance
suite. Nothing else. The per-contract factory module is gone, the backend that
selected one is a declaration rather than a constructor call, and a contract
with no implementation anywhere is not carried at all.

[NEP 13](0013-dialects-and-capability-backends.md) decided what a seam is and
why substitution has to be checkable. This proposal does not revisit that. It
records what the shape of it cost after a year of contracts accumulating, and
what was removed.

::: seealso
- [NEP 13](0013-dialects-and-capability-backends.md) for the design this
  narrows
- [libraries.md](../learn/projects/portability/libraries.md) for how a backend
  is written today
:::

## Motivation

### One contract was stated in four places

A seam's members lived in its factory module as two lists of strings. Its
identity lived in the registry. Its declared interface, where it had one, lived
in `nupp.runtime.seam.contracts`. Its name lived again in whichever compiler
table classified the module it stood behind.

`contracts.nupp` was written to end exactly this drift, and it did -- for the
seven contracts that had been migrated. The other twenty-two still spelled out
member lists that nothing compared against anything.

### The browser provider list was written three times

The compiler resolves a build against a descriptor rather than requiring the
backend module, because requiring one meant loading eighteen factory modules to
learn eighteen strings. So `nupp.compiler.browser` restated the browser
backend's selections, and the portable-compiler differential oracle restated
them again.

All three had to agree. Two of them did not: the oracle listed twelve seams
where the backend selected eighteen, so it generated code for a program with no
`text.buffer`, `host.path`, `peg`, `numeric.simd`, `host.wasm` or `compute.gpu`
and compared it against a bundle that had all six. A comment in
`nupp.compiler.browser` already recorded the previous instance of the same
failure, where a missing `text.buffer` entry made `nupp.derive` unreachable in
a browser that had a buffer provider all along.

### A backend was code the compiler refused to run

`Backend.new("name", {JSON.seam("provider")})` is a call, so reading it
statically meant matching its shape: collecting `const` `require` bindings into
a table of local names, recognising one call against `nupp.runtime.backend`,
resolving each positional entry back to a compiler-owned factory module, and
pulling a string literal out of each. About a hundred and fifty lines
interpreting the syntax of a value.

### A third of the contracts had no implementation

`data.bitset`, `data.utf8`, `data.base64`, `data.hash`, `io.bytes`,
`host.files`, `host.net`, `host.tls` and `host.process` were carried as
registry entries, factory modules and conformance suites with no provider
anywhere in the tree, and in most cases nothing a provider could have been:
a browser has no filesystem to stand behind `host.files`. Meanwhile the
gate they imposed was real. `nupp.data.utf8` reads scalars out of ordinary
strings and needs nothing a `lua51` target lacks, and a program reaching it was
told to select a backend that could not exist.

## Decision

**A backend is a declaration.** A constant name, and a map from contract name to
the module that answers it:

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

The compiler reads the value. A seam cannot be selected twice because it is a
key, and the order it was written in is not a fact about the backend, so the
descriptor is sorted before it is fingerprinted.

**Every contract states its members once.** As a declared interface in
`nupp.runtime.seam.contracts` wherever its surface is one a loaded table can be
checked against, which is seventeen of the twenty. The other three --
`compute.gpu`, `host.workers` and `suspension` -- own affine surfaces, and an
interface restating one would either lie about the ownership or describe
something no loaded module could answer for; those name their checkable half in
the registry, beside the rest of their identity.

**One installer.** `nupp.runtime.seam.module` takes a contract name and a
provider module. The twenty factory modules that differed only in which
constants they closed over are gone, and with them the `Seam` and `Backend`
objects a backend used to be assembled from.

**A contract with no implementation is not carried.** The nine are removed. What
they gated is classified for what it is: `nupp.io` and bitsets need C storage,
the host modules need C interop, and `nupp.data.utf8` needs nothing.

## Consequences

The seam layer is three modules and one suite per contract, where it was those
plus a factory apiece. A contract is added by writing its interface, its
registry entry and its suite; there is no fourth file, and no list of module
names in a build manifest to keep in step.

Reading a backend no longer interprets syntax, so the failure modes it had --
a shadowed `require`, a non-constant name, an entry that is not a recognised
constructor call -- are not states the input can be in.

The browser host requires the browser backend's declaration instead of
restating it, and so does the differential oracle. The three lists are one.

A project that wanted to supply `host.files` or `host.net` from Lua can no
longer declare it. Nothing could, and nothing did; the contract comes back with
the provider that needs it, which is one registry entry, one interface and one
suite.
