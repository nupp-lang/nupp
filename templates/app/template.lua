-- The default template: the smallest project that is genuinely complete.
--
-- `name` is declared only to constrain it. Its value comes from `--name` or the
-- destination directory, and the pattern is the one a module name has to satisfy
-- for `require` to reach it.
return {
   description = "A runnable program, with a test and a task to start it",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "a project name must use lowercase letters, digits,"
            .. " hyphens, or underscores",
      },
   },

   after = { "git" },
}
