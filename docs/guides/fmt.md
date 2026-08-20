# Formatter

`nupp fmt` rewrites Nupp source into one canonical layout. The style is fixed:
there is no configuration file and no editor setting, and only `--width` and
`--no-method-parens` change what the output looks like.

```bash
nupp fmt              # list what is unformatted, project-wide
nupp fmt --write      # rewrite in place
nupp fmt --check      # report only
nupp fmt src/x.nupp   # format one file to stdout
```

## Formatter modes

What a run does with its result follows from how it was called.

- **Naming files** formats each one to stdout, whether or not it changed. A
  filter that sometimes emits nothing is a filter that sometimes empties a file.
- **`--write`** rewrites in place, lists what it changed, and exits 0.
- **`--check`, naming no files, or `--json`** lists the files that are not
  formatted, writes nothing, and exits 1 when that list is non-empty.

With no files named, the subject is every `.nupp` and `.d.nupp` under the
manifest's include roots, minus build output. `--write` and `--check` together
is a usage error: one fixes the formatting and the other reports it.

`--json` separates a file that cannot be formatted from one that merely is not.
`unformatted` names the files a `--write` run would change, and `failed` names
the files whose formatting reported a diagnostic:

```json
{"ok": true, "unformatted": ["src/a.nupp"], "written": 0, "failed": []}
```

## Formatting rules

Three measurements are fixed:

- Indentation is 4 spaces.
- Code breaks at 120 columns, which `--width` moves.
- Docblock text wraps at 88 columns, which nothing moves.

### Breaking a line

Ordinary line breaks are soft: a short expression or delimited group is put on
one line. Statements, comments, docblocks, blank lines, and block closers are
structural boundaries. An over-long group breaks one element per line; with no
group to break, `and`, `or`, `..`, and the arithmetic operators are the break
points.

An `if` is always broken across lines, however short it is, and an ordinary
`function` body always has its own lines. `|| ->` is the one-line function form:

```nupp
local ready = |request: Request| -> request.method == "GET"

if ready(incoming) then
    return handler(incoming)
end
```

### Method chains

A chain of method calls is a sequence of steps, so an over-long chain breaks
between them rather than inside the first call's arguments. The receiver keeps
the call that heads the chain and every later step lines up under it:

::: code-group
```nupp [Written]
local production = endpoint:withUserInfo(nil):withHost("api.example.com"):withPort(nil):withQuery(nil):withFragment(nil)
```

```nupp [Formatted]
local production = endpoint:withUserInfo(nil)
    :withHost("api.example.com")
    :withPort(nil)
    :withQuery(nil)
    :withFragment(nil)
```
:::

An operator joining two operands is looser than the chain inside either of
them, so a chain that is one operand of an `and` waits until the line is down
to the chain itself. A single method call is not a chain: its arguments break.

### Argument lists

An argument list that no longer fits on one line is still a list, so it is
written as one: every argument under the opener, one per line, with the closing
parenthesis on its own. That holds however the list stopped fitting, whether on
the width, a comment inside it, or an argument whose own body is a block.

```nupp
report:put(
    "header",
    function(row: string): string
        return row
    end,
    "footer"
)
```

### Trailing blocks

The exception is the argument that runs down the page on purpose. A trailing
function or table hugs the call that takes it, because the line that opens the
call already says what is being done and to what, and only the body follows:

```nupp
table.sort(rows, |a, b| -> do
    return a.id < b.id
end)

report:configure("name", {
    retries = 3,
    timeout = 30,
})
```

The hug holds while the arguments before it, and that argument's own opening,
still fit on that line. Past that the list spreads like any other, and an
argument that goes multiline anywhere but last never hugs at all: the arguments
after it would read as a continuation of its body rather than as arguments. A
table constructor spreads on the same terms and has nothing to hug, so a
constructor that outgrows its line puts one field on each.

### Types

A type breaks in the same order. The `|` and `&` of a union or an intersection
join whole types, so they are looser than any bracket on the line: an
overloaded signature breaks between its overloads, and a union too long to fit
reads as one member per line.

```nupp
local pcall: function<A..., R...>(scoped f: function(A...): R..., A...): ((true, R...) | (false, any))
    & function<A..., R...>(takes f: function(A...): R..., A...): ((true, R...) | (false, any))
```

Type parameters are part of a signature's header, the way a record's `is`
clause is. A signature that does not fit is nearly always its parameters, so
those are what break and `function<E, A..., R...>` stays as written. A generic
parameter list breaks only when it is all the line has to break.

A shape type of several fields is a list of them and is written as one, each
field on its own line however short the whole is. A shape of exactly one field
is not a list: it is a single type standing where a type goes, so it stays on
the line that names it and breaks only when the width says so.

```nupp
record http.Options
    headers: {string: string}?
    limits: {
        connections: integer,
        redirects: integer
    }?
end
```

### Whitespace and docblocks

Blank runs collapse to one, leading blanks are stripped, trailing whitespace
goes, and a file ends with exactly one newline. A bare `;` terminates the
statement before it and stays on that statement's line rather than taking one of
its own. A clause whose sources are parenthesized is not a call of the word that
opens it, so `borrows (source)` and a closure's `takes (a, b)` keep the space
that says so.

Docblocks are reflowed and set off with a blank line. `@tag` lines are
recognized, continuations indent by five spaces, and fenced or indented
verbatim blocks are left alone. Backtick and tilde fences close only on a run
of the same character at least as long as their opener.

```nupp
--- Opens a session against the account service.
---
--- @param id the stable account identifier, which the caller reads from the
---     account service's own registry
local function openSession(id: uint64): Session
```

### Method parentheses

A method call left in its sugar form gets its parentheses back:

::: code-group
```nupp [Written]
obj:configure{retries = 3}
obj:log"starting"
```

```nupp [Formatted]
obj:configure({retries = 3})
obj:log("starting")
```
:::

A plain call is not a method call and keeps its sugar. Pass
`--no-method-parens` to turn the rewrite off and leave every call exactly as
written, or set it once for the whole project in `nupp.lua`:

```lua
return {
    fmt = { methodParens = false },
}
```

`--no-method-parens` wins if both are given; there is no flag to force parens
back on over a manifest that turned them off.

::: deepdive
`f{...}` and `f"..."` are how the language writes a record constructor and a
single string argument, and both forms are used deliberately in checked source.
Parenthesizing them would rewrite constructor after constructor across a
project for no gain in what the line means, where a method call's sugar hides
the receiver's argument list behind a brace. The rewrite is limited to the case
where the parentheses are what makes the call readable.
:::

### Line width

`--width N` changes the code column past which a line breaks, at least 20. The
default, 120, is unchanged from before this was a flag; docblock text keeps
wrapping at 88 columns regardless of `--width`.

### Opting a file out

`@!nofmt` is a leading inner annotation that leaves one whole file untouched:

```nupp
@!nofmt
-- generated source or a deliberate non-canonical layout
```

It must be the file's first annotation and has no region form.

## Limits

The formatter guarantees that its output re-lexes to a token sequence identical
in kind and text to the input. When a rewrite would break that, it returns the
input untouched and reports `NUPP4001`.

That invariant is why it cannot change a quote style, add or remove a table
constructor's trailing comma, or rewrite a numeric literal. Those change the
token stream, so no policy about them is available to the formatter.

Two rewrites are exempted, each proven safe rather than merely whitespace. A
single-value annotation loses its redundant `member =` where the checker has
proved the two forms equivalent:

::: code-group
```nupp [Written]
@documentation(text = "A user")
```

```nupp [Formatted]
@documentation("A user")
```
:::

Those tokens are marked for omission and excluded from the fingerprint. The
final comma in a type shape is likewise redundant and is omitted.
Parenthesizing a method call's sugar-form arguments is the other rewrite: the
inserted tokens are folded into the sequence checked against instead, so a bug
that put a paren in the wrong place would still be caught.

## Idempotence

`fmt(fmt(x)) == fmt(x)`, asserted over the whole test corpus. Internally the
formatter iterates to a fixpoint, capped at 24 passes.

## Editor integration

The language server implements `textDocument/formatting` and
`textDocument/rangeFormatting` with the same formatter. Two details matter:

- A file with parse errors produces no edits. A file that does not parse is
  left exactly as it is.
- Edits are emitted per run of changed lines rather than as one
  whole-document replacement, which preserves cursors and folds.

Range formatting formats the whole document and then keeps the edits that fall
inside the requested range.

::: seealso
- [lsp.md](lsp.md#lsp-features) for the rest of what the language server answers
- [editors.md](editors.md) for connecting an editor to it
- [diagnostics.md](../reference/diagnostics.md#diagnostic-index) for `NUPP4001`
  and every other code
:::
