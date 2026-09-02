---
order: 540
---

# Documentation generator

`nupp doc` renders a project's API reference from its source, together with the
handwritten Markdown pages the manifest lists. This site is built by it.

```bash
nupp doc site -o build/docs src
nupp doc markdown -o docs/api.md src
nupp doc json -o build/docs.json src
nupp doc both -o build/docs
```

The generator reads the parser's lossless CST and never invokes the checker or
the code generator, so a documentation build costs parsing and rendering alone.
Unchanged output files are left untouched.

## Choosing a format and a target

```text
nupp doc [site|markdown|json|both] [-o PATH] [--target NAME] [--title TITLE] [--all] [path...]
```

The format is a positional word rather than a flag, and `md` is accepted for
`markdown`. With none, the manifest's configured format is used, and `site` if
it has none. Anything in first position that is not a format word is a path.

`--target` names which docs target to render, the way `nupp build --target`
names which target to build. Only a manifest carrying more than one needs it:
with no top-level `docs` table and several `kind = "docs"` targets, the one
`build.default` names is rendered, and a `build.default` naming something else
makes `nupp doc` ask which was meant. Two docs targets are two deliverables,
usually writing to two directories, so a run that chooses between them on its
own writes somewhere nobody asked for.

### Renderer dependencies

`nupp doc` needs [lunamark](https://github.com/jgm/lunamark) and stops with a
message if it is missing. Scintillua is optional: without it, a fence in a
language it cannot load renders as escaped text. Both are ordinary [rock
dependencies](../projects/build.md#rock-dependencies), so a docs target that declares them
has them installed by the command that renders:

```lua
docs = {
   kind = "docs",
   dependencies = { "lunamark", "scintillua" },
   sources = { "src" },
}
```

Nupp supplies Lunamark's UTF-8 integration itself. Numeric and named character
entities are encoded with `nupp.data.utf8`. Markdown reference labels collapse
spaces, tabs and line endings and compare ASCII letters without case; non-ASCII
UTF-8 bytes compare exactly. Thus `[name][CAFÉ]` and `[name][café]` are different
references, while `[name][TAG]` and `[name][tag]` are the same. The rule is
independent of the host locale and of a native Unicode casing-table revision.

## Doc comments

Two forms document a file, and they are different.

**A long comment at the very top of a file** is that file's module
documentation, kept as Markdown. Only whitespace may precede it, and an
ordinary `--` header does not count.

```nupp
--[[
What this module is for.

Prose here is rendered as Markdown.
]]
```

It is the same Markdown a page is written in, so headings, cross-references,
admonitions and code groups all work, and its headings join the module page's
outline. A module documented in sections says them here, beside what they
describe, rather than in a file next to the source. Write `--[==[` when the
prose itself contains `]]`.

A link in a doc comment names a repository path rather than a relative one,
because a comment is written in a source file and rendered on a page routed
somewhere else: `[ownership](docs/learn/runtime/ownership/borrowing.md)`.

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
| `@param <name> <text>` | Named, by parameter |
| `@field <name> <text>` | Named, by field |
| `@typearg <name> <text>` | Named, by type parameter |
| `@return <text>` | Listed, one per occurrence, in order |
| `@returns <text>` | The same tag |
| `@raises <text>` | Listed, one per occurrence, in order |
| `@module [text]` | Overrides the file's module blurb |
| `@export`, `@public` | Force a declaration public |
| `@local` | Keep a declaration out; `--all` brings it back |
| `@namespace [prefix]` | Document a shape's own fields as modules |

A tag's description continues onto any following indented line. Any other
`@name` is kept as a tag with its value.

Tags are read wherever a function is declared, including the typed bindings and
function-typed record fields that declaration files are written with, so
`local ipairs: function<V>(t: {V}): ...` documents its arguments like any other
function. The checker reports an `@param` name that does not match a real
parameter.

### Raised errors

`@raises` says what makes a function raise, one line per condition. Lua has no
signature to find that out from, so it is written down:

```nupp
--- Reads the whole file at `path`.
---
--- @raises when the file cannot be opened
--- @raises when a read fails partway through
local function slurp(path: string): string
```

The `undocumented-raise` lint asks a documented function that calls `error` to
say so. It judges only documented functions, `assert` does not count, and it
does not propagate through calls, because documenting what a callee raises is a
claim the checker cannot verify. See [lints.md](../../reference/lints.md) for
configuring it.

### Namespaces

`@namespace` is for a shape with no file of its own to be documented from: a
compiler-provided intrinsic namespace declared once, whose fields are the
surface a reader actually reaches. On a `local name: {...}` declaration it
replaces that one item with a module per field, named `prefix.field`, or the
enclosing module's own name when `prefix` is omitted.

```nupp
--- @namespace nupp
local nupp: {
    --- @namespace
    data: {
        --- Hashes bytes with SHA-256.
        sha256: function(bytes: string): string
    },
    math: nupp.MathLibrary,
}
```

A field inside one of those modules may carry `@namespace` too; it becomes a
nested module instead of a value on its parent. A field written inline, as
`data` above, documents its own fields directly, and a field written as a type
name, as `math: nupp.MathLibrary`, is followed to a record of that name
declared in the same file. Documentation never resolves a type the way the
checker does, so a field answering to neither is left out rather than guessed
at. This is how the [`nupp` standard
library](../runtime/data/standard-library.md), whose native members have no file to
require them by, gets pages nested under `nupp`.

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
  whatever it is, field, method, property or nested type, and anything tagged
  `@internal`.

A hidden member leaves the rendered declaration too, not only the member
table: the signature block a page shows for a record is the record's public
surface, so a reader never sees a name the documentation refuses to describe.
`includePrivate = true` on the docs target includes them.

Metamethods are the one exception to the `_` rule. A metamethod is named for
the Lua operation it implements, so `__index` says which operator this is
rather than that it is private, and a declared `metamethod` is documented like
any other member. `@internal` still opts one out. See
[metamethods.md](../language/metamethods.md) for declaring them.

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

### Cleanup names

`affine(T, cleanup)` names an exact cleanup identity, and a library's terminal
is usually private: the prelude declares `__nuppDestroyReader` and never means
a caller to write it. Wherever a rendered signature applies `affine` to a
cleanup the documentation hides, the argument prints as `_`:

```nupp
newReader: function(self: ByteView): affine(Reader, _)
```

The argument is replaced rather than dropped, because `affine(Reader)` is a
different type: transfer-only, with deliberately no terminal at all. `_` keeps the
obligation the value carries in the type while saying the name behind it is not
the reader's to write. A cleanup the documentation does
describe prints as written. See
[ownership.md](../runtime/ownership/borrowing.md#terminal-contract) for what the
terminal promises.

## Markdown pages

A docs target can carry handwritten pages alongside the generated API, written
in ordinary Markdown with the additions below. Every fence is highlighted,
static code until one asks to be an editor, and backtick and tilde fences are
both accepted: a closer uses the same character and at least as many of it as
the opener, so a longer fence can show a shorter one literally.

### Captions

A caption names a block, and becomes a tab label inside a code group:

````markdown
```lua [Generated Lua]
local x = 1
```
````

### Line numbers

Numbering may start partway into a file:

````markdown
```nupp:line-numbers=41
local offset = true
```
````

The numbers sit in their own gutter, so selecting the block copies the code
without them.

### Code groups

A code group renders several blocks as tabs, and needs no JavaScript:

````markdown
::: code-group
```nupp [Nupp]
local record Point
    x: number
end
```

```lua [Generated Lua]
local Point = {} Point.__index = Point
```
:::
````

### Columns

A columns block lays its headings and their bodies out side by side instead of
stacked, three to a row:

````markdown
::: columns

## Learning Nupp

- [Installation](../../getting-started/installation.md)
- [Tour of Nupp](../../getting-started/tour.md)

## Language reference

- [Type system](../language/types/index.md)

## Performance

- [Performance](../performance/index.md)

:::
````

Each `##` inside opens its own column; a narrow viewport collapses the row
back to a single stack.

### Admonitions

An admonition is a titled aside whose body remains ordinary Lunamark Markdown:

````markdown
::: note Optional title
Use **normal Markdown** here, including links, lists, and fenced code.
:::
````

The kinds are `note`, `info`, `tip`, `warning`, `danger`, `seealso`, and
`deepdive`. Omit the title to use the kind's own: `See also` for `seealso`,
`Dive deeper` for `deepdive`, and the capitalized kind for the rest. Containers
may nest, and a fenced code block containing `:::` does not close its
admonition.

`seealso` renders as an always-open aside in its own color, holding the pages a
reader who finished a section goes to next:

````markdown
::: seealso
- [ownership.md](../runtime/ownership/borrowing.md) for the contract reference
- [c-interop.md](../runtime/c-interop/index.md) for what a C boundary adds to it
:::
````

`deepdive` renders collapsed, because it answers a question the page did not
raise: why a design is shaped the way it is, and what that cost. A reader
following a task scrolls past it, and a reader who stopped to wonder opens it
in one click.

````markdown
::: deepdive Why the CST
Rendering from the checker's output would make a documentation build cost a
type-check, and a project that does not check would document nothing.
:::
````

### Playgrounds

A playground is the editor rather than a picture of one. A Nupp fence asks for
one with `:playground`:

````markdown
```nupp:playground
local type Priority = "low" | "high"
local p: Priority = "urgent"
```
````

The program is checked in the reader's browser, as they type, by the real
compiler. A caption becomes the editor's accessible label, and `:line-numbers`
outranks the ask, so a numbered excerpt keeps the starting line it requested
and stays text. ` ```playground ` is the explicit form, and an empty block of it
opens on the playground's own example menu instead of a program:

````markdown
```playground
```
````

The block is an inline `<nupp-playground>` custom element, not an iframe. A
site using it serves the playground's `dist/` at `/playground/`, the way
`nupp task docs-serve` does, so the page can load `doc-app.js`, its shared
compiler worker, and the browser-safe compiler. Editors size from their
content; long programs scroll after 28rem. A fence with authored source also
carries it as ordinary fallback markup, and an upgraded example menu keeps that
markup in sync with its current program, so Reader Mode and a browser without
scripting both see source rather than an editor. See
[`editors/playground`](https://github.com/nupp-lang/nupp/tree/main/editors/playground)
for how the editor works and what it cannot do.

::: deepdive
Asking is how a page gets an editor, because most examples on one should not be
editors. A fragment does not check on its own, a step in a sequence checks as
an error the prose has already explained, and a program the page has shown
before teaches nothing a second time. Opting in keeps the editor on the example
a reader would actually try, which is usually the first one on the page.
:::

### Home page

A page whose entry or frontmatter says `layout = "home"` renders a hero above
its prose and a feature showcase inside it, and writes both in Markdown between
comment markers rather than configuring them beside the page.

````markdown
<!-- nupp:hero -->

# Project

One line under the title.

[Get started](getting-started/installation)
[Playground](/playground/)

![A project logo](images/project.png)

<!-- /nupp:hero -->

<!-- nupp:features -->

## Project checks

The paragraph beside the sample.

```nupp
local answer: integer = 42
```

<!-- /nupp:features -->
````

In the hero, the heading is the title, the first paragraph is the line under
it, any further prose is the paragraph below that, the image is the
illustration, and a paragraph of nothing but links is the row of buttons, the
first of which is the one the page is for. In the showcase, each `##` heading
is a card: its prose is the caption, and its fenced block is the sample beside
it. A card that shows an image instead shows that.

The showcase renders where it was written, so a home page decides for itself
what a reader meets first. Everything outside the two regions is the page's
ordinary Markdown.

### File embeds

An embed reads a file at build time, guessing the language from its extension:

```markdown
<<< @docs/grammar.abnf
```

This site's [grammar reference](../../reference/grammar.md) is written this way,
so it cannot drift from the file it documents.

### Highlighting

Use `nupp` as the language for Nupp source. It is highlighted by the compiler's
own parser and lexer, which agree about tokens and contextual syntax and can
turn a name into a link into the API reference. A `:playground` fence is
checked instead, by the compiler itself, once the reader engages with the
frame. Every other language goes to Scintillua.

### Links between pages

Links are written as ordinary relative Markdown paths to the source file, as in
`[ownership](../runtime/ownership/borrowing.md)`, and are rewritten to the page's
public route at build time. Fragments survive. A page source may open with
`---`-delimited front matter, which is stripped.

## Outline and sidebar

A page's outline follows its own structure: a heading written under a section
is listed under that section, the way a module page lists a declaration under
its group. A long generated page therefore opens as the handful of sections it
is made of rather than as a list of everything on it.

The sidebar's sections are collapsed except the one holding the page being
read, and the API reference is open only on a module page. Inside it, every
top-level branch stands open on every page: a top-level branch is a library,
and there are few enough of them that naming them costs no room. The deeper
branches stay shut except along the path to the module being read.

## Moved pages

`redirects` lists the routes a page used to answer at. A stub is written at
each one pointing at where the page is now, so a link somebody else wrote
still arrives:

```lua
{
   path = "guides/build",
   title = "Build system",
   source = "docs/learn/projects/build.md",
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

Links inside the documentation need none of this. They name the source file and
are rewritten to whatever route it is published at, so moving a page leaves
them working. Redirects are for addresses this project does not control:
bookmarks, search results, and links from other sites.

## Generated index pages

Two pages are generated from the compiler itself rather than from a project's
sources, each configured by the route it should answer at.

### Diagnostic index

`diagnostics` generates a page holding every diagnostic code:

```lua
diagnostics = {
   path = "reference/diagnostics",
   title = "Diagnostics",
   source = "docs/reference/diagnostics.md",
},
```

With a `source`, that file's prose opens the page and the generated index is
appended to it under a `## Diagnostic index` heading; a page that writes that
heading itself would give the route two. Without a `source`, the generated
index is the whole page.

The entries are the compiler's own explanations, so nothing lists the codes and
nothing goes stale when one is added. Each code is a section that states the
rule, shows the program that reports it, and shows the same program corrected.
A lint's section also says its name, category, and default level. Sections are
grouped by family, and a code links to its related codes by anchor.

A code gets a section when the compiler knows it specifically: it has an
example pair of its own, or it is a lint. A code that resolves only through its
family does not, because the family answers for all of them at once. Where such
a code appears among another section's related codes it is named rather than
linked. The area reference a code carries is linked when the docs target
publishes that file and named as a path when it does not, so a page the site
does not build never becomes a dead link.

::: deepdive
One page rather than one per code, because an index is searched: the browser's
find reaches every code, rule and program at once. That is also why no program
there asks for an editor, since text inside an editor frame is not findable.
Each reported program instead carries a link that opens it in the playground.
:::

### LuaJIT standard library

`stdlib` generates a page holding the LuaJIT standard library:

```lua
stdlib = {path = "luajit", title = "LuaJIT standard library"},
```

The page is the compiler's own declarations: the prelude it loads into every
check, and the declaration files behind `require("ffi")`,
`require("string.buffer")` and the `jit` submodules. A signature on the page is
the signature the checker enforces, because the two read the same file.

The compiler-provided globals come first, then one section per library table,
`string`, `table`, `math` and the rest, then the modules `require` loads, then
the types those signatures name, and last the `Layout` graph a reified `struct`
is measured by. A name on the page is the name a program writes: `print` is a
global and `string.format` is a member, so `#print` and `#string.format` both
address what they look like they address. Every code block is static, for the
same reason the diagnostic index's blocks are.

What `nupp` itself provides is not on the page. Those are modules with pages of
their own, and the prelude declares them only so that checked code can see
them; the semantic descriptor graph a `comptime` block walks is documented with
the callable [`nupp.reflect`](../language/reflection.md) namespace instead of
leaking ambient types here. The page needs no `sources` entry, and a project's
own manifest cannot point it at other files: the declarations belong to the
compiler rendering the site, which is what makes the page true of the toolchain
a reader is holding.

## Cross-references

A Markdown link whose target names something the documentation knows resolves
to whatever documents it. The name may be a module, a declaration, or a member,
and it works the same in a handwritten page, a module blurb, and a `---` run:

```markdown
[the zone module](nupp.profile.zone)
[](nupp.profile.zone.Zone)
[the guard's field](nupp.profile.zone.Zone.active)
[](nupp.mem.span#writable-spans)
```

Empty link text stands for the target, so `[](nupp.profile.zone)` renders that
name as code and links it, which is the whole cost of a reference in passing.

An unqualified name works wherever it is unambiguous, and a name declared in
the module being rendered resolves to that module first. A name two modules
both export resolves to neither, because guessing between them would silently
point at the wrong one.

A fragment rides along: the name resolves and the anchor is kept, which is how
one page names a section of a module page written in that module's own blurb.

A target that reads as a URL or has a slash is left alone, so ordinary links are
never captured. A name nothing documents is left alone too, except that empty
link text still renders the name, so a reference to something that has moved
reads as the name it used to have rather than as an invisible link. References
inside a code block are code. A highlighted Nupp block can link names into the
API reference; a `:playground` block treats them only as program text.

In `markdown` output the same references resolve to anchors within the
document. A module's own `llms.txt` holds one module, so a reference to a
neighbor keeps its name and drops its link.

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

### Module overview pages

A configured page whose `path` is a module's route is that module's overview,
rendered above the generated API rather than as a second page beside it:

```lua
{ path = "modules/engine", title = "Engine", source = "docs/engine.md" },
```

The route is `modules/` followed by the module name with its dots as slashes. A
module's own prose belongs in its blurb, beside what it describes; an overview
is for a page that is somebody else's as well, filed at the module route so a
reader arriving from either direction reads one page rather than two accounts of
the same thing. It is ordinary page Markdown, so cross-references, links to
other pages, code groups, and admonitions all work, and its headings join the
page outline above the generated ones. `title` overrides the generated `Module:`
or `Namespace:` one. A module with both an overview and a blurb shows the
overview first.

An entry naming no `source` renders nothing of its own. That is how a module
route keeps answering at an address a handwritten page used to have, by carrying
`redirects` and leaving the blurb to say what the module is.

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

## Docs target

```lua
docs = {
   kind = "docs",
   sources = { "src" },
   format = "both",
   outDir = "build/docs",
   title = "Project API",
   pages = { { glob = "docs/**.md" } },
}
```

Then `nupp build --target docs`, and `nupp check --target docs` parses and
validates every source without writing output. See [documentation
targets](../projects/build.md#documentation-targets) for every key one takes.

## FAQ

### Why is a declaration missing from the reference?

It is private by default: a name starting with `_`, a file or module under
`internal`, or a file marked `@!internal`. Render with `--all`, or set
`includePrivate = true` on the target, to see them. See [Public
surface](#public-surface) for the whole rule.

### Does `nupp doc` type-check the sources it reads?

No. It renders from the parser's CST, so a project whose check fails still
documents, and a signature on a page is the one that was written rather than
one the checker confirmed. Run `nupp check --target docs` to parse and validate
a docs target without writing output.

### How does a page get published without being listed in the manifest?

A page entry names a `glob` instead of a `path` and a `source`, and every
Markdown file it matches is published at the route its own path gives. What the
path cannot say -- where the page sits in the navigation, what navigation calls
it -- the page says in frontmatter. See [page trees](../projects/build.md#page-trees).

A `directory` entry does the same for a collection, publishing every document
under it beneath one generated index. See [page
directories](../projects/build.md#page-directories) for numbering and how the index is
built.

::: seealso
- [cli.md](../../reference/cli.md#doc) for the command's flags and JSON report
- [annotations.md](../../reference/annotations.md) for `@!internal` and the rest of
  the file-level annotations
- [diagnostics.md](../../reference/diagnostics.md) for the page the `diagnostics`
  key generates
:::
