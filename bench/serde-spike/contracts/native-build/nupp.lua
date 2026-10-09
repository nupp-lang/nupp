return {
    include = {"../src", "../../../../src"},
    build = {
        outDir = "build",
        default = "compiled-contracts",
        targets = {
            [
                "compiled-contracts"
            ] = {
                kind = "modules",
                entries = {
                    "contract.compiledfixture",
                    "nupp.serde.jsoncompiled",
                    "nupp.codec.json.aot",
                    "contract.hotpath",
                    "contract.matrix",
                    "contract.breadth"
                },
                optimize = 1,
                aot = "require",
            },
        },
    },
}
