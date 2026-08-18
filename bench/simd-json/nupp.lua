return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "simd-json",
      targets = {
         ["simd-json"] = {
            kind = "modules",
            description = "Build the detachable SIMD JSON experiment",
            entries = { "simd_json" },
            aot = "require",
         },
      },
   },
}
