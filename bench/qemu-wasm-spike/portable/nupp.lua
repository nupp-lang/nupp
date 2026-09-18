return {
    include = {"src", "../project/src", "../../../src"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                dialect = "lua51",
                output = "../../../build/qemu-wasm-spike/web/portable-app.lua",
                outDir = "../../../build/qemu-wasm-spike/portable",
            }
        }
    },
}
