return {
   include = {"src", "../../../src"},
   build = {
      outDir = "build",
      default = "columns-soa",
      targets = {
         ["columns-soa"] = {
            kind = "modules",
            entries = {"measure"},
            optimize = 1,
            aot = "require",
         },
      },
   },
}
