# Formatter

```bash
nupp fmt              # list what is unformatted, project-wide
nupp fmt --write      # rewrite in place
nupp fmt --check      # report only
nupp fmt src/x.nupp   # format one file to stdout
```

The style is fixed. There is no configuration file and no editor setting.
`nupp fmt` otherwise takes options about what to do with the result, plus two
knobs over the style itself, described below.

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

## Formatting rules

| Setting | Value |
| --- | --- |
| `Indent` | 4 spaces |
| Code width | 120 columns (--width) |
| Docblock text width | 88 columns |

Ordinary line breaks are soft: a short expression or delimited group is put on
one line. Statements, comments, docblocks, blank lines, and block closers are
structural boundaries. An over-long group breaks one element per line; with no
group to break, `and`, `or`, `..`, and the arithmetic operators are the break
points. An `if` is always broken across lines, however short it is, and an
ordinary `function` body always has its own lines. `|| ->` is the one-line
function spelling.

A chain of method calls is a sequence of steps, so an over-long chain breaks
between them rather than inside the first call's arguments. The receiver keeps
the call that heads the chain and every later step lines up under it:

```nupp:static
local production = endpoint:withUserInfo(nil):withHost("api.example.com"):withPort(nil):withQuery(nil):withFragment(nil)
```

An operator joining two operands is looser than the chain inside either of
them, so a chain that is one operand of an `and` waits until the line is down
to the chain itself. A single method call is not a chain: its arguments break.

Blank runs collapse to one, leading blanks are stripped, trailing whitespace
goes, and a file ends with exactly one newline.

Docblocks are reflowed and set off with a blank line. `@tag` lines are
recognized, continuations indent by five spaces, and fenced or indented
verbatim blocks are left alone.

`@!nofmt` is a leading inner annotation that leaves one whole file untouched:

```nupp
@!nofmt
-- generated source or a deliberate non-canonical layout
```

It must be the file's first annotation and has no region form.

A method call left in its sugar form gets its parentheses back:

```nupp:static
obj:configure({retries = 3}) -- becomes
obj:configure({retries = 3})

obj:log("starting") -- becomes
obj:log("starting")
```

A plain call is not a method call and keeps its sugar. `f{...}` and `f"..."` are
how the language spells a record constructor, and touching those would be a much
bigger, noisier rewrite than "give a method its parens back." Pass
`--no-method-parens` to turn this off and leave every call exactly as written,
or set it once for the whole project in `nupp.lua`:

```lua
return {
    fmt = { methodParens = false },
}
```

`--no-method-parens` wins if both are given; there is no flag to force parens
back on over a manifest that turned them off.

`--width N` changes the code column past which a line breaks, at least 20.
The default, 120, is unchanged from before this was a flag; docblock text
keeps wrapping at 88 columns regardless of `--width`.

## Limits

The formatter guarantees that its output re-lexes to a token sequence identical
in kind and text to the input. When a rewrite would break that, it returns the
input untouched and reports **NUPP4001**.

That invariant is why it cannot change a quote style, add or remove a table
constructor's trailing comma, or rewrite a numeric literal. That is not a policy
decision: those change the token stream.

Two rewrites are exempted, each proven safe rather than merely whitespace. A
single-value annotation loses its redundant `member =` where the checker has
proved the two spellings equivalent:

```nupp
@documentation(text = "A user")   -- becomes
@documentation("A user")
```

Those tokens are marked for omission and excluded from the fingerprint.
The final comma in a type shape is likewise redundant and is omitted.
Parenthesizing a method call's sugar-form arguments, described above, is the
other rewrite: the inserted tokens are folded into the sequence checked against
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

## Diagnostics

- **NUPP4001**: formatting could not safely produce a result, so the input is
  left untouched. The formatter refuses whatever it cannot prove it would
  preserve.
