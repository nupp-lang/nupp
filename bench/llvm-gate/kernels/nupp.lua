-- The kernels Gates A1 and B compare: the simd11 shapes, each in scalar and
-- explicit-SIMD form. One target per tier, so a comparison names exactly the
-- tier it measures, on the platform that has it; `gate` is the host's widest.
local function tier(name, platform)
   return {
      aotTarget = platform,
      kind = "modules",
      entries = {"kernels"},
      optimize = 1,
      aot = "require",
      aotFeatures = {minimum = name, maximum = name},
   }
end

return {
   include = {"src"},
   build = {
      outDir = "build",
      default = "gate",
      targets = {
         gate = {kind = "modules", entries = {"kernels"}, optimize = 1, aot = "require"},
         baseline = tier("baseline", "x86_64-unknown-linux-gnu"),
         avx2 = tier("avx2", "x86_64-unknown-linux-gnu"),
         avx512f = tier("avx512f", "x86_64-unknown-linux-gnu"),
         neon = tier("neon", "aarch64-apple-darwin"),
      },
   },
}
