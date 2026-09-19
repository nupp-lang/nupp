return {
    include = {"src"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "dist/app.lua",
                outDir = "build/app",
                dialect = "lua51",

                aot = "require-wasm",
            },
            luajit = {
                kind = "bundle",
                entries = {"run"},
                sources = {"src"},
                output = "dist/luajit-app.lua",
                outDir = "build/luajit-app",
                dialect = "luajit",
                host = "browser",

                aot = "require-wasm",
            },
        },
    },
}
