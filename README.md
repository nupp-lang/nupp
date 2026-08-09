# Nupp

*A typed programming language for LuaJIT that makes FFI comfortable.*

Nupp is a gradually typed superset of LuaJIT's Lua dialect, implementing every
[LuaJIT 3.0 syntax extension](https://github.com/LuaJIT/LuaJIT/issues/1475) and
adding to them rather than subtracting
([docs/grammar.abnf](docs/grammar.abnf)). Most of that syntax is written
straight through to the output, because LuaJIT 2.1 backported it; generated
code needs LuaJIT 2.1.1784535649 or newer. Unlike every existing typed Lua, its
types are not always erased: `struct` declarations lower to FFI cdata (fixed
layout, no hash lookups) and C headers import as typed declarations. Owned C
resources are affine: `@owned(...)` records deterministic cleanup obligations,
`takes` calls move them, borrows cannot escape, and
`pinned<T>` handles keep Lua-managed pointers alive across declared
`retains`/`releases` C calls. Raw-pointer reconstruction is confined to
explicit `unsafe do` blocks. See
[docs/ownership.md](docs/ownership.md) and explicit
[`with` resource scopes](docs/with.md). A
trace-aware checker (types that know what the JIT will compile) is on the
roadmap ([plans/todo.md](plans/todo.md)).

A file's extension says which floor it is held to, so it is visible where the
file is rather than in a setting that governs everything at once: `.nupp` is
checked strictly, `.g.nupp` is the same typed syntax with the strict floor
down, and a plain `.lua` file is Lua, built and run unchanged, with the typed
layer refused in it. The marker is not part of the module's name, so
`require("models")` finds `models.g.nupp` and a file can change layer without
anything that requires it noticing. `nupp check --strict` holds every file to
the floor whatever it is called. See
[docs/type-system/overview.md](docs/type-system/overview.md).

Compiler and lint output includes stable codes, source spans, related
locations, repair help, and structured fixes; see
[docs/diagnostics.md](docs/diagnostics.md).

<img src="docs/public/images/nupp.png" alt="Nupp" width="460" align="center"/>

Status: pre-0.1, with the typed checker, incremental query core, C interop,
and editor tooling under active development. The resource model also covers
default `@dispose` operations, affine records, checked owned/borrowed C output
parameters, parameter-effect inference, and raw coroutine suspension. See
[docs/ownership.md](docs/ownership.md) for the complete contract reference and
[plans/plan.md](plans/plan.md) for the broader roadmap.

    nupp ast [--json] <file>    dump an indented parsed syntax tree
    nupp check [file...]        check files, or the manifest project graph
    nupp fmt [-w|--check] [f…]  format files or the project; --check only reports
    nupp build [file...]        build files, or the default manifest target
    nupp clean [--target name]  remove configured build outputs
    nupp tasks [name]           list or inspect manifest project tasks
    nupp test [args...]         build, then run the configured test command
    nupp coverage [args...]     run an instrumented build and write a coverage report
    nupp task <name> [args...]  build, then run a named tasks.<name> from nupp.lua
    nupp doc [site|markdown]    generate fast CST-based API documentation
    nupp fixpoint               verify the self-hosting compiler rebuild
    nupp run <file> [args]      compile and run; require project .nupp/.lua
    nupp run --profile <file>   sample it; --jit-aborts records what the JIT refused
    nupp import-c <header.h>    eject typed C bindings as a module [--lib name]
    nupp rock init|pack|test    create and package typed Lua rocks
    nupp lints                  list the lints and the level each runs at
    nupp explain CODE           the rule behind a diagnostic, either way round
    nupp reference              print the whole language in ~4k tokens
    nupp reference --skill      eject the same reference as an agent skill
    nupp completions bash|zsh|fish  print shell command completion
    nupp lsp serve [root]       LSP server over stdio
    nupp lsp <operation> ...    semantic inspect, navigation, and refactoring

Every command supports `-h`/`--help`; `nupp help <command>` prints the same
command-specific reference.

Language-aware operations are also available without an editor. Positions are
1-based byte line and column numbers, matching compiler diagnostics; add
`--json` for stable machine-readable output:

    nupp lsp inspect FILE LINE COLUMN
    nupp lsp definition FILE LINE COLUMN
    nupp lsp references [--include-declaration] FILE LINE COLUMN
    nupp lsp symbols [--file FILE] [PATTERN]
    nupp lsp rename [--write] FILE LINE COLUMN NEW_NAME
    nupp lsp actions [--only quickfix|refactor] FILE LINE COLUMN

Rename previews its semantic project-wide edits unless `--write` is given.
`nupp lsp` and `nupp lsp ROOT` remain aliases for the stdio server.

## Declarations and modules

A typed declaration says where it lives the way an ordinary Lua definition
does — `local` keeps it to the file, a qualified name puts it on that table,
and `global` publishes it project-wide:

    local models = {}

    local type UserId = uint32      -- private to this file
    record models.User              -- a member of models, like function models.f
        id: UserId
    end
    global type AppId = uint64      -- visible project-wide as a global

    return models

A declaration that names none of the three is refused (NUPP2119): plain Lua
would have made the name a global, so the same silence is not reused for a
different meaning. Inside its own body a declaration answers to its simple
name, so a recursive field reads `User?` rather than `models.User?`. See
[docs/modules.md](docs/modules.md) for the full rules and worked examples.

Records and interfaces can declare trusted metamethod contracts, bounded
generic surfaces, and ordinary inline method bodies. Runtime metatable setup
remains explicit Lua rather than compiler-generated behavior; see
[docs/metamethods.md](docs/metamethods.md).

LuaJIT's soft-keyword `const` declaration is supported for immutable local
bindings, including typed bindings and local functions:

    const MAX_USERS: integer = 100
    const function lookupUser(id: UserId): User? return nil end

Another file reaches a member through the module it was attached to, so every
name shows where it came from:

    local models = require("models")

    local user: models.User = new models.User {id = 1}

A module path also names a type directly, as in `models.user.User`. Only a
`global` is reachable without saying where it comes from. Runtime module
values follow Lua exactly: a module's type is whatever the file returned, and
a declaration with a runtime value — a record's table, a struct's ctype — puts
itself on that table, so there is nothing merged in behind your back. A
`.d.nupp` declaration file is the exception: it describes an interface it does
not own and returns no table of its own, so a bare declaration there is that
interface. Ordinary Lua assignments and functions keep
their normal `_G` behavior; `global` is only contextual before typed
declarations.

Deterministic resource scopes consume any value returned by an `@owned`
producer and expose a borrow inside the body:

    @owned(closeFile)
    function files.open(path: string): LuaFile
        local file = io.open(path, "r")
        if not file then error("cannot open " .. path) end
        return file
    end

    with file = files.open("input.txt") do
        print(file:read("*a"))
    end

Cleanup runs on fallthrough, errors, and structured control flow. Suspending a
raw coroutine while the cleanup obligation is live is rejected because the
coroutine may never resume. See [docs/with.md](docs/with.md) for ordering,
failure, and lifetime rules.

## Profiling

The profiler is part of the toolchain, in two channels:

    nupp run --profile app.nupp      # where the time went -> profile.out
    nupp run --jit-aborts app.nupp   # what the JIT refused -> jit-aborts.csv

`--profile` writes collapsed-stack text that
[speedscope.app](https://speedscope.app), FlameGraph.pl and inferno read
directly; `--profile=2` samples every 2ms rather than the default 10. The leaf
of each stack carries the VM state most of its samples were in, so `_[I]` on
something hot means the compiler is not running it.

`--jit-aborts` answers the question a sampler cannot — whether the hot code was
compiled at all. It writes one CSV row per place LuaJIT gave up, with a
blacklisted trace, permanently demoted to the interpreter, ranked first.

`nupp.zone` names the phases of a program so samples and aborts report
themselves in its terms rather than only in function names, and
`nupp.profile` is the same two channels driven from code, for when the
interesting window is one frame rather than the whole run. See
[docs/tooling/profiling.md](docs/tooling/profiling.md).

## Layout

    src/nupp/compiler/  compiler sources — Nupp (.nupp) only: self-hosted
    bootstrap/     tracked stage-0 compiler used by a fresh clone
    build/nupp/compiler/ generated artifacts (gitignored): the .lua that nupp
                   generates from src (`nupp fixpoint` verifies them)
    tests/         test suite (plain LuaJIT runner, no dependencies)
    docs/          the documentation site's sources
    plans/         design records and the roadmap

`docs/` is organized the way the generated site is, and `nupp.lua` maps each
file to its route:

    docs/start/        getting started: install, tour, why, syntax, ownership
    docs/type-system/  records, structs, interfaces, unions, generics, narrowing
    docs/tooling/      one page per tool: cli, build, fmt, doc, lsp, editors
    docs/*.md          the reference: grammar, modules, ownership, with,
                       c-interop, annotations, lints, diagnostics, distribution

`docs/reference.md` is generated by `nupp reference` and committed; edit the
compiler rather than the file. Links between pages are ordinary relative
Markdown paths, rewritten to public routes at build time, so they work both in
the repository and on the site.

## Development

    ./bin/nupp build      rebuild the compiler from nupp.lua
    ./bin/nupp clean      remove all configured build outputs
    ./bin/nupp tasks      list the configured build targets
    ./bin/nupp check      check the configured project graph
    ./bin/nupp test       build, then run tests (requires LuaJIT and cjson)
    ./bin/nupp fixpoint   verify the byte-identical self-hosting rebuild
    ./bin/nupp task docs-serve   build the docs site and playground, serve both

`nupp task docs-serve` (nupp.lua's `tasks.docs-serve`) builds the docs site
and the playground and serves both together — the docs site at `/`, the
playground at `/playground/`, the same path the homepage's own "Playground"
button links to — until Ctrl+C. See [Tasks](docs/tooling/tasks.md) for the
general mechanism this uses.

The Lua libraries the toolchain uses are dependencies like any other. `nupp.lua`
declares lunamark and Scintillua as `kind = "luarocks"` rocks, the docs target
depends on them, and `nupp doc` or `nupp build --target docs` installs them —
with LPeg and the rest of what LuaRocks resolves — into a project-local `.rocks`
tree that `bin/nupp` and `tests/run` also put on the search path. Nothing is
installed globally, so two checkouts can hold different versions without either
breaking the other. The compiler itself does not need them; `nupp doc` does.

A stamped binary has no rock tree to install into, so it carries them: the
`dist` target lists both as `bundle` rocks, their Lua rides in the payload, and
the LPeg and utf8 they need in C are linked into the host stub beside cjson.
`nupp doc` works out of the box from a binary, on a machine with no LuaJIT and
no LuaRocks.

The toolchain compiles and runs generated code, so it needs the same LuaJIT
generated code does: **2.1.1784535649 or newer**, the first build carrying the
backported syntax extensions. `./bin/nupp` checks and says which build is
wanted, rather than letting a run fail on a line nobody wrote.

The project build, C and Cargo dependency providers, cache behavior, and
bootstrap workflow are documented in [docs/tooling/build.md](docs/tooling/build.md).
[Working with LuaRocks](docs/tooling/luarocks.md) covers typed library layout,
clean-consumer testing, and publication.
Metamethod contracts, `self`, contract inheritance, bounded generics, and
inline record methods are documented in
[docs/metamethods.md](docs/metamethods.md).

## Documentation

`nupp doc` extracts API documentation directly from the lossless parser CST.
It deliberately skips type checking and code generation, making documentation
builds proportional to parsing and rendering alone. Adjacent `---` docblocks
document functions, variables, types, records, structs, interfaces,
C declarations, and record fields. The usual `@param`, `@return`, `@raises`,
`@field`, `@typearg`, `@local`, and `@export` annotations are understood.

`@raises` says what makes a function raise, one line per condition, and is the
one docblock tag the checker reads as well as renders: a documented function
that calls `error` without one is
[`undocumented-raise`](docs/lints.md#undocumented-raise). Raising is part of how
a function is called, and a caller who does not know has no reason to be ready
for it.

Annotations are read wherever a function is declared, including the typed
bindings and function-typed record fields that declaration files are written
with, so `local ipairs: function<V>(t: {V}): ...` documents its arguments and
results like any other function. A long comment at the top of a file is that
file's module documentation, kept as markdown; an explicit `@module` docblock
still takes precedence.

A `.d.nupp` file documents in full without `--all`, because `local` there is
not privacy: its bindings are the globals or the exports it describes. Mark a
declaration `@local` to keep it out. Ordinary modules keep the usual default,
where only globals, exported types, and `@export` declarations are shown.

    ./bin/nupp doc site -o build/docs src
    ./bin/nupp doc markdown -o docs/api.md src
    ./bin/nupp doc both -o build/docs

Site output is a responsive three-column layout with its own color system,
typography, navigation, badges, code treatment, and light/dark behavior. Both
side columns have matching header controls and remember their collapsed state. Non-home pages add previous and next links, while the left
navigation becomes a hamburger drawer on small screens. Nupp code uses the
compiler lexer; Scintillua's lexers highlight fenced Lua, GLSL, shell,
JSON, and other languages. Every page links to a colocated `llms.txt`; the site
root also contains an index at `llms.txt` and the combined reference at
`llms-full.txt`.
`both` writes the static site plus `api.md` into the output directory.

Markdown is rendered by [lunamark](https://github.com/jgm/lunamark), which is
required: `nupp doc` says so and stops if it is not installed. Scintillua is
optional and degrades — if it or a requested lexer is unavailable, nuppdoc
still emits safely escaped code without highlighting that block. Both are rocks
the docs target depends on, so the command that renders is the command that
installs them — and both are carried by the `dist` binary, which renders
without installing anything at all.

Documentation is also a build target kind, so it participates in the ordinary
manifest workflow:

```lua
build = {
    targets = {
        docs = {
            kind = "docs",
            sources = { "src" },
            format = "both",
            outDir = "build/docs",
            title = "My project API",
            name = "My project",
            description = "The project documentation.",
            includePrivate = false,
            github = "https://github.com/example/project",
            pages = {
                {
                    path = "",
                    title = "My project",
                    source = "docs/index.md",
                    layout = "home",
                    heroTitle = "Build with My project",
                    heroText = "A short introduction.",
                    heroActions = {
                        { text = "Get started", path = "guide", theme = "brand" },
                    },
                    features = {
                        { icon = "◆", title = "Typed", details = "Useful contracts." },
                    },
                },
                { path = "guide", title = "Guide", source = "docs/guide.md" },
            },
        },
    },
}
```

Source files whose basename starts with `_`, files anywhere below an
`internal/` directory, and record methods or members whose name starts with
`_` are omitted by default. Set `includePrivate = true` on the docs target to
include them explicitly.

Page paths become directory-style routes such as `guide/index.html`. Module
pages live below `modules/`, and compatibility redirects preserve the former
`modules/name.html` URLs. A page source is Markdown relative to `nupp.lua`.
Home pages additionally accept `heroTitle`, `heroText`, `heroContent`,
`heroImage`, `heroImageAlt`, `heroActions`, and `features`. Each feature has a `title` and
`details`, and may supply an `icon`, an `image` with `imageAlt`, or a `code`
sample with an optional `codeLanguage`. Features render as an alternating
showcase after the home page's Markdown content. Add
`<!-- nupp:features -->` on its own line to render the showcase at that point
instead.

Run it with `nupp build --target docs`. `nupp check --target docs` parses and
validates every selected source without writing output. Warm rebuilds avoid
rewriting byte-identical generated files.

## Visual Studio Code

The extension in `editors/vscode` provides `.nupp` syntax and semantic
highlighting, diagnostics, navigation, hover, completion, signature help,
rename, references, formatting, and code actions — quick fixes carried by the
diagnostics themselves, plus `with` scope wrap and unwrap refactorings.
Install its client dependency, open the
repository root in VS Code, and run the `Run Nupp extension` launch
configuration:

    cd editors/vscode
    npm install

The development extension finds `bin/nupp` in the workspace automatically.
For other workspaces, install `nupp` on `PATH` or set `nupp.serverPath` to its
absolute path.

## Claude Code

`editors/claude-code` is a plugin marketplace registering the same server for
`.nupp`, so Claude Code's LSP tool reads the language rather than the text:

    claude plugin marketplace add ./editors/claude-code
    claude plugin install nupp-lsp@nupp

`nupp` has to be on `PATH`, and Claude Code has to be restarted afterwards —
it builds its file-type-to-server table when a session starts. See
[editors/claude-code/plugins/nupp-lsp](editors/claude-code/plugins/nupp-lsp)
for what that tool does and does not get.

## Browser playground

`editors/playground` checks and compiles Nupp in the browser with the real,
self-hosted compiler — `bootstrap/nupp.lua` running client-side in a pure-JS
Lua VM, no server round-trip:

    cd editors/playground
    npm install
    npm run serve

`embed.html` is the same checker with none of the surrounding page — an
editor with inline diagnostics, meant for `<iframe>`. See
[editors/playground/README.md](editors/playground/README.md) for how running
LuaJIT-authored source client-side works at all, and the one class of program
(real C structs/FFI) it can't check.

## The language in one piece

No model has been trained on Nupp, and every one of them is fluent in Lua. So
the reference worth having is not a tutorial but a list of what this language
adds and what catches each addition being got wrong:

    nupp reference                                  # ~4k tokens of markdown
    nupp reference --skill -o .claude/skills/nupp/SKILL.md

It comes out of the binary rather than off a website, so a reader always gets
the reference belonging to the compiler they are running — a reference from
another version is worse than none, because nothing tells them it is wrong. The
lint and diagnostic tables are generated from the registries, every example is
compiled by the test suite, and every code it cites has to resolve in `nupp
explain`. [docs/reference.md](docs/reference.md) is the same document,
committed, and the doc site renders it into its `llms.txt`.
