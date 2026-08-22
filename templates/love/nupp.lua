return {
   include = { "src" },

   dependencies = {
      love = {
         kind = "types",
         format = "luacats",
         source = {
            git = "https://github.com/LuaCATS/love2d.git",
            rev = "c630dd883cda128a19d850bd5e3911110b271609",
         },
         path = "library",
      },
   },

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
