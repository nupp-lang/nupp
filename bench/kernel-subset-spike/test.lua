-- Structural and rejection tests for the test-only `@kernel` compiler.

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
assert(first.irText == second.irText, "equivalent input produced different kernel IR")
assert(first.c == second.c, "equivalent input produced different C")
assert(first.binding == second.binding, "equivalent input produced different checked bindings")
assert(first.irText:find("load:f32 left[i]", 1, true), "IR lost the left load")
assert(first.irText:find("widen_f32_f64", 1, true), "IR lost ordinary Nupp widening")
assert(first.irText:find("mul:f64", 1, true), "IR lost binary64 multiplication")
assert(first.irText:find("disjoint r0 r1 proof(exclusive_borrow)", 1, true),
   "IR lost output/input disjointness")
assert(first.irText:find("may_alias r1 r2 proof(shared_borrows)", 1, true),
   "IR incorrectly made shared inputs disjoint")
assert(first.c:find("float *restrict output", 1, true), "C lost output restrict")
assert(not first.c:find("const float *restrict left", 1, true), "C restricted a shared input")
assert(not first.c:find("const float *restrict right", 1, true), "C restricted a shared input")
assert(first.c:find("vaddq_f64", 1, true), "NEON lowering lost vector addition")
assert(first.c:find("_mm256_mul_pd", 1, true), "AVX2 lowering lost vector multiplication")
assert(first.c:find("ks_scale_add_forced_scalar", 1, true), "C lost the forced-scalar baseline")
assert(first.c:find("ks_scale_add_auto", 1, true), "C lost the auto-vectorized baseline")
local autoStart = assert(first.c:find("void ks_scale_add_auto(", 1, true))
local vectorStart = assert(first.c:find("#if defined(__aarch64__)", autoStart, true))
local autoBody = first.c:sub(autoStart, vectorStart - 1)
assert(not autoBody:find("vectorize(disable)", 1, true),
   "the auto-vectorized baseline still disables vectorization")

do
   local renamed = assert(source:gsub("scaleAdd", "blendRows"))
   local result = assert(compiler.compile(renamed, "renamed.nupp"))
   assert(result.ir.symbol == "ks_blend_rows", "private symbol still depends on the spike workload")
   assert(result.c:find("void ks_blend_rows(", 1, true), "renamed C symbol was not emitted")
   assert(result.binding:find("blendRows = ks_blend_rows", 1, true),
      "renamed checked binding was not emitted")
end

do
   local fact = table.remove(first.ir.aliasFacts, 1)
   local ok, problem = pcall(compiler.verifyIR, first.ir)
   table.insert(first.ir.aliasFacts, 1, fact)
   assert(not ok and tostring(problem):find("alias relationship", 1, true),
      "IR verifier accepted a missing disjointness fact")
end

local function rejected(label, changed, expected)
   local artifacts, diagnostics = compiler.compile(changed, label .. ".nupp")
   assert(not artifacts, label .. " unexpectedly compiled")
   assert(#diagnostics == 1, label .. " did not produce one source-local diagnostic")
   local rendered = compiler.renderDiagnostic(diagnostics[1])
   assert(rendered:find(expected, 1, true), rendered)
   assert(rendered:find(label .. ".nupp:", 1, true) == 1, rendered)
   assert(rendered:find(": kernel subset:", 1, true), rendered)
end

rejected(
   "unsupported-type",
   assert(source:gsub("scale: float", "scale: string", 1)),
   "parameter type string is not admitted"
)
rejected(
   "offset-load",
   assert(source:gsub("left:get%(i%)", "left:get(i + 1)", 1)),
   "span loads must use the loop index exactly"
)
rejected(
   "dynamic-call",
   assert(source:gsub("right:get%(i%) %* scale", "math.sin(scale)", 1)),
   "expression kind call is not admitted"
)
rejected(
   "allocation",
   assert(source:gsub(
      "output:set%(i, left:get%(i%) %+ right:get%(i%) %* scale%)",
      "local values = {scale}",
      1
   )),
   "loop body must be one output:set(index, value) call"
)
rejected(
   "missing-kernel",
   assert(source:gsub("@kernel", "@ordinary", 1)),
   "no @kernel function was found"
)

io.write("kernel subset validation: passed\n")
