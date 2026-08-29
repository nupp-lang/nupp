-- Two targets over one source tree, differing only in what they do with `@aot`.
-- `sha256` compiles the digest ahead of time and calls the compiled entry;
-- `sha256-scalar` leaves the same Nupp source to LuaJIT. Building both into
-- separate directories is what lets one benchmark process measure them against
-- each other and against the same colocated C control.
return {
   include = { "src", "../../src" },

   dependencies = {
      -- The implementation being replaced, kept as the control it now is.
      -- Nothing else in the tree builds this: it left the native provider when
      -- `nupp.data.digest` took over, and it lives here beside `legacy.lua`
      -- for the same reason, which is that a port is worth what it can be
      -- measured against.
      sha256_control = {
         kind = "c",
         sources = { "sha256_control.c" },
         headers = { "nupp_sha256.h" },
         cflags = { "-std=gnu11", "-O2", "-DNDEBUG", "-Wall", "-Wextra", "-Werror" },
      },
   },

   build = {
      outDir = "build",
      default = "sha256",
      targets = {
         ["sha256"] = {
            kind = "modules",
            description = "Build the digest with its `@aot` entry compiled",
            entries = { "sha256bench" },
            optimize = 1,
            aot = "require",
            dependencies = { "sha256_control" },
         },
         ["sha256-scalar"] = {
            kind = "modules",
            description = "Build the same source with `@aot` left to LuaJIT",
            entries = { "sha256bench" },
            optimize = 1,
            aot = "off",
         },
      },
   },
}
