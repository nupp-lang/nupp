return {
    include = {"typed"},
    build = {targets = {typed = {
        kind = "modules",
        entries = {"mandelbrot", "gemm"},
        outDir = "build/typed",
        aot = "require",
        optimize = 1,
    }}},
}
