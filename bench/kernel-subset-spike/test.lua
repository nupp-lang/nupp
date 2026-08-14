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
assert(first.irText == second.irText, "equivalent input produced different native IR")
assert(first.c == second.c, "equivalent input produced different C")
assert(first.binding == second.binding, "equivalent input produced different checked bindings")

assert(first.irText:find("native-c-ir 2", 1, true), "IR version was not widened")
assert(first.irText:find("disjoint r0 r1 proof(exclusive_borrow)", 1, true),
   "IR lost output/output disjointness")
assert(first.irText:find("may_alias r2 r3 proof(shared_borrows)", 1, true),
   "IR incorrectly made shared inputs disjoint")
assert(first.irText:find("clamp -> f64", 1, true), "IR lost the pure helper")
assert(first.irText:find("let mixed:f64", 1, true), "IR lost the scalar local")
assert(first.irText:find("math.sqrt", 1, true), "IR lost the math intrinsic")
assert(first.irText:find("store output[i]", 1, true), "IR lost the first output")
assert(first.irText:find("store magnitude[i]", 1, true), "IR lost the second output")
assert(first.irText:find("if lt(", 1, true), "IR lost structured control flow")

assert(first.c:find("float *restrict p_output", 1, true), "C lost the first output restrict")
assert(first.c:find("float *restrict p_magnitude", 1, true), "C lost the second output restrict")
assert(not first.c:find("const float *restrict p_left", 1, true), "C restricted a shared input")
assert(first.c:find("ks_transform_helper_clamp", 1, true), "C lost the static helper")
assert(first.c:find("sqrt(v1_mixed)", 1, true), "C lost the math call")
assert(first.c:find("ks_transform_forced_scalar", 1, true), "C lost the scalar oracle")
local autoStart = assert(first.c:find("void ks_transform(", 1, true))
assert(not first.c:sub(autoStart):find("vectorize(disable)", 1, true),
   "the optimized C implementation disables vectorization")

do
   local renamed = assert(source:gsub("transform", "processRows"))
   local result = assert(compiler.compile(renamed, "renamed.nupp"))
   assert(result.ir.symbol == "ks_process_rows", "private symbol depends on the example name")
   assert(result.binding:find("processRows = ks_process_rows", 1, true),
      "renamed checked binding was not emitted")
end

do
   local fact = table.remove(first.ir.aliasFacts, 1)
   local ok, problem = pcall(compiler.verifyIR, first.ir)
   table.insert(first.ir.aliasFacts, 1, fact)
   assert(not ok and tostring(problem):find("alias matrix", 1, true),
      "IR verifier accepted an incomplete alias matrix")
end

local function rejected(label, changed, expected)
   local artifacts, diagnostics = compiler.compile(changed, label .. ".nupp")
   assert(not artifacts, label .. " unexpectedly compiled")
   assert(#diagnostics == 1, label .. " did not produce one source-local diagnostic")
   local rendered = compiler.renderDiagnostic(diagnostics[1])
   assert(rendered:find(expected, 1, true), rendered)
   assert(rendered:find(label .. ".nupp:", 1, true) == 1, rendered)
end

rejected(
   "unsupported-type",
   assert(source:gsub("scale: float", "scale: string", 1)),
   "parameter type string is not admitted"
)
rejected(
   "offset-load",
   assert(source:gsub("left:get%(i%)", "left:get(i + 1)", 1)),
   "span loads must use the active loop index exactly"
)
rejected(
   "dynamic-call",
   assert(source:gsub("math.sqrt%(mixed%)", "math.sin(mixed)", 1)),
   "not an admitted intrinsic or helper"
)
rejected(
   "allocation",
   assert(source:gsub(
      "local mixed = clamp%(left:get%(i%) %+ right:get%(i%) %* scale, limit%)",
      "local mixed = {limit}",
      1
   )),
   "expression kind tableExpr is not admitted"
)
rejected(
   "assignment",
   assert(source:gsub("output:set%(i, mixed%)", "mixed = mixed + 1", 1)),
   "statement kind assignStmt is not admitted"
)
rejected(
   "recursive-helper",
   assert(source:gsub(
      "return math.max%(%-limit, math.min%(value, limit%)%)",
      "return clamp(value, limit)",
      1
   )),
   "recursive native helpers are not admitted"
)
rejected(
   "missing-kernel",
   assert(source:gsub("@kernel", "@ordinary", 1)),
   "no @kernel function was found"
)

io.write("native C subset validation: passed\n")
