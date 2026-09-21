return {
    include = {"src", "luajit"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "dist/app.lua",
                outDir = "build/app",
                dialect = "luajit",
                host = "browser",

                aot = "require-wasm",
            },
            luajit = {
                kind = "bundle",
                entries = {"run"},
                sources = {"luajit"},
                output = "dist/luajit-app.lua",
                outDir = "build/luajit-app",
                dialect = "luajit",
                host = "browser",

                aot = "require-wasm",
            },
        },
    },
}
