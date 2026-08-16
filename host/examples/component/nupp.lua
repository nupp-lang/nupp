return {
    include = {"src"},
    build = {
        kind = "component",
        description = "Build the embeddable example component",
        entries = {"app.main"},
        exports = {"game.answer"},
    },
}
