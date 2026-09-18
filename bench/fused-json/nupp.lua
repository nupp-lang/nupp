-- Throughput benchmark for the fused JSON decoder.
--
-- The decoder under test is the tree's own
-- `nupp.codec.json.internal.decoder.fused`. `run.sh` copies it here under a
-- second module name before building, so the same benchmark measures whichever
-- checkout it is run from and a branch that rewrites the decoder needs no
-- change here.
--
-- `aot = "require"` is the whole point: without it the authored body runs
-- interpreted through the portable decoder and the numbers say nothing about
-- the vector scan. `tests/bench.lua` refuses to measure unless the entry it
-- calls is in the `__nuppAotCompiled` registry.
return {
   include = {"src", "../../src"},

   build = {
      outDir = "build",
      default = "fused-json",
      targets = {
         ["fused-json"] = {
            kind = "modules",
            description = "Build the fused JSON decoder ahead of time",
            entries = {"nupp.codec.json.internal.decoder.fusedbench"},
            optimize = 1,
            aot = "require",
         },
      },
   },
}
