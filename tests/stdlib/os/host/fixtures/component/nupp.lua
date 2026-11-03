return {
    include = {"src"},
    build = {
        kind = "component",
        description = "The host channel's contract scenarios, for an embedding application to drive",
        entries = {"contract"},
        exports = {"contract.load", "contract.start", "contract.poll", "contract.result", "contract.direct"},
    },
}
