-- The vector encoder for `bench/base64`, built on its own beside the scalar
-- reference it is tested against.
--
-- `encode` asserts nothing: it tests `simd.species` and keeps a byte loop for
-- a target without vectors, so the file checks under any target. It still
-- lives in its own project rather than inside `bench/base64`, because a
-- project reaching the compiler's `src` from one level deeper writes its
-- generated C into its own source tree instead of its build directory.
--
-- `base64reference` is the plain per-triple encoder the differential in
-- `tests/` holds the vector path to. It is ordinary Nupp and is built here so
-- both modules come out of one build.
return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "base64-simd",
      targets = {
         ["base64-simd"] = {
            kind = "modules",
            description = "Build the vector encoder and its scalar reference",
            entries = { "base64simd", "base64reference" },
            optimize = 1,
            aot = "require",
         },
      },
   },
}
