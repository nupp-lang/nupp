-- The SIMD validator for `bench/utf8`, built on its own beside the scalar
-- reference it is tested against.
--
-- `validPrefix` asserts nothing: it tests `simd.species` and keeps a scalar
-- ladder for a target without vectors, so the file checks under any target.
-- It still lives in its own project rather than inside `bench/utf8`, because a
-- project reaching the compiler's `src` from one level deeper writes its
-- generated C into its own source tree instead of its build directory.
--
-- `utf8reference` is the table-driven decoder the differential in `tests/`
-- holds the vector path to. It is ordinary Nupp and is built here so both
-- modules come out of one build.
return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "utf8-simd",
      targets = {
         ["utf8-simd"] = {
            kind = "modules",
            description = "Build the lookup validator and its scalar reference",
            entries = { "utf8simd", "utf8reference" },
            aot = "require",
         },
      },
   },
}
