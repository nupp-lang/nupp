-- Two targets over one source tree, differing only in what they do with `@aot`.
-- `base64` compiles the encoder ahead of time and calls the compiled entry;
-- `base64-scalar` leaves the same Nupp source to LuaJIT. Building both into
-- separate directories is what lets one benchmark process measure them against
-- each other and against the same colocated C control.
return {
   include = { "src", "../../src" },

   dependencies = {
      -- The ceiling this spike exists to measure: the same encoder written the
      -- way a C programmer would write it, scalar and vectorized, so the
      -- question "what would the missing SIMD operations buy" has a number
      -- rather than a citation behind it.
      base64_control = {
         kind = "c",
         sources = { "base64_control.c" },
         headers = { "nupp_base64.h" },
         cflags = { "-std=gnu11", "-O2", "-DNDEBUG", "-Wall", "-Wextra", "-Werror" },
      },
   },

   build = {
      outDir = "build",
      default = "base64",
      targets = {
         ["base64"] = {
            kind = "modules",
            description = "Build the encoder with its `@aot` entry compiled",
            entries = { "base64bench" },
            optimize = 1,
            aot = "require",
            dependencies = { "base64_control" },
         },
         ["base64-scalar"] = {
            kind = "modules",
            description = "Build the same source with `@aot` left to LuaJIT",
            entries = { "base64bench" },
            optimize = 1,
            aot = "off",
         },
      },
   },
}
