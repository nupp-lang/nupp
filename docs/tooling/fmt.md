# The formatter

```bash
nupp fmt              # list what is unformatted, project-wide
nupp fmt --write      # rewrite in place
nupp fmt --check      # report only
nupp fmt src/x.nupp   # format one file to stdout
```

The style is fixed. There is no configuration file, no manifest key, and no
editor setting. `nupp fmt` otherwise takes options about what to do with the
result, plus one knob over the style itself: `--no-method-parens`, described
below.

## Three modes

**Naming files** formats each to stdout, whether or not it changed. A filter
that sometimes emits nothing is a filter that sometimes empties a file.

**`--write`** rewrites in place, lists what it changed, and exits 0.

**`--check`, or naming no files, or `--json`** lists the files that are not
formatted, writes nothing, and exits 1 if the list is non-empty. With no files
the subject is every `.nupp` and `.d.nupp` under the manifest's include roots,
minus build output.

`--write` and `--check` together is a usage error: one fixes the formatting and
the other reports it.

`--json` separates a file that *cannot* be formatted from one that merely is
not:

```json
{"ok": true, "unformatted": ["src/a.nupp"], "written": 0, "failed": []}
```

## What it does

```
 Setting              Value
 ───────────────────  ──────────
 Indent               4 spaces
 Code width           120 columns
 Docblock text width  88 columns
```

Existing line breaks are respected — lines are never joined. An over-long line
breaks one element per group: an argument list, a parameter list, a table
constructor. With no group to break, `and`, `or`, `..`, and the arithmetic
operators are the break points. An `if` is always broken across lines, however
short it is.

Blank runs collapse to one, leading blanks are stripped, trailing whitespace
goes, and a file ends with exactly one newline.

Docblocks are reflowed and set off with a blank line. `@tag` lines are
recognized, continuations indent by five spaces, and fenced or indented
verbatim blocks are left alone.

A method call left in its sugar form gets its parentheses back:

```nupp
obj:configure{retries = 3}   -- becomes
obj:configure({retries = 3})

obj:log"starting"            -- becomes
obj:log("starting")
```

A plain call is not a method call and keeps its sugar — `f{...}` and `f"..."`
are how the language spells a record constructor, and touching those would be
a much bigger, noisier rewrite than "give a method its parens back." Pass
`--no-method-parens` to turn this off and leave every call exactly as written.

## What it will not do

The formatter guarantees that its output re-lexes to a token sequence identical
in kind and text to the input. When a rewrite would break that, it returns the
input untouched and reports **NUPP4001**.

That invariant is why it cannot change a quote style, add or remove a trailing
comma, or rewrite a numeric literal — not as a policy decision, but because
those change the token stream.

Two rewrites are exempted, each proven safe rather than merely whitespace. A
single-value annotation loses its redundant `member =` where the checker has
proved the two spellings equivalent:

```nupp
@documentation(text = "A user")   -- becomes
@documentation("A user")
```

Those tokens are marked for omission and excluded from the fingerprint.
Parenthesizing a method call's sugar-form arguments, described above, is the
other: the inserted tokens are folded into the sequence checked against
instead, so a bug that put a paren in the wrong place would still be caught.

## Idempotence

`fmt(fmt(x)) == fmt(x)`, asserted over the whole test corpus. Internally the
formatter iterates to a fixpoint, capped at 24 passes.

## In an editor

The language server implements `textDocument/formatting` and
`textDocument/rangeFormatting` with the same formatter. Two details matter:

- A file with parse errors produces no edits. A file that does not parse is
  left exactly as it is.
- Edits are emitted per run of changed lines rather than as one
  whole-document replacement, which preserves cursors and folds.

Range formatting formats the whole document and then keeps the edits that fall
inside the requested range.
