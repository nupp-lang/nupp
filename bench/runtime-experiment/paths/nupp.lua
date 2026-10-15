-- The shipped path normalizer left to LuaJIT. Its LLVM-compiled twin (the
-- `llvm-aot` row in RESULTS.md) went with the LLVM backend.
return {
    include = {"src", ".", "../../../src"},
    build = {
        outDir = "build",
        default = "paths-scalar",
        targets = {
            ["paths-scalar"] = {kind = "modules", description = "the same source left to LuaJIT", entries = {"nupp.bench.pathbench"}, optimize = 1, aot = "off"},
        },
    },
}
