return {
   include = { "src" },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "binary",
            description = "Build ${name}",
            entries = { "main" },
            stub = "nupp",
            output = "build/${name}",
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
