-- Two targets over one source tree, differing only in what they do with `@aot`.
-- `utf8` compiles the validator ahead of time and calls the compiled entry;
-- `utf8-scalar` leaves the same Nupp source to LuaJIT. Building both into
-- separate directories is what lets one benchmark process measure them against
-- each other, against `nupp.data.utf8` as it ships, and against the rock.
return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "utf8",
      targets = {
         ["utf8"] = {
            kind = "modules",
            description = "Build the validator with its `@aot` entry compiled",
            entries = { "utf8bench" },
            aot = "require",
         },
         ["utf8-scalar"] = {
            kind = "modules",
            description = "Build the same source with `@aot` left to LuaJIT",
            entries = { "utf8bench" },
            aot = "off",
         },
      },
   },
}
