-- The spike's entry into the AOT backend.
--
-- Everything this used to do lives in `nupp.compiler.aot.compile` now. What is
-- left is where the compiled object lands, which is the one thing about this
-- pipeline that is a property of the spike rather than of the compiler.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local aot = require("nupp.compiler.aot.compile")
local targets = require("nupp.compiler.aot.target")
local verify = require("nupp.compiler.aot.verify")

local compiler = {}

--- Where the compiled object lands, which is what the generated module loads.
local SPIKE_LIBRARY = "bench/kernel-subset-spike/build/libkernel_subset_spike"

compiler.renderDiagnostic = aot.renderDiagnostic

-- The IR corruption tests reach for this: they damage verified IR and require
-- the rules to fire, which is the whole point of the rules being separate from
-- the pass that produced it.
compiler.verifyIR = verify.program

function compiler.compile(source, filename, checked)
   -- The host, at whatever tier holds a gang. The spike compiles for the machine
   -- it is about to run on, so a conservative default would only mean the
   -- differentials stopped testing the lane bodies.
   local host = assert(require("nupp.compiler.targetlayout").hostKey())
   local architecture = targets.architecture(host)
   local selected = assert(targets.select(nil, targets.tiers(architecture)[1]))
   local gangBytes = os.getenv("NUPP_AOT_BENCH_GANG_BYTES")
   if gangBytes ~= nil and gangBytes ~= "16" then
      error("NUPP_AOT_BENCH_GANG_BYTES accepts only 16")
   end
   -- The SIMD Mandelbrot comparison holds the source fixed while asking for
   -- one physical Neon register. This is a benchmark ceiling, not a target
   -- available to ordinary project builds.
   if gangBytes == "16" then
      selected = {triple = host, architecture = architecture, tier = "baseline"}
   end
   local artifacts, diagnostics = aot.artifacts(source, filename, checked, SPIKE_LIBRARY, selected)
   if not artifacts then return nil, diagnostics end

   return {
      ir = artifacts.programs[1],
      irText = artifacts.irText,
      c = artifacts.c,
      binding = artifacts.binding,
   }, diagnostics
end

return compiler
