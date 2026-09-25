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
    {source = "src/nupp/spi/init.nupp", output = "nupp/compiler/nupp/spi/init.nupp"},
    {source = "src/nupp/runtime/bitops/spi.nupp", output = "nupp/compiler/nupp/runtime/bitops/spi.nupp"},
    {source = "src/nupp/text/spi.nupp", output = "nupp/compiler/nupp/text/spi.nupp"},
    {source = "src/nupp/random/spi.nupp", output = "nupp/compiler/nupp/random/spi.nupp"},
    {
        source = "src/nupp/runtime/representation/spi.nupp",
        output = "nupp/compiler/nupp/runtime/representation/spi.nupp"
    },
    {source = "src/nupp/codec/json/spi.nupp", output = "nupp/compiler/nupp/codec/json/spi.nupp"},
    {source = "src/nupp/io/path/spi.nupp", output = "nupp/compiler/nupp/io/path/spi.nupp"},
    {source = "src/nupp/time/spi.nupp", output = "nupp/compiler/nupp/time/spi.nupp"},
    {source = "src/nupp/io/uri/spi.nupp", output = "nupp/compiler/nupp/io/uri/spi.nupp"},
    {source = "src/nupp/runtime/uuid/spi.nupp", output = "nupp/compiler/nupp/runtime/uuid/spi.nupp"},
    {source = "src/nupp/runtime/target.nupp", output = "nupp/compiler/nupp/runtime/target.nupp"},
    {source = "src/re.g.nupp", output = "nupp/compiler/re.g.nupp"},
    {source = "src/nupp/text/internal/buffer.d.nupp", output = "nupp/compiler/nupp/text/internal/buffer.d.nupp"},
    {source = "src/nupp/text/init.nupp", output = "nupp/compiler/nupp/text/init.nupp"},
    {source = "src/nupp/cli/init.g.nupp", output = "nupp/compiler/nupp/cli/init.g.nupp"},
    {source = "src/nupp/cli/internal/optparser.nupp", output = "nupp/compiler/nupp/cli/internal/optparser.nupp"},
    {source = "src/nupp/cli/internal/decode.g.nupp", output = "nupp/compiler/nupp/cli/internal/decode.g.nupp"},
    {source = "src/nupp/cli/internal/terminal.nupp", output = "nupp/compiler/nupp/cli/internal/terminal.nupp"},
    {
        source = "src/nupp/cli/internal/application.g.nupp",
        output = "nupp/compiler/nupp/cli/internal/application.g.nupp"
    },
    {source = "src/nupp/runtime/workersprovider.nupp", output = "nupp/compiler/nupp/runtime/workersprovider.nupp"},
    {source = "src/nupp/runtime/wasm.nupp", output = "nupp/compiler/nupp/runtime/wasm.nupp"},
    {source = "src/nupp/runtime/uuid/init.nupp", output = "nupp/compiler/nupp/runtime/uuid/init.nupp"},
    {source = "src/nupp/runtime/browser/memory.g.nupp", output = "nupp/compiler/nupp/runtime/browser/memory.g.nupp"},
    {source = "src/nupp/runtime/timeprovider.nupp", output = "nupp/compiler/nupp/runtime/timeprovider.nupp"},
    {source = "src/nupp/runtime/structvalue.nupp", output = "nupp/compiler/nupp/runtime/structvalue.nupp"},
    {source = "src/nupp/workers/spi.nupp", output = "nupp/compiler/nupp/workers/spi.nupp"},
    {source = "src/nupp/io/tls/spi.nupp", output = "nupp/compiler/nupp/io/tls/spi.nupp"},
    {source = "src/nupp/suspension/spi.nupp", output = "nupp/compiler/nupp/suspension/spi.nupp"},
    {source = "src/nupp/io/process/spi.nupp", output = "nupp/compiler/nupp/io/process/spi.nupp"},
    {source = "src/nupp/io/net/spi.nupp", output = "nupp/compiler/nupp/io/net/spi.nupp"},
    {source = "src/nupp/io/http/spi.nupp", output = "nupp/compiler/nupp/io/http/spi.nupp"},
    {source = "src/nupp/io/files/spi.nupp", output = "nupp/compiler/nupp/io/files/spi.nupp"},
    {source = "src/nupp/io/files/messages.nupp", output = "nupp/compiler/nupp/io/files/messages.nupp"},
    {source = "src/nupp/io/files/path.nupp", output = "nupp/compiler/nupp/io/files/path.nupp"},
    {source = "src/nupp/gpu/spi.nupp", output = "nupp/compiler/nupp/gpu/spi.nupp"},
    {source = "src/nupp/runtime/cancellation.nupp", output = "nupp/compiler/nupp/runtime/cancellation.nupp"},
    {
        source = "src/nupp/runtime/representation/init.nupp",
        output = "nupp/compiler/nupp/runtime/representation/init.nupp"
    },
    {source = "src/nupp/runtime/provider/workers.nupp", output = "nupp/compiler/nupp/runtime/provider/workers.nupp"},
    {
        source = "src/nupp/runtime/provider/suspension.nupp",
        output = "nupp/compiler/nupp/runtime/provider/suspension.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativeuuid.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativeuuid.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativeuri.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativeuri.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativetls.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativetls.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativetime.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativetime.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativestorage.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativestorage.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativeprocess.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativeprocess.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativepath.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativepath.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativenet.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativenet.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativehttp.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativehttp.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativefiles.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativefiles.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativegpurelease.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativegpurelease.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativegpu.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativegpu.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativebuffer.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativebuffer.nupp"
    },
    {source = "src/nupp/runtime/int64.nupp", output = "nupp/compiler/nupp/runtime/int64.nupp"},
    {source = "src/nupp/runtime/bitops/init.nupp", output = "nupp/compiler/nupp/runtime/bitops/init.nupp"},
    {source = "src/nupp/gpu/api.nupp", output = "nupp/compiler/nupp/gpu/api.nupp"},
    {source = "src/nupp/gpu/types.nupp", output = "nupp/compiler/nupp/gpu/types.nupp"},
    {source = "src/nupp/gpu/operations.nupp", output = "nupp/compiler/nupp/gpu/operations.nupp"},
    "src/nupp/compiler/decls/*.d.nupp",
    "src/nupp/compiler/decls/jit/*.d.nupp",
    {source = "src/nupp/test.nupp", output = "nupp/compiler/nupp/test.nupp"},
    {source = "tests/run.lua", output = "nupp/compiler/nupp/test/runner.lua"},
    -- The tools' own files, carried beside the compiler's so that
    -- `nupp.compiler.bundled` is the one place anything carried is read from.
    {source = "src/nupp/tools/build/stub-catalog.json", output = "nupp/compiler/build/stub-catalog.json",},
    {source = "src/nupp/tools/doc/theme.css", output = "nupp/compiler/doc/theme.css"},
    "src/nupp/compiler/aot/include/*.h",
    "src/nupp/compiler/aot/llvm/wasm/*.ll",
    {source = "src/nupp/derive.nupp", output = "nupp/compiler/nupp/derive.nupp"},
    {source = "src/nupp/bench/init.nupp", output = "nupp/compiler/nupp/bench/init.nupp"},
    {source = "src/nupp/profile/zone.nupp", output = "nupp/compiler/nupp/profile/zone.nupp"},
    {source = "src/nupp/profile/trace.nupp", output = "nupp/compiler/nupp/profile/trace.nupp"},
    {source = "src/nupp/profile/init.nupp", output = "nupp/compiler/nupp/profile/init.nupp"},
    {source = "src/nupp/mem/indexed.nupp", output = "nupp/compiler/nupp/mem/indexed.nupp"},
    {source = "src/nupp/mem/span.nupp", output = "nupp/compiler/nupp/mem/span.nupp"},
    {source = "src/nupp/gpu/init.nupp", output = "nupp/compiler/nupp/gpu/init.nupp"},
    {source = "src/nupp/gpu/layout.nupp", output = "nupp/compiler/nupp/gpu/layout.nupp"},
    {source = "src/nupp/random/init.nupp", output = "nupp/compiler/nupp/random/init.nupp"},
    {source = "src/nupp/simd.nupp", output = "nupp/compiler/nupp/simd.nupp"},
    {source = "src/nupp/codec/valuebuilder.nupp", output = "nupp/compiler/nupp/codec/valuebuilder.nupp"},
    {source = "src/nupp/mem/heap.nupp", output = "nupp/compiler/nupp/mem/heap.nupp"},
    {source = "src/nupp/mem/sharedbytes.nupp", output = "nupp/compiler/nupp/mem/sharedbytes.nupp"},
    {source = "src/nupp/mem/soa.nupp", output = "nupp/compiler/nupp/mem/soa.nupp"},
    {source = "src/nupp/codec/json/init.nupp", output = "nupp/compiler/nupp/codec/json/init.nupp"},
    {
        source = "src/nupp/codec/json/internal/decode.nupp",
        output = "nupp/compiler/nupp/codec/json/internal/decode.nupp",
    },
    {
        source = "src/nupp/codec/json/internal/decoder/fused.nupp",
        output = "nupp/compiler/nupp/codec/json/internal/decoder/fused.nupp",
    },
    {
        source = "src/nupp/codec/json/internal/decoder/eager.nupp",
        output = "nupp/compiler/nupp/codec/json/internal/decoder/eager.nupp",
    },
    {
        source = "src/nupp/codec/json/internal/decoder/serde.nupp",
        output = "nupp/compiler/nupp/codec/json/internal/decoder/serde.nupp",
    },
    {source = "src/nupp/codec/json/provider.nupp", output = "nupp/compiler/nupp/codec/json/provider.nupp",},
    {source = "src/nupp/codec/json/aot.nupp", output = "nupp/compiler/nupp/codec/json/aot.nupp",},
    {source = "src/nupp/serde.nupp", output = "nupp/compiler/nupp/serde.nupp"},
    {source = "src/nupp/digest/internal/streaming.nupp", output = "nupp/compiler/nupp/digest/internal/streaming.nupp"},
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
    {source = "src/nupp/mem/array.nupp", output = "nupp/compiler/nupp/mem/array.nupp"},
    {source = "src/nupp/util/internal/pool.nupp", output = "nupp/compiler/nupp/util/internal/pool.nupp"},
    {source = "src/nupp/mem/arena.nupp", output = "nupp/compiler/nupp/mem/arena.nupp"},
    {source = "src/nupp/events.nupp", output = "nupp/compiler/nupp/events.nupp"},
    {source = "src/nupp/text/utf8.nupp", output = "nupp/compiler/nupp/text/utf8.nupp"},
    {source = "src/nupp/codec/base64.nupp", output = "nupp/compiler/nupp/codec/base64.nupp"},
    {source = "src/nupp/runtime/native.nupp", output = "nupp/compiler/nupp/runtime/native.nupp"},
    {source = "src/nupp/digest/init.nupp", output = "nupp/compiler/nupp/digest/init.nupp"},
    {source = "src/nupp/mac/spi.nupp", output = "nupp/compiler/nupp/mac/spi.nupp"},
    {source = "src/nupp/system/spi.nupp", output = "nupp/compiler/nupp/system/spi.nupp"},
    {source = "src/nupp/runtime/provider/digest.nupp", output = "nupp/compiler/nupp/runtime/provider/digest.nupp"},
    {source = "src/nupp/runtime/provider/checksum.nupp", output = "nupp/compiler/nupp/runtime/provider/checksum.nupp"},
    {source = "src/nupp/runtime/provider/mac.nupp", output = "nupp/compiler/nupp/runtime/provider/mac.nupp"},
    {
        source = "src/nupp/runtime/provider/nativecrypto.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativecrypto.nupp"
    },
    {
        source = "src/nupp/runtime/provider/nativesystem.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativesystem.nupp"
    },
    {source = "src/nupp/digest/spi.nupp", output = "nupp/compiler/nupp/digest/spi.nupp"},
    {source = "src/nupp/digest/internal/context.nupp", output = "nupp/compiler/nupp/digest/internal/context.nupp"},
    {source = "src/nupp/digest/internal/builtin.nupp", output = "nupp/compiler/nupp/digest/internal/builtin.nupp"},
    {source = "src/nupp/digest/internal/words.nupp", output = "nupp/compiler/nupp/digest/internal/words.nupp"},
    {source = "src/nupp/digest/internal/constants.nupp", output = "nupp/compiler/nupp/digest/internal/constants.nupp"},
    {source = "src/nupp/checksum/init.nupp", output = "nupp/compiler/nupp/checksum/init.nupp"},
    {source = "src/nupp/checksum/spi.nupp", output = "nupp/compiler/nupp/checksum/spi.nupp"},
    {source = "src/nupp/checksum/internal/builtin.nupp", output = "nupp/compiler/nupp/checksum/internal/builtin.nupp"},
    {source = "src/nupp/mac/init.nupp", output = "nupp/compiler/nupp/mac/init.nupp"},
    {source = "src/nupp/compression/init.nupp", output = "nupp/compiler/nupp/compression/init.nupp"},
    {source = "src/nupp/compression/spi.nupp", output = "nupp/compiler/nupp/compression/spi.nupp"},
    {
        source = "src/nupp/runtime/provider/nativecompression.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativecompression.nupp"
    },
    {source = "src/nupp/util/internal/hash.nupp", output = "nupp/compiler/nupp/util/internal/hash.nupp"},
    {source = "src/nupp/util/internal/uuid.nupp", output = "nupp/compiler/nupp/util/internal/uuid.nupp"},
    {source = "src/nupp/codec/hex.nupp", output = "nupp/compiler/nupp/codec/hex.nupp"},
    {source = "src/nupp/system/init.nupp", output = "nupp/compiler/nupp/system/init.nupp"},
    {source = "src/nupp/runtime/browser/system.nupp", output = "nupp/compiler/nupp/runtime/browser/system.nupp"},
    {source = "src/nupp/util/init.nupp", output = "nupp/compiler/nupp/util/init.nupp"},
    {source = "src/nupp/util/internal/bitset.nupp", output = "nupp/compiler/nupp/util/internal/bitset.nupp"},
    {source = "src/nupp/util/internal/store.nupp", output = "nupp/compiler/nupp/util/internal/store.nupp"},
    {source = "src/nupp/util/internal/protected.nupp", output = "nupp/compiler/nupp/util/internal/protected.nupp"},
    {source = "src/nupp/mem/init.nupp", output = "nupp/compiler/nupp/mem/init.nupp"},
    {source = "src/nupp/io/path/init.nupp", output = "nupp/compiler/nupp/io/path/init.nupp"},
    {source = "src/nupp/io/path/provider.nupp", output = "nupp/compiler/nupp/io/path/provider.nupp"},
    {source = "src/nupp/io/path/pathtext.nupp", output = "nupp/compiler/nupp/io/path/pathtext.nupp"},
    {source = "src/nupp/io/uri/init.nupp", output = "nupp/compiler/nupp/io/uri/init.nupp"},
    {source = "src/nupp/io/files/init.nupp", output = "nupp/compiler/nupp/io/files/init.nupp"},
    {source = "src/nupp/io/init.nupp", output = "nupp/compiler/nupp/io/init.nupp"},
    {source = "src/nupp/log.nupp", output = "nupp/compiler/nupp/log.nupp"},
    {source = "src/nupp/suspension/init.nupp", output = "nupp/compiler/nupp/suspension/init.nupp"},
    {source = "src/nupp/time/init.nupp", output = "nupp/compiler/nupp/time/init.nupp"},
    {source = "src/nupp/io/net/init.nupp", output = "nupp/compiler/nupp/io/net/init.nupp"},
    {source = "src/nupp/io/tls/init.nupp", output = "nupp/compiler/nupp/io/tls/init.nupp"},
    {source = "src/nupp/io/process/init.nupp", output = "nupp/compiler/nupp/io/process/init.nupp"},
    {source = "src/nupp/workers/init.nupp", output = "nupp/compiler/nupp/workers/init.nupp"},
    {source = "src/nupp/tasks.nupp", output = "nupp/compiler/nupp/tasks.nupp"},
    {source = "src/nupp/io/http/init.nupp", output = "nupp/compiler/nupp/io/http/init.nupp"},
    {source = "src/nupp/workers/native.d.nupp", output = "nupp/compiler/nupp/workers/native.d.nupp"},
}

-- Bootstrap module builds do not execute GPU programs. Keep those compiler
-- builds independent of WGPU; the compiler and distribution targets also run
-- user programs through `run` and `bench`, so they enable GPU support below.
local COMPILER_NATIVE_FEATURES = {gpu = false, workers = false}
for _, resource in ipairs({
    "src/nupp/io/net/internal.nupp",
    "src/nupp/io/net/types.nupp",
    "src/nupp/io/process/types.nupp",
    "src/nupp/io/tls/types.nupp",
    "src/nupp/io/http/messages.nupp",
    "src/nupp/io/internal/bytes.nupp",
    "src/nupp/io/internal/ownedreader.nupp",
    "src/nupp/io/internal/scalars.nupp",
    "src/nupp/io/internal/lines.nupp",
    "src/nupp/io/http/internal/transport.nupp",

    "src/nupp/gpu/internal.nupp",
    "src/nupp/gpu/layoutfacts.nupp",
    "src/nupp/runtime/browser/webgpu/internal.nupp",
    "src/nupp/runtime/browser/uri.nupp",
    "src/nupp/io/uri/pathtext.nupp",
    "src/nupp/io/uri/provider.nupp",
    "src/nupp/runtime/browser/init.nupp",
    "src/nupp/runtime/provider/init.nupp",
    "src/nupp/compiler/init.nupp",
    "src/nupp/compiler/runtime/extensions.nupp",
    "src/nupp/compiler/runtime/math.nupp",
    "src/nupp/compiler/runtime/reflect.nupp",
    "src/nupp/digest/internal/sha256.nupp",
    "src/nupp/runtime/browser/effects.g.nupp",
    "src/nupp/runtime/browser/response.g.nupp",
    "src/nupp/runtime/browser/workercodec.g.nupp",
    "src/nupp/runtime/browser/crypto.g.nupp",
    "src/nupp/runtime/browser/http.g.nupp",
    "src/nupp/runtime/browser/files.g.nupp",
    "src/nupp/runtime/browser/path.nupp",
    "src/nupp/browser/init.nupp",
    "src/nupp/runtime/browser/suspension.g.nupp",
    "src/nupp/runtime/browser/time.g.nupp",
    "src/nupp/runtime/browser/workers.g.nupp",
    "src/nupp/runtime/provider/lunajson.nupp",
    "src/nupp/runtime/provider/scalarbitops.nupp",
    "src/nupp/runtime/provider/tablebuffer.nupp",
    "src/nupp/runtime/storage.nupp",
    "src/nupp/runtime/managed.g.nupp",
    "src/nupp/runtime/vendor/lunajson/decoder.lua",
    "src/nupp/runtime/vendor/lunajson/encoder.lua",
}) do
    RESOURCES[#RESOURCES + 1] = {source = resource, output = resource:gsub("^src/", "nupp/compiler/"),}
end
local LUAJIT_BROWSER_RESOURCES = {}
for index, resource in ipairs(RESOURCES) do
    LUAJIT_BROWSER_RESOURCES[index] = resource
end
LUAJIT_BROWSER_RESOURCES[
    #LUAJIT_BROWSER_RESOURCES + 1
] = {source = "build/browser-luajit/preludeimage.bin", output = "nupp/compiler/preludeimage.bin",}
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
                entries = {"nupp.tools.main"},

                nativeFeatures = {gpu = true, workers = false},
                resources = RESOURCES,
            },
            testRunner = {
                kind = "binary",
                description = "Build the worker-hosted test runner",
                outDir = "build/test-runner",
                entries = {"main"},
                sources = {"tests/runner/main.g.nupp", "tests/runner/job.g.nupp"},

                nativeFeatures = {workers = true, lpeg = true},
                stub = "nupp",
                output = "build/nupp-test",
            },
            bootstrapCompiler = {
                kind = "modules",
                description = "Build the self-contained stage-zero compiler",
                outDir = "build/bootstrap-compiler",
                entries = {"nupp.tools.main"},

                nativeFeatures = COMPILER_NATIVE_FEATURES,
                resources = RESOURCES,
            },
            browserLuaJITCompiler = {
                kind = "bundle",
                description = "Build the LuaJIT browser compiler candidate",
                outDir = "build/browser-luajit/compiler",
                output = "build/browser-luajit/nupp-compiler.lua",
                dialect = "luajit",
                entries = {"nupp.tools.browserluajit"},
                sources = {"src/nupp/tools/browserluajit.nupp"},
                resources = LUAJIT_BROWSER_RESOURCES,
            },
            browserLuaJITCompilerWithoutPrelude = {
                kind = "bundle",
                description = "Build the LuaJIT browser prelude generator",
                outDir = "build/browser-luajit/bootstrap",
                output = "build/browser-luajit/bootstrap/nupp-compiler.lua",
                dialect = "luajit",
                entries = {"nupp.tools.browserluajit"},
                sources = {"src/nupp/tools/browserluajit.nupp"},
                resources = RESOURCES,
            },
            browserLuaJITApplicationRuntime = {
                kind = "bundle",
                description = "Build the LuaJIT browser application runtime",
                outDir = "build/browser-luajit/app",
                output = "build/browser-luajit/nupp-app-runtime.lua",
                dialect = "luajit",
                entries = {"nupp.runtime.browser.playground"},
                sources = {"src/nupp/runtime/browser/playground.g.nupp"},
            },
            -- Nupp stamped into a feature-matched host as one self-contained
            -- executable. It is the first payload the format ever carries, on
            -- purpose: a packager that cannot package itself has no business
            -- claiming it packages anything.
            dist = {
                kind = "binary",
                description = "Stamp the compiler into a self-contained binary",
                entries = {"nupp.tools.main"},
                -- Carried, not just installed: a binary is handed to someone who
                -- has no rock tree, and `nupp doc` is one of the commands it
                -- claims to have.
                dependencies = {"lunamark_lpeg", "lunamark_cosmo", "lunamark_getopt", "lunamark", "scintillua",},

                nativeFeatures = {gpu = true, workers = false},
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
                pages = {
                    {glob = "docs/**.md"},
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
            "test-fleet"
        ] = {
            description = "Run cross-platform tests on locally owned workers",
            argv = {"python3", "scripts/test-fleet"},
        },
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
        -- The compiler this tree's first stage is compiled by. It is the previous
        -- release's, fetched and verified against the digest pinned in
        -- `scripts/toolchain.pins`, which is also what `bin/nupp` starts from in a
        -- checkout that has never been built. It is fetched rather than committed,
        -- and that costs: the sources below may only use a language feature the
        -- pinned release already understands.
        --
        -- Run through `sh`, because this is a shell script and the command is
        -- spawned rather than handed to a shell: Windows cannot execute it by name
        -- and reported it as an unrecognized program, which is where `nupp fixpoint`
        -- stopped there. Every host that can run `bin/nupp` at all has `sh`.
        bootstrap = "sh scripts/toolchain stage0",
        -- The target `nupp fixpoint --binary` stamps twice. Naming it here rather
        -- than in the command keeps the compiler from knowing anything about how
        -- this particular project chose to package itself.
        binary = "dist",
    },
}
