-- A typed LuaRocks library: runtime Lua as ordinary rock modules, with matching
-- public declarations in a versioned `nupp/` directory.
--
-- This is what `nupp rock init` writes, and it writes it by scaffolding this
-- template. The pattern is `nupp.compiler.rock`'s own rule for a rock name,
-- which is stricter than a directory name has to be and is the reason a
-- template can declare one at all.
return {
   description = "A typed library packaged as a LuaRocks rock",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "rock name must use lowercase letters, digits, hyphens,"
            .. " or underscores",
      },
   },

   after = { "git" },
}
