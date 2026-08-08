# The documentation generator

```bash
nupp doc site -o build/docs src
nupp doc markdown -o docs/api.md src
nupp doc both -o build/docs
```

This site is built by it.

`nupp doc` reads the parser's lossless CST and never invokes the checker or the
code generator, so a documentation build costs parsing and rendering alone.
Unchanged output files are left untouched.

```
nupp doc [site|markdown|both] [-o PATH] [--title TITLE] [--all] [path...]
```

The format is a positional word rather than a flag, and `md` is accepted for
`markdown`. With none, the manifest's configured format is used, and `site` if
it has none. Anything in first position that is not a format word is a path.

`nupp doc` needs [lunamark](https://github.com/jgm/lunamark) and stops with a
message if it is missing. Scintillua is optional: without it, a fence in a
language it cannot load renders as escaped text. Both are ordinary
[rock dependencies](build.md#rock-dependencies), so a docs target that declares
them has them installed by the command that renders:

```lua
docs = {
   kind = "docs",
   dependencies = { "lunamark", "scintillua" },
   sources = { "src" },
}
```

## Doc comments

Two forms, and they are different.

**A long comment at the very top of a file** is that file's module
documentation, kept as Markdown. Only whitespace may precede it, and an
ordinary `--` header does not count.

```nupp
--[[
What this module is for.

Prose here is rendered as Markdown.
]]
```

**A run of `---` line comments** immediately above a declaration documents it:

```nupp
--- Opens a session against the account service.
---
--- @param id the stable account identifier
--- @return the open session
--- @raises when the service refuses the connection
@owned(closeSession)
local function openSession(id: uint64): Session
```

Only the final adjacent run counts. An ordinary `--` comment or a blank line is
a hard boundary, so a copyright header cannot become the first declaration's
documentation.

### Tags

```
 Tag                        Shape
 ─────────────────────────  ──────────────────────────────────
 @param <name> <text>       Named, by parameter
 @field <name> <text>       Named, by field
 @typearg <name> <text>     Named, by type parameter
 @return <text>             Listed, one per occurrence, in order
 @returns <text>            The same tag
 @raises <text>             Listed, one per occurrence, in order
 @module [text]             Overrides the file's module blurb
 @export, @public           Force a declaration public
 @local                     Keep a declaration out; --all brings it back
```

A tag's description continues onto any following indented line. Any other
`@name` is kept as a tag with its value.

`@raises` says what makes a function raise, one line per condition. Lua has no
signature to find that out from, so it is written down. The
`undocumented-raise` lint asks a documented function that calls `error` to say
so; it judges only documented functions, `assert` does not count, and it does
not propagate through calls, because documenting what a callee raises is a
claim the checker cannot verify.

Tags are read wherever a function is declared, including the typed bindings and
function-typed record fields that declaration files are written with, so
`local ipairs: function<V>(t: {V}): ...` documents its arguments like any other
function.

## What is public

Without `--all`, an ordinary module shows its globals, its exported types, and
anything marked `@export`. Private by default:

- a source file whose basename starts with `_`;
- any file below an `internal/` directory;
- a record method or member whose name starts with `_`.

`includePrivate = true` on the docs target includes them.

A `.d.nupp` declaration file documents in full without `--all`, because `local`
there is not privacy — its bindings are the interface it describes. Mark one
`@local` to keep it out.

## Markdown pages

A docs target can carry handwritten pages alongside the generated API. Beyond
ordinary Markdown, four things are available in a fenced block.

**A caption**, which also becomes a tab label:

````
```lua [Generated Lua]
local x = 1
```
````

**Line numbers**, optionally starting partway into a file:

````
```nupp:line-numbers=41
local offset = true
```
````

The numbers sit in their own gutter, so selecting the block copies the code
without them.

**Code groups**, which need no JavaScript:

````
::: code-group
```nupp [Nupp]
local record Point x: number end
```

```lua [Generated Lua]
const Point = {} Point.__index = Point
```
:::
````

**Admonitions**, whose bodies remain ordinary Lunamark Markdown:

````
::: note Optional title
Use **normal Markdown** here, including links, lists, and fenced code.
:::
````

The supported kinds are `note`, `info`, `tip`, `warning`, and `danger`. Omit
the title to use the capitalized kind. Containers may nest, and a fenced code
block containing `:::` does not close its admonition.

**File embeds**, which read a file at build time:

```
<<< @docs/grammar.abnf
```

The language is guessed from the extension. This page's
[grammar reference](../grammar.md) is written this way, so it cannot drift from
the file it documents.

Use `nupp` as the language for Nupp source: it is highlighted by the compiler's
own lexer, which agrees with the compiler about what a token is and can turn a
name into a link into the API reference. Every other language goes to
Scintillua.

Links between pages are written as ordinary relative Markdown paths to the
source file — `[ownership](ownership.md)` — and are rewritten to the page's
public route at build time. Fragments survive.

A page source may open with `---`-delimited front matter, which is stripped.

## Output

**`site`** writes a page per route, `assets/style.css`, `assets/site.js`, a
JavaScript search index, and redirect stubs for the former `modules/name.html`
URLs. The header search opens with Ctrl-K or Command-K and searches page titles
and headings together with modules, declarations, and members.

**`markdown`** writes one file: a section per module, with signature blocks and
tables for type parameters, arguments, returns, methods, fields, and values.

**`both`** writes the site plus `api.md` inside the output directory.

Every page also emits a colocated `llms.txt` holding its Markdown. The output
root adds an `llms.txt` index and `llms-full.txt`, the whole reference
concatenated.

## As a build target

```lua
docs = {
   kind = "docs",
   sources = { "src" },
   format = "both",
   outDir = "build/docs",
   title = "Project API",
   pages = { { path = "guide", title = "Guide", source = "docs/guide.md" } },
}
```

Then `nupp build --target docs`, and `nupp check --target docs` parses and
validates every source without writing output. [The build
system](build.md#documentation-targets) documents every key.
