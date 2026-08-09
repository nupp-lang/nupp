-- The languages a stamped binary can highlight a fenced block in. Scintillua
-- ships a hundred and sixty lexers and they are 1.7 MB, which is more than the
-- rest of the binary put together; these are the ones a technical document
-- actually fences, and a fence in anything else renders as escaped text the way
-- it does with no Scintillua at all.
--
-- Nupp itself is not here: it is highlighted by the compiler's own lexer, which
-- is the only one that agrees with the compiler about what a token is.
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
      -- `bundle` is what a binary carries: the Lua of it, since the C of it --
      -- LPeg, and the utf8 the entity table needs -- is linked into the host
      -- stub instead. Named rather than swept, because the tree also holds a
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
            entries = { "compiler.main" },
            resources = {
               "src/compiler/decls/*.d.nupp",
               "src/compiler/decls/jit/*.d.nupp",
               {source = "src/nupp/resources.nupp", output = "compiler/nupp/resources.nupp"},
               {source = "src/nupp/zone.nupp", output = "compiler/nupp/zone.nupp"},
               {source = "src/nupp/profile.nupp", output = "compiler/nupp/profile.nupp"},
            },
         },
         -- Nupp stamped into a feature-matched host as one self-contained
         -- executable. It is the first payload the format ever carries, on
         -- purpose: a packager that cannot package itself has no business
         -- claiming it packages anything.
         dist = {
            kind = "binary",
            description = "Stamp the compiler into a self-contained binary",
            entries = { "compiler.main" },
            -- Carried, not just installed: a binary is handed to someone who
            -- has no rock tree, and `nupp doc` is one of the commands it
            -- claims to have.
            dependencies = { "lunamark", "scintillua" },
            resources = {
               "src/compiler/decls/*.d.nupp",
               "src/compiler/decls/jit/*.d.nupp",
               {source = "src/nupp/resources.nupp", output = "compiler/nupp/resources.nupp"},
               {source = "src/nupp/zone.nupp", output = "compiler/nupp/zone.nupp"},
               {source = "src/nupp/profile.nupp", output = "compiler/nupp/profile.nupp"},
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
            description = "Typed, safe, fast LuaJIT.",
            github = "https://github.com/nupp-lang/nupp",
            logo = "images/nupp.svg",
            favicon = "images/nupp-icon-32.png",
            public = "docs/public",
            customCss = "docs/public/nupp.css",
            lexers = "docs/lexers",
            pages = {
               {
                  path = "",
                  title = "Nupp",
                  source = "docs/home.md",
                  layout = "home",
                  heroTitle = "Nupp",
                  heroText = "Typed, safe, fast LuaJIT.",
                  heroContent = "Nupp adds types and ownership to LuaJIT, making C interop "
                     .. "and performance approachable.",
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
                        code = [[with file = resources.open_file("report.txt", "r") do
    local contents = file:read("*a")
    send(borrows contents)
end -- the file is closed on every structured exit]],
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
                        title = "Optimize what the JIT can't infer",
                        details = "Nupp leaves hot loops to LuaJIT's tracer and specializes the "
                           .. "work that happens before a trace exists: constants, table shapes, "
                           .. "and facts preserved by types.",
                        code = [[local function packetSize(): integer
    return 8 * 1024 + 32
end

-- -O1 folds this before LuaJIT ever sees the function.]],
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
                  title = "A tour of Nupp",
                  source = "docs/start/tour.md",
               },
               {
                  path = "getting-started/why",
                  title = "Reasons to use Nupp",
                  source = "docs/start/why.md",
               },
               {
                  path = "getting-started/syntax",
                  title = "Nupp syntax",
                  source = "docs/start/syntax.md",
               },
               {
                  path = "getting-started/ownership",
                  title = "Ownership",
                  source = "docs/start/ownership.md",
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
                  path = "type-system/narrowing",
                  title = "Narrowing",
                  source = "docs/type-system/narrowing.md",
               },

               {
                  path = "tooling/cli",
                  title = "nupp command",
                  source = "docs/tooling/cli.md",
               },
               {
                  path = "tooling/build",
                  title = "Build system",
                  source = "docs/tooling/build.md",
               },
               {
                  path = "tooling/luarocks",
                  title = "Working with LuaRocks",
                  source = "docs/tooling/luarocks.md",
               },
               {
                  path = "tooling/fmt",
                  title = "Formatter",
                  source = "docs/tooling/fmt.md",
               },
               {
                  path = "tooling/doc",
                  title = "Documentation generator",
                  source = "docs/tooling/doc.md",
               },
               {
                  path = "tooling/lsp",
                  title = "Language server",
                  source = "docs/tooling/lsp.md",
               },
               {
                  path = "tooling/editors",
                  title = "Editors",
                  source = "docs/tooling/editors.md",
               },
               {
                  path = "tooling/testing",
                  title = "Testing",
                  source = "docs/tooling/testing.md",
               },
               {
                  path = "tooling/tasks",
                  title = "Tasks",
                  source = "docs/tooling/tasks.md",
               },
               {
                  path = "tooling/profiling",
                  title = "Profiling",
                  source = "docs/tooling/profiling.md",
               },
               {
                  path = "tooling/optimization",
                  title = "Optimization",
                  source = "docs/tooling/optimization.md",
               },

               -- Generated by `nupp reference` and committed, so the site, the
               -- llms.txt beside it, and the binary all say the same thing.
               -- tests/referencetest.lua fails if it drifts.
               {
                  path = "reference/language",
                  title = "Language reference",
                  source = "docs/reference.md",
               },
               {
                  path = "reference/regex",
                  title = "nupp.regex",
                  source = "docs/regex.md",
               },
               {
                  path = "reference/grammar",
                  title = "Grammar",
                  source = "docs/grammar.md",
               },
               {
                  path = "reference/modules",
                  title = "Declarations and modules",
                  source = "docs/modules.md",
               },
               {
                  path = "reference/metamethods",
                  title = "Metamethods",
                  source = "docs/metamethods.md",
               },
               -- A page whose path is a module's route is that module's
               -- overview, rendered above its generated API rather than
               -- beside it.
               {
                  path = "modules/nupp",
                  title = "Namespace: nupp",
                  source = "docs/nupp.md",
               },
               {
                  path = "reference/ownership",
                  title = "Ownership",
                  source = "docs/ownership.md",
               },
               {
                  path = "reference/with",
                  title = "Resource scopes",
                  source = "docs/with.md",
               },
               {
                  path = "reference/c-interop",
                  title = "C interop",
                  source = "docs/c-interop.md",
               },
               {
                  path = "reference/annotations",
                  title = "Annotations",
                  source = "docs/annotations.md",
               },
               {
                  path = "reference/effects",
                  title = "Effect contracts",
                  source = "docs/effects.md",
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
