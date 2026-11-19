---
name: nupp-c-style
description: Apply Nupp's layout and Doxygen conventions when writing, documenting, adopting, or reviewing Nupp-owned C source and headers.
---

# Nupp C style

Nupp follows PUC-Rio Lua's C layout, as specified by the repository's
[formatter](../../../.clang-format) and [C guidance](../../../AGENTS.md).
Indent with two spaces and aim for 80 columns. Put opening braces on the
same line and `else` on the line after the closing brace. Write `if (ready)`,
`fn (type arg)` in declarations and definitions, and `fn(arg)` in calls.

Preserve existing names and ABI. Use one statement per line, brace every
control body, and leave blank lines between definitions and major steps.
Put a blank line before a leading comment group and keep the group with
the code it describes. Start a file's opening comment on the first line.
Use the same spacing when editing C++ and assembly by hand.

Name new Nupp-owned `.c` and `.h` files in luacase. Join words in lowercase
with no underscores or hyphens, as in `definitionlist.c` and `definitionlist.h`.

## Doxygen comments

Open a `.c` or `.h` file with a Doxygen block containing `@file` and a brief
description of its purpose.
Use `/** ... */` above declarations for caller contracts. Put API contracts in
the header and document implementation invariants beside their code. Document
ownership, borrow duration, buffer units, thread constraints, and failure
behavior wherever callers need them. Use `@param`, `@return`, or `@retval`
when that structure makes the contract clearer. Use ordinary `/* ... */`
comments for explanations within a function body.

```c
/**
 * @file
 * @brief File queue interface for the core reactor.
 */

/**
 * @brief Takes the next finished job.
 * @return The job ticket, or zero when no finished job is available.
 */
uint64_t nuppiotake (void);
```

From the repository root with pipx installed, run `scripts/format-c --write`
to format the Nupp-owned files listed by `scripts/format-c --list`. Use
`scripts/format-c --check` to verify their layout.

## When to add a proof

Consider a bounded proof when a change adds or alters a small, precise
invariant and a failure would have substantial consequences. Copy bounds,
allocation arithmetic, and ownership across callbacks are good candidates
when tests can sample only a few inputs or operation orders.

Extend an existing proof if it covers the same contract. Use ordinary tests
for routine changes and native integration tests when the behavior depends on
the OS or the real event loop. Keep production code simple and limit any
extraction to the logic the harness needs to share.

CI runs each proof only when its covered C sources, headers, or harness change.
Use the [Nupp C proofs skill](../nupp-c-proofs/SKILL.md) to write and register it.
