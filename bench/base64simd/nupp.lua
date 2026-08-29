-- The vectorized encoder for `bench/base64`, built on its own because it can
-- only ever be compiled.
--
-- `simd.preferredU8` creates an AOT-only value, so a target with `aot = "off"`
-- refuses this file at check time. A project's `include` covers every target in
-- it, so `bench/base64`'s scalar target could not check this source either. A
-- separate project is how the benchmark says that out loud, and it sits beside
-- `bench/base64` for the same reason `bench/utf8simd` sits beside `bench/utf8`.
return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "base64-simd",
      targets = {
         ["base64-simd"] = {
            kind = "modules",
            description = "Build the vectorized encoder, which has no uncompiled form",
            entries = { "base64simd" },
            optimize = 1,
            aot = "require",
         },
      },
   },
}
