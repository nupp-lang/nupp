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
      argv = { "nupp", "test-runner" },
   },

   tasks = {
      start = {
         description = "Run ${name}",
         argv = { "nupp", "run", "src/main.nupp" },
      },
   },
}
