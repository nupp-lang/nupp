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

-- Windows runners do not carry a dependable pkg-config. The CI setup can name
-- the two dependency roots outright; ordinary builds keep using the packages
-- installed on their host. Both roots are one contract, so a partial override
-- is a configuration error rather than a link command assembled from two
-- unrelated installations.
local JSON_SIMDJSON_ROOT = os.getenv("NUPP_JSON_SIMDJSON_ROOT")
local JSON_LUAJIT_ROOT = os.getenv("NUPP_JSON_LUAJIT_ROOT")
if (JSON_SIMDJSON_ROOT == nil) ~= (JSON_LUAJIT_ROOT == nil) then
   error("NUPP_JSON_SIMDJSON_ROOT and NUPP_JSON_LUAJIT_ROOT must be set together")
end
local JSON_EXPLICIT_ROOTS = JSON_SIMDJSON_ROOT ~= nil
local JSON_CFLAGS = {
   "-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
}
if JSON_EXPLICIT_ROOTS then
   JSON_CFLAGS[#JSON_CFLAGS + 1] = "-DSIMDJSON_THREADS_ENABLED=1"
end

-- The built-in project templates `nupp init` scaffolds from.
--
-- They live outside `src` on purpose. A template's filenames carry the
-- substitutions that make it a template -- `src/${moduleName}.nupp` -- and a
-- tree under an include root is a tree the compiler tries to compile, so the
-- one place these cannot go is beside the modules that read them.
--
-- Staged under the compiler's own modules so `nupp.compiler.bundled` finds them
-- by one relative path whether it is reading a directory or a stamped binary's
-- payload. That is also why each is named rather than globbed: a string
-- resource derives its output from the include roots, which for a path outside
-- them means staging beside the build rather than under the modules, and a
-- resource landing there is dropped from a bundle as unreachable.
--
-- `tests/templatetest.lua` holds this list to the directory, so a template file
-- added without a line here fails the suite rather than going quietly missing
-- from every released binary.
local TEMPLATE_FILES = {
   "app/.gitignore",
   "app/README.md",
   "app/nupp.lua",
   "app/src/greeting.nupp",
   "app/src/main.nupp",
   "app/template.lua",
   "app/tests/run.lua",
   "lib/${name}-dev-1.rockspec",
   "lib/nupp.lua",
   "lib/nupp/${moduleName}.d.nupp",
   "lib/src/${moduleName}.nupp",
   "lib/template.lua",
   "lib/tests/run.lua",
}

-- What the compiler carries, which both the module build and the stamped binary
-- want in full. One list because they have never differed and a second copy is
-- how they would start to.
local RESOURCES = {
   "src/nupp/compiler/decls/*.d.nupp",
   "src/nupp/compiler/decls/jit/*.d.nupp",
   {source = "src/nupp/derive.nupp", output = "nupp/compiler/nupp/derive.nupp"},
   {source = "src/nupp/extensions.nupp", output = "nupp/compiler/nupp/extensions.nupp"},
   {source = "src/nupp/profile/zone.nupp", output = "nupp/compiler/nupp/profile/zone.nupp"},
   {source = "src/nupp/profile/trace.nupp", output = "nupp/compiler/nupp/profile/trace.nupp"},
   {source = "src/nupp/profile.nupp", output = "nupp/compiler/nupp/profile.nupp"},
   {source = "src/nupp/mem/indexed.nupp", output = "nupp/compiler/nupp/mem/indexed.nupp"},
   {source = "src/nupp/mem/span.nupp", output = "nupp/compiler/nupp/mem/span.nupp"},
   {source = "src/nupp/simd.nupp", output = "nupp/compiler/nupp/simd.nupp"},
   {source = "src/nupp/data/valuebuilder.g.nupp", output = "nupp/compiler/nupp/data/valuebuilder.g.nupp"},
   {source = "src/nupp/mem/heap.nupp", output = "nupp/compiler/nupp/mem/heap.nupp"},
   {source = "src/nupp/mem/soa.nupp", output = "nupp/compiler/nupp/mem/soa.nupp"},
   {source = "src/nupp/data/json.nupp", output = "nupp/compiler/nupp/data/json.nupp"},
   {source = "src/nupp/data/serde.nupp", output = "nupp/compiler/nupp/data/serde.nupp"},
   {source = "src/nupp/data/hmac.nupp", output = "nupp/compiler/nupp/data/hmac.nupp"},
   {
      source = "src/nupp/runtime/backend.nupp",
      output = "nupp/compiler/nupp/runtime/backend.nupp",
   },
   {
      source = "src/nupp/runtime/seam/json.nupp",
      output = "nupp/compiler/nupp/runtime/seam/json.nupp",
   },
   {
      source = "src/nupp/runtime/seam/jsonsuite.nupp",
      output = "nupp/compiler/nupp/runtime/seam/jsonsuite.nupp",
   },
   {
      source = "src/nupp/runtime/seam/bitops.nupp",
      output = "nupp/compiler/nupp/runtime/seam/bitops.nupp",
   },
   {
      source = "src/nupp/runtime/seam/bitopssuite.nupp",
      output = "nupp/compiler/nupp/runtime/seam/bitopssuite.nupp",
   },
   {source = "src/nupp/data/utf8.nupp", output = "nupp/compiler/nupp/data/utf8.nupp"},
   {source = "src/nupp/native.nupp", output = "nupp/compiler/nupp/native.nupp"},
   {source = "src/nupp/data/init.nupp", output = "nupp/compiler/nupp/data/init.nupp"},
   {source = "src/nupp/mem/init.nupp", output = "nupp/compiler/nupp/mem/init.nupp"},
   {source = "src/nupp/managed.nupp", output = "nupp/compiler/nupp/managed.nupp"},
   {source = "src/nupp/io/path.nupp", output = "nupp/compiler/nupp/io/path.nupp"},
   {source = "src/nupp/io/uri.nupp", output = "nupp/compiler/nupp/io/uri.nupp"},
   {source = "src/nupp/io/files.nupp", output = "nupp/compiler/nupp/io/files.nupp"},
   {source = "src/nupp/io/init.nupp", output = "nupp/compiler/nupp/io/init.nupp"},
   {source = "src/nupp/log.nupp", output = "nupp/compiler/nupp/log.nupp"},
   {source = "src/nupp/suspension.nupp", output = "nupp/compiler/nupp/suspension.nupp"},
   {source = "src/nupp/pegruntime.nupp", output = "nupp/compiler/nupp/pegruntime.nupp"},
   {source = "src/nupp/mathruntime.nupp", output = "nupp/compiler/nupp/mathruntime.nupp"},
   {source = "src/nupp/reflectruntime.nupp", output = "nupp/compiler/nupp/reflectruntime.nupp"},
   {source = "src/nupp/io/process.nupp", output = "nupp/compiler/nupp/io/process.nupp"},
   {source = "src/nupp/workers.nupp", output = "nupp/compiler/nupp/workers.nupp"},
   {source = "src/nupp/io/http.nupp", output = "nupp/compiler/nupp/io/http.nupp"},
   {source = "src/nupp/workers/native.d.nupp", output = "nupp/compiler/nupp/workers/native.d.nupp"},
   {source = "src/nupp/data/jsonnative.d.nupp", output = "nupp/compiler/nupp/data/jsonnative.d.nupp"},
}
local SEAM_FACTORY_RESOURCES = {
   "registry", "module", "bitset", "files", "hash", "hmacsha256", "http",
   "int64", "iobytes", "path", "peg", "process", "sha256", "simd",
   "structvalue", "suspension", "uri", "utf8", "uuid", "workers",
}
for _, name in ipairs(SEAM_FACTORY_RESOURCES) do
   RESOURCES[#RESOURCES + 1] = {
      source = "src/nupp/runtime/seam/" .. name .. ".nupp",
      output = "nupp/compiler/nupp/runtime/seam/" .. name .. ".nupp",
   }
end
for _, relative in ipairs(TEMPLATE_FILES) do
   RESOURCES[#RESOURCES + 1] = {
      source = "templates/" .. relative,
      output = "nupp/compiler/templates/" .. relative,
   }
end

return {
   include = { "src" },

   -- What `nupp doc` renders with. Both are installed into `.rocks`, a tree
   -- this checkout owns, so two checkouts can want different versions without
   -- either able to break the other's build by upgrading something. `bin/nupp`
   -- and `tests/run` put that tree on the search path, and a build puts it
   -- there for itself, so nothing here is installed globally.
   dependencies = {
      jsonNative = {
         kind = "c",
         cc = os.getenv("NUPP_JSON_CC") or "c++",
         sources = { "runtime/json/json.cpp" },
         headers = { "runtime/json/json.h", "runtime/json/serde.inc" },
         includeDirs = JSON_EXPLICIT_ROOTS and {
            JSON_SIMDJSON_ROOT .. "/include",
            JSON_LUAJIT_ROOT,
         } or nil,
         cflags = JSON_CFLAGS,
         ldflags = JSON_EXPLICIT_ROOTS and {
            JSON_SIMDJSON_ROOT .. "/lib/simdjson.lib",
            JSON_LUAJIT_ROOT .. "/lua51.lib",
         } or nil,
         -- One shell-compatible string keeps the stage-zero compiler able to build
         -- this dependency; the self-hosted builder splits it into the same two
         -- package names before invoking pkg-config without a shell.
         pkgConfig = not JSON_EXPLICIT_ROOTS and "simdjson luajit" or nil,
      },
      -- Renders the markdown. Pulls in lpeg, cosmo, alt-getopt and luautf8,
      -- which LuaRocks resolves rather than this file listing them.
      --
      -- `bundle` is what a binary carries. The official `re.lua` frontend is Lua
      -- payload; LPeg itself and the utf8 the entity table needs are native host
      -- features selected from the bundled sources. Named rather than swept,
      -- because the tree also holds a command-line program and its tests, which
      -- nothing here ever asks for.
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
            dependencies = { "jsonNative" },
            resources = RESOURCES,
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
            resources = RESOURCES,
            stub = "nupp",
            output = "build/dist/nupp",
         },
         docs = {
            kind = "docs",
            dependencies = { "lunamark", "scintillua", "jsonNative" },
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
            -- Every diagnostic code, generated from what `nupp explain` knows and
            -- appended to the handwritten page that says what a diagnostic is.
            -- Listing them here instead would be a copy of the compiler's own
            -- table, stale the first time a code is added.
            diagnostics = {
               path = "reference/diagnostics",
               title = "Diagnostics",
               source = "docs/reference/diagnostics.md",
               redirects = { "reference/diagnostic-index" },
            },
            -- The LuaJIT surface on one page, read from the declarations the
            -- checker itself loads. The prelude is public API written in a
            -- private tree, so without this the one library every program uses
            -- is the one the site never shows. It sits in the API reference
            -- beside `nupp`, because a reader looking a name up does not know
            -- which of the two libraries declared it until they have found it.
            stdlib = {
               path = "modules/luajit",
               title = "LuaJIT standard library",
            },
            -- The site is the docs tree: a page is published by being written
            -- to `docs/`, at the route its path gives, under the title its
            -- heading gives. What a path cannot say, a page says in its own
            -- front matter -- `order` places it, `title` renames it in
            -- navigation, `redirects` carries the routes it used to answer at
            -- -- so nothing here repeats a directory listing back at itself.
            --
            -- The style guide is written for whoever writes the docs rather
            -- than for whoever reads them, so it is the one file in the tree
            -- the site does not publish.
            pages = {
               { glob = "docs/**.md", exclude = { "docs/style.md" } },
               -- A directory rather than a glob: an enhancement proposal is
               -- published by being written, and its index -- the numbers, the
               -- titles, and the statuses -- is generated from the proposals
               -- rather than kept beside them.
               {
                  path = "reference/neps",
                  title = "NEPs",
                  directory = "docs/neps",
               },
               -- What deriving adds to a declaration reads as one page
               -- whether a reader arrives from the reference or from the
               -- module route, so the reference page is also the overview
               -- above `nupp.derive`'s generated field list. Every other
               -- standard module says what it has to say in its own blurb.
               {
                  path = "modules/nupp/derive",
                  title = "nupp.derive",
                  source = "docs/reference/derives.md",
               },
               -- `nupp.io.path` answered at a handwritten route before it was
               -- filed under the module, and that address is not this site's
               -- to stop answering. A module page has no file of its own to
               -- carry the redirect in front matter.
               {
                  path = "modules/nupp/io/path",
                  title = "nupp.io.path",
                  redirects = { "concepts/paths-and-uris" },
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
      ["annotated-lua-corpus"] = {
         description = "Fetch the pinned LuaLS corpus and exercise annotation ingestion",
         build = "compiler",
         argv = { "sh", "scripts/annotated-lua-corpus.sh" },
         env = { LUA_PATH = "build/?.lua;;" },
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
