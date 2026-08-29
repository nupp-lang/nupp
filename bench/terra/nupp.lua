-- Two targets over one kernel source, differing only in what they do with
-- `@aot`. `terra-bench` compiles the four entries and calls them;
-- `terra-bench-scalar` builds the same text and leaves it to LuaJIT. Building
-- both into separate directories is what lets one benchmark process measure
-- them against each other, against the Terra kernels, and against the same
-- colocated C control.
return {
   include = { "src", "../../src" },

   dependencies = {
      -- The C the other three are read against. It is written to be the
      -- obvious transcription of each kernel and nothing cleverer, because its
      -- job is to be the number a reader already has an intuition for.
      terra_bench_control = {
         kind = "c",
         sources = { "native/control.c" },
         headers = { "native/control.h" },
         cflags = {
            "-std=gnu11", "-O3", "-DNDEBUG", "-ffp-contract=off",
            "-Wall", "-Wextra", "-Werror",
         },
      },
   },

   build = {
      outDir = "build",
      default = "terra-bench",
      targets = {
         ["terra-bench"] = {
            kind = "modules",
            description = "Build the kernels with their `@aot` entries compiled",
            entries = { "kernels" },
            aot = "require",
            dependencies = { "terra_bench_control" },
         },
         ["terra-bench-scalar"] = {
            kind = "modules",
            description = "Build the same kernels with `@aot` left to LuaJIT",
            entries = { "kernels" },
            aot = "off",
         },
      },
   },
}
