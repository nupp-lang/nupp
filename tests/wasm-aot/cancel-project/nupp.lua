return {
    include = {"src"},
    dependencies = {
        lunajson = {kind = "luarocks", version = "1.2.3-1", bundle = {"lunajson.lua", "lunajson/**.lua"},},
    },
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "dist/app.lua",
                outDir = "build/app",
                dialect = "lua51",
                backends = {"nupp.runtime.backend.browser"},
                dependencies = {"lunajson"},
            },
        },
    },
}
