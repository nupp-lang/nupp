---
name: nupp-c-style
description: Apply Nupp's C style when writing, adopting, or reviewing Nupp-owned C source and headers.
---

# Nupp C style

Nupp's layout comes from handwritten LuaJIT C at Nupp's pinned revision:
[tables](https://github.com/LuaJIT/LuaJIT/blob/1edc3e52b67eaf6ce5f809be8e17d6862594b8bc/src/lj_tab.c),
[strings](https://github.com/LuaJIT/LuaJIT/blob/1edc3e52b67eaf6ce5f809be8e17d6862594b8bc/src/lj_str.c),
[debug support](https://github.com/LuaJIT/LuaJIT/blob/1edc3e52b67eaf6ce5f809be8e17d6862594b8bc/src/lj_debug.c),
and [bytecode writing](https://github.com/LuaJIT/LuaJIT/blob/1edc3e52b67eaf6ce5f809be8e17d6862594b8bc/src/lj_bcwrite.c).

Indent in two-column steps with eight-column tabs for deeper indentation.
Aim for 80 columns. Put function opening braces on the next line and control
braces on the same line. Write `} else {`, `if (ready)`, `fn(a, b)`, and `T *ptr`.

For Nupp, preserve existing names and ABI. Use one statement per line, expand
blocks, and leave blank lines between definitions and major steps. Review
the groups inside functions by hand.

```c
static int save(const char *path)
{
  FILE *file = fopen(path, "w");
  if (file == NULL) {
    return -1;
  }

  int status = write_payload(file);

  int close_status = fclose(file);
  return status != 0 ? status : close_status;
}
```

From the repository root with pipx installed, run `scripts/format-c --write`
to format rollout files or `scripts/format-c --check` for the CI check.
Add new or adopted Nupp-owned files to the [rollout list](../../../scripts/format-c).
Keep legacy, generated, and vendored files outside the rollout.
