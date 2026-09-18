return {
    include = {"src", "../../../build/qemu-wasm-spike/provider-src", "../../../src"},
    build = {
        targets = {
            app = {
                kind = "bundle",
                entries = {"main"},
                sources = {"src"},
                output = "../../../build/qemu-wasm-spike/web/app.lua",
                outDir = "../../../build/qemu-wasm-spike/project",
                dialect = "luajit",
                nativeFeatures = {
                    path = false,
                    time = false,
                    uri = false,
                    http = false,
                    workers = false,
                    sharedbytes = false,
                    gpu = false
                },
            },
        },
    },
}
