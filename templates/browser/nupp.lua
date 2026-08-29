return {
   include = { "src" },

   dependencies = {
      lunajson = {
         kind = "luarocks",
         version = "1.2.3-1",
         bundle = { "lunajson.lua", "lunajson/**.lua" },
      },
   },

   build = {
      outDir = "build",
      default = "app",
      targets = {
         app = {
            kind = "bundle",
            description = "Build ${name} for the browser",
            entries = { "main" },
            sources = { "src" },
            output = "dist/app.lua",
            outDir = "build/app",
            dialect = "lua51",
            dependencies = { "lunajson" },
            backends = { "nupp.runtime.backend.browser" },
         },
      },
   },

   test = {
      build = "app",
      argv = { "node", "tests/build.test.mjs" },
   },

   tasks = {
      package = {
         description = "Build the verified browser application package",
         argv = { "sh", "scripts/package.sh" },
      },
      serve = {
         description = "Serve the packaged application on localhost:8787",
         argv = { "node", "scripts/serve.mjs", "dist/browser" },
      },
   },
}
