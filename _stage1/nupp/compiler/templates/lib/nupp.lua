return {
   include = { "src" },
   build = {
      outDir = "build",
      entries = { "${moduleName}" },
   },
   test = {
      argv = { "luajit", "tests/run.lua" },
      env = { LUA_PATH = "build/?.lua;;" },
   },
}
