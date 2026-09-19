return {
    include = {"src", "../../src"},

    dependencies = {
        simdjson_bench_native = {
            kind = "c",
            cc = "c++",
            path = "../..",
            sources = {"bench/simd-json/native/simdjson_control.cpp"},
            headers = {"bench/simd-json/native/simdjson_control.h", "bench/simd-json/native/serde.inc",},
            cflags = {"-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",},
            pkgConfig = {"simdjson", "luajit"},
        },
    },

    build = {
        outDir = "build",
        default = "simd-json",
        targets = {
            [
                "simd-json"
            ] = {
                kind = "modules",
                description = "Build the detachable SIMD JSON experiment",
                entries = {"simd_json", "production_json_test"},
                optimize = 1,
                aot = "require",
                dependencies = {"simdjson_bench_native"},
            },
            -- The structural indexer alone, with the byte-at-a-time reference
            -- it is tested against. It needs no external simdjson dependency.
            [
                "simd-json-index"
            ] = {
                kind = "modules",
                description = "Build the structural indexer and its scalar reference",
                sources = {"src/simd_json/indexer.nupp", "src/simd_json/indexer_reference.nupp"},
                optimize = 1,
                aot = "require",
            },
        },
    },
}
