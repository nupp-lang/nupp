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
   {source = "src/nupp/owners/set.nupp", output = "nupp/compiler/nupp/owners/set.nupp"},
   {source = "src/nupp/io/file.nupp", output = "nupp/compiler/nupp/io/file.nupp"},
   {source = "src/nupp/owners/store.nupp", output = "nupp/compiler/nupp/owners/store.nupp"},
   {source = "src/nupp/derive.nupp", output = "nupp/compiler/nupp/derive.nupp"},
   {source = "src/nupp/profile/zone.nupp", output = "nupp/compiler/nupp/profile/zone.nupp"},
   {source = "src/nupp/profile/trace.nupp", output = "nupp/compiler/nupp/profile/trace.nupp"},
   {source = "src/nupp/profile.nupp", output = "nupp/compiler/nupp/profile.nupp"},
   {source = "src/nupp/mem/indexed.nupp", output = "nupp/compiler/nupp/mem/indexed.nupp"},
   {source = "src/nupp/mem/span.nupp", output = "nupp/compiler/nupp/mem/span.nupp"},
   {source = "src/nupp/simd.nupp", output = "nupp/compiler/nupp/simd.nupp"},
   {source = "src/nupp/data/valuebuilder.g.nupp", output = "nupp/compiler/nupp/data/valuebuilder.g.nupp"},
   {source = "src/nupp/mem/heap.nupp", output = "nupp/compiler/nupp/mem/heap.nupp"},
   {source = "src/nupp/mem/soa.nupp", output = "nupp/compiler/nupp/mem/soa.nupp"},
   {source = "src/nupp/data/bitset.nupp", output = "nupp/compiler/nupp/data/bitset.nupp"},
   {source = "src/nupp/data/fnv1a64.nupp", output = "nupp/compiler/nupp/data/fnv1a64.nupp"},
   {source = "src/nupp/data/crc32.nupp", output = "nupp/compiler/nupp/data/crc32.nupp"},
   {source = "src/nupp/data/json.nupp", output = "nupp/compiler/nupp/data/json.nupp"},
   {source = "src/nupp/data/utf8.nupp", output = "nupp/compiler/nupp/data/utf8.nupp"},
   {source = "src/nupp/native.nupp", output = "nupp/compiler/nupp/native.nupp"},
   {source = "src/nupp/data/init.nupp", output = "nupp/compiler/nupp/data/init.nupp"},
   {source = "src/nupp/mem/init.nupp", output = "nupp/compiler/nupp/mem/init.nupp"},
   {source = "src/nupp/owners/init.nupp", output = "nupp/compiler/nupp/owners/init.nupp"},
   {source = "src/nupp/data/sha256.nupp", output = "nupp/compiler/nupp/data/sha256.nupp"},
   {source = "src/nupp/data/uuid4.nupp", output = "nupp/compiler/nupp/data/uuid4.nupp"},
   {source = "src/nupp/data/uuid7.nupp", output = "nupp/compiler/nupp/data/uuid7.nupp"},
   {source = "src/nupp/log.nupp", output = "nupp/compiler/nupp/log.nupp"},
   {source = "src/nupp/suspension.nupp", output = "nupp/compiler/nupp/suspension.nupp"},
   {source = "src/nupp/io/process.nupp", output = "nupp/compiler/nupp/io/process.nupp"},
   {source = "src/nupp/workers.nupp", output = "nupp/compiler/nupp/workers.nupp"},
   {source = "src/nupp/io/http.nupp", output = "nupp/compiler/nupp/io/http.nupp"},
   {source = "src/nupp/io/processnative.d.nupp", output = "nupp/compiler/nupp/io/processnative.d.nupp"},
   {source = "src/nupp/workers/native.d.nupp", output = "nupp/compiler/nupp/workers/native.d.nupp"},
   {source = "src/nupp/io/httpnative.d.nupp", output = "nupp/compiler/nupp/io/httpnative.d.nupp"},
   {source = "src/nupp/data/jsonnative.d.nupp", output = "nupp/compiler/nupp/data/jsonnative.d.nupp"},
}
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
         headers = { "runtime/json/json.h" },
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
                     .. "workers, and self-contained builds without hiding the Lua underneath.",
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
                        title = "Strict typing for LuaJIT",
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
                        title = "Gradual typing for existing code",
                        details = "Every valid LuaJIT program is already valid Nupp. Add type "
                           .. "syntax under gradual checks, then rename a file when it is ready "
                           .. "for a strict boundary—without changing how other modules load it.",
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
                        title = "Comptime types",
                        details = "A comptime function can inspect and construct types with "
                           .. "normal branches, loops, and recursion. Its result participates in "
                           .. "inference and narrowing, then the whole function erases.",
                        code = [[local comptime function Optional(T: type): type
    return nupp.types.optional(T)
end

local value: Optional(string) = nil
value = "ready"]],
                     },
                     {
                        title = "Borrow checker and ownership",
                        details = "Ownership, borrowing, pinning, and deterministic cleanup make "
                           .. "the important rules at a C boundary explicit—and make leaks and "
                           .. "use-after-move errors reportable.",
                        code = [[local files = require("nupp.io.file")

do
    local file = files.open("report.txt", "r")
    local contents = file:read("*a")
    send(borrows contents)
end -- the file is closed on every structured exit]],
                     },
                     {
                        title = "C and FFI in the type systems",
                        details = "Import a header or write declarations with the real ABI, then "
                           .. "state what each call borrows, consumes, and returns. Nupp checks "
                           .. "the contract while LuaJIT FFI still makes the call.",
                        code = [[cdef struct nativeBuffer
    size: uint64
end

cdef function buffer_free(takes buffer: nativeBuffer*)

cdef function buffer_create_c(size: uint64): nativeBuffer*

local function buffer_create(size: uint64): Owned<nativeBuffer*, buffer_free>
    return buffer_create_c(size)
end

cdef function buffer_read(
    borrows buffer: nativeBuffer*,
    exclusive output: uint8*,
    size: uint64
): int32]],
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
                        title = "Derive checked behavior from declarations",
                        details = "Bundled and project-defined comptime providers can add Debug, "
                           .. "Default, JSON, or a project contract. Generated members use "
                           .. "normal lookup, inference, interfaces, and editor navigation.",
                        code = [[@derive(nupp.derive.Debug, nupp.derive.JSON)
local record User
    id: integer
    name: string
end

local user = new User(id = 42, name = "Ada")
print(user:debug(), user:toJSON())]],
                     },
                     {
                        title = "Async that works like blocking code",
                        details = "HTTP requests look like ordinary blocking calls. Without a "
                           .. "handler they block; under a host scheduler, each parks its "
                           .. "coroutine. The checker tracks suspension separately from the "
                           .. "return type. "
                           .. "[Follow the call from function to scheduler]"
                           .. "(concepts/suspension/index.html).",
                        code = [[local http = require("nupp.io.http")
local suspension = require("nupp.suspension")
local client = assert(http.newClient())

local function fetch(url: string): integer
    local response = assert(client:send(new http.Request(
        url = assert(nupp.io.URI.new(url))
    )))
    local status = response.status
    response:close()
    return status
end

local statuses = suspension.all({function(): integer
    return fetch("https://example.com/")
end, function(): integer
    return fetch("https://example.org/")
end,})

client:close()
print(statuses[1], statuses[2])]],
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
                        title = "Turn raw pointers into checked spans",
                        details = "Counted C pointers become sealed spans that retain their root, "
                           .. "check every index and slice, and keep writable access affine. The "
                           .. "adapter verifies equal lengths before calling C exactly once.",
                        code = [[cdef function transform(
    borrows output: int32* countedBy(count),
    borrows input: const int32* countedBy(count),
    count: uint64
)

local spans = require("nupp.mem.span")
local input = ffi.new<int32[256]>()
local output = ffi.new<int32[256]>()
local readable = spans.fromCarray(input, 256)
local writable = spans.writeCarray(output, 256)

transform(writable, readable)
drop writable

local result = spans.fromCarray(output, 256)
print(result[1])]],
                     },
                     {
                        title = "Ship only what the program uses",
                        details = "Resolved library uses select exactly the required native "
                           .. "providers, then Nupp stamps them with the program into a "
                           .. "self-contained LuaJIT host. Content-addressed inputs make the "
                           .. "result reproducible byte for byte.",
                        code = [[nupp build --target dist
nupp fixpoint --binary]],
                        codeLanguage = "text",
                     },
                     {
                        title = "Flatten structured calls without allocations",
                        details = "Nupp leaves hot loops to LuaJIT's tracer and uses types where "
                           .. "the tracer cannot: plucked arguments share stable table paths and "
                           .. "become flat positional arguments without tables, varargs, or "
                           .. "closures.",
                        code = [[local record Vec2
    x: number
    y: number
end

update(
    (x, y) = entity.body.position,
    (vx, vy) = entity.body.velocity,
    delta = delta
)
-- entity.body is read once; update receives x, y, vx, vy, delta.]],
                     },
                     {
                        title = "Erase instrumentation from hot paths",
                        details = "Logging filters and profiling zones are compiler intrinsics. "
                           .. "A disabled severity evaluates none of its arguments, while zone "
                           .. "push and pop inline—leaving no Lua call for a hot path to pay for.",
                        code = [[nupp.log.debug("spawn at %d,%d", x, y) -- unevaluated when filtered

local zone = require("nupp.profile.zone")
zone.push("physics")
stepWorld()
zone.pop() -- inlined against the zone stack, not called]],
                     },
                     {
                        title = "Build constants before startup",
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
                        title = "A standard library for real programs",
                        details = "Make HTTP requests, run child processes, encode JSON, work with "
                           .. "hashes and identifiers, and compile typed PEG parsers without "
                           .. "assembling a third-party stack.",
                        code = [[nupp.io.http      HTTP client, TLS, streaming bodies
nupp.io.process   processes, pipes, timeouts
nupp.data.json    JSON encoding and decoding
nupp.data         hashes, checksums, UUIDs, UTF-8
nupp.peg          typed parsing-expression grammars]],
                        codeLanguage = "text",
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
                  source = "docs/getting-started/installation.md",
               },
               {
                  path = "getting-started/tour",
                  title = "Tour of Nupp",
                  source = "docs/getting-started/tour.md",
               },
               {
                  path = "getting-started/why",
                  title = "Reasons to use Nupp",
                  source = "docs/getting-started/why.md",
               },
               {
                  path = "concepts/strictness",
                  title = "Gradual typing",
                  source = "docs/concepts/strictness.md",
               },
               {
                  path = "concepts/syntax",
                  title = "Nupp syntax",
                  source = "docs/concepts/syntax.md",
               },
               {
                  path = "concepts/calls",
                  title = "Named and plucked arguments",
                  source = "docs/concepts/calls.md",
               },
               {
                  path = "concepts/switch-expressions",
                  title = "Switch expressions",
                  source = "docs/concepts/switch-expressions.md",
               },
               {
                  path = "concepts/declarations",
                  title = "Declarations and modules",
                  source = "docs/concepts/declarations.md",
               },
               {
                  path = "concepts/ownership",
                  title = "Ownership",
                  source = "docs/concepts/ownership.md",
               },
               {
                  path = "concepts/exact-affine-scopes",
                  title = "Exact affine scopes",
                  source = "docs/concepts/exact-affine-scopes.md",
               },
               {
                  path = "concepts/suspension",
                  title = "Suspension",
                  source = "docs/concepts/suspension.md",
                  redirects = { "concepts/suspension-handlers" },
               },
               {
                  path = "concepts/workers",
                  title = "Workers",
                  source = "docs/concepts/workers.md",
               },
               {
                  path = "concepts/effects",
                  title = "Effect contracts",
                  source = "docs/concepts/effects.md",
               },
               {
                  path = "concepts/c-interop",
                  title = "C interop",
                  source = "docs/concepts/c-interop.md",
               },
               {
                  path = "concepts/structure-of-arrays",
                  title = "Structure-of-arrays storage",
                  source = "docs/concepts/structure-of-arrays.md",
               },
               {
                  path = "concepts/standard-library",
                  title = "Standard library",
                  source = "docs/concepts/standard-library.md",
               },
               {
                  path = "concepts/paths-and-uris",
                  title = "Paths and URIs",
                  source = "docs/concepts/paths-and-uris.md",
               },
               {
                  path = "concepts/metamethods",
                  title = "Metamethods",
                  source = "docs/concepts/metamethods.md",
               },
               {
                  path = "concepts/comptime",
                  title = "Comptime",
                  source = "docs/concepts/comptime.md",
               },
               {
                  path = "concepts/reflection",
                  title = "Reflection",
                  source = "docs/concepts/reflection.md",
               },
               {
                  path = "getting-started/tooling",
                  title = "Tooling",
                  source = "docs/getting-started/tooling.md",
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
                  path = "type-system/affine-types",
                  title = "Affine types",
                  source = "docs/type-system/affine-types.md",
               },
               {
                  path = "type-system/ownership",
                  title = "Ownership and borrowing",
                  source = "docs/type-system/ownership.md",
                  redirects = { "reference/ownership" },
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
                  title = "Comptime types",
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
                  source = "docs/modules/nupp/io/files.md",
               },
               {
                  path = "modules/nupp/data",
                  title = "nupp.data",
                  source = "docs/modules/nupp/data.md",
               },
               {
                  path = "modules/nupp/data/json",
                  title = "nupp.data.json",
                  source = "docs/modules/nupp/data/json.md",
               },
               {
                  path = "modules/nupp/data/utf8",
                  title = "nupp.data.utf8",
                  source = "docs/modules/nupp/data/utf8.md",
               },
               {
                  path = "modules/nupp/data/bitset",
                  title = "nupp.data.bitset",
                  source = "docs/modules/nupp/data/bitset.md",
               },
               {
                  path = "modules/nupp/derive",
                  title = "nupp.derive",
                  source = "docs/reference/derives.md",
               },
               {
                  path = "modules/nupp/io",
                  title = "nupp.io",
                  source = "docs/modules/nupp/io.md",
               },
               {
                  path = "modules/nupp/log",
                  title = "nupp.log",
                  source = "docs/modules/nupp/log.md",
               },
               {
                  path = "modules/nupp/math",
                  title = "nupp.math",
                  source = "docs/modules/nupp/math.md",
               },
               {
                  path = "modules/nupp/mem/span",
                  title = "nupp.mem.span",
                  source = "docs/modules/nupp/mem/span.md",
               },
               {
                  path = "modules/nupp/peg",
                  title = "nupp.peg",
                  source = "docs/modules/nupp/peg.md",
               },
               {
                  path = "guides/build",
                  title = "Build system",
                  source = "docs/guides/build.md",
               },
               {
                  path = "guides/embedding",
                  title = "Embedding Nupp",
                  source = "docs/guides/embedding.md",
               },
               {
                  path = "guides/luarocks",
                  title = "Working with LuaRocks",
                  source = "docs/guides/luarocks.md",
               },
               {
                  path = "guides/fmt",
                  title = "Formatter",
                  source = "docs/guides/fmt.md",
               },
               {
                  path = "guides/doc",
                  title = "Documentation generator",
                  source = "docs/guides/doc.md",
               },
               {
                  path = "guides/lsp",
                  title = "Language server",
                  source = "docs/guides/lsp.md",
               },
               {
                  path = "guides/editors",
                  title = "Editors",
                  source = "docs/guides/editors.md",
               },
               {
                  path = "guides/testing",
                  title = "Testing",
                  source = "docs/guides/testing.md",
               },
               {
                  path = "guides/tasks",
                  title = "Tasks",
                  source = "docs/guides/tasks.md",
               },
               {
                  path = "guides/profiling",
                  title = "Profiling",
                  source = "docs/guides/profiling.md",
               },
               {
                  path = "guides/jit-trace-checking",
                  title = "LuaJIT trace checking",
                  source = "docs/guides/jit-trace-checking.md",
               },
               {
                  path = "guides/hot-reload",
                  title = "Hot reload",
                  source = "docs/guides/hot-reload.md",
               },
               {
                  path = "guides/ahead-of-time",
                  title = "Ahead-of-time compilation",
                  source = "docs/guides/ahead-of-time.md",
               },
               {
                  path = "guides/performance",
                  title = "Performance",
                  source = "docs/guides/performance.md",
               },

               {
                  path = "reference/cli",
                  title = "nupp command",
                  source = "docs/reference/cli.md",
               },
               {
                  path = "reference/grammar",
                  title = "Grammar",
                  source = "docs/reference/grammar.md",
               },
               {
                  path = "reference/annotations",
                  title = "Annotations",
                  source = "docs/reference/annotations.md",
               },
               {
                  path = "reference/derives",
                  title = "Declaration derives",
                  source = "docs/reference/derives.md",
               },
               {
                  path = "reference/lints",
                  title = "Lints",
                  source = "docs/reference/lints.md",
               },
               {
                  path = "reference/diagnostics",
                  title = "Diagnostics",
                  source = "docs/reference/diagnostics.md",
               },
               {
                  path = "reference/distribution",
                  title = "Distribution",
                  source = "docs/reference/distribution.md",
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
