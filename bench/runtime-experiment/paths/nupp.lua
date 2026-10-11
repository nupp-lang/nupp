-- Two targets over the shipped path normaliser: `paths` compiles its `@aot`
-- entry ahead of time through LLVM, `paths-scalar` leaves it to LuaJIT.
return {
    include = {"src", ".", "../../../src"},
    build = {
        outDir = "build",
        default = "paths",
        targets = {
            ["paths"] = {kind = "modules", description = "normaliser with its @aot entry compiled", entries = {"nupp.bench.pathbench"}, optimize = 1, aot = "require"},
            ["paths-scalar"] = {kind = "modules", description = "the same source left to LuaJIT", entries = {"nupp.bench.pathbench"}, optimize = 1, aot = "off"},
        },
    },
}
