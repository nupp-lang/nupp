return {
   include = { "src", "../../src" },

   dependencies = {
      simdjson_bench = {
         kind = "c",
         cc = "c++",
         path = "../..",
         sources = { "runtime/json/json.cpp" },
         headers = { "runtime/json/json.h" },
         cflags = {
            "-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
         },
         pkgConfig = { "simdjson", "luajit" },
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
