return {
    include = {"src"},
    build = {targets = {
        native = {
            outDir = "build/luajit",
            entries = {"main"},
            dialect = "luajit",
        },
        portable = {
            outDir = "build/lua51",
            entries = {"main"},
            dialect = "lua51",
            backends = {"portable.backend"},
        },
    }},
}
