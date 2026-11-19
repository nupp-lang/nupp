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

Name new Nupp-owned `.c` and `.h` files in luacase. Join words directly in
lowercase, as in `definitionlist.c` and `definitionlist.h`.

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
