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
    "lexer",
    "awk",
    "bash",
    "batch",
    "c",
    "clojure",
    "cmake",
    "coffeescript",
    "cpp",
    "csharp",
    "css",
    "diff",
    "dockerfile",
    "elixir",
    "erlang",
    "fish",
    "go",
    "haskell",
    "html",
    "ini",
    "java",
    "javascript",
    "json",
    "julia",
    "latex",
    "lua",
    "makefile",
    "markdown",
    "nim",
    "perl",
    "php",
    "powershell",
    "python",
    "r",
    "ruby",
    "rust",
    "scala",
    "sql",
    "swift",
    "text",
    "toml",
    "typescript",
    "xml",
    "yaml",
    "zig",
}

local bundledLexers = {}
for _, name in ipairs(LEXERS) do
    bundledLexers[#bundledLexers + 1] = "scintillua/lexers/" .. name .. ".lua"
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
    "app/tests/greetingtest.nupp",
    "browser/.gitignore",
    "browser/README.md",
    "browser/nupp.lua",
    "browser/scripts/package.sh",
    "browser/scripts/serve.mjs",
    "browser/src/main.nupp",
    "browser/template.lua",
    "browser/tests/build.test.mjs",
    "browser/web/app.mjs",
    "browser/web/index.html",
    "browser-simd/.gitignore",
    "browser-simd/README.md",
    "browser-simd/nupp.lua",
    "browser-simd/scripts/package.sh",
    "browser-simd/scripts/serve.mjs",
    "browser-simd/src/backend.nupp",
    "browser-simd/src/scalar.nupp",
    "browser-simd/src/simd.nupp",
    "browser-simd/template.lua",
    "browser-simd/tests/build.test.mjs",
    "browser-simd/web/app.mjs",
    "browser-simd/web/index.html",
    "love/.gitignore",
    "love/README.md",
    "love/nupp.lua",
    "love/src/game.nupp",
    "love/src/main.nupp",
    "love/template.lua",
    "love/tests/gametest.nupp",
    "lib/${name}-dev-1.rockspec",
    "lib/nupp.lua",
    "lib/nupp/${moduleName}.d.nupp",
    "lib/src/${moduleName}.nupp",
    "lib/template.lua",
    "lib/tests/greettest.nupp",
}

-- What the compiler carries, which both the module build and the stamped binary
-- want in full. One list because they have never differed and a second copy is
-- how they would start to.
local RESOURCES = {
    "src/nupp/compiler/decls/*.d.nupp",
    "src/nupp/compiler/decls/jit/*.d.nupp",
    {source = "src/nupp/test.g.nupp", output = "nupp/compiler/nupp/test.g.nupp"},
    {source = "tests/run.lua", output = "nupp/compiler/nupp/test/runner.lua"},
    {source = "src/nupp/compiler/build/stub-catalog.json", output = "nupp/compiler/build/stub-catalog.json",},
    {source = "src/nupp/derive.nupp", output = "nupp/compiler/nupp/derive.nupp"},
    {source = "src/nupp/services.nupp", output = "nupp/compiler/nupp/services.nupp"},
    {source = "src/nupp/profile/zone.nupp", output = "nupp/compiler/nupp/profile/zone.nupp"},
    {source = "src/nupp/profile/trace.nupp", output = "nupp/compiler/nupp/profile/trace.nupp"},
    {source = "src/nupp/profile/init.nupp", output = "nupp/compiler/nupp/profile/init.nupp"},
    {source = "src/nupp/mem/indexed.nupp", output = "nupp/compiler/nupp/mem/indexed.nupp"},
    {source = "src/nupp/mem/span.nupp", output = "nupp/compiler/nupp/mem/span.nupp"},
    {source = "src/nupp/gpu.nupp", output = "nupp/compiler/nupp/gpu.nupp"},
    {source = "src/nupp/gpulayout.nupp", output = "nupp/compiler/nupp/gpulayout.nupp"},
    {source = "src/nupp/random.nupp", output = "nupp/compiler/nupp/random.nupp"},
    {source = "src/nupp/simd.nupp", output = "nupp/compiler/nupp/simd.nupp"},
    {source = "src/nupp/data/valuebuilder.nupp", output = "nupp/compiler/nupp/data/valuebuilder.nupp"},
    {source = "src/nupp/mem/heap.nupp", output = "nupp/compiler/nupp/mem/heap.nupp"},
    {source = "src/nupp/mem/sharedbytes.nupp", output = "nupp/compiler/nupp/mem/sharedbytes.nupp"},
    {source = "src/nupp/mem/soa.nupp", output = "nupp/compiler/nupp/mem/soa.nupp"},
    {source = "src/nupp/data/json.nupp", output = "nupp/compiler/nupp/data/json.nupp"},
    {source = "src/nupp/data/jsondecode.nupp", output = "nupp/compiler/nupp/data/jsondecode.nupp"},
    {source = "src/nupp/data/jsondecoder/fused.nupp", output = "nupp/compiler/nupp/data/jsondecoder/fused.nupp",},
    {source = "src/nupp/data/jsondecoder/eager.nupp", output = "nupp/compiler/nupp/data/jsondecoder/eager.nupp",},
    {source = "src/nupp/data/jsondecoder/serde.nupp", output = "nupp/compiler/nupp/data/jsondecoder/serde.nupp",},
    {source = "src/nupp/data/json/provider.nupp", output = "nupp/compiler/nupp/data/json/provider.nupp",},
    {source = "src/nupp/data/json/aot.nupp", output = "nupp/compiler/nupp/data/json/aot.nupp",},
    {source = "src/nupp/data/serde.nupp", output = "nupp/compiler/nupp/data/serde.nupp"},
    {source = "src/nupp/data/hmac.nupp", output = "nupp/compiler/nupp/data/hmac.nupp"},
    {source = "src/nupp/runtime/backend.nupp", output = "nupp/compiler/nupp/runtime/backend.nupp",},
    {source = "src/nupp/runtime/backend/browser.nupp", output = "nupp/compiler/nupp/runtime/backend/browser.nupp",},
    {source = "src/nupp/runtime/backend/portable.nupp", output = "nupp/compiler/nupp/runtime/backend/portable.nupp",},
    {source = "src/nupp/runtime/backend/wasm.nupp", output = "nupp/compiler/nupp/runtime/backend/wasm.nupp",},
    {
        source = "src/nupp/runtime/provider/tablestruct.nupp",
        output = "nupp/compiler/nupp/runtime/provider/tablestruct.nupp",
    },
    {
        source = "src/nupp/runtime/provider/scalarsimd.nupp",
        output = "nupp/compiler/nupp/runtime/provider/scalarsimd.nupp",
    },
    {
        source = "src/nupp/runtime/provider/wasmstoragefactory.nupp",
        output = "nupp/compiler/nupp/runtime/provider/wasmstoragefactory.nupp",
    },
    {
        source = "src/nupp/runtime/provider/wasmstorage.nupp",
        output = "nupp/compiler/nupp/runtime/provider/wasmstorage.nupp",
    },
    {source = "src/nupp/wasm.nupp", output = "nupp/compiler/nupp/wasm.nupp"},
    {source = "src/nupp/runtime/seam/base64.nupp", output = "nupp/compiler/nupp/runtime/seam/base64.nupp",},
    {source = "src/nupp/runtime/seam/base64suite.nupp", output = "nupp/compiler/nupp/runtime/seam/base64suite.nupp",},
    {source = "src/nupp/runtime/seam/json.nupp", output = "nupp/compiler/nupp/runtime/seam/json.nupp",},
    {source = "src/nupp/runtime/seam/jsonsuite.nupp", output = "nupp/compiler/nupp/runtime/seam/jsonsuite.nupp",},
    {source = "src/nupp/runtime/seam/bitops.nupp", output = "nupp/compiler/nupp/runtime/seam/bitops.nupp",},
    {source = "src/nupp/runtime/seam/bitopssuite.nupp", output = "nupp/compiler/nupp/runtime/seam/bitopssuite.nupp",},
    {source = "src/nupp/data/utf8.nupp", output = "nupp/compiler/nupp/data/utf8.nupp"},
    {source = "src/nupp/data/base64.nupp", output = "nupp/compiler/nupp/data/base64.nupp"},
    {source = "src/nupp/runtime/nativev2.nupp", output = "nupp/compiler/nupp/runtime/nativev2.nupp"},
    {source = "src/nupp/data/init.nupp", output = "nupp/compiler/nupp/data/init.nupp"},
    {source = "src/nupp/mem/init.nupp", output = "nupp/compiler/nupp/mem/init.nupp"},
    {source = "src/nupp/io/path/init.nupp", output = "nupp/compiler/nupp/io/path/init.nupp"},
    {source = "src/nupp/io/path/provider.nupp", output = "nupp/compiler/nupp/io/path/provider.nupp"},
    {source = "src/nupp/io/pathtext.nupp", output = "nupp/compiler/nupp/io/pathtext.nupp"},
    {source = "src/nupp/io/uri.nupp", output = "nupp/compiler/nupp/io/uri.nupp"},
    {source = "src/nupp/io/files.nupp", output = "nupp/compiler/nupp/io/files.nupp"},
    {source = "src/nupp/io/init.nupp", output = "nupp/compiler/nupp/io/init.nupp"},
    {source = "src/nupp/log.nupp", output = "nupp/compiler/nupp/log.nupp"},
    {source = "src/nupp/suspension.nupp", output = "nupp/compiler/nupp/suspension.nupp"},
    {source = "src/nupp/time.nupp", output = "nupp/compiler/nupp/time.nupp"},
    {source = "src/nupp/io/net.nupp", output = "nupp/compiler/nupp/io/net.nupp"},
    {source = "src/nupp/io/tls.nupp", output = "nupp/compiler/nupp/io/tls.nupp"},
    {source = "src/nupp/io/process.nupp", output = "nupp/compiler/nupp/io/process.nupp"},
    {source = "src/nupp/workers/init.nupp", output = "nupp/compiler/nupp/workers/init.nupp"},
    {source = "src/nupp/tasks.nupp", output = "nupp/compiler/nupp/tasks.nupp"},
    {source = "src/nupp/io/http.nupp", output = "nupp/compiler/nupp/io/http.nupp"},
    {source = "src/nupp/workers/native.d.nupp", output = "nupp/compiler/nupp/workers/native.d.nupp"},
}

-- The compiler carries the GPU runtime as source for programs that select it,
-- but does not execute it itself. Keep an ordinary compiler build independent
-- of WGPU; an application that reaches `nupp.gpu` still selects the provider.
local COMPILER_NATIVE_FEATURES = {gpu = false}
local SEAM_FACTORY_RESOURCES = {
    "registry",
    "module",
    "contracts",
    "bitset",
    "browsercrypto",
    "browserstorage",
    "files",
    "hash",
    "hmacsha256",
    "http",
    "int64",
    "iobytes",
    "net",
    "path",
    "peg",
    "process",
    "sha256",
    "simd",
    "tls",
    "structvalue",
    "suspension",
    "textbuffer",
    "time",
    "uri",
    "utf8",
    "uuid",
    "gpu",
    "wasm",
    "workers",
}
for _, name in ipairs(SEAM_FACTORY_RESOURCES) do
    RESOURCES[
        #RESOURCES + 1
    ] = {
        source = "src/nupp/runtime/seam/" .. name .. ".nupp",
        output = "nupp/compiler/nupp/runtime/seam/" .. name .. ".nupp",
    }
end
local SEAM_SUITE_RESOURCES = {
    "bitset",
    "browsercrypto",
    "browserstorage",
    "files",
    "hash",
    "hmacsha256",
    "http",
    "int64",
    "iobytes",
    "net",
    "path",
    "peg",
    "process",
    "sha256",
    "simd",
    "structvalue",
    "textbuffer",
    "gpu",
    "tls",
    "suspension",
    "time",
    "uri",
    "utf8",
    "uuid",
    "wasm",
    "workers",
}
for _, name in ipairs(SEAM_SUITE_RESOURCES) do
    RESOURCES[
        #RESOURCES + 1
    ] = {
        source = "src/nupp/runtime/seam/" .. name .. "suite.nupp",
        output = "nupp/compiler/nupp/runtime/seam/" .. name .. "suite.nupp",
    }
end
for _, resource in ipairs({
    "src/nupp/compiler/runtime/extensions.nupp",
    "src/nupp/compiler/runtime/math.nupp",
    "src/nupp/compiler/runtime/reflect.nupp",
    "src/nupp/data/digest.nupp",
    "src/nupp/runtime/browser/effects.g.nupp",
    "src/nupp/runtime/browser/response.g.nupp",
    "src/nupp/runtime/browser/workercodec.g.nupp",
    "src/nupp/browser/gpu.g.nupp",
    "src/nupp/runtime/provider/browsercrypto.g.nupp",
    "src/nupp/runtime/provider/browserhttp.g.nupp",
    "src/nupp/runtime/provider/browserpath.nupp",
    "src/nupp/runtime/provider/browserstorage.g.nupp",
    "src/nupp/runtime/provider/browserwebgpu.nupp",
    "src/nupp/runtime/provider/browsersuspension.g.nupp",
    "src/nupp/runtime/provider/browsertime.g.nupp",
    "src/nupp/runtime/provider/browseruri.g.nupp",
    "src/nupp/runtime/provider/browserworkers.g.nupp",
    "src/nupp/runtime/provider/lunajson.nupp",
    "src/nupp/runtime/provider/nativegpu.nupp",
    "src/nupp/runtime/provider/scalarbitops.nupp",
    "src/nupp/runtime/provider/tablebuffer.nupp",
    "src/nupp/runtime/vendor/lunajson/decoder.lua",
    "src/nupp/runtime/vendor/lunajson/encoder.lua",
}) do
    RESOURCES[#RESOURCES + 1] = {source = resource, output = resource:gsub("^src/", "nupp/compiler/"),}
end
local PLAYGROUND_COMPILER_RESOURCES = {}
for index, resource in ipairs(RESOURCES) do
    PLAYGROUND_COMPILER_RESOURCES[index] = resource
end
-- Generated rather than committed. The image is derived from the compiler's own
-- declaration checker, so a checked-in copy is stale the moment the checker
-- moves, and nothing in the ordinary loop compares them -- only a separate job
-- that builds Lua 5.1.5 to ask. `scripts/prelude-image` makes it and then makes
-- this bundle; the bundle below is what it makes it with.
PLAYGROUND_COMPILER_RESOURCES[
    #PLAYGROUND_COMPILER_RESOURCES + 1
] = {source = "build/playground/preludeimage.bin", output = "nupp/compiler/preludeimage.bin",}
for _, relative in ipairs(TEMPLATE_FILES) do
    RESOURCES[#RESOURCES + 1] = {source = "templates/" .. relative, output = "nupp/compiler/templates/" .. relative,}
end

return {
    include = {"src", "tests/runner", "evals/lib"},

    -- What `nupp doc` renders with. Both are installed into `.rocks`, a tree
    -- this checkout owns, so two checkouts can want different versions without
    -- either able to break the other's build by upgrading something. `bin/nupp`
    -- and `tests/run` put that tree on the search path, and a build puts it
    -- there for itself, so nothing here is installed globally.
    dependencies = {
        -- Lunamark's rockspec names an obsolete native UTF-8 module. Its actual
        -- retained dependencies are pinned here, and Nupp supplies the two UTF-8
        -- operations Lunamark needs while constructing its parser.
        lunamark_lpeg = {kind = "luarocks", rock = "lpeg", version = "1.1.0-2",},
        lunamark_cosmo = {kind = "luarocks", rock = "cosmo", version = "16.06.04-1",},
        lunamark_getopt = {kind = "luarocks", rock = "alt-getopt", version = "0.8.0-2",},
        -- Renders the markdown. The retained rocks it needs are listed above so
        -- their dependency boundary is Nupp's rather than upstream's.
        --
        -- `bundle` is what a binary carries. The official `re.lua` frontend is Lua
        -- payload; LPeg itself is a native host feature selected from the bundled
        -- sources. Named rather than swept,
        -- because the tree also holds a command-line program and its tests, which
        -- nothing here ever asks for.
        lunamark = {
            kind = "luarocks",
            version = "0.6.0-1",
            rockDependencies = false,
            bundle = {"lunamark.lua", "lunamark/**.lua", "cosmo.lua", "cosmo/**.lua", "re.lua",},
        },
        -- Syntax highlighting for fenced code in the generated site. Not
        -- published on LuaRocks, so the rockspec beside it stands in for the one
        -- upstream does not ship.
        scintillua = {kind = "luarocks", rockspec = "rocks/scintillua-6.7-1.rockspec", bundle = bundledLexers,},
    },

    build = {
        outDir = "build",
        default = "compiler",
        targets = {
            compiler = {
                kind = "modules",
                description = "Build the self-hosted compiler",
                optimize = 2,
                entries = {"nupp.compiler.main"},
                backends = {"nupp.runtime.backend.lunajson"},
                nativeFeatures = COMPILER_NATIVE_FEATURES,
                resources = RESOURCES,
            },
            testRunner = {
                kind = "binary",
                description = "Build the worker-hosted test runner",
                outDir = "build/test-runner",
                entries = {"main"},
                sources = {"tests/runner/main.g.nupp", "tests/runner/job.g.nupp"},
                backends = {"nupp.runtime.backend.lunajson"},
                nativeFeatures = {workers = true},
                stub = "nupp",
                output = "build/nupp-test",
            },
            bootstrapCompiler = {
                kind = "modules",
                description = "Build the self-contained stage-zero compiler",
                outDir = "build/bootstrap-compiler",
                entries = {"nupp.compiler.main"},
                backends = {"nupp.runtime.backend.lunajson"},
                nativeFeatures = COMPILER_NATIVE_FEATURES,
                resources = RESOURCES,
            },
            playgroundCompiler = {
                kind = "bundle",
                description = "Build the stock-Lua in-memory compiler",
                outDir = "build/playground",
                output = "build/playground/nupp-compiler.lua",
                dialect = "lua51",
                entries = {"nupp.compiler.browser"},
                sources = {"src/nupp/compiler/browser.nupp"},
                backends = {"nupp.runtime.backend.browser"},
                resources = PLAYGROUND_COMPILER_RESOURCES,
            },
            -- The same bundle without the image, which is what generates one:
            -- `source` mode reads the compiler's declaration checker and never
            -- hydrates an image, so this only has to load. Hydrating is the one
            -- thing it cannot do, and the one thing nothing asks of it.
            playgroundCompilerWithoutPrelude = {
                kind = "bundle",
                description = "Build the portable compiler with no prelude image",
                outDir = "build/playground-bootstrap",
                output = "build/playground-bootstrap/nupp-compiler.lua",
                dialect = "lua51",
                entries = {"nupp.compiler.browser"},
                sources = {"src/nupp/compiler/browser.nupp"},
                backends = {"nupp.runtime.backend.browser"},
                resources = RESOURCES,
            },
            playgroundApplicationRuntime = {
                kind = "bundle",
                description = "Build the checked playground application runtime",
                outDir = "build/playground-app",
                output = "build/playground/nupp-app-runtime.lua",
                dialect = "lua51",
                entries = {"nupp.runtime.browser.playground"},
                sources = {"src/nupp/runtime/browser/playground.g.nupp"},
                backends = {"nupp.runtime.backend.browser"},
            },
            -- Nupp stamped into a feature-matched host as one self-contained
            -- executable. It is the first payload the format ever carries, on
            -- purpose: a packager that cannot package itself has no business
            -- claiming it packages anything.
            dist = {
                kind = "binary",
                description = "Stamp the compiler into a self-contained binary",
                entries = {"nupp.compiler.main"},
                -- Carried, not just installed: a binary is handed to someone who
                -- has no rock tree, and `nupp doc` is one of the commands it
                -- claims to have.
                dependencies = {"lunamark_lpeg", "lunamark_cosmo", "lunamark_getopt", "lunamark", "scintillua",},
                backends = {"nupp.runtime.backend.lunajson"},
                nativeFeatures = COMPILER_NATIVE_FEATURES,
                resources = RESOURCES,
                stub = "nupp",
                output = "build/dist/nupp",
                payloadOutput = "build/dist/nupp.payload.lua",
            },
            docs = {
                kind = "docs",
                dependencies = {"lunamark_lpeg", "lunamark_cosmo", "lunamark_getopt", "lunamark", "scintillua",},
                sources = {"src"},
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
                },
                -- The LuaJIT surface on one page, read from the declarations the
                -- checker itself loads. The prelude is public API written in a
                -- private tree, so without this the one library every program uses
                -- is the one the site never shows. It sits in the API reference
                -- beside `nupp`, because a reader looking a name up does not know
                -- which of the two libraries declared it until they have found it.
                stdlib = {path = "modules/luajit", title = "LuaJIT standard library",},
                -- The site is the docs tree: a page is published by being written
                -- to `docs/`, at the route its path gives, under the title its
                -- heading gives. What a path cannot say, a page says in its own
                -- front matter, so nothing here repeats a directory listing back
                -- at itself.
                --
                -- The style guide is written for whoever writes the docs rather
                -- than for whoever reads them, so it is the one file in the tree
                -- the site does not publish.
                pages = {
                    {glob = "docs/**.md", exclude = {"docs/style.md"}},
                    -- A directory rather than a glob: an enhancement proposal is
                    -- published by being written, and its index -- the numbers, the
                    -- titles, and the statuses -- is generated from the proposals
                    -- rather than kept beside them.
                    {path = "reference/neps", title = "NEPs", directory = "docs/neps",},
                    -- What deriving adds to a declaration reads as one page
                    -- whether a reader arrives from the reference or from the
                    -- module route, so the reference page is also the overview
                    -- above `nupp.derive`'s generated field list. Every other
                    -- standard module says what it has to say in its own blurb.
                    {path = "modules/nupp/derive", title = "nupp.derive", source = "docs/reference/derives.md",},
                    {path = "modules/nupp/io/path", title = "nupp.io.path",},
                },
            },
        },
    },

    test = {build = "testRunner", argv = {"build/nupp-test"}, env = {NUPP_TEST_BUILD = "build"},},

    tasks = {
        [
            "docs-serve"
        ] = {
            description = "Build the docs site and playground, serve both " .. "until stopped",
            argv = {"node", "scripts/docs-serve.mjs"},
        },
        [
            "annotated-lua-corpus"
        ] = {
            description = "Fetch the pinned LuaLS corpus and exercise annotation ingestion",
            build = "compiler",
            argv = {"sh", "scripts/annotated-lua-corpus.sh"},
            env = {LUA_PATH = "build/?.lua;;"},
        },
    },

    selfHost = {
        target = "compiler",
        bootstrapTarget = "bootstrapCompiler",
        bootstrap = "bootstrap/nupp.lua",
        -- The target `nupp fixpoint --binary` stamps twice. Naming it here rather
        -- than in the command keeps the compiler from knowing anything about how
        -- this particular project chose to package itself.
        binary = "dist",
    },
}
