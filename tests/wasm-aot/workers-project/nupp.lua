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
                dialect = "luajit",
                host = "browser",

            },
            luajit = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "dist/luajit-app.lua",
                outDir = "build/luajit-app",
                dialect = "luajit",
                host = "browser",

            },
        },
    },
}
