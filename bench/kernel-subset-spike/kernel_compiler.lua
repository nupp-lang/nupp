-- A test-only compiler for a deliberately small `@aot` subset.
--
-- It consumes Nupp's real CST, validates an admitted whole-function shape,
-- verifies a sealed typed IR, and emits private scalar C for Clang to optimize.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
package.path = root .. "/build/?.lua;" .. package.path

local lane = require("nupp.compiler.aot.lane")
local intensity = require("nupp.compiler.aot.intensity")
local admit = require("nupp.compiler.aot.admit")
local lower = require("nupp.compiler.aot.lower")
local scalarIR = require("nupp.compiler.aot.scalar")
local irVerify = require("nupp.compiler.aot.verify")
local irText = require("nupp.compiler.aot.text")
local rewriteRules = require("nupp.compiler.aot.rewrite")
local emitRules = require("nupp.compiler.aot.emit")
local bindingRules = require("nupp.compiler.aot.binding")
local parser = require("nupp.compiler.parser")
local cst = require("nupp.compiler.cst")

local compiler = {}
local STOP = {}

local function firstToken(node)
   return node and cst.firstToken(node) or nil
end

local site = lower.site

local function nameOf(node)
   return node and node.kind == "name" and node.token and node.token.text or nil
end

local compactType = lower.compactType

local function receiverName(node)
   return nameOf(node)
end

local function dotCount(node)
   if not node or node.kind ~= "dotIndex" or not node.name or node.name.text ~= "count" then
      return nil
   end
   return receiverName(node.obj)
end

local function dottedName(node)
   if not node then return nil end
   if node.kind == "name" then return nameOf(node) end
   if node.kind == "dotIndex" and node.name then
      local base = dottedName(node.obj)
      return base and base .. "." .. node.name.text or nil
   end
   return nil
end

local privateSymbol = scalarIR.privateSymbol
local cIdentifier = scalarIR.cIdentifier

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

local function copyEnvironment(environment)
   local copied = {}
   for name, value in pairs(environment) do copied[name] = value end
   return copied
end

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

   local ok, ir = pcall(function()
      local applications, helperDecls, structDecls = {}, {}, {}
      for _, block in ipairs(parsed.root.blocks or {}) do
         for _, stat in ipairs(block.stats or {}) do
            if stat.kind == "pragmaStmt" then
               -- Annotations stack, so walk the whole chain rather than only
               -- looking at the outermost one. `@aot` may be written above or
               -- below `@relax`, and both orders mean the same thing.
               local chain, cursor = {}, stat
               while cursor and cursor.kind == "pragmaStmt" do
                  chain[#chain + 1] = cursor
                  cursor = cursor.stat
               end
               local isAot = false
               for _, link in ipairs(chain) do
                  if link.name and link.name.text == "aot" then isAot = true end
               end
               if checked then
                  isAot = cursor and cursor.body and cursor.body.aotRequired == true
               end
               if isAot then
                  applications[#applications + 1] = {chain = chain, tail = cursor, at = stat}
               end
            elseif stat.kind == "localFuncStmt" and stat.name then
               helperDecls[stat.name.text] = stat
            elseif stat.kind == "recordDecl" and stat.declKind == "struct" and stat.name then
               structDecls[stat.name.text] = stat
            end
         end
      end
      if #applications == 0 then
         reject(parsed.root, "no @aot function was found")
      elseif #applications > 1 then
         reject(applications[2], "this spike accepts exactly one @aot function")
      end

      local selected = applications[1]
      local application = selected.at
      local fn = selected.tail
      if not fn or fn.kind ~= "localFuncStmt" then
         reject(fn or application, "@aot must decorate a local function with a visible body")
      end
      -- `@relax("fp-contract")` is the only relaxation this spike acts on. It
      -- permits the backend to fuse a multiply and an add into one rounding,
      -- which is faster and gives a different answer, so it is per function and
      -- appears in the IR rather than being a build-wide compiler flag.
      local body = fn.body
      local fpContract = body.relaxedGuarantees
         and body.relaxedGuarantees["fp-contract"] == true or false
      -- Lane lowering is attempted for every admitted body; `lanes = false`
      -- declines it. A body that cannot lower lane-parallel is not an error --
      -- it compiles scalar, and the vectorisation check is what has something to
      -- say about it.
      local wantsLanes = body.lanesDeclined ~= true
      local lanesRequired = body.lanesRequired == true
      if not checked then
         for _, link in ipairs(selected.chain) do
            local written = link.name and link.name.text
            if written == "aot" then
               for _, arg in ipairs(link.annotationArgs or {}) do
                  local name = arg.name and arg.name.text
                  if name == "lanes" then
                     if arg.expr and arg.expr.kind == "falseExpr" then wantsLanes = false end
                     if arg.expr and arg.expr.kind == "trueExpr" then lanesRequired = true end
                  else
                     reject(link, "@aot takes lanes = true, lanes = false, or nothing")
                  end
               end
            elseif written == "relax" then
               for _, arg in ipairs(link.annotationArgs or {}) do
                  local token = firstToken(arg.expr)
                  local text = token and token.text or ""
                  if text:sub(1, 1) == '"' or text:sub(1, 1) == "'" then
                     text = text:sub(2, -2)
                  end
                  if text == "fp-contract" then fpContract = true end
               end
            end
         end
      end
      if not body or body.generics or body.varargParam or body.captureTakes or body.captureBorrows then
         reject(body or fn, "generic, variadic, and capturing kernels are not admitted")
      end
      if #(body.rets or {}) ~= 1 or compactType(body.rets[1]) ~= "nil" then
         reject(body, "the map-kernel prototype must return nil")
      end

      local storageTypes = admit.STORAGE
      -- Which structs may be reified and what a span holds is
      -- `nupp.compiler.aot.lower`'s: a layout is a claim about memory, and the
      -- shape it has to have is compiler policy.
      local layoutState = {ordered = {}, byName = {}}
      local layouts = layoutState.ordered

      local function spanElement(spelling, prefix, at)
         return lower.spanElement(spelling, prefix, at, structDecls, layoutState, loweringContext)
      end

      local params, byName, spans, writes, reads = {}, {}, {}, {}, {}
      for _, raw in ipairs(body.params or {}) do
         local name = raw.name and raw.name.text
         if not name then reject(raw, "every kernel parameter must be named") end
         if byName[name] then reject(raw, "duplicate kernel parameter " .. name) end

         local spelling = compactType(raw.type)
         local mode = raw.modeTok and raw.modeTok.text or nil
         local param
         local writeElement = spanElement(spelling, "span%.WriteSpan", raw.type or raw)
         local readElement = spanElement(spelling, "span%.Span", raw.type or raw)
         if writeElement then
            if mode ~= "exclusive" then
               reject(raw, "a writable float span must be declared exclusive")
            end
            param = {
               kind = "write_span", name = name, type = writeElement.type,
               element = writeElement, region = "r" .. tostring(#spans), access = "readwrite",
               ownership = "exclusive", source = site(raw),
            }
            writes[#writes + 1] = param
            spans[#spans + 1] = param
         elseif readElement then
            if mode ~= "borrows" then
               reject(raw, "a readable float span must be declared borrows")
            end
            param = {
               kind = "read_span", name = name, type = readElement.type,
               element = readElement,
               region = "r" .. tostring(#spans), access = "read",
               ownership = "shared", source = site(raw),
            }
            reads[#reads + 1] = param
            spans[#spans + 1] = param
         elseif spelling == "float" or spelling == "number" or spelling == "integer" then
            if mode then reject(raw, "a uniform float parameter has no ownership mode") end
            param = {
               kind = "uniform", name = name, type = spelling == "float" and "f32" or "f64",
               sourceType = spelling, source = site(raw),
            }
         elseif spelling == "uint32" or spelling == "int32" then
            if mode then reject(raw, "a uniform integer parameter has no ownership mode") end
            param = {
               kind = "uniform", name = name, type = spelling == "uint32" and "u32" or "i32",
               sourceType = spelling, source = site(raw),
            }
         else
            reject(raw.type or raw, "parameter type " .. spelling .. " is not admitted")
         end
         params[#params + 1] = param
         byName[name] = param
      end
      if #writes == 0 then reject(body, "the map-kernel prototype needs a writable span") end
      if #reads == 0 then reject(body, "the map-kernel prototype needs a readable span") end
      local primary = writes[1]

      local regions, aliasFacts = {}, {}
      for _, param in ipairs(spans) do
         regions[#regions + 1] = {
            id = param.region, param = param.name, access = param.access,
            proof = param.ownership .. "_borrow",
         }
      end
      for left = 1, #spans do
         for right = left + 1, #spans do
            local hasWrite = spans[left].kind == "write_span" or spans[right].kind == "write_span"
            aliasFacts[#aliasFacts + 1] = {
               relation = hasWrite and "disjoint" or "may_alias",
               left = spans[left].region,
               right = spans[right].region,
               proof = hasWrite and "exclusive_borrow" or "shared_borrows",
            }
         end
      end

      local stats = body.body and body.body.stats or {}
      if #stats ~= 2 and #stats ~= 3 then
         reject(body.body or body, "the admitted body is a length guard, optional range guard, and one numeric loop")
      end

      local guard = stats[1]
      if guard.kind ~= "ifStmt" or #(guard.clauses or {}) ~= 1 or guard.elseClause then
         reject(guard, "the first statement must be a single length-mismatch guard")
      end
      local clause = guard.clauses[1]
      local guardBody = clause.body and clause.body.stats or {}
      local errorCall = guardBody[1] and guardBody[1].kind == "callStmt" and guardBody[1].expr or nil
      if #guardBody ~= 1 or not errorCall or errorCall.kind ~= "call"
         or nameOf(errorCall.obj) ~= "error"
      then
         reject(guard, "a length guard must call error directly")
      end

      local guarded = {}
      local function collectGuards(expr)
         if expr and expr.kind == "binop" and expr.op and expr.op.text == "or" then
            collectGuards(expr.lhs)
            collectGuards(expr.rhs)
            return
         end
         if not expr or expr.kind ~= "binop" or not expr.op or expr.op.text ~= "~=" then
            reject(expr or guard, "the guard may only compare span counts with ~=")
         end
         local left, right = dotCount(expr.lhs), dotCount(expr.rhs)
         local other
         if left == primary.name then other = right
         elseif right == primary.name then other = left
         end
         if not other or not byName[other] or not byName[other].region or other == primary.name then
            reject(expr, "each guard comparison must compare the primary output with another span")
         end
         if guarded[other] then reject(expr, "duplicate length guard for " .. other) end
         guarded[other] = site(expr)
      end
      collectGuards(clause.cond)
      local guards = {}
      for _, span in ipairs(spans) do
         if span ~= primary then
            if not guarded[span.name] then reject(guard, "the length guard does not cover span " .. span.name) end
            guards[#guards + 1] = {
               op = "equal_count", left = primary.name, right = span.name,
               source = guarded[span.name],
            }
         end
      end

      local rangeGuard
      local loop = stats[#stats]
      if #stats == 3 then
         local candidate = stats[2]
         if candidate.kind ~= "ifStmt" or #(candidate.clauses or {}) ~= 1 or candidate.elseClause then
            reject(candidate, "the optional second statement must be a range guard")
         end
         local rangeClause = candidate.clauses[1]
         local rangeBody = rangeClause.body and rangeClause.body.stats or {}
         local rangeError = rangeBody[1] and rangeBody[1].kind == "callStmt" and rangeBody[1].expr or nil
         if #rangeBody ~= 1 or not rangeError or rangeError.kind ~= "call"
            or nameOf(rangeError.obj) ~= "error"
         then
            reject(candidate, "a range guard must call error directly")
         end
         local written = cst.textOf(rangeClause.cond):gsub("%s+", "")
         local firstName, lastName = written:match(
            "^([%a_][%w_]*)<1or([%a_][%w_]*)>[%a_][%w_]*%.countor"
         )
         local expected = firstName and (
            firstName .. "<1or" .. lastName .. ">" .. primary.name .. ".countor"
               .. firstName .. ">" .. lastName .. "+1"
         ) or ""
         if written ~= expected then
            reject(rangeClause.cond, "range guard must be `first < 1 or last > output.count or first > last + 1`")
         end
         local firstParam, lastParam = byName[firstName], byName[lastName]
         if not firstParam or not lastParam or firstParam.kind ~= "uniform" or lastParam.kind ~= "uniform"
            or firstParam.sourceType ~= "integer" or lastParam.sourceType ~= "integer"
         then
            reject(rangeClause.cond, "range bounds must be uniform integer parameters")
         end
         rangeGuard = {first = firstName, last = lastName, count = primary.name, source = site(candidate)}
      end
      if loop.kind ~= "fornumStmt" then reject(loop, "the final statement must be a numeric for loop") end
      local first = loop.start and (nameOf(loop.start) or (loop.start.kind == "number" and loop.start.token.text))
      if first ~= (rangeGuard and rangeGuard.first or "1") then
         reject(loop.start or loop, "kernel loop start must match its verified range")
      end
      if loop.step then reject(loop.step, "the first subset does not admit an explicit loop step") end
      local stop = nameOf(loop.stop) or dotCount(loop.stop)
      local expectedStop = rangeGuard and rangeGuard.last or primary.name
      if stop ~= expectedStop then
         reject(loop.stop or loop, "the loop bound must match its verified range")
      end
      local index = loop.var and loop.var.text
      if not index then reject(loop, "the kernel loop needs an index variable") end

      -- Lowering an expression, and a visible pure helper, are
      -- `nupp.compiler.aot.lower`'s. What the source is allowed to say and what
      -- the IR it becomes means are both compiler policy.
      local kernel = {
         params = byName,
         layouts = layoutState,
         helperDecls = helperDecls,
         helpers = {},
         helperOrder = {},
         helperState = {},
         symbol = privateSymbol(fn.name.text),
         loopSource = site(loop),
         index = index,
         serial = 0,
         context = loweringContext,
      }
      local helpers = kernel.helperOrder

      local function lowerExpression(node, environment, activeIndex)
         return lower.expression(node, environment, activeIndex, kernel)
      end

      -- Lowering a statement is `nupp.compiler.aot.lower`'s too, so the whole
      -- admitted body -- what it may say and what it becomes -- is one module's.
      local function lowerBlock(rawStats, environment)
         return lower.block(rawStats or {}, environment, kernel)
      end

      local environment = {}
      for _, param in ipairs(params) do
         if param.kind == "uniform" then environment[param.name] = param end
      end
      local statements = lowerBlock(loop.body and loop.body.stats or {}, environment)
      if #statements == 0 then reject(loop.body or loop, "the native loop body may not be empty") end

      return {
         version = 3,
         name = fn.name.text,
         symbol = privateSymbol(fn.name.text),
         fpContract = fpContract,
         wantsLanes = wantsLanes,
         lanesRequired = lanesRequired,
         params = params,
         layouts = layouts,
         regions = regions,
         aliasFacts = aliasFacts,
         guards = guards,
         rangeGuard = rangeGuard,
         helpers = helpers,
         loop = {
            index = index,
            first = rangeGuard and rangeGuard.first or 1,
            last = rangeGuard and rangeGuard.last or primary.name,
            count = primary.name,
            statements = statements, source = site(loop),
         },
         source = site(fn),
      }
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

-- The released fixed-width scalar operations, as IR. Each is one binary32 or
-- wrapping int32 operation with an exact `nupp.math` implementation behind it,
-- which is what lets the backend emit the native instruction and still owe the
-- same answer as ordinary Nupp.
local FIXED_BINARY = {
   f32_add = "f32", f32_sub = "f32", f32_mul = "f32", f32_div = "f32",
   i32_add = "i32", i32_sub = "i32", i32_mul = "i32",
}
-- Operations whose native instruction is right about the value and wrong about
-- NaN, and the C helper that repairs it. Emitting the bare instruction would let
-- an AOT build change bits that `nupp.math.f32.toBits` can read back, so each
-- carries its correction rather than being left out of the subset.
local FIXED_CORRECTED = {
   f32_min = {element = "f32", arity = 2, helper = "nupp_f32_min"},
   f32_max = {element = "f32", arity = 2, helper = "nupp_f32_max"},
   f32_fma = {element = "f32", arity = 3, helper = "nupp_f32_fma"},
}
local FIXED_OPERATOR = {
   f32_add = "+", f32_sub = "-", f32_mul = "*", f32_div = "/",
   i32_add = "+", i32_sub = "-", i32_mul = "*",
}

--[[
Lane-parallel lowering.

`@aot(simd = true)` says the admitted loop's iterations are independent. This pass takes
the loop body that was already lowered, typed, and bound as scalar IR and
rewrites it to run several iterations at once: a value that depends on the loop
index becomes a vector, a value that does not stays scalar and broadcasts where
it meets one, a conditional becomes a mask, and an assignment under a mask
becomes a select so inactive lanes keep what they had.

It runs on IR rather than on the tree because the front end has already settled
what everything means. What is left is a choice about how many iterations to do
at a time, which is exactly the kind of decision an IR pass should own.

The gang size follows the widths the loop's varying values actually need, not a
single element type. Ordinary Nupp arithmetic is binary64, so a loop written
with operators gets four binary64 lanes: two NEON registers or one AVX2
register per live value, which a body of eight of them can hold, where eight
lanes would be four registers each and would spill.

A loop whose varying values are all 32-bit -- because the source asked for
binary32 and wrapping int32 through the released `nupp.math` namespaces -- gets
eight lanes at the same register cost. That is a different program with
different answers, and it is the source that says so; this pass only declines
to waste half of each register on it.

The tail is a scalar epilogue over the same body rather than a masked final
group, because a masked load still reads the addresses it masks off and the
last element of a span may be the last byte of a page.
]]

--- The lane shapes this backend can choose between. Both are 32 bytes wide, so
--- a group costs the same registers either way and only the lane count differs.
-- Declared in `nupp.compiler.aot.lane`, which is where this backend is going.
-- Keeping a second copy here is how the two would disagree about what a gang is.
local SHAPES = lane.SHAPES

local SHAPE_BY_NAME = {}
for _, entry in ipairs(SHAPES) do SHAPE_BY_NAME[entry.name] = entry end

-- The lane rewrite lives in `nupp.compiler.aot.rewrite`.
local function vectorizeLoop(ir, reject, shape)
   return rewriteRules.loop(ir, shape, function(message) reject(nil, message) end)
end

-- The rules live in `nupp.compiler.aot.verify`, against the typed vocabulary.
-- This spike hands one over and keeps nothing of its own: what makes IR well
-- formed is compiler policy, not a property of a test-only front end.
local verifyIR = irVerify.program

compiler.verifyIR = verifyIR

-- The readable form lives in `nupp.compiler.aot.text`.
local irLines = irText.program

-- Lane and scalar rendering both live in `nupp.compiler.aot.emit`.
local renderExpr = emitRules.lane

local cType = emitRules.cType

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
      -- Try the shapes widest lane count first. The 32-bit gang refuses the
      -- moment any varying value turns out to be binary64, so a loop written
      -- with ordinary operators lands on f64x4 exactly as it did before, and a
      -- loop whose values the source established as float or int32 gets twice
      -- the lanes for the same registers. The pass builds fresh IR and touches
      -- nothing else, so a declined attempt costs a retry and no state.
      --
      -- Only the last shape's refusals are reported. A loop that cannot lower
      -- at all cannot lower in any width, and the binary64 refusal is the one
      -- that names the construct rather than the width.
      local refusals
      for position = #SHAPES, 1, -1 do
         local attempted, lanes = {}, nil
         local ok, problem = pcall(function()
            lanes = vectorizeLoop(ir, function(_, message)
               attempted[#attempted + 1] = diagnostic(filename, ir.loop.source, message)
               error(STOP, 0)
            end, SHAPES[position])
         end)
         if ok then ir.lanes = lanes break end
         if problem ~= STOP then error(problem, 0) end
         if os.getenv("NUPP_SPIKE_SHAPES") then
            for _, refusal in ipairs(attempted) do
               io.stderr:write("shape ", SHAPES[position].name, ": ",
                  renderDiagnostic(refusal), "\n")
            end
         end
         refusals = attempted
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
