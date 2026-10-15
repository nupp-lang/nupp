-- A typed library: its modules, with matching public declarations in a
-- versioned `nupp/` directory.
--
-- The pattern keeps the name usable as a package name, which is stricter than
-- a directory name has to be.
return {
   description = "A typed library with public declarations",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "library name must use lowercase letters, digits, hyphens,"
            .. " or underscores",
      },
   },

   after = { "git" },
}
