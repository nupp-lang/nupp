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
    {source = "src/nupp/text/spi.nupp", output = "nupp/compiler/nupp/text/spi.nupp"},
    {source = "src/nupp/random/spi.nupp", output = "nupp/compiler/nupp/random/spi.nupp"},
    {source = "src/nupp/mem/representation/spi.nupp", output = "nupp/compiler/nupp/mem/representation/spi.nupp"},
    {source = "src/nupp/codec/json/spi.nupp", output = "nupp/compiler/nupp/codec/json/spi.nupp"},
    {source = "src/nupp/codec/json/number.nupp", output = "nupp/compiler/nupp/codec/json/number.nupp"},
    {source = "src/nupp/io/path/spi.nupp", output = "nupp/compiler/nupp/io/path/spi.nupp"},
    {source = "src/nupp/time/spi.nupp", output = "nupp/compiler/nupp/time/spi.nupp"},
    {source = "src/nupp/io/uri/spi.nupp", output = "nupp/compiler/nupp/io/uri/spi.nupp"},
    {source = "src/nupp/util/spi.nupp", output = "nupp/compiler/nupp/util/spi.nupp"},
    {source = "src/nupp/runtime/target.nupp", output = "nupp/compiler/nupp/runtime/target.nupp"},
    {source = "src/nupp/text/internal/buffer.d.nupp", output = "nupp/compiler/nupp/text/internal/buffer.d.nupp"},
    {source = "src/nupp/text/init.nupp", output = "nupp/compiler/nupp/text/init.nupp"},
    {source = "src/nupp/cli/init.nupp", output = "nupp/compiler/nupp/cli/init.nupp"},
    {source = "src/nupp/cli/internal/optparser.nupp", output = "nupp/compiler/nupp/cli/internal/optparser.nupp"},
    {source = "src/nupp/cli/internal/decode.nupp", output = "nupp/compiler/nupp/cli/internal/decode.nupp"},
    {source = "src/nupp/cli/internal/terminal.nupp", output = "nupp/compiler/nupp/cli/internal/terminal.nupp"},
    {source = "src/nupp/cli/internal/terminalhost.nupp", output = "nupp/compiler/nupp/cli/internal/terminalhost.nupp"},
    {source = "src/nupp/cli/internal/table.nupp", output = "nupp/compiler/nupp/cli/internal/table.nupp"},
    {source = "src/nupp/cli/internal/application.nupp", output = "nupp/compiler/nupp/cli/internal/application.nupp"},
    {source = "src/nupp/runtime/workersprovider.nupp", output = "nupp/compiler/nupp/runtime/workersprovider.nupp"},
    {source = "src/nupp/runtime/uuidprovider.nupp", output = "nupp/compiler/nupp/runtime/uuidprovider.nupp"},
    {source = "src/nupp/runtime/browser/memory.nupp", output = "nupp/compiler/nupp/runtime/browser/memory.nupp"},
    {source = "src/nupp/runtime/timeprovider.nupp", output = "nupp/compiler/nupp/runtime/timeprovider.nupp"},
    {source = "src/nupp/runtime/structvalue.nupp", output = "nupp/compiler/nupp/runtime/structvalue.nupp"},
    {source = "src/nupp/workers/spi.nupp", output = "nupp/compiler/nupp/workers/spi.nupp"},
    {source = "src/nupp/io/tls/spi.nupp", output = "nupp/compiler/nupp/io/tls/spi.nupp"},
    {source = "src/nupp/suspension/spi.nupp", output = "nupp/compiler/nupp/suspension/spi.nupp"},
    {source = "src/nupp/suspension/selected.nupp", output = "nupp/compiler/nupp/suspension/selected.nupp"},
    {source = "src/nupp/io/process/spi.nupp", output = "nupp/compiler/nupp/io/process/spi.nupp"},
    {source = "src/nupp/io/net/spi.nupp", output = "nupp/compiler/nupp/io/net/spi.nupp"},
    {source = "src/nupp/io/http/spi.nupp", output = "nupp/compiler/nupp/io/http/spi.nupp"},
    {source = "src/nupp/io/files/spi.nupp", output = "nupp/compiler/nupp/io/files/spi.nupp"},
    {source = "src/nupp/io/files/messages.nupp", output = "nupp/compiler/nupp/io/files/messages.nupp"},
    {source = "src/nupp/io/files/path.nupp", output = "nupp/compiler/nupp/io/files/path.nupp"},
    {source = "src/nupp/gpu/spi.nupp", output = "nupp/compiler/nupp/gpu/spi.nupp"},
    {source = "src/nupp/suspension/cancellation.nupp", output = "nupp/compiler/nupp/suspension/cancellation.nupp"},
    {source = "src/nupp/mem/representation/init.nupp", output = "nupp/compiler/nupp/mem/representation/init.nupp"},
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
    {source = "src/nupp/runtime/bitops.nupp", output = "nupp/compiler/nupp/runtime/bitops.nupp"},
    {source = "src/nupp/gpu/api.nupp", output = "nupp/compiler/nupp/gpu/api.nupp"},
    {source = "src/nupp/gpu/types.nupp", output = "nupp/compiler/nupp/gpu/types.nupp"},
    {source = "src/nupp/gpu/operations.nupp", output = "nupp/compiler/nupp/gpu/operations.nupp"},
    "src/nupp/compiler/decls/*.d.nupp",
    "src/nupp/compiler/decls/jit/*.d.nupp",
    {source = "src/nupp/test.nupp", output = "nupp/compiler/nupp/test.nupp"},
    {source = "tests/run.lua", output = "nupp/compiler/nupp/test/runner.lua"},
    -- The tools' own files, carried beside the compiler's so that
    -- `nupp.compiler.bundled` is the one place anything carried is read from.
    {source = "src/nupp/tools/doc/theme.css", output = "nupp/compiler/doc/theme.css"},
    {source = "src/nupp/derive.nupp", output = "nupp/compiler/nupp/derive.nupp"},
    {source = "src/nupp/bench/init.nupp", output = "nupp/compiler/nupp/bench/init.nupp"},
    {source = "src/nupp/bench/internal/statistics.nupp", output = "nupp/compiler/nupp/bench/internal/statistics.nupp"},
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
        source = "src/nupp/codec/json/internal/builder.nupp",
        output = "nupp/compiler/nupp/codec/json/internal/builder.nupp",
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
    {source = "src/nupp/serde/init.nupp", output = "nupp/compiler/nupp/serde/init.nupp"},
    {source = "src/nupp/serde/internal/accessors.nupp", output = "nupp/compiler/nupp/serde/internal/accessors.nupp"},
    {source = "src/nupp/serde/internal/carrier.nupp", output = "nupp/compiler/nupp/serde/internal/carrier.nupp"},
    {source = "src/nupp/serde/internal/context.nupp", output = "nupp/compiler/nupp/serde/internal/context.nupp"},
    {source = "src/nupp/serde/debug.nupp", output = "nupp/compiler/nupp/serde/debug.nupp"},
    {
        source = "src/nupp/serde/internal/declaration.nupp",
        output = "nupp/compiler/nupp/serde/internal/declaration.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/defaults.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/defaults.nupp"
    },
    {source = "src/nupp/serde/internal/document.nupp", output = "nupp/compiler/nupp/serde/internal/document.nupp"},
    {
        source = "src/nupp/serde/internal/documentcodec.nupp",
        output = "nupp/compiler/nupp/serde/internal/documentcodec.nupp"
    },
    {
        source = "src/nupp/serde/internal/documentreader.nupp",
        output = "nupp/compiler/nupp/serde/internal/documentreader.nupp"
    },
    {
        source = "src/nupp/serde/internal/documentwriter.nupp",
        output = "nupp/compiler/nupp/serde/internal/documentwriter.nupp"
    },
    {source = "src/nupp/serde/internal/errors.nupp", output = "nupp/compiler/nupp/serde/internal/errors.nupp"},
    {source = "src/nupp/serde/adapters.nupp", output = "nupp/compiler/nupp/serde/adapters.nupp"},
    {source = "src/nupp/serde/codec.nupp", output = "nupp/compiler/nupp/serde/codec.nupp"},
    {source = "src/nupp/serde/internal/identity.lua", output = "nupp/compiler/nupp/serde/internal/identity.lua"},
    {source = "src/nupp/serde/document.nupp", output = "nupp/compiler/nupp/serde/document.nupp"},
    {source = "src/nupp/serde/json.nupp", output = "nupp/compiler/nupp/serde/json.nupp"},
    {
        source = "src/nupp/serde/internal/json/compiled.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/compiled.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/encoder.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/encoder.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/diagnostic.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/diagnostic.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/document.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/document.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/extensions.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/extensions.nupp"
    },
    {source = "src/nupp/serde/internal/json/lower.nupp", output = "nupp/compiler/nupp/serde/internal/json/lower.nupp"},
    {source = "src/nupp/serde/internal/json/plan.nupp", output = "nupp/compiler/nupp/serde/internal/json/plan.nupp"},
    {
        source = "src/nupp/serde/internal/json/reader.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/reader.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/syntax.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/syntax.nupp"
    },
    {
        source = "src/nupp/serde/internal/json/writer.nupp",
        output = "nupp/compiler/nupp/serde/internal/json/writer.nupp"
    },
    {source = "src/nupp/serde/internal/list.nupp", output = "nupp/compiler/nupp/serde/internal/list.nupp"},
    {source = "src/nupp/serde/internal/memo.nupp", output = "nupp/compiler/nupp/serde/internal/memo.nupp"},
    {source = "src/nupp/serde/internal/indexed.nupp", output = "nupp/compiler/nupp/serde/internal/indexed.nupp"},
    {source = "src/nupp/serde/native.nupp", output = "nupp/compiler/nupp/serde/native.nupp"},
    {
        source = "src/nupp/serde/internal/native/reader.nupp",
        output = "nupp/compiler/nupp/serde/internal/native/reader.nupp"
    },
    {
        source = "src/nupp/serde/internal/native/writer.nupp",
        output = "nupp/compiler/nupp/serde/internal/native/writer.nupp"
    },
    {source = "src/nupp/serde/internal/numbers.nupp", output = "nupp/compiler/nupp/serde/internal/numbers.nupp"},
    {
        source = "src/nupp/serde/internal/persistence.nupp",
        output = "nupp/compiler/nupp/serde/internal/persistence.nupp"
    },
    {
        source = "src/nupp/serde/internal/publication.nupp",
        output = "nupp/compiler/nupp/serde/internal/publication.nupp"
    },
    {source = "src/nupp/serde/internal/scalar.nupp", output = "nupp/compiler/nupp/serde/internal/scalar.nupp"},
    {source = "src/nupp/serde/internal/structure.nupp", output = "nupp/compiler/nupp/serde/internal/structure.nupp"},
    {source = "src/nupp/serde/internal/timestamps.nupp", output = "nupp/compiler/nupp/serde/internal/timestamps.nupp"},
    {source = "src/nupp/serde/internal/value.nupp", output = "nupp/compiler/nupp/serde/internal/value.nupp"},
    {source = "src/nupp/serde/internal/view.nupp", output = "nupp/compiler/nupp/serde/internal/view.nupp"},
    {source = "src/nupp/digest/internal/streaming.nupp", output = "nupp/compiler/nupp/digest/internal/streaming.nupp"},
    {
        source = "src/nupp/runtime/provider/tablestruct.nupp",
        output = "nupp/compiler/nupp/runtime/provider/tablestruct.nupp",
    },
    {
        source = "src/nupp/runtime/provider/scalarsimd.nupp",
        output = "nupp/compiler/nupp/runtime/provider/scalarsimd.nupp",
    },
    {source = "src/nupp/mem/array.nupp", output = "nupp/compiler/nupp/mem/array.nupp"},
    {source = "src/nupp/util/internal/pool.nupp", output = "nupp/compiler/nupp/util/internal/pool.nupp"},
    {source = "src/nupp/mem/arena.nupp", output = "nupp/compiler/nupp/mem/arena.nupp"},
    {source = "src/nupp/events.nupp", output = "nupp/compiler/nupp/events.nupp"},
    {source = "src/nupp/text/utf8.nupp", output = "nupp/compiler/nupp/text/utf8.nupp"},
    {source = "src/nupp/text/regex.nupp", output = "nupp/compiler/nupp/text/regex.nupp"},
    {
        source = "src/nupp/text/internal/regexhost.nupp",
        output = "nupp/compiler/nupp/text/internal/regexhost.nupp"
    },
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
    {
        source = "src/nupp/runtime/provider/nativecrc.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativecrc.nupp"
    },
    {source = "src/nupp/runtime/browser/crc.nupp", output = "nupp/compiler/nupp/runtime/browser/crc.nupp"},
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
    {source = "src/nupp/host/spi.nupp", output = "nupp/compiler/nupp/host/spi.nupp"},
    {source = "src/nupp/host/init.nupp", output = "nupp/compiler/nupp/host/init.nupp"},
    {source = "src/nupp/host/pump.nupp", output = "nupp/compiler/nupp/host/pump.nupp"},
    {
        source = "src/nupp/runtime/provider/nativehost.nupp",
        output = "nupp/compiler/nupp/runtime/provider/nativehost.nupp"
    },
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
    {source = "src/nupp/foreign.nupp", output = "nupp/compiler/nupp/foreign.nupp"},
    {source = "src/nupp/suspension/init.nupp", output = "nupp/compiler/nupp/suspension/init.nupp"},
    {source = "src/nupp/suspension/host.nupp", output = "nupp/compiler/nupp/suspension/host.nupp"},
    {source = "src/nupp/time/init.nupp", output = "nupp/compiler/nupp/time/init.nupp"},
    {source = "src/nupp/io/net/init.nupp", output = "nupp/compiler/nupp/io/net/init.nupp"},
    {source = "src/nupp/io/tls/init.nupp", output = "nupp/compiler/nupp/io/tls/init.nupp"},
    {source = "src/nupp/io/process/init.nupp", output = "nupp/compiler/nupp/io/process/init.nupp"},
    {source = "src/nupp/workers/init.nupp", output = "nupp/compiler/nupp/workers/init.nupp"},
    {source = "src/nupp/tasks.nupp", output = "nupp/compiler/nupp/tasks.nupp"},
    {source = "src/nupp/io/http/init.nupp", output = "nupp/compiler/nupp/io/http/init.nupp"},
    {source = "src/nupp/workers/native.d.nupp", output = "nupp/compiler/nupp/workers/native.d.nupp"},
}

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
    "src/nupp/io/uri/whatwg.nupp",
    "src/nupp/io/uri/provider.nupp",
    "src/nupp/runtime/browser/init.nupp",
    "src/nupp/compiler/init.nupp",
    "src/nupp/compiler/runtime/extensions.nupp",
    "src/nupp/compiler/runtime/math.nupp",
    "src/nupp/compiler/runtime/reflect.nupp",
    "src/nupp/compiler/runtime/typewitness.nupp",
    "src/nupp/digest/internal/sha256.nupp",
    "src/nupp/runtime/browser/effects.nupp",
    "src/nupp/host/internal/values.nupp",
    "src/nupp/runtime/browser/host.nupp",
    "src/nupp/runtime/browser/hostwire.nupp",
    "src/nupp/runtime/browser/response.nupp",
    "src/nupp/runtime/browser/workercodec.nupp",
    "src/nupp/runtime/browser/crypto.nupp",
    "src/nupp/runtime/browser/http.nupp",
    "src/nupp/runtime/browser/files.nupp",
    "src/nupp/runtime/browser/path.nupp",
    "src/nupp/runtime/browser/suspension.nupp",
    "src/nupp/runtime/browser/time.nupp",
    "src/nupp/runtime/browser/workers.nupp",
    "src/nupp/runtime/provider/lunajson.nupp",
    "src/nupp/runtime/provider/scalarbitops.nupp",
    "src/nupp/runtime/provider/tablebuffer.nupp",
    "src/nupp/runtime/storage.nupp",
    "src/nupp/runtime/managed.nupp",
    "src/nupp/runtime/vendor/lunajson/decoder.lua",
    "src/nupp/runtime/vendor/lunajson/encoder.lua",
}) do
    RESOURCES[#RESOURCES + 1] = {source = resource, output = resource:gsub("^src/", "nupp/compiler/"),}
end
for _, relative in ipairs(TEMPLATE_FILES) do
    RESOURCES[#RESOURCES + 1] = {source = "templates/" .. relative, output = "nupp/compiler/templates/" .. relative,}
end
-- What the VM supplies natively, declared beside its crate: a compiler with no
-- checkout behind it types `nupp.vm.*` from these copies.
for _, relative in ipairs({
    "nupp/cli/internal/terminalhost.d.nupp",
    "nupp/compiler/hostpid.d.nupp",
    "nupp/compiler/nativecdecl.d.nupp",
    "nupp/compiler/nativehash.d.nupp",
    "nupp/digest/internal/sha256.d.nupp",
    "nupp/generator.d.nupp",
    "nupp/runtime/provider/nativestorage.d.nupp",
    "nupp/runtime/provider/nativeuuid.d.nupp",
    "nupp/tasks.d.nupp",
    "nupp/tools/build/clockhost.d.nupp",
    "nupp/tools/bytecodecache.d.nupp",
    "nupp/vm.d.nupp",
    "nupp/vm/clock.d.nupp",
    "nupp/vm/compression.d.nupp",
    "nupp/vm/coroutine.d.nupp",
    "nupp/vm/crc.d.nupp",
    "nupp/vm/files.d.nupp",
    "nupp/vm/foreign.d.nupp",
    "nupp/vm/http.d.nupp",
    "nupp/vm/markdown.d.nupp",
    "nupp/vm/net.d.nupp",
    "nupp/vm/ownedCoroutine.d.nupp",
    "nupp/vm/persist.d.nupp",
    "nupp/vm/process.d.nupp",
    "nupp/vm/regex.d.nupp",
    "nupp/vm/snapshot.d.nupp",
    "nupp/vm/taskScope.d.nupp",
    "nupp/vm/tasks.d.nupp",
    "nupp/vm/uri.d.nupp",
}) do
    RESOURCES[#RESOURCES + 1] = {
        source = "native/crates/vm/decls/" .. relative,
        output = "nupp/compiler/vmdecls/" .. relative,
    }
end

return {
    include = {"src", "tests/runner", "evals/lib"},

    build = {
        outDir = "build",
        default = "dist",
        targets = {
            testRunner = {
                kind = "binary",
                description = "Build the worker-hosted test runner",
                outDir = "build/test-runner",
                entries = {"main"},
                -- Lua suites load project modules by name after discovery, so no
                -- static entry graph can enumerate what a selected run will need.
                -- Carry the source set the suites test; coverage then instruments the
                -- same modules an ordinary runner can load dynamically.
                sources = {"tests/runner/main.nupp", "tests/runner/job.nupp", "src/nupp/**.nupp"},

                nativeFeatures = {workers = true},
                resources = RESOURCES,
                stub = "nupp",
                output = "build/nupp-test",
            },
            -- The compiler as one self-contained executable: its image stamped
            -- onto the VM runtime. A packager that cannot package itself has no
            -- business claiming it packages anything.
            dist = {
                kind = "binary",
                description = "Stamp the compiler into a self-contained binary",
                entries = {"nupp.tools.main"},
                nativeFeatures = {gpu = true, workers = false},
                resources = RESOURCES,
                stub = "nupp",
                output = "build/dist/nupp",
            },
            docs = {
                kind = "docs",
                sources = {"src"},
                format = "both",
                outDir = "build/docs",
                title = "Nupp API",
                name = "Nupp",
                description = "A statically typed Lua dialect with its own VM.",
                github = "https://github.com/nupp-lang/nupp",
                logo = "images/nupp.svg",
                favicon = "images/nupp-icon-32.png",
                public = "docs/public",
                customCss = "docs/public/nupp.css",
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
        runtime = {
            description = "Build the native interpreter core object from the handler sources",
            argv = {"python3", "scripts/vm-cli", "runtime"},
        },
        [
            "docs-serve"
        ] = {
            description = "Build the docs site and serve it until stopped",
            argv = {"node", "scripts/docs-serve.mjs"},
        },
        [
            "annotated-lua-corpus"
        ] = {
            description = "Fetch the pinned LuaLS corpus and exercise annotation ingestion",
            argv = {"sh", "scripts/annotated-lua-corpus.sh"},
        },
    },

    selfHost = {
        target = "dist",
        -- The compiler image this tree's first stage is lowered by. It is a
        -- release's root CLI image, fetched and verified against the digest pinned
        -- in `scripts/toolchain.pins`, which is also what `bin/nupp` builds a VM
        -- compiler from in a checkout that has none. It is fetched rather than
        -- committed, and that costs: the sources below may only use a language
        -- feature the pinned image already understands, and the runtime must load
        -- its image format.
        --
        -- Run through `sh`, because this is a shell script and the command is
        -- spawned rather than handed to a shell: Windows cannot execute it by name
        -- and reported it as an unrecognized program, which is where `nupp fixpoint`
        -- stopped there. Every host that can run `bin/nupp` at all has `sh`.
        bootstrap = "sh scripts/toolchain stage0-image",
        -- The target `nupp fixpoint --binary` stamps twice. Naming it here rather
        -- than in the command keeps the compiler from knowing anything about how
        -- this particular project chose to package itself.
        binary = "dist",
    },
}
