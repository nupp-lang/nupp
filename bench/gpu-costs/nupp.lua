return {
    include = {"src"},
    build = {targets = {native = {kind = "modules", entries = {"kernels"}, outDir = "build", aot = "require",}}},
}
