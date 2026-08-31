return {
    include = {"typed"},
    build = {targets = {typed = {
        kind = "modules",
        entries = {
            "mandelbrot", "gemm", "transformer", "reduction", "compaction",
            "fastmath", "quantgemv",
        },
        outDir = "build/typed",
        aot = "require",
        optimize = 1,
    }}},
}
