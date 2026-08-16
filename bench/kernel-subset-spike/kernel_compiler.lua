-- The spike's entry into the AOT backend.
--
-- Everything this used to do lives in `nupp.compiler.aot.compile` now. What is
-- left is where the compiled object lands, which is the one thing about this
-- pipeline that is a property of the spike rather than of the compiler.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local aot = require("nupp.compiler.aot.compile")
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
   local artifacts, diagnostics = aot.artifacts(source, filename, checked, SPIKE_LIBRARY)
   if not artifacts then return nil, diagnostics end

   return {
      ir = artifacts.programs[1],
      irText = artifacts.irText,
      c = artifacts.c,
      binding = artifacts.binding,
   }, diagnostics
end

return compiler
