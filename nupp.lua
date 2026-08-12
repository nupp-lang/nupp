-- The languages a stamped binary can highlight a fenced block in. Scintillua
-- ships a hundred and sixty lexers and they are 1.7 MB, which is more than the
-- rest of the binary put together; these are the ones a technical document
-- actually fences, and a fence in anything else renders as escaped text the way
-- it does with no Scintillua at all.
--
-- Nupp itself is not here: it is highlighted by the compiler's own parser and
-- lexer, which agree about both tokens and contextual syntax. The project lexer
-- directory still carries a Nupp Scintillua lexer for Scintillua consumers.
--
-- Closed under embedding. A lexer loads another to highlight what it contains --
-- HTML reaches for CSS and JavaScript, Markdown for everything it fences -- so
-- leaving one out breaks the lexer that wanted it rather than only itself.
local LEXERS = {
   "lexer", "awk", "bash", "batch", "c", "clojure", "cmake", "coffeescript",
   "cpp", "csharp", "css", "diff", "dockerfile", "elixir", "erlang", "fish",
   "go", "haskell", "html", "ini", "java", "javascript", "json", "julia",
   "latex",
   "lua", "makefile", "markdown", "nim", "perl", "php", "powershell", "python",
   "r", "ruby", "rust", "scala", "sql", "swift", "text", "toml", "typescript",
   "xml", "yaml", "zig",
}

local bundledLexers = {}
for _, name in ipairs(LEXERS) do
   bundledLexers[#bundledLexers + 1] = "scintillua/lexers/" .. name .. ".lua"
end

return {
   include = { "src" },

   -- What `nupp doc` renders with. Both are installed into `.rocks`, a tree
   -- this checkout owns, so two checkouts can want different versions without
   -- either able to break the other's build by upgrading something. `bin/nupp`
   -- and `tests/run` put that tree on the search path, and a build puts it
   -- there for itself, so nothing here is installed globally.
   dependencies = {
      -- Renders the markdown. Pulls in lpeg, cosmo, alt-getopt and luautf8,
      -- which LuaRocks resolves rather than this file listing them.
      --
      -- `bundle` is what a binary carries. LPeg calls are supplied by Nupp's PEG
      -- compatibility frontend; only the utf8 the entity table needs is linked
      -- into the host stub. Named rather than swept, because the tree also holds a
      -- command-line program and its tests, which nothing here ever asks for.
      lunamark = {
         kind = "luarocks",
         version = "0.6.0-1",
         bundle = {
            "lunamark.lua", "lunamark/**.lua",
            "cosmo.lua", "cosmo/**.lua",
            "re.lua",
         },
      },
      -- Syntax highlighting for fenced code in the generated site. Not
      -- published on LuaRocks, so the rockspec beside it stands in for the one
      -- upstream does not ship.
      scintillua = {
         kind = "luarocks",
         rockspec = "rocks/scintillua-6.7-1.rockspec",
         bundle = bundledLexers,
      },
   },

   build = {
      outDir = "build",
      default = "compiler",
      targets = {
         compiler = {
            kind = "modules",
            description = "Build the self-hosted compiler",
            entries = { "nupp.compiler.main" },
            resources = {
               "src/nupp/compiler/decls/*.d.nupp",
               "src/nupp/compiler/decls/jit/*.d.nupp",
               {source = "src/nupp/resources.nupp", output = "nupp/compiler/nupp/resources.nupp"},
               {source = "src/nupp/zone.nupp", output = "nupp/compiler/nupp/zone.nupp"},
               {source = "src/nupp/profile.nupp", output = "nupp/compiler/nupp/profile.nupp"},
               {source = "src/nupp/span.nupp", output = "nupp/compiler/nupp/span.nupp"},
               {source = "src/nupp/heap.nupp", output = "nupp/compiler/nupp/heap.nupp"},
               {source = "src/nupp/suspension.nupp", output = "nupp/compiler/nupp/suspension.nupp"},
               {source = "src/nupp/io/process.nupp", output = "nupp/compiler/nupp/io/process.nupp"},
               {source = "src/nupp/io/processtypes.nupp", output = "nupp/compiler/nupp/io/processtypes.nupp"},
               {source = "src/nupp/workers.nupp", output = "nupp/compiler/nupp/workers.nupp"},
               {source = "src/nupp/io/http.nupp", output = "nupp/compiler/nupp/io/http.nupp"},
               {source = "src/nupp/compiler/decls/processnative.d.nupp", output = "nupp/compiler/decls/processnative.d.nupp"},
               {source = "src/nupp/compiler/decls/workersnative.d.nupp", output = "nupp/compiler/decls/workersnative.d.nupp"},
               {source = "src/nupp/compiler/decls/httpnative.d.nupp", output = "nupp/compiler/decls/httpnative.d.nupp"},
            },
         },
         -- Nupp stamped into a feature-matched host as one self-contained
         -- executable. It is the first payload the format ever carries, on
         -- purpose: a packager that cannot package itself has no business
         -- claiming it packages anything.
         dist = {
            kind = "binary",
            description = "Stamp the compiler into a self-contained binary",
            entries = { "nupp.compiler.main" },
            -- Carried, not just installed: a binary is handed to someone who
            -- has no rock tree, and `nupp doc` is one of the commands it
            -- claims to have.
            dependencies = { "lunamark", "scintillua" },
            resources = {
               "src/nupp/compiler/decls/*.d.nupp",
               "src/nupp/compiler/decls/jit/*.d.nupp",
               {source = "src/nupp/resources.nupp", output = "nupp/compiler/nupp/resources.nupp"},
               {source = "src/nupp/zone.nupp", output = "nupp/compiler/nupp/zone.nupp"},
               {source = "src/nupp/profile.nupp", output = "nupp/compiler/nupp/profile.nupp"},
               {source = "src/nupp/span.nupp", output = "nupp/compiler/nupp/span.nupp"},
               {source = "src/nupp/heap.nupp", output = "nupp/compiler/nupp/heap.nupp"},
               {source = "src/nupp/suspension.nupp", output = "nupp/compiler/nupp/suspension.nupp"},
               {source = "src/nupp/io/process.nupp", output = "nupp/compiler/nupp/io/process.nupp"},
               {source = "src/nupp/io/processtypes.nupp", output = "nupp/compiler/nupp/io/processtypes.nupp"},
               {source = "src/nupp/workers.nupp", output = "nupp/compiler/nupp/workers.nupp"},
               {source = "src/nupp/io/http.nupp", output = "nupp/compiler/nupp/io/http.nupp"},
               {source = "src/nupp/compiler/decls/processnative.d.nupp", output = "nupp/compiler/decls/processnative.d.nupp"},
               {source = "src/nupp/compiler/decls/workersnative.d.nupp", output = "nupp/compiler/decls/workersnative.d.nupp"},
               {source = "src/nupp/compiler/decls/httpnative.d.nupp", output = "nupp/compiler/decls/httpnative.d.nupp"},
            },
            stub = "nupp",
            output = "build/dist/nupp",
         },
         docs = {
            kind = "docs",
            dependencies = { "lunamark", "scintillua" },
            sources = { "src" },
            format = "both",
            outDir = "build/docs",
            title = "Nupp API",
            name = "Nupp",
            description = "LuaJIT with static guarantees.",
            github = "https://github.com/nupp-lang/nupp",
            logo = "images/nupp.svg",
            favicon = "images/nupp-icon-32.png",
            public = "docs/public",
            customCss = "docs/public/nupp.css",
            lexers = "docs/lexers",
            -- Every diagnostic code on one page, generated from what `nupp explain`
            -- knows. Listing them here instead would be a copy of the compiler's
            -- own table, stale the first time a code is added. It sits beside the
            -- page that says what a diagnostic is, which is what it indexes.
            diagnostics = {
               path = "reference/diagnostic-index",
               title = "Diagnostic index",
            },
            -- The LuaJIT surface on one page, read from the declarations the
            -- checker itself loads. The prelude is public API written in a
            -- private tree, so without this the one library every program uses
            -- is the one the site never shows.
            stdlib = {
               path = "reference/luajit",
               title = "LuaJIT standard library",
            },
            pages = {
               {
                  path = "",
                  title = "Nupp",
                  source = "docs/home.md",
                  layout = "home",
                  heroTitle = "Nupp",
                  heroText = "LuaJIT with static guarantees.",
                  heroContent = "Nupp gives LuaJIT precise types, checked C interop, "
                     .. "deterministic ownership, scheduler-neutral suspension, isolated "
                     .. "workers, and self-contained builds—without hiding the Lua underneath.",
                  heroImage = "images/nupp.png",
                  heroImageAlt = "A nuppeppo in a moonlit forest",
                  heroActions = {
                     {
                        text = "Get started",
                        path = "getting-started/installation",
                        theme = "brand",
                     },
                     {
                        text = "Playground",
                        path = "/playground/",
                     },
                  },
                  features = {
                     {
                        title = "Add types without leaving Lua behind",
                        details = "Start with a LuaJIT program that already runs. Add "
                           .. "annotations where they earn their keep, then tighten a file "
                           .. "to strict Nupp when it is ready.",
                        code = [[-- models.g.nupp: type syntax, gradual checks
local function scale(point, factor)
    return {x = point.x * factor, y = point.y * factor}
end

-- models.nupp: the same code, now a checked boundary
local function scale(point: Point, factor: number): Point
    return new Point {x = point.x * factor, y = point.y * factor}
end]],
                     },
                     {
                        title = "Model real data precisely",
                        details = "Records stay flexible Lua tables. Structs become compact "
                           .. "FFI cdata with a fixed C layout. Use the representation your "
                           .. "data actually needs.",
                        code = [[local record User
    name: string
    online: boolean
end

local struct Vec2
    x: float
    y: float
end]],
                     },
                     {
                        title = "Write expressive, checked APIs",
                        details = "Generics, interfaces, unions, overloads, and control-flow "
                           .. "narrowing make contracts useful without making Lua feel heavy.",
                        code = [[local function first<V>(items: {V}): V?
    return items[1]
end

local function label(value: string | number): string
    if value is string then return value:upper() end
    return string.format("%.2f", value)
end]],
                     },
                     {
                        title = "Make FFI contracts visible",
                        details = "Declare native functions with their real C-compatible types. "
                           .. "Nupp checks every call while LuaJIT still does the fast work.",
                        code = [[cdef struct timeval
    tv_sec: int64
    tv_usec: int32
end

cdef function gettimeofday(tv: timeval*, tz: voidptr?): int32]],
                     },
                     {
                        title = "Import headers instead of transcribing them",
                        details = "Turn a C header into a typed Nupp declaration module, then "
                           .. "keep the generated boundary reviewed and versioned with the code "
                           .. "that calls it.",
                        code = [[# Generate typed bindings you can commit and edit.

nupp import-c native/library.h --out src/library.d.nupp

# Or use a header directly while compiling.
local native = cheader("native/library.h")]],
                        codeLanguage = "text",
                     },
                     {
                        title = "Give resources a lifetime the checker can see",
                        details = "Ownership, borrowing, pinning, and deterministic cleanup make "
                           .. "the important rules at a C boundary explicit—and make leaks and "
                           .. "use-after-move errors reportable.",
                        code = [[do
    local file = resources.openFile("report.txt", "r")
    local contents = file:read("*a")
    send(borrows contents)
end -- the file is closed on every structured exit]],
                     },
                     {
                        title = "Suspend without coloring the call graph",
                        details = "A suspension-aware call returns its ordinary value. It blocks "
                           .. "without a handler and parks its coroutine under a host scheduler. "
                           .. "The checker tracks that effect separately from the return type. "
                           .. "[Follow the call from function to scheduler]"
                           .. "(concepts/suspension/index.html).",
                        code = [[local process = require("nupp.io.process")

local function compilerVersion(): string
    local child = assert(process.new({args = {"cc", "--version"}}))
    local result = assert(child:communicate())
    child:close()
    return result.output
end

local function printVersion(): nil
    print(compilerVersion())
end

printVersion()]],
                     },
                     {
                        title = "Use every core without sharing the heap",
                        details = "Workers run fresh LuaJIT states on native threads and exchange "
                           .. "bounded, serialized messages. Calls read like functions, failures "
                           .. "cross back, and ownership guarantees every worker is joined.",
                        code = [[local workers = require("nupp.workers")

do
    local hasher = workers.spawn("workers.hash")
    local answer = hasher:call({
        name = "level1",
        bytes = contents,
    })
end]],
                     },
                     {
                        title = "Capture what native calls are allowed to do",
                        details = "Effect contracts describe whether a call borrows, takes, or "
                           .. "returns ownership. The compiler infers those facts for Nupp code "
                           .. "and checks them at module boundaries.",
                        code = [[cdef function send(borrows bytes: cstring): int32

@owned(free)
cdef function malloc(size: uint64): voidptr
cdef function free(takes value: voidptr)]],
                     },
                     {
                        title = "Keep the LuaJIT you already know",
                        details = "Every valid LuaJIT program is valid Nupp. Keep Lua's small, "
                           .. "direct model, then opt into interpolation, typed declarations, and "
                           .. "the rest of Nupp where they help.",
                        code = [[local name = "Nupp"
local status = ready ? "go" : "wait"
print(`Hello, ${name}: ${status}`)]],
                     },
                     {
                        title = "Pay only for the native runtime you use",
                        details = "The compiler follows resolved standard-library uses and builds "
                           .. "exactly their Rust or C providers. Paths, workers, and every "
                           .. "other native facility disappear completely when the program does "
                           .. "not use them.",
                        code = [[local source = nupp.io.Path.new("src", "main.nupp")

-- Path support is selected for this target. Workers, URI
-- support, UUID generation, and unrelated native code are absent.]],
                     },
                     {
                        title = "Ship a deterministic, self-contained program",
                        details = "Build modules, one-file Lua bundles, or executables with a "
                           .. "feature-matched LuaJIT host. Sorted payloads and content-addressed "
                           .. "inputs make identical source produce byte-identical output.",
                        code = [[nupp build --target dist
nupp fixpoint --binary]],
                        codeLanguage = "text",
                     },
                     {
                        title = "Optimize what the JIT can't infer",
                        details = "Nupp leaves hot loops to LuaJIT's tracer and uses types where "
                           .. "the tracer cannot: declared call projections share stable table "
                           .. "paths and become flat positional arguments without tables, "
                           .. "varargs, or closures.",
                        code = [[local record Vec2
    x: number
    y: number
    expands (x, y)
end

update(
    ...entity.body.position,
    ...entity.body.velocity,
    delta
)
-- entity.body is read once; update receives x, y, x, y, delta.]],
                     },
                     {
                        title = "Compiler intrinsics",
                        details = "A logged line and a zone marker are calls the compiler "
                           .. "knows enough to remove. A filtered nupp.log severity evaluates "
                           .. "none of its arguments, and a zone push or discarded pop on the "
                           .. "module nupp.zone returns generates inline--no call left for a "
                           .. "hot path to pay for.",
                        code = [[nupp.log.debug("spawn at %d,%d", x, y) -- unevaluated when filtered

local zone = require("nupp.zone")
zone.push("physics")
stepWorld()
zone.pop() -- inlined against the zone stack, not called]],
                     },
                     {
                        title = "Compute what you can before the program runs",
                        details = "comptime do ... end runs ordinary Nupp while the file is "
                           .. "compiled and writes the answer into the output as a literal. "
                           .. "Deterministic and sandboxed: no clock, no files, no randomness "
                           .. "-- and no macros, because it produces data rather than code.",
                        code = [[const CRC32 = comptime do
    const entries = {}
    for byte = 0, 255 do
        local acc = byte
        for _ = 1, 8 do
            acc = acc & 1 ~= 0 and 0xedb88320 ~ (acc >> 1) or acc >> 1
        end
        entries[byte + 1] = acc
    end
    return entries
end

-- The generated Lua holds the table, not the loop that built it.]],
                     },
                     {
                        title = "Carry the whole workflow in one toolchain",
                        details = "Check, format, build, test, profile, generate documentation, "
                           .. "explain errors, and power an editor from the same language-aware compiler. No "
                           .. "glue scripts required.",
                        code = [[nupp check          # type-check the project
nupp fmt            # apply Nupp's fixed style
nupp test           # build and run the configured suite
nupp run --profile  # write a speedscope-compatible profile
nupp lsp            # start the language server]],
                        codeLanguage = "text",
                     },
                  },
               },
               -- The sidebar groups pages by the first segment of their route
               -- and titles the group from it, so the order here is the order
               -- a reader meets the sections in.
               {
                  path = "getting-started/installation",
                  title = "Installation",
                  source = "docs/start/installation.md",
               },
               {
                  path = "getting-started/tour",
                  title = "Tour of Nupp",
                  source = "docs/start/tour.md",
               },
               {
                  path = "getting-started/why",
                  title = "Reasons to use Nupp",
                  source = "docs/start/why.md",
               },
               {
                  path = "concepts/strictness",
                  title = "Strictness floors",
                  source = "docs/concepts/strictness.md",
               },
               {
                  path = "concepts/syntax",
                  title = "Nupp syntax",
                  source = "docs/start/syntax.md",
               },
               {
                  path = "concepts/calls",
                  title = "Named and plucked arguments",
                  source = "docs/concepts/calls.md",
               },
               {
                  path = "concepts/declarations",
                  title = "Declarations and modules",
                  source = "docs/modules.md",
               },
               {
                  path = "concepts/ownership",
                  title = "Ownership",
                  source = "docs/start/ownership.md",
               },
               {
                  path = "concepts/suspension",
                  title = "Suspension",
                  source = "docs/start/suspension.md",
               },
               {
                  path = "concepts/suspension-handlers",
                  title = "Suspension handlers",
                  source = "docs/start/suspension-handlers.md",
               },
               {
                  path = "concepts/workers",
                  title = "Workers",
                  source = "docs/start/workers.md",
               },
               {
                  path = "concepts/effects",
                  title = "Effect contracts",
                  source = "docs/effects.md",
               },
               {
                  path = "concepts/c-interop",
                  title = "C interop",
                  source = "docs/c-interop.md",
               },
               {
                  path = "concepts/standard-library",
                  title = "Standard library",
                  source = "docs/stdlib.md",
               },
               {
                  path = "concepts/paths-and-uris",
                  title = "Paths and URIs",
                  source = "docs/path-uri.md",
               },
               {
                  path = "concepts/metamethods",
                  title = "Metamethods",
                  source = "docs/metamethods.md",
               },
               {
                  path = "concepts/comptime",
                  title = "Comptime",
                  source = "docs/concepts/comptime.md",
               },
               {
                  path = "concepts/reflection",
                  title = "Semantic reflection",
                  source = "docs/concepts/reflection.md",
               },
               {
                  path = "getting-started/tooling",
                  title = "Tooling",
                  source = "docs/start/tooling.md",
               },

               {
                  path = "type-system/overview",
                  title = "Overview",
                  source = "docs/type-system/overview.md",
               },
               {
                  path = "type-system/primitives",
                  title = "Primitive types",
                  source = "docs/type-system/primitives.md",
               },
               {
                  path = "type-system/records",
                  title = "Records and structs",
                  source = "docs/type-system/records.md",
               },
               {
                  path = "type-system/interfaces",
                  title = "Interfaces",
                  source = "docs/type-system/interfaces.md",
               },
               {
                  path = "type-system/refinements",
                  title = "Refinements",
                  source = "docs/type-system/refinements.md",
               },
               {
                  path = "type-system/properties",
                  title = "Property capabilities",
                  source = "docs/type-system/properties.md",
               },
               {
                  path = "type-system/unions",
                  title = "Unions",
                  source = "docs/type-system/unions.md",
               },
               {
                  path = "type-system/intersections",
                  title = "Intersections",
                  source = "docs/type-system/intersections.md",
               },
               {
                  path = "type-system/overloads",
                  title = "Overloads and overrides",
                  source = "docs/type-system/overloads.md",
               },
               {
                  path = "type-system/generics",
                  title = "Generics",
                  source = "docs/type-system/generics.md",
               },
               {
                  path = "type-system/type-level-computation",
                  title = "Type-level computation",
                  source = "docs/type-system/type-level-computation.md",
               },
               {
                  path = "type-system/packs",
                  title = "Type packs",
                  source = "docs/type-system/packs.md",
               },
               {
                  path = "type-system/associated-types",
                  title = "Associated types",
                  source = "docs/type-system/associated-types.md",
               },
               {
                  path = "type-system/narrowing",
                  title = "Narrowing",
                  source = "docs/type-system/narrowing.md",
               },

               -- The same handwritten pages, again as overviews on the
               -- @namespace-synthesized module routes, so a reader who
               -- follows a cross-reference into the API reference finds
               -- the same prose above the generated field list.
               {
                  path = "modules/nupp/io/files",
                  title = "Filesystem metadata",
                  source = "docs/files.md",
               },
               {
                  path = "modules/nupp/data",
                  title = "Module: nupp.data",
                  source = "docs/data.md",
               },
               {
                  path = "modules/nupp/io",
                  title = "Module: nupp.io",
                  source = "docs/io.md",
               },
               {
                  path = "modules/nupp/log",
                  title = "Module: nupp.log",
                  source = "docs/logging.md",
               },
               {
                  path = "modules/nupp/math",
                  title = "Module: nupp.math",
                  source = "docs/math.md",
               },
               {
                  path = "modules/nupp/peg",
                  title = "Module: nupp.peg",
                  source = "docs/peg.md",
               },
               {
                  path = "guides/build",
                  title = "Build system",
                  source = "docs/tooling/build.md",
               },
               {
                  path = "guides/luarocks",
                  title = "Working with LuaRocks",
                  source = "docs/tooling/luarocks.md",
               },
               {
                  path = "guides/fmt",
                  title = "Formatter",
                  source = "docs/tooling/fmt.md",
               },
               {
                  path = "guides/doc",
                  title = "Documentation generator",
                  source = "docs/tooling/doc.md",
               },
               {
                  path = "guides/lsp",
                  title = "Language server",
                  source = "docs/tooling/lsp.md",
               },
               {
                  path = "guides/editors",
                  title = "Editors",
                  source = "docs/tooling/editors.md",
               },
               {
                  path = "guides/testing",
                  title = "Testing",
                  source = "docs/tooling/testing.md",
               },
               {
                  path = "guides/tasks",
                  title = "Tasks",
                  source = "docs/tooling/tasks.md",
               },
               {
                  path = "guides/profiling",
                  title = "Profiling",
                  source = "docs/tooling/profiling.md",
               },
               {
                  path = "guides/optimization",
                  title = "Optimization",
                  source = "docs/tooling/optimization.md",
               },
               {
                  path = "guides/constant-folding",
                  title = "Constant folding",
                  source = "docs/tooling/constant-folding.md",
               },

               -- Generated by `nupp reference` and committed, so the site, the
               -- llms.txt beside it, and the binary all say the same thing.
               -- tests/referencetest.lua fails if it drifts.

               {
                  path = "reference/cli",
                  title = "nupp command",
                  source = "docs/tooling/cli.md",
               },
               {
                  path = "reference/language",
                  title = "Language reference",
                  source = "docs/reference.md",
               },
               {
                  path = "reference/grammar",
                  title = "Grammar",
                  source = "docs/grammar.md",
               },
               {
                  path = "reference/ownership",
                  title = "Ownership",
                  source = "docs/ownership.md",
               },
               {
                  path = "reference/annotations",
                  title = "Annotations",
                  source = "docs/annotations.md",
               },
               {
                  path = "reference/derives",
                  title = "Declaration derives",
                  source = "docs/derives.md",
               },
               {
                  path = "reference/lints",
                  title = "Lints",
                  source = "docs/lints.md",
               },
               {
                  path = "reference/diagnostics",
                  title = "Diagnostics",
                  source = "docs/diagnostics.md",
               },
               {
                  path = "reference/distribution",
                  title = "Distribution",
                  source = "docs/distribution.md",
               },
            },
         },
      },
   },

   test = {
      build = "compiler",
      argv = { "luajit", "tests/run.lua" },
   },

   tasks = {
      ["docs-serve"] = {
         description = "Build the docs site and playground, serve both "
            .. "until stopped",
         argv = { "node", "scripts/docs-serve.mjs" },
      },
      -- The Lua suite reaches the native providers through their ABI, which is
      -- the level a program sees them at. What it cannot reach is what only the
      -- provider knows: the file lane's budget, its refusals, and what a
      -- cancelled transfer gives back.
      ["native-test"] = {
         description = "Run the Rust providers' own unit tests",
         argv = {
            "cargo", "test",
            "--manifest-path", "runtime/native/Cargo.toml",
            "--no-default-features",
            "--features", "files,path,uri,uuid,sha256",
         },
      },
   },

   selfHost = {
      target = "compiler",
      bootstrap = "bootstrap/nupp.lua",
      -- The target `nupp fixpoint --binary` stamps twice. Naming it here rather
      -- than in the command keeps the compiler from knowing anything about how
      -- this particular project chose to package itself.
      binary = "dist",
   },
}
