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

assert(first.irText:find("native-c-ir 3", 1, true), "IR version was not widened")
assert(first.irText:find("Transform2D{x:f32,y:f32", 1, true), "IR lost the struct layout")
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
assert(first.binding:find("exclusive transforms: voidptr", 1, true), "private ABI did not erase pointer spelling")
assert(first.binding:find("transforms:ref()", 1, true), "wrapper lost span projection")
assert(first.binding:find("first < 1 or last > transforms.count", 1, true), "wrapper lost range check")

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
rejected("offset-load", assert(source:gsub("motions:get%(i%)", "motions:get(i + 1)", 1)), "active loop index exactly")
rejected("dynamic-call", assert(source:gsub("math.sqrt%(dx %* dx %+ dy %* dy%)", "math.random()", 1)), "not an admitted intrinsic or helper")
rejected("mutable-value-get", assert(source:gsub("transforms:getMut%(i%)", "transforms:get(i)", 1)), "span reads use")
rejected("allocation", assert(source:gsub("local nextX = transform.x %+ dx", "local nextX = {dx}", 1)), "tableExpr is not admitted")
rejected(
   "recursive-helper",
   assert(source:gsub("return x %* scale, y %* scale", "return scalePair(x, y, scale), y", 1)),
   "recursive native helpers are not admitted"
)
rejected("missing-kernel", assert(source:gsub("@aot", "@ordinary", 1)), "no @aot function was found")
rejected(
   "lane-short-circuit",
   assert(laneSource:gsub("nextY < 0%.0", "nextY < 0.0 and from.x > 0.0", 1)),
   "mask-aware short-circuit"
)

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
