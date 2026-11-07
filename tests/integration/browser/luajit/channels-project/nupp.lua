return {
    include = {"src"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"nupp.tests.channelmain"},
                sources = {"src"},
                output = "dist/app.lua",
                outDir = "build/app",
                host = "browser",
            }
        }
    },
}
