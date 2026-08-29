-- The SIMD validator for `bench/utf8`, built on its own because it can only
-- ever be compiled.
--
-- `simd.preferredU8` creates an AOT-only value, so a target with `aot = "off"`
-- refuses the file at check time. A project's `include` covers every target in
-- it, so `bench/utf8`'s scalar target could not check this source either. A
-- separate project is how the benchmark says that out loud rather than working
-- around it -- and it sits beside `bench/utf8` rather than inside it because a
-- project reaching the compiler's `src` from one level deeper writes its
-- generated C into its own source tree instead of its build directory.
return {
   include = { "src", "../../src" },

   build = {
      outDir = "build",
      default = "utf8-simd",
      targets = {
         ["utf8-simd"] = {
            kind = "modules",
            description = "Build the lookup4 validator, which has no uncompiled form",
            entries = { "utf8simd" },
            aot = "require",
         },
      },
   },
}
