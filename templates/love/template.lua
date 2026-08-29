return {
   description = "A small LÖVE game using Nupp's LuaJIT compatibility target",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "a project name must use lowercase letters, digits,"
            .. " hyphens, or underscores",
      },
   },

   after = { "git" },
}
