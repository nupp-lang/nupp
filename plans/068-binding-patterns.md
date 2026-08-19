# Binding patterns and braced plucking

Status: proposed — nothing below exists. Written 2026-08-18. This is the
independent binding-pattern part of superseded plan 067.

## Decision

Add shallow named binding patterns to `local` and `const`, with `as` for local
aliases. Change plucked named arguments from parentheses to braces so a brace
consistently means "select these names" at a binding or call site. Function
parameters remain ordinary named declarations; Nupp uses plucking at the call
site for named-parameter projection.

Ship this before declared modules. The feature is generic and works with any
record or table value, including today's return-table modules:

```nupp
const {decode, Encoder as JSONEncoder} = require("nupp.data.json")
local {x, y as vertical} = position

draw({x, y} = position, color = "blue")
```

This plan does not add `type` selections. Selecting an erased type from a
module needs the declared-module interface and belongs to plan 069.

## Binding syntax

A shallow pattern may replace the single name in a `local` or `const`
declaration:

```nupp
local {x, y} = point
const {red, green as g, blue} = color
```

Each entry names a readable field. `as` changes only the name of the new local:

```nupp
local __value = color
local red = __value.red
local g = __value.green
local blue = __value.blue
```

The right-hand side is evaluated exactly once. Field reads happen once each,
from left to right in source order, so behavior is defined even for an indexer
with effects. The locals enter scope only after all reads have succeeded; a
pattern cannot refer to an earlier binding in the same pattern.

`local` creates mutable local bindings. `const` creates immutable local
bindings. Neither modifier changes the mutability of the selected fields or
the source value.

A type annotation applies to an entry, not to the whole brace:

```nupp
const {x: number, y as vertical: number} = point
```

The annotation checks the corresponding field read and the resulting local.
The parser does not admit a post-pattern annotation whose meaning would be
unclear.

The checker diagnoses:

- a missing or unreadable field;
- a repeated source field;
- repeated resulting local names, including aliases;
- an annotation incompatible with the selected field;
- selection from a value that cannot be indexed by a literal field name; and
- an affine read or partial move that the equivalent field access would not
  permit.

Initial patterns are reads and snapshots, not a new ownership operation. They
do not implicitly move fields out of an affine aggregate. Existing ownership
rules decide whether each expanded read is legal. A future move-pattern design
must handle partial initialization and destruction explicitly.

Only one value may appear on the right. This avoids giving a brace a positional
relationship with Lua's multiple returns:

```nupp
local {x, y} = point       -- valid
local {x, y} = make(), z   -- invalid
```

## Deliberate limits

The first implementation has no:

- nested patterns;
- tuple or positional patterns;
- default values or rest captures;
- computed field names;
- declaration patterns in loops or comprehensions;
- assignment to an existing set of locals; or
- destructuring in function parameter declarations.

These are separate language decisions, especially for missing values,
ownership, and evaluation order. The shallow form is useful without them.

## Braced plucked arguments

Nupp keeps normal named parameters:

```nupp
local function draw(x: number, y: number, color: string?): nil
end
```

At a call site, braces project fields into parameter slots:

```nupp
draw({x, y} = position, color = "blue")
```

This is equivalent to:

```nupp
draw(x = position.x, y = position.y, color = "blue")
```

Pluck entries are parameter names and therefore do not take `as`. In
particular, this is rejected:

```nupp
draw({y as color} = position)
```

Use an ordinary named argument when the source field and parameter differ:

```nupp
draw(color = position.y)
```

This keeps `as`'s meaning precise: it creates a local binding name. A pluck
creates no local and already has named-argument syntax for remapping.

The existing pluck semantics otherwise stay intact. The operand is a name or
dotted path, entries form an unordered parameter set, common prefixes are
evaluated once wherever the current lowering promises it, and the generated
Lua receives ordinary positional arguments. Source order never changes the
callee's parameter order.

The grammar recognizes `{...} =` as a pluck only in a call argument position.
It therefore does not reinterpret an ordinary table constructor. The
formatter always includes the spaces around `=` and uses the existing
multiline trailing-comma rules for a long brace.

## Migration from parenthesized plucks

The source tree is pre-1.0 and the rewrite is mechanical, so there is no
release in which both forms are accepted. In the same change:

1. the formatter and generator switch to braces;
2. the tree and fixtures are rewritten;
3. the old `(x, y) = value` form becomes invalid; and
4. the parser retains enough recognition to issue a targeted diagnostic with
   one whole-source fix to `{x, y} = value`.

The diagnostic compatibility does not make parentheses part of the accepted
grammar. It can be removed after downstream source has had a release containing
the fix.

## Checking and lowering

The checker represents a binding pattern as one declaration with ordered
entries rather than fabricating CST declarations. It resolves and checks the
source once, applies ordinary literal-field lookup to each entry, and then
installs all result locals. Definition, reference, rename, and ownership data
attach to the real entry nodes.

Generation evaluates the source into a temporary whenever repeating it could
change behavior or duplicate work. A simple stable local may be reused. Each
field is then read into the new local. Optimizations may remove the temporary
only when they preserve the one-evaluation and left-to-right guarantees.

Pattern use with a statically understood return-table module is ordinary
structural field selection. It does not create a second module resolver and
does not change `require` semantics. Plan 069 extends the same pattern node
with a module-only erased `type` entry after declared interfaces exist.

## Tooling

- The formatter preserves entry order and `as` aliases and uses trailing
  commas for multiline patterns.
- Completion after `{` offers readable fields and excludes fields already
  selected.
- Go-to-definition on the source name reaches the selected field; on the alias
  it reaches the local binding.
- Rename of an aliased local changes only the alias and its references. Rename
  of an unaliased local may insert `as` rather than rename the source field.
- Code actions provide the whole parenthesis-to-brace pluck migration.
- Hover states both the selected field type and the resulting local type.

## Implementation sequence

1. Add CST nodes for shallow binding patterns and braced plucks.
2. Parse, format, and round-trip both new forms; recognize old plucks only for
   their diagnostic and fix.
3. Check patterns by the equivalent ordered field reads and install all locals
   after selection.
4. Lower patterns with one source evaluation and update ownership/source maps.
5. Change pluck lowering to consume the brace CST without changing its runtime
   argument ordering.
6. Extend LSP completion, navigation, rename, hover, and code actions.
7. Rewrite the compiler, standard library, tests, and docs atomically.

## Verification

- Parser and formatter round trips for local and const patterns, aliases,
  annotations, multiline braces, and braced plucks.
- Diagnostics and fixes for old plucks, illegal `as` in plucks, repeated source
  or local names, missing fields, incompatible annotations, and unsupported
  nested patterns.
- Runtime tests proving the source is evaluated once and effectful fields are
  read once from left to right.
- Ownership fixtures proving a pattern grants no partial-move escape hatch.
- Generator and bytecode fixtures proving a module destructure is direct field
  selection with no helper or per-use loader.
- LSP fixtures for definitions, references, aliases, rename, completion, and
  source maps.
- Compiler `fixpoint` after self-hosted source adopts braces.

## Completion criteria

- Shallow `local` and `const` patterns work for ordinary values and current
  return-table modules.
- `as` is the single binding-alias spelling and is not accepted in plucks.
- Braced plucks are the only accepted pluck syntax, with a mechanical fix from
  the old form.
- Function parameter declarations remain ordinary named declarations.
- Evaluation and ownership behavior matches the explicit expanded reads.
