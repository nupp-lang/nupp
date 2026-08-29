return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "modules",
            description = "Build ${name}",
            entries = { "main" },
         },
      },
   },

   test = {
      argv = { "luajit", "tests/run.lua" },
      env = { LUA_PATH = "build/?.lua;;" },
   },

   tasks = {
      start = {
         description = "Run ${name}",
         argv = { "nupp", "run", "src/main.nupp" },
      },
   },
}
