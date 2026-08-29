-- A dual browser package: one scalar AOT kernel and one SIMD128 kernel selected
-- by WebAssembly validation before either application starts.
return {
   description = "A browser application with scalar and SIMD128 AOT kernels",

   variables = {
      name = {
         pattern = "^[a-z0-9][a-z0-9_-]*$",
         invalid = "a project name must use lowercase letters, digits,"
            .. " hyphens, or underscores",
      },
   },

   after = { "git" },
}
