---
title: Provider-backed streaming compression
status: Implemented
created: 2026-09-14
---

## Summary

Add compression as retained format descriptors over a typed provider catalog.
A descriptor constructs bounded streaming state and supplies both ordinary byte
I/O adapters and one-shot conveniences. The first provider is Rust-native and
supports gzip, zlib and raw DEFLATE. Other targets can replace that provider at
the same seam without changing callers or adding provider decisions to chunk
operations.

## Goals

- One public acquisition path for every format, including formats added by a
  package or target-specific provider.
- Streaming through the existing `Reader`, `Writer` and span contracts, with a
  bounded amount of adapter storage.
- Validation of wrapped-format trailers before decompression reports EOF.
- Explicit output and expansion limits at the facade, independent of provider
  implementation.
- Format-specific parameters that stay typed and cannot accidentally configure
  a different format.
- A native implementation usable by interpreted, sidecar AOT, static AOT and
  embedding hosts without adding compression to unrelated artifacts.

## Non-goals

- Replacing the HTTP client's transparent content decoding in the first
  implementation. Its request limit and a decompressor output limit are
  distinct policies and must not be silently merged.
- Making compression an ambient global or folding it into byte I/O.
- Claiming raw DEFLATE has integrity protection it does not carry.
- Selecting a provider by discovery order.

## Decision

### Retained formats

`compression.format(name)` is the only public format acquisition operation. It
raises when the assembled catalog does not contain the canonical name and
returns a retained descriptor otherwise. `compression.formats()` exists for
enumeration, not as a second operational path.

The facade assembles and validates its provider catalog once while loading.
Every descriptor retains its chosen provider implementation. Encoder and
decoder steps therefore call state directly; they do not repeat a name lookup
or target test for each chunk.

This is the same class of boundary as a Java `getInstance` factory, but the name
`format` says what the returned value represents and leaves `create` available
for constructing stream state.

### Adapters and ownership

Decompression is a `Reader` wrapper because consumers already know how to read,
copy and parse that contract. Compression is a `Writer` wrapper because
producers already know how to fill it. Both factories consume the wrapped I/O
owner, so there is one close obligation and one component decides when the
underlying endpoint is released.

A compression writer has a separate consuming `finish()` operation. Finishing
may write a trailer, may suspend through its destination and may fail. The
ordinary non-suspending `close()` terminal cannot promise any of those things;
closing an unfinished wrapper aborts and reports misuse instead of manufacturing
a valid-looking stream.

Decoder EOF is likewise semantic rather than merely an empty upstream read. A
wrapper reports EOF only after the provider has reached the stream end and
validated any container checksum and size fields. Truncation, malformed data,
disallowed trailing bytes and limit violations are failures.

### Typed parameters

Workspace and safety limits are common adapter options. Codec controls are
nominal parameter records carrying a readonly format tag. The descriptor checks
that tag before constructing provider state and passes the typed record to the
provider, which validates its own fields before creating state.

This keeps the extension point open without accepting an untyped string map.
It also lets a browser provider say that it supports gzip generally but not a
particular parameter set, allowing provider selection to fall back or report a
precise unsupported option before streaming begins.

### Native boundary

The native ABI owns generational encoder and decoder handles. One call borrows
an input span and an exclusive output span, then returns scalar consumed,
written and state values. No pointer survives the call. Output space belongs to
the adapter, so normal chunking neither materializes a Lua string nor transfers
an allocation across the ABI.

The Rust implementation uses the already-selected DEFLATE ecosystem with its
pure-Rust zlib backend. Gzip and zlib verification happens in that state machine;
the Nupp adapter owns policy such as output limits and rejection of trailing
bytes.

## Rejected alternatives

### Only a reader wrapper

That makes decoding compose but leaves encoding, in-memory use and provider
selection to unrelated APIs. A symmetric descriptor with reader, writer and
one-shot operations keeps one catalog and one lifecycle model.

### Public per-format constants

Constants plus name lookup create two acquisition paths and make provider-added
formats second-class. One named operation gives built-in and supplied formats
the same seam.

### An open options table

`{[string]: any}` would defer misspelled or mismatched codec options to runtime
and force providers to interpret each other's private vocabulary. Tagged
records make the mismatch a declared contract.

### Finishing from `close`

It would hide a potentially failing write inside automatic cleanup and conflict
with the non-suspending close contract. Explicit finishing keeps publication in
ordinary control flow and cleanup as abort-only fallback.
