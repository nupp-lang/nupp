return {
   include = { "src" },
   build = {
      outDir = "build",
      entries = { "${moduleName}" },
   },
   test = {
      argv = { "nupp", "test-runner" },
   },
}
