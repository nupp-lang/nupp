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
assert(first.irText:find("mul:f32", 1, true), "IR lost multiplication")
assert(first.c:find("vaddq_f32", 1, true), "NEON lowering lost vector addition")
assert(first.c:find("_mm256_mul_ps", 1, true), "AVX2 lowering lost vector multiplication")

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
