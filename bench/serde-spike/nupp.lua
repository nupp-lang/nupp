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
      jsonNative = {
         kind = "c",
         cc = "c++",
         path = "../..",
         sources = { "runtime/json/json.cpp" },
         headers = { "runtime/json/json.h", "runtime/json/serde.inc" },
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
            dependencies = { "serde_spike_native", "jsonNative" },
         },
      },
   },
}
