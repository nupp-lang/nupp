return {
   include = { "src", "../../src" },

   dependencies = {
      simdjson_bench = {
         kind = "c",
         cc = "c++",
         sources = { "native/simdjson_bench.cpp" },
         headers = { "native/simdjson_bench.h" },
         cflags = {
            "-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
         },
         pkgConfig = "simdjson",
      },
   },

   build = {
      outDir = "build",
      default = "simd-json",
      targets = {
         ["simd-json"] = {
            kind = "modules",
            description = "Build the detachable SIMD JSON experiment",
            entries = { "simd_json" },
            aot = "require",
            dependencies = { "simdjson_bench" },
         },
      },
   },
}
