return {
    include = {".", "../../../src"},
    build = {outDir = "build", default = "kernels", targets = {kernels = {kind = "modules", entries = {"kernels"}, optimize = 1, aot = "require"}}}
}
