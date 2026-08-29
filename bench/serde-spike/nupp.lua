return {
   include = { "src", "../../src" },

   dependencies = {
      serde_spike_native = {
         kind = "c",
         cc = "c++",
         sources = { "serde_spike.cpp" },
         cflags = {
            "-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
         },
         pkgConfig = "simdjson luajit",
      },
      simdjson_bench_native = {
         kind = "c",
         cc = "c++",
         path = "../..",
         sources = { "bench/simd-json/native/simdjson_control.cpp" },
         headers = {
            "bench/simd-json/native/simdjson_control.h",
            "bench/simd-json/native/serde.inc",
         },
         cflags = {
            "-std=c++17", "-O3", "-DNDEBUG", "-Wall", "-Wextra", "-Werror",
         },
         pkgConfig = "simdjson luajit",
      },
   },

   build = {
      outDir = "build",
      default = "serde-spike",
      targets = {
         ["serde-spike"] = {
            kind = "modules",
            entries = { "serde_spike" },
            aot = "require",
            dependencies = { "serde_spike_native", "simdjson_bench_native" },
         },
      },
   },
}
