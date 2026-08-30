return {
    include = {"typed"},
    build = {targets = {typed = {
        kind = "modules",
        entries = {"mandelbrot"},
        outDir = "build/mandelbrot/typed",
        aot = "require",
        optimize = 1,
    }}},
}
