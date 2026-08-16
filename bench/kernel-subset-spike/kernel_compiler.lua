-- A test-only compiler for a deliberately small `@aot` subset.
--
-- It consumes Nupp's real CST, validates an admitted whole-function shape,
-- verifies a sealed typed IR, and emits private scalar C for Clang to optimize.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local intensity = require("nupp.compiler.aot.intensity")
local lower = require("nupp.compiler.aot.lower")
local scalarIR = require("nupp.compiler.aot.scalar")
local irVerify = require("nupp.compiler.aot.verify")
local irText = require("nupp.compiler.aot.text")
local rewriteRules = require("nupp.compiler.aot.rewrite")
local emitRules = require("nupp.compiler.aot.emit")
local bindingRules = require("nupp.compiler.aot.binding")
local parser = require("nupp.compiler.parser")

local compiler = {}
local STOP = {}

local site = lower.site

local function diagnostic(filename, node, message)
   local at = site(node)
   return {file = filename, line = at.line, column = at.column, message = message}
end

local function renderDiagnostic(value)
   return ("%s:%d:%d: kernel subset: %s"):format(
      value.file, value.line, value.column, value.message
   )
end

compiler.renderDiagnostic = renderDiagnostic

local function parseKernel(source, filename, checked)
   local parsed = checked or parser.parse(source, filename)
   if #parsed.errors > 0 then
      local diagnostics = {}
      for _, problem in ipairs(parsed.errors) do
         diagnostics[#diagnostics + 1] = {
            file = filename,
            line = problem.line or 1,
            column = problem.col or 1,
            message = "syntax error: " .. problem.msg,
         }
      end
      return nil, diagnostics
   end

   local diagnostics = {}
   local function reject(node, message)
      diagnostics[#diagnostics + 1] = diagnostic(filename, node, message)
      error(STOP, 0)
   end

   -- Where a width may change is `nupp.compiler.aot.lower`'s. It reports by
   -- position rather than by node, because what it refuses is about values
   -- meeting and not about syntax.
   local loweringContext = {
      reject = function(at, message)
         diagnostics[#diagnostics + 1] = {
            file = filename, line = at and at.line or 1,
            column = at and at.column or 1, message = message,
         }
         error(STOP, 0)
      end,
   }

   -- Lowering the whole function is `nupp.compiler.aot.lower`'s. What is left
   -- here is the driver: parse, lower, verify, try each gang width, emit.
   local ok, ir = pcall(function()
      local found = lower.scan(parsed.root, checked and true or false)
      if #found.applications == 0 then
         reject(parsed.root, "no @aot function was found")
      elseif #found.applications > 1 then
         reject(found.applications[2].at, "this spike accepts exactly one @aot function")
      end

      return lower.program(found, found.applications[1], checked and true or false, loweringContext)
   end)

   if not ok then
      if ir ~= STOP then error(ir, 0) end
      return nil, diagnostics
   end
   return ir, diagnostics
end

-- Declared in `nupp.compiler.aot.intensity`, which is where this decision
-- belongs: whether a loop is worth running several iterations at once is
-- compiler policy, not a property of this spike.
local function arithmeticIntensity(ir)
   local estimate = intensity.estimate(ir.loop.statements)
   return estimate.perByte, estimate.operations, estimate.bytes, estimate.worthwhile
end

-- The rules live in `nupp.compiler.aot.verify`, against the typed vocabulary.
-- This spike hands one over and keeps nothing of its own: what makes IR well
-- formed is compiler policy, not a property of a test-only front end.
local verifyIR = irVerify.program

compiler.verifyIR = verifyIR

-- The readable form lives in `nupp.compiler.aot.text`.
local irLines = irText.program

-- The whole C file lives in `nupp.compiler.aot.emit`.
local renderC = emitRules.program

--- Where the compiled object lands, which is what the generated module loads.
local SPIKE_LIBRARY = "bench/kernel-subset-spike/build/libkernel_subset_spike"

local function renderBinding(ir)
   return bindingRules.module(ir, SPIKE_LIBRARY)
end

function compiler.compile(source, filename, checked)
   local ir, diagnostics = parseKernel(source, filename, checked)
   if not ir then return nil, diagnostics end
   verifyIR(ir)
   -- The lane-parallel pass runs on verified scalar IR: what it rewrites has
   -- already been proved to mean something, so a refusal here is only ever
   -- about lowering it several iterations at a time.
   local worthwhile
   ir.intensity, ir.operations, ir.touchedBytes, worthwhile = arithmeticIntensity(ir)
   if not ir.lanesRequired and not worthwhile then
      ir.wantsLanes = false
      ir.thin = true
   end
   ir.lanesDeclined = not ir.wantsLanes
   if ir.wantsLanes then
      -- Choosing a gang is `nupp.compiler.aot.rewrite`'s. Only the narrowest
      -- shape's refusals are kept: a loop that cannot lower at all cannot lower
      -- in any width, and the binary64 refusal is the one that names the
      -- construct rather than the width.
      local attempts = rewriteRules.select(ir)
      local refusals
      for _, attempt in ipairs(attempts) do
         refusals = {}
         for _, why in ipairs(attempt.refusals) do
            refusals[#refusals + 1] = diagnostic(filename, ir.loop.source, why)
            if os.getenv("NUPP_SPIKE_SHAPES") then
               io.stderr:write("shape ", attempt.shape, ": ",
                  renderDiagnostic(refusals[#refusals]), "\n")
            end
         end
      end
      -- A body that cannot lower lane-parallel still compiles: it keeps its
      -- scalar loop, and the refusals are carried so the vectorisation check can
      -- name the construct that stopped it rather than the build failing on a
      -- performance property.
      if not ir.lanes then
         ir.laneRefusals = refusals
         ir.lanesDeclined = false
      else
         verifyIR(ir)
      end
   end
   return {
      ir = ir,
      irText = irLines(ir),
      c = renderC(ir),
      binding = renderBinding(ir),
   }, diagnostics
end

return compiler
