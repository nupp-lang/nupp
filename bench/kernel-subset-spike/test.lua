-- Structural and rejection tests for the test-only native-C compiler.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local compiler = dofile(here .. "kernel_compiler.lua")

local function read(path)
   local file = assert(io.open(path, "rb"))
   local value = assert(file:read("*a"))
   assert(file:close())
   return value
end

local source = read(here .. "kernels.nupp")
local first, problems = compiler.compile(source, "kernels.nupp")
assert(first, problems[1] and compiler.renderDiagnostic(problems[1]))
local second = assert(compiler.compile(source, "kernels.nupp"))
assert(first.irText == second.irText, "equivalent input produced different AOT IR")
assert(first.c == second.c, "equivalent input produced different C")
assert(first.binding == second.binding, "equivalent input produced different checked bindings")

-- The header carries the version the compiler stamps, whatever that is today.
-- A literal here named revision 3 and sat failing through seven more, because
-- nothing bumps it and nothing reads it: the only thing this can usefully claim
-- is that the text and the compiler agree on one number.
local scalarIR = require("nupp.compiler.aot.scalar")
assert(first.irText:find("native-c-ir " .. tostring(scalarIR.VERSION), 1, true),
   "IR text does not carry the version the compiler stamps")
-- What each field is stored as, whatever else the layout line has since learned
-- to say about where that storage came from.
assert(first.irText:match("Transform2D{x:f32[^,]*,y:f32"), "IR lost the struct layout")
assert(first.irText:find("write_span transforms:struct:Transform2D", 1, true), "IR lost struct storage")
assert(first.irText:find("readwrite", 1, true), "writable span is not readable")
assert(first.irText:find("disjoint r0 r1 proof(exclusive_borrow)", 1, true), "IR lost disjointness")
assert(first.irText:find("range first last count(transforms)", 1, true), "IR lost ranged iteration")
assert(first.irText:find("scalePair -> f64,f64", 1, true), "IR lost multiple helper results")
assert(first.irText:find("let dx:f64,dy:f64", 1, true), "IR lost multiple local binding")
assert(first.irText:find("set nextX", 1, true), "IR lost mutable locals")
assert(first.irText:find("set local:ref:Transform2D transform.x", 1, true), "IR lost field stores")
assert(first.irText:find("math.sqrt", 1, true), "IR lost closed math")
assert(first.irText:find("band(", 1, true), "IR lost integer bit operations")
assert(first.irText:find("lshift(", 1, true), "IR lost shifts")

assert(first.c:find("KsTransform2D *restrict p_transforms", 1, true), "C lost output restrict")
assert(first.c:find("const KsMotion *p_motions", 1, true), "C lost const input")
assert(first.c:find("offsetof(KsTransform2D, flags)", 1, true), "C lost layout evidence")
assert(first.c:find("ks_advance_helper_scale_pair_result", 1, true), "C lost result struct")
assert(first.c:find("sqrt(", 1, true), "C lost the math call")
assert(first.c:find("ks_advance_forced_scalar", 1, true), "C lost the scalar oracle")
local autoStart = assert(first.c:find("void ks_advance(", 1, true))
assert(not first.c:sub(autoStart):find("vectorize(disable)", 1, true), "optimized C disables vectorization")

assert(first.binding:find("layoutof(Transform2D)", 1, true), "binding does not verify layout")
-- A span reaches the private ABI as a pointer to its element type, and a shared
-- one keeps `const`. This used to assert the reverse -- that every span was
-- erased to `voidptr` -- which is exactly what stopped being true, because
-- erasing them asks the LuaJIT FFI to discard const at the call.
assert(first.binding:find("exclusive transforms: Transform2D*", 1, true),
   "writable span lost its element pointer type")
assert(first.binding:find("borrows motions: const Motion*", 1, true),
   "shared span lost const on the way to the private ABI")
assert(first.binding:find("transforms:ref()", 1, true), "wrapper lost span projection")
assert(first.binding:find("first < 1 or last > #transforms", 1, true), "wrapper lost range check")

do
   local renamed = assert(source:gsub("advance", "processRows"))
   local result = assert(compiler.compile(renamed, "renamed.nupp"))
   assert(result.ir.symbol == "ks_process_rows", "private symbol depends on example name")
   assert(result.binding:find("processRows = processRows", 1, true), "renamed wrapper was not emitted")
end

do
   local fact = table.remove(first.ir.aliasFacts, 1)
   local ok, problem = pcall(compiler.verifyIR, first.ir)
   table.insert(first.ir.aliasFacts, 1, fact)
   assert(not ok and tostring(problem):find("alias matrix", 1, true), "IR accepted an incomplete alias matrix")
end

local laneSource = read(here .. "lanedemo.nupp")
local lane = assert(compiler.compile(laneSource, "lanedemo.nupp"))
assert(lane.irText:find("uniform dt:f32", 1, true),
   "refined float parameter lost its established private ABI")
assert(lane.irText:find("simd lanes(4)", 1, true), "SIMD contract produced no lane IR")
assert(lane.irText:find("let step:f64", 1, true),
   "uniform local disappeared from lane IR")
assert(lane.irText:find("let $if", 1, true),
   "lane branch did not capture its mask before mutating condition state")
assert(lane.c:find("size_t groups", 1, true), "lane C lost its whole-group loop")
assert(lane.c:find("for (; i < end; ++i)", 1, true), "lane C lost its scalar epilogue")
assert(not lane.c:find("ks_f32x8", 1, true), "removed explicit-vector path remains in C")

do
   local target
   for _, statement in ipairs(lane.ir.lanes.statements) do
      if statement.op == "vassign" then
         for _, assignment in ipairs(statement.values) do
            if assignment.target.kind == "vfield" then
               target = assignment.target
               break
            end
         end
      end
      if target then break end
   end
   assert(target, "lane fixture contains no field store")
   local span = target.span
   target.span = "source"
   local ok, problem = pcall(compiler.verifyIR, lane.ir)
   target.span = span
   assert(not ok and tostring(problem):find("lane field assignment", 1, true),
      "IR accepted a lane store through a shared span")
end

local function rejected(label, changed, expected)
   local artifacts, diagnostics = compiler.compile(changed, label .. ".nupp")
   assert(not artifacts, label .. " unexpectedly compiled")
   assert(#diagnostics == 1, label .. " did not produce one source-local diagnostic")
   local rendered = compiler.renderDiagnostic(diagnostics[1])
   assert(rendered:find(expected, 1, true), rendered)
   assert(rendered:find(label .. ".nupp:", 1, true) == 1, rendered)
end

rejected("unsupported-field", assert(source:gsub("drag: float", "drag: string", 1)), "field type string is not admitted")
rejected("offset-load", assert(source:gsub("motions%[i%]", "motions[i + 1]", 1)), "counted-loop index")
rejected("dynamic-call", assert(source:gsub("math.sqrt%(dx %* dx %+ dy %* dy%)", "math.random()", 1)), "not an admitted intrinsic or helper")
rejected("shared-output", assert(source:gsub("exclusive transforms", "borrows transforms", 1)), "must be declared exclusive")
-- Allocating where a number belongs. This used to be refused as `tableExpr is
-- not admitted`, by the catch-all every unhandled expression kind fell to; a
-- table is a lowered expression now, so what refuses this is the arithmetic that
-- reads it. The refusal still lands on the source line, which is what this case
-- is here to hold.
rejected("allocation", assert(source:gsub("local nextX = transform.x %+ dx", "local nextX = {dx}", 1)), "arithmetic operands must both be numeric")
-- An allocation nothing reads, which the arithmetic above cannot catch. This is
-- the case that reached the IR verifier and raised `Lua allocation outside a
-- builder`, an uncaught error carrying no source, until a counted native loop
-- learned to refuse a Lua value where it is written.
rejected(
   "unread-allocation",
   assert(source:gsub("local damping = math%.max%(0, 1 %- motion%.drag %* dt%)",
      "local scratch = {dx}\n        local damping = math.max(0, 1 - motion.drag * dt)", 1)),
   "not admitted in a counted native loop"
)
rejected(
   "recursive-helper",
   assert(source:gsub("return x %* scale, y %* scale", "return scalePair(x, y, scale), y", 1)),
   "recursive native helpers are not admitted"
)
rejected("missing-kernel", assert(source:gsub("@aot", "@ordinary", 1)), "no @aot function was found")
do
   local changed = assert(laneSource:gsub(
      "nextY < 0%.0", "nextY < 0.0 and from.x > 0.0", 1
   ))
   local short = assert(compiler.compile(changed, "lane-short-circuit.nupp"))
   assert(short.irText:find("vshort_and", 1, true),
      "pure short-circuit expression lost its verified mask operation")
   local function findShort(node)
      if type(node) ~= "table" then return nil end
      if node.op == "vshort" and node.verb == "and" then return node end
      for _, value in pairs(node) do
         local found = findShort(value)
         if found then return found end
      end
   end
   local operation = assert(findShort(short.ir.lanes), "short-circuit IR node is missing")
   operation.effect = nil
   local ok, problem = pcall(compiler.verifyIR, short.ir)
   operation.effect = "pure_total"
   assert(not ok and tostring(problem):find("effect proof", 1, true),
      "IR accepted eager short-circuiting without its effect proof")
end

do
   local mandelbrotSource = read(here .. "mandelbrot.nupp")
   local mandelbrot = assert(compiler.compile(mandelbrotSource, "mandelbrot.nupp"))
   assert(mandelbrot.irText:find("vwhile any", 1, true),
      "varying inner loop did not become a live-mask loop")
   assert(mandelbrot.irText:find("vbreak", 1, true),
      "varying break did not retire lanes")
   assert(mandelbrot.irText:find("vbreak exit-if-empty", 1, true),
      "profitable lane retirement did not receive the loop liveness test")
   local laneLoopStart = assert(mandelbrot.irText:find("vwhile any", 1, true))
   local laneLoopEnd = assert(mandelbrot.irText:find("\n  end", laneLoopStart, true))
   assert(not mandelbrot.irText:sub(laneLoopStart, laneLoopEnd):find("vset escaped", 1, true),
      "break result remains loop-carried")
   assert(mandelbrot.irText:sub(laneLoopEnd):find(
      "vset escaped = vselect", 1, true
   ), "break result was not derived once after the loop")
   assert(mandelbrot.irText:find("escapes[i..i+3].iterations", 1, true),
      "integer field store lost its lane narrowing")
   -- Named for the mask it tests, so a file holding two gangs gets one of these
   -- per gang rather than two definitions of the same name.
   assert(mandelbrot.c:find("if (ks_any_m64x4(", 1, true)
      and mandelbrot.c:find("while (true)", 1, true)
      and mandelbrot.c:find("if (!ks_any_m64x4(", 1, true),
      "generated C did not move horizontal termination behind retirement")
   assert(mandelbrot.c:find("vmaxvq_u32", 1, true),
      "AArch64 mask-any helper lost its native horizontal reduction")
   assert(mandelbrot.c:find("vld2q_f32", 1, true),
      "adjacent two-field AoS loads did not become a Neon deinterleave")
   assert(mandelbrot.c:find("p_points[i + 0].re", 1, true),
      "AoS deinterleave lost its portable gather fallback")

   local laneLoop
   for _, statement in ipairs(mandelbrot.ir.lanes.statements) do
      if statement.op == "vwhile" then laneLoop = statement break end
   end
   assert(laneLoop, "Mandelbrot lane IR contains no verified loop")
   local conditionType = laneLoop.condition.type
   laneLoop.condition.type = "f64x4"
   local ok, problem = pcall(compiler.verifyIR, mandelbrot.ir)
   laneLoop.condition.type = conditionType
   assert(not ok and tostring(problem):find("invalid lane", 1, true),
      "IR accepted a non-mask lane-loop condition")

   local branchDead = assert(mandelbrotSource:gsub(
      "escaped = 1\n                break",
      "zx = 123.0\n                escaped = 1\n                break",
      1
   ))
   local branchDeadResult = assert(compiler.compile(branchDead, "lane-branch-dead.nupp"))
   assert(branchDeadResult.irText:find("vset zx = vselect", 1, true),
      "dead-state speculation escaped its controlling branch mask")

   local continued = assert(mandelbrotSource:gsub(
      "escaped = 1\n                break",
      "escaped = 1\n                iteration = maxIterations\n                continue",
      1
   ))
   local continuedResult = assert(compiler.compile(continued, "lane-continue.nupp"))
   assert(continuedResult.irText:find("vcontinue", 1, true),
      "varying continue did not mask the rest of its iteration")
   assert(continuedResult.irText:find(
      "vmand:m64x4(local:m64x4 $if", 1, true
   ), "statements after a lane exit lost the current executing mask")
   assert(not continuedResult.irText:find("exit-if-empty", 1, true),
      "a loop with continue unsafely moved its horizontal liveness test")

   local laneContinue
   for _, statement in ipairs(continuedResult.ir.lanes.statements) do
      if statement.op == "vwhile" then
         for _, inner in ipairs(statement.body) do
            if inner.op == "vcontinue" then laneContinue = inner break end
         end
      end
      if laneContinue then break end
   end
   assert(laneContinue, "continued fixture contains no lane continue")
   laneContinue.exitWhenEmpty = true
   local continueOk, continueProblem = pcall(compiler.verifyIR, continuedResult.ir)
   laneContinue.exitWhenEmpty = nil
   assert(not continueOk and tostring(continueProblem):find("immediate lane%-loop exit"),
      "IR accepted an immediate empty-loop exit on continue")
end

local unaryMath = {"abs", "floor", "ceil", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "exp", "log", "deg", "rad"}
for _, name in ipairs(unaryMath) do
   local changed = assert(source:gsub("math.sqrt%(dx %* dx %+ dy %* dy%)", "math." .. name .. "(dx)", 1))
   assert(compiler.compile(changed, "math-" .. name .. ".nupp"), "closed math intrinsic " .. name .. " was rejected")
end
for _, name in ipairs({"atan2", "pow", "fmod"}) do
   local changed = assert(source:gsub("math.sqrt%(dx %* dx %+ dy %* dy%)", "math." .. name .. "(dx, dy)", 1))
   assert(compiler.compile(changed, "math-" .. name .. ".nupp"), "closed math intrinsic " .. name .. " was rejected")
end

io.write("native C Tecs subset validation: passed\n")
