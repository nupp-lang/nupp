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
            entries = { "nupp.main" },
            resources = {
               "src/nupp/decls/*.d.nupp",
               "src/nupp/decls/jit/*.d.nupp",
               "src/nupp/std/*.nupp",
            },
         },
         -- Nupp stamped into the host as one self-contained executable. It is
         -- the first payload the format ever carries, on purpose: a packager
         -- that cannot package itself has no business claiming it packages
         -- anything. Build the stub first with
         -- `cargo build --release --manifest-path host/Cargo.toml`.
         dist = {
            kind = "binary",
            description = "Stamp the compiler into a self-contained binary",
            entries = { "nupp.main" },
            -- Carried, not just installed: a binary is handed to someone who
            -- has no rock tree, and `nupp doc` is one of the commands it
            -- claims to have.
            dependencies = { "lunamark", "scintillua" },
            resources = {
               "src/nupp/decls/*.d.nupp",
               "src/nupp/decls/jit/*.d.nupp",
               "src/nupp/std/*.nupp",
            },
            stub = "build/host/release/nupp-host",
            output = "build/dist/nupp",
         },
         docs = {
            kind = "docs",
            dependencies = { "lunamark", "scintillua" },
            sources = { "src/nupp" },
            format = "both",
            outDir = "build/docs",
            title = "Nupp API",
            name = "Nupp",
            description = "A systems language for LuaJIT with ownership, "
               .. "C interop, and built-in tooling.",
            github = "https://github.com/nupp-lang/nupp",
            logo = "images/nupp.svg",
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
                  heroText = "A systems language for LuaJIT with ownership, "
                     .. "C interop, and built-in tooling.",
                  heroImage = "images/nupp.png",
                  heroImageAlt = "A nuppeppo in a moonlit forest",
                  heroActions = {
                     {
                        text = "Get started",
                        path = "getting-started/installation",
                        theme = "brand",
                     },
                     {
                        text = "Browse the API",
                        path = "modules/nupp/main",
                     },
                  },
                  features = {
                     {
                        icon = "◆",
                        title = "Safe ownership",
                        details = "Owned, borrowed, pinned, and deterministic "
                           .. "resource lifetimes.",
                     },
                     {
                        icon = "C",
                        title = "Direct C interop",
                        details = "Typed declarations and header imports built "
                           .. "for LuaJIT FFI.",
                     },
                     {
                        icon = "⚡",
                        title = "Fast toolchain",
                        details = "Parser, formatter, build tool, documentation, "
                           .. "and LSP in one binary.",
                     },
                     {
                        icon = "<>",
                        title = "Lua-shaped",
                        details = "A familiar language that keeps Lua's small, expressive core.",
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
                  title = "Why use Nupp?",
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
                  path = "type-system/enums",
                  title = "Enums",
                  source = "docs/type-system/enums.md",
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
                  title = "The nupp command",
                  source = "docs/tooling/cli.md",
               },
               {
                  path = "tooling/build",
                  title = "The build system",
                  source = "docs/tooling/build.md",
               },
               {
                  path = "tooling/fmt",
                  title = "The formatter",
                  source = "docs/tooling/fmt.md",
               },
               {
                  path = "tooling/doc",
                  title = "The documentation generator",
                  source = "docs/tooling/doc.md",
               },
               {
                  path = "tooling/lsp",
                  title = "The language server",
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

   selfHost = {
      target = "compiler",
      bootstrap = "bootstrap/nupp.lua",
      -- The target `nupp fixpoint --binary` stamps twice. Naming it here rather
      -- than in the command keeps the compiler from knowing anything about how
      -- this particular project chose to package itself.
      binary = "dist",
   },
}
