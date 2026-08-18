# Documentation generator

```bash
nupp doc site -o build/docs src
nupp doc markdown -o docs/api.md src
nupp doc json -o build/docs.json src
nupp doc both -o build/docs
```

This site is built by it.

`nupp doc` reads the parser's lossless CST and never invokes the checker or the
code generator, so a documentation build costs parsing and rendering alone.
Unchanged output files are left untouched.

```
nupp doc [site|markdown|json|both] [-o PATH] [--target NAME] [--title TITLE] [--all] [path...]
```

The format is a positional word rather than a flag, and `md` is accepted for
`markdown`. With none, the manifest's configured format is used, and `site` if
it has none. Anything in first position that is not a format word is a path.

`--target` names which docs target to render, the way `nupp build --target`
names which target to build. It is needed only by a manifest that has more than
one: with no top-level `docs` table and several `kind = "docs"` targets, the one
`build.default` names is rendered, and if that names something else `nupp doc`
asks which was meant rather than choosing. Two docs targets are two
deliverables, usually writing to two directories, and a run that picks between
them on its own writes somewhere nobody asked for.

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
local function openSession(id: uint64): affine(Session, closeSession)
```

Only the final adjacent run counts. An ordinary `--` comment or a blank line is
a hard boundary, so a copyright header cannot become the first declaration's
documentation.

### Tags

| Tag | Shape |
| --- | --- |
| @param <name> <text> | Named, by parameter |
| @field <name> <text> | Named, by field |
| @typearg <name> <text> | Named, by type parameter |
| @return <text> | Listed, one per occurrence, in order |
| @returns <text> | The same tag |
| @raises <text> | Listed, one per occurrence, in order |
| @module [text] | Overrides the file's module blurb |
| `@export`, `@public` | Force a declaration public |
| `@local` | Keep a declaration out; --all brings it back |
| @namespace [prefix] | Document a shape's own fields as modules |

A tag's description continues onto any following indented line. Any other
`@name` is kept as a tag with its value.

`@namespace` is for a shape with no file of its own to be documented from: an
ambient global declared once, whose fields are the surface a reader actually
reaches. On a `local name: {...}` declaration it replaces that one item with a
module per field, named `prefix.field` (the enclosing module's own name, when
`prefix` is omitted). A field inside one of those modules may carry `@namespace`
too; it becomes a nested module instead of a value on its parent. A field
written inline (`data: {...}`) documents its own fields directly; a field
spelled as a name (`math: nupp.MathLibrary`) is followed to a record of that
name declared in the same file. Documentation never resolves a type the way the
checker does, so a field answering to neither is left out rather than guessed
at. This is how the standard library's own `nupp` global, covering `nupp.data`,
`nupp.io`, and `nupp.math`, gets pages nested under `nupp` without a file to
require any of them by, since native members have none.

`@raises` says what makes a function raise, one line per condition. Lua has no
signature to find that out from, so it is written down. The
`undocumented-raise` lint asks a documented function that calls `error` to say
so; it judges only documented functions, `assert` does not count, and it does
not propagate through calls, because documenting what a callee raises is a
claim the checker cannot verify.

Tags are read wherever a function is declared, including the typed bindings and
function-typed record fields that declaration files are written with, so
`local ipairs: function<V>(t: {V}): ...` documents its arguments like any other
function. The checker reports `NUPP1007` when an `@param` name does not match a
real parameter.

## Public surface

Without `--all`, an ordinary module shows its globals, its exported types, and
anything marked `@export`. Private by default:

- a source file whose basename starts with `_`;
- any module named `internal`, and everything under it: the `internal/`
  directory, the single-file `internal.nupp`, and the namespace an
  `@namespace` declaration spells `internal` all describe the same private
  module;
- a file beginning with `@!internal`;
- every module below an `init.nupp` beginning with `@!internal`;
- a member of a record, interface, or struct whose name starts with `_`,
  whatever it is — field, method, property, or nested type — and anything
  tagged `@internal`.

A hidden member leaves the rendered declaration too, not only the member
table: the signature block a page shows for a record is the record's public
surface, so a reader never sees a name the documentation refuses to describe.

Metamethods are the one exception to the `_` rule. A metamethod is named for
the Lua operation it implements, so `__index` says which operator this is
rather than that it is private, and a declared `metamethod` is documented like
any other member. `@internal` still opts one out.

`includePrivate = true` on the docs target includes them.

`@!internal` is a file-level inner annotation, not a docblock tag. Put it first
in a namespace's `init.nupp` to keep that module and every descendant out of
public API documentation without naming the directory `internal`:

```nupp
@!internal
return {}
```

It affects documentation only. The compiler still checks, builds, and resolves
the modules normally.

A `.d.nupp` declaration file documents in full without `--all`, because `local`
there is not privacy. Its bindings are the interface it describes. Mark one
`@local` to keep it out.

## Markdown pages

A docs target can carry handwritten pages alongside the generated API. Beyond
ordinary Markdown, five things are available in a fenced block. Every fence is
highlighted, static code until one asks to be an editor.
Backtick and tilde fences are both accepted. A closer uses the same character
and at least as many of it as the opener, so a longer fence can show a shorter
one literally.

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
local record Point
    x: number
end
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

**A playground**, which is also the editor rather than a picture of one. A Nupp
fence asks for one with `:playground`:

````
```nupp:playground
local type Priority = "low" | "high"
local p: Priority = "urgent"
```
````

The program is checked in the reader's browser, as they type, by the real
compiler. See
[`editors/playground`](https://github.com/nupp-lang/nupp/tree/main/editors/playground)
for how that works and what it cannot do. A caption becomes the editor's
accessible label, and `:line-numbers` outranks the ask, so a numbered excerpt
keeps the starting line it requested and stays text.

Asking is how a page gets an editor because most examples on it should not be
one: a fragment, one step of a sequence, or a program the page has already
shown checks as an error the prose has already explained. The usual number is
one, the example a reader would try first. ` ```playground ` remains the
explicit spelling, and an empty block of it opens on the playground's own
example menu instead of a program:

````
```playground
```
````

The block is an inline `<nupp-playground>` custom element, not an iframe. A site
using it serves the playground's `dist/` at `/playground/`, the way `nupp task
docs-serve` does, so the page can load `doc-app.js`, its shared compiler worker,
and the browser-safe compiler. Editors size from their content; long programs
scroll after 28rem. Because the editor lives in the page, CodeMirror popups are
not clipped at an iframe boundary. A fence with authored source also carries it
as ordinary fallback markup, and an upgraded example menu keeps the same markup
in sync with its current program. Reader Mode therefore sees source rather than
the editor's line-number gutter; a browser without scripting sees authored
source as a static code block.

**File embeds**, which read a file at build time:

```
<<< @docs/grammar.abnf
```

The language is guessed from the extension. This page's
[grammar reference](../grammar.md) is written this way, so it cannot drift from
the file it documents.

Use `nupp` as the language for Nupp source. It is highlighted by the compiler's
own parser and lexer, which agree about tokens and contextual syntax and can
turn a name into a link into the API reference. A `:playground` fence is checked
instead, by the compiler itself, once the reader engages with the frame. Every
other language goes to Scintillua.

Links between pages are written as ordinary relative Markdown paths to the
source file, as in `[ownership](ownership.md)`, and are rewritten to the page's
public route at build time. Fragments survive.

A page source may open with `---`-delimited front matter, which is stripped.

A page's outline follows its own structure: a heading written under a section
is listed under that section, the way a module page lists a declaration under
its group. A long generated page opens as the handful of sections it is made
of rather than as a list of everything on it.

The sidebar behaves the same way across pages. Its sections are collapsed
except the one holding the page being read, and the API reference is open only
on a module page, where the branches leading to that module are the ones
expanded.

## Moved pages

`redirects` lists the routes a page used to answer at. A stub is written at
each one pointing at where the page is now, so a link somebody else wrote
still arrives:

```lua
{
   path = "guides/build",
   title = "Build system",
   source = "docs/tooling/build.md",
   redirects = {"tooling/build", "reference/build"},
},
```

The stub is a meta refresh with a canonical link and a plain anchor, so a
bookmark, a search result and a reader with scripting off all reach the page.

A former route is cleaned the way `path` is, so `tooling/build`,
`/tooling/build` and `tooling/build/index.html` all name the same one. An empty
route is refused rather than written to the site root.

A page whose `path` is a module's route is that module's overview, and its
redirects move onto the module's own page with it. That is what lets a page
that documented a module from somewhere else keep its former address after it
is filed under the module.

Links inside the documentation do not need this. They name the source file and
are rewritten to whatever route it is published at, so moving a page leaves
them working. Redirects are for addresses this project does not control:
bookmarks, search results, and links from other sites.

## Diagnostic index

`diagnostics` generates a page holding every diagnostic code, at the route it
names:

```lua
diagnostics = {path = "diagnostics", title = "Diagnostic index"},
```

The page is the compiler's own explanations, so nothing lists the codes and
nothing goes stale when one is added. Each code is a section that states the
rule, shows the program that reports it, and shows the same program corrected.
A lint's section also says its name, category, and default level. Sections are
grouped by family, and a code links to its related codes by anchor.

One page rather than one per code, because an index is searched: the browser's
find reaches every code, rule and program at once. That is also why no program
there asks for an editor, since text inside an editor frame is not findable.
Each reported program carries a link that opens it in the playground.

A code gets a section when the compiler knows it specifically: it has an example
pair of its own, or it is a lint. A code that resolves only through its family
does not, because the family answers for all of them at once. Where such a code
appears among another section's related codes it is named rather than linked.

The area reference a code carries is linked when the docs target publishes that
file and named as a path when it does not, so a page the site does not build
never becomes a dead link.

## Standard library index

`stdlib` generates a page holding the LuaJIT standard library, at the route it
names:

```lua
stdlib = {path = "luajit", title = "LuaJIT standard library"},
```

The page is the compiler's own declarations: the prelude it loads into every
check, and the declaration files behind `require("ffi")`,
`require("string.buffer")` and the `jit` submodules. A signature on the page is
the signature the checker enforces, because the two read the same file.

The ambient globals come first, then one section per library table — `string`,
`table`, `math` and the rest — then the modules `require` loads, then the types
those signatures name, and last the `Layout` graph a reified `struct` is measured
by. The semantic descriptor graph a `comptime` block walks is documented with
the callable `nupp.reflect` namespace instead of leaking ambient types onto this
page.

A name on the page is the name a program writes. `print` is a global and
`string.format` is a member, so that is what each one's heading, anchor and
search entry say, and `#print` and `#string.format` both address what they look
like they address.

Every code block on the page is static, as on the diagnostic index and for the
same reason: an index is searched, and the browser's own find cannot reach text
inside an editor frame. A signature is a declaration rather than a program
besides, so there is nothing there for an editor to check.

What `nupp` itself provides is not on the page. Those are modules with pages of
their own, and the prelude declares them only so that checked code can see them.

The page needs no `sources` entry, and a project's own manifest cannot point it
at other files: the declarations belong to the compiler rendering the site, which
is what makes the page true of the toolchain a reader is holding.

## Cross-references

A Markdown link whose target names something the documentation knows resolves
to whatever documents it. The name may be a module, a declaration, or a member,
and it works the same in a handwritten page, a module blurb, and a `---` run:

```
[the zone module](nupp.zone)
[](nupp.zone.Zone)
[the guard's field](nupp.zone.Zone.active)
```

Empty link text stands for the target, so `[](nupp.zone)` renders that name as
code and links it, which is the whole cost of a reference in passing.

An unqualified name works wherever it is unambiguous, and a name declared in
the module being rendered resolves to that module first. A name two modules
both export resolves to neither, because guessing between them would silently
point at the wrong one.

A target that reads as a URL, has a slash, or carries a fragment is left alone,
so ordinary links are never captured. A name nothing documents is left alone
too, except that empty link text still renders the name, so a reference to
something that has moved reads as the name it used to have rather than as an
invisible link. References inside a code block are code. A highlighted Nupp
block can link names into the API reference; a `:playground` block treats them
only as program text.

In `markdown` output the same references resolve to anchors within the
document. A module's own `llms.txt` holds one module, so a reference to a
neighbour keeps its name and drops its link.

## Module pages

Every module gets its own page: its blurb, a table of the modules nested under
it, and a table per group of what it declares: constructors, types, functions,
and values. The detailed reference repeats those group headings, nests each
declaration beneath its group, and uses the same hierarchy in the page outline
and companion Markdown.

A directory with no `init.nupp` gets a page too, holding the modules below it
and nothing else. That is the name every module inside it is spelled with, and
it would otherwise be the one name in the reference that led nowhere. Such a
page is titled `Namespace:` rather than `Module:`, and its entries in the
sidebar, the search index, and the Markdown output say the same.

A constructor is a function whose last name segment matches
`constructorPattern`, which defaults to `^new`. Set it to another Lua pattern to
match a different convention, or to `""` to leave every function in Functions.
Deciding by result type instead would file every accessor and query under
Constructors, so the name is what answers.

### Overviews

A configured page whose `path` is a module's route is that module's overview,
rendered above the generated API rather than as a second page beside it:

```lua
{ path = "modules/engine", title = "Engine", source = "docs/engine.md" },
```

The route is `modules/` followed by the module name with its dots as slashes.
This is where prose longer than a blurb belongs, being a page a doc comment
would have to hold. It is ordinary page Markdown, so cross-references, links to
other pages, code groups, and admonitions all work, and its headings join the
page outline above the generated ones. `title` overrides the generated `Module:`
or `Namespace:` one. A module with both an overview and a blurb shows the
overview first.

## Output

**`site`** writes a page per route, `assets/style.css`, `assets/site.js`, a
JavaScript search index, and redirect stubs for the former `modules/name.html`
URLs. The header search opens with Ctrl-K or Command-K and searches page titles
and headings together with modules, declarations, and members.

**`markdown`** writes one file: a section per module, with signature blocks and
tables for type parameters, arguments, returns, methods, fields, and values.

**`json`** writes the parse-only documentation model for external generators.
The top-level `schemaVersion` lets a consumer reject a model shape it does not
understand; `modules` contains the same declarations, members, doc tags, and
signatures that the built-in renderers consume. This positional format is
separate from `--json`, which controls the command's own success report.

**`both`** writes the site plus `api.md` inside the output directory.

Every page also emits a colocated `llms.txt` holding its Markdown. The output
root adds an `llms.txt` index and `llms-full.txt`, the whole reference
concatenated. A successful site build records the files it owns and removes any
that the next successful build no longer produces, including pages whose route
changed or whose source disappeared.

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
