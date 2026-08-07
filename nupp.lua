return {
   include = { "src" },

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
            resources = {
               "src/nupp/decls/*.d.nupp",
               "src/nupp/decls/jit/*.d.nupp",
            },
            stub = "build/host/release/nupp-host",
            output = "build/dist/nupp",
         },
         docs = {
            kind = "docs",
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
                        path = "guide/getting-started",
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
               {
                  path = "guide/getting-started",
                  title = "Getting started",
                  source = "docs/guides/getting-started.md",
               },
               {
                  path = "guide/modules-and-types",
                  title = "Modules and types",
                  source = "docs/guides/modules-and-types.md",
               },
               {
                  path = "guide/c-interop",
                  title = "Calling C safely",
                  source = "docs/guides/c-interop.md",
               },
               {
                  path = "guide/managing-resources",
                  title = "Managing resources",
                  source = "docs/guides/managing-resources.md",
               },
               {
                  path = "guide/annotations-and-lints",
                  title = "Annotations and lints",
                  source = "docs/guides/annotations-and-lints.md",
               },
               {
                  path = "guide/profiling",
                  title = "Profiling",
                  source = "docs/guides/profiling.md",
               },
               {
                  path = "guide/optimization",
                  title = "Optimization",
                  source = "docs/guides/optimization.md",
               },
               {
                  path = "guide/build",
                  title = "Build system reference",
                  source = "docs/build.md",
               },
               {
                  path = "guide/modules",
                  title = "Module reference",
                  source = "docs/modules.md",
               },
               {
                  path = "guide/ownership",
                  title = "Ownership reference",
                  source = "docs/ownership.md",
               },
               {
                  path = "reference/annotations",
                  title = "Annotations",
                  source = "docs/annotations.md",
               },
               {
                  path = "reference/metamethods",
                  title = "Metamethods",
                  source = "docs/metamethods.md",
               },
               {
                  path = "reference/lints",
                  title = "Lints",
                  source = "docs/lints.md",
               },
               {
                  path = "reference/grammar",
                  title = "Grammar",
                  source = "docs/grammar.md",
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
