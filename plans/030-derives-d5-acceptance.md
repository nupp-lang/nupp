# Derives D5 acceptance record

Status: acceptance record for the built-in derives, which shipped. The
user-defined provider question it deliberately left open was answered by
[comptime-derive-recipes.md](033-comptime-derive-recipes.md).

The D5 proving workloads live in `tests/deriveacceptancetest.lua`. They exercise
the constrained built-in result model rather than proposing a provider API.

## Internal workloads

- Compiler planner limits use `Debug` and `Default`; their values and debug bytes
  are compared with a written construction before the derived result is accepted.
- A manifest/build-cache-shaped record runs a pinned JSON corpus. Encoding bytes,
  decoded values, unknown-key rejection and failure paths are compared.

## External proving case

The external model is adapted from
`tecs.io.mcp.transport.Request` in the Tecs consumer. Its public `name` and
JSON-encoded `arguments` fields run a corpus of `world.list`, `world.spawn` and
`session.inspect` requests through derived `Debug` and `JSON`.

The model needed only:

- deterministic record debug output;
- deterministic JSON field ordering;
- strict unknown-key rejection;
- string preservation for the already-encoded arguments payload.

The private `loader.CPtr` request handle is deliberately refused. It represents
runtime ownership and cannot be serialized by the constrained JSON result model.
The proving case did not request token construction, AST access, declaration
injection, arbitrary I/O, conditional member names or caller-selected lowering.

This evidence does not justify D6 by itself. A restricted user-defined semantic
provider should remain gated until an external case needs a semantic result that
cannot be expressed by the four built-ins without asking for token or AST macros.
