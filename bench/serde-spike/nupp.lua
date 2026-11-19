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
         sources = { "bench/serde-spike/simdjson-native/simdjsoncontrol.cpp" },
         headers = {
            "bench/serde-spike/simdjson-native/simdjsoncontrol.h",
            "bench/serde-spike/simdjson-native/serde.inc",
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
            aot = "off",
            dependencies = { "serde_spike_native", "simdjson_bench_native" },
         },
      },
   },
}
