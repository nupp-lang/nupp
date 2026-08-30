return {
   include = { "src" },
   dependencies = {
      tiny = {
         kind = "c",
         sources = { "native/tiny.c" },
         bindings = { header = "native/tiny.h" },
      },
   },
   build = {
      kind = "binary",
      stub = "nupp",
      standalone = true,
      aot = "require",
      outDir = "build",
      output = "build/pack-smoke",
      entries = { "main" },
      dependencies = { "tiny" },
   },
}
