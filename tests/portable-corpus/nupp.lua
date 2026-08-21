return {
    include = {"src"},
    build = {
        entries = {"main"},
        dialect = "lua51",
        backends = {"backend"},
    },
}
