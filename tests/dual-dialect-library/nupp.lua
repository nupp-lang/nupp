return {
    include = {"src"},
    build = {targets = {native = {outDir = "build/luajit", entries = {"main"}, dialect = "luajit",},},},
}
