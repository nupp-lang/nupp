-- A browser application using LuaJIT and checked browser platform services.
-- Packaging uses the source distribution and its pinned guest toolchain.
return {
    description = "A browser application using crypto, timers, and storage",

    variables = {
        name = {
            pattern = "^[a-z0-9][a-z0-9_-]*$",
            invalid = "a project name must use lowercase letters, digits," .. " hyphens, or underscores",
        },
    },

    after = {"git"},
}
