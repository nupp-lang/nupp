return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "modules",
            description = "Build ${name}",
         },
      },
   },

   tasks = {
      start = {
         description = "Run ${name}",
         argv = { "nupp", "run", "src/main.nupp" },
      },
   },
}
