return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "game",
      targets = {
         game = {
            kind = "modules",
            description = "Build ${name} for LÖVE",
            dialect = "luajit-compat",
            entries = { "main" },
         },
      },
   },

   test = {
      build = "game",
      argv = { "luajit", "tests/run.lua" },
      env = { LUA_PATH = "build/?.lua;;" },
   },

   tasks = {
      play = {
         build = "game",
         description = "Build ${name} and start it with LÖVE",
         argv = { "love", "build" },
      },
   },
}
