-- A browser application using the checked platform backend and Lua 5.1 Wasm
-- host. Packaging needs the Nupp source distribution because that is where the
-- pinned Emscripten host builder currently lives.
return {
   description = "A browser application using crypto, timers, and storage",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "a project name must use lowercase letters, digits,"
            .. " hyphens, or underscores",
      },
   },

   after = { "git" },
}
