-- Emit the deliberately narrow GPU subset from Nupp's verified scalar AOT IR.

local parser = require("nupp.compiler.parser")
local check = require("nupp.compiler.check")
local env = require("nupp.compiler.env")
local compile = require("nupp.compiler.aot.compile")

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local root = here .. "../.."
local input = assert(arg[1], "usage: generate-msl.lua INPUT.nupp OUTPUT.msl")
local output = assert(arg[2], "usage: generate-msl.lua INPUT.nupp OUTPUT.msl")

local function read(path)
   local file = assert(io.open(path, "rb"))
   local value = assert(file:read("*a"))
   assert(file:close())
   return value
end

local function write(path, value)
   local file = assert(io.open(path, "wb"))
   assert(file:write(value))
   assert(file:close())
end

local function identifier(value)
   return value:gsub("[^%w_]", "_")
end

local source = read(input)
local parsed = parser.parse(source, input)
local diagnostics = check.check(parsed, input, env.new(root))
if #diagnostics > 0 then
   for _, problem in ipairs(diagnostics) do
      io.stderr:write(problem.code or "error", ": ", problem.message, "\n")
   end
   os.exit(1)
end

local programs, refusals = compile.lower(source, input, parsed)
if #refusals > 0 then
   for _, problem in ipairs(refusals) do
      io.stderr:write(compile.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end
assert(#programs == 1, "the spike accepts exactly one @aot function")
local program = programs[1]
assert(program.entryMode == "kernel" and program.loop, "GPU entry must be a map kernel")
assert(program.loop.first == 1 and program.loop.last == program.loop.count,
   "the spike currently dispatches a whole span")

local types = {f32 = "float", i32 = "int", u32 = "uint", bool = "bool"}
local function metalType(value)
   local layout = value:match("^struct:(.+)$")
   return layout or types[value]
end
local binary = {
   add = "+", sub = "-", mul = "*", div = "/", mod = "%",
   lt = "<", le = "<=", gt = ">", ge = ">=", eq = "==", ne = "!=",
   ["and"] = "&&", ["or"] = "||", band = "&", bor = "|", bxor = "^",
   lshift = "<<", rshift = ">>", arshift = ">>",
}
local fixed = {
   f32_add = "+", f32_sub = "-", f32_mul = "*", f32_div = "/",
   i32_add = "+", i32_sub = "-", i32_mul = "*",
   u32_add = "+", u32_sub = "-", u32_mul = "*",
   u32_and = "&", u32_or = "|", u32_xor = "^", u32_shl = "<<", u32_shr = ">>",
}

local expression
expression = function(value)
   local op = value.op
   if op == "local" or op == "helper_param" then
      return identifier(value.cName or value.name)
   elseif op == "uniform" then
      return "uniforms." .. identifier(value.name)
   elseif op == "load" then
      assert(value.index == program.loop.index, "only the dispatch index may load a span")
      return identifier(value.span) .. "[dispatch_index]"
   elseif op == "element_ref" then
      assert(value.index == program.loop.index, "only the dispatch index may reference a span")
      return "&" .. identifier(value.span) .. "[dispatch_index]"
   elseif op == "field_load" then
      return "(" .. expression(value.object) .. ")->" .. identifier(value.field)
   elseif op == "constant" then
      return value.value
   elseif op == "constant_i32" then
      return value.value
   elseif op == "bool" then
      return value.value and "true" or "false"
   elseif fixed[op] or binary[op] then
      local token = fixed[op] or binary[op]
      return "(" .. expression(value.left) .. " " .. token .. " " .. expression(value.right) .. ")"
   elseif op == "neg" then
      return "(-" .. expression(value.value) .. ")"
   elseif op == "not" then
      return "(!" .. expression(value.value) .. ")"
   elseif op == "bnot" or op == "u32_not" then
      return "(~" .. expression(value.value) .. ")"
   elseif op == "narrow_f64_f32" then
      return "float(" .. expression(value.value) .. ")"
   elseif op == "widen_f32_f64" then
      -- Metal on Apple GPUs has no binary64 arithmetic. A widening that is
      -- immediately narrowed is harmless; standalone binary64 operations are
      -- rejected by the type checks below.
      return expression(value.value)
   elseif op == "numeric_cast" then
      return tostring(metalType(value.type)) .. "(" .. expression(value.value) .. ")"
   elseif op == "f32_sqrt" then
      return "sqrt(" .. expression(value.value) .. ")"
   end
   error("GPU subset does not emit expression " .. tostring(op), 0)
end

local lines = {}
local function line(depth, value)
   lines[#lines + 1] = string.rep("    ", depth) .. value
end

local statements
statements = function(values, depth)
   for _, statement in ipairs(values) do
      local op = statement.op
      if op == "let" then
         local reference = statement.type:match("^ref:(.+)$")
         if reference then
            assert(statement.value.op == "element_ref", "GPU references must point into spans")
            local qualifier = statement.value.mutable and "device " or "device const "
            line(depth, qualifier .. reference .. "* " .. identifier(statement.cName)
               .. " = " .. expression(statement.value) .. ";")
         else
            assert(metalType(statement.type), "GPU local must have fixed width: " .. statement.type)
            line(depth, metalType(statement.type) .. " " .. identifier(statement.cName)
               .. " = " .. expression(statement.value) .. ";")
         end
      elseif op == "assign" then
         assert(#statement.values == 1, "the spike does not yet emit parallel assignment")
         local assignment = statement.values[1]
         local target
         if assignment.target.kind == "local" then
            target = identifier(assignment.target.cName or assignment.target.name)
         elseif assignment.target.kind == "field" then
            target = "(" .. expression(assignment.target.object) .. ")->"
               .. identifier(assignment.target.field)
         else
            error("GPU subset does not emit assignment target "
               .. tostring(assignment.target.kind), 0)
         end
         line(depth, target .. " = " .. expression(assignment.value) .. ";")
      elseif op == "store" then
         assert(statement.index == program.loop.index, "only the dispatch index may store a span")
         line(depth, identifier(statement.span) .. "[dispatch_index] = "
            .. expression(statement.value) .. ";")
      elseif op == "while" then
         line(depth, "while (" .. expression(statement.condition) .. ") {")
         statements(statement.body, depth + 1)
         line(depth, "}")
      elseif op == "if" then
         for index, clause in ipairs(statement.clauses) do
            line(depth, (index == 1 and "if (" or "else if (")
               .. expression(clause.condition) .. ") {")
            statements(clause.body, depth + 1)
            line(depth, "}")
         end
         if statement.elseBody then
            line(depth, "else {")
            statements(statement.elseBody, depth + 1)
            line(depth, "}")
         end
      elseif op == "break" or op == "continue" then
         line(depth, op .. ";")
      elseif op == "block" then
         line(depth, "{")
         statements(statement.body, depth + 1)
         line(depth, "}")
      else
         error("GPU subset does not emit statement " .. tostring(op), 0)
      end
   end
end

local readonly, writable, uniforms = {}, {}, {}
for _, param in ipairs(program.params) do
   if param.kind == "read_span" then
      assert(metalType(param.type), "GPU span must have fixed-width elements")
      readonly[#readonly + 1] = param
   elseif param.kind == "write_span" then
      assert(metalType(param.type), "GPU span must have fixed-width elements")
      writable[#writable + 1] = param
   elseif param.kind == "uniform" then
      assert(metalType(param.type), "GPU uniform must have fixed width")
      uniforms[#uniforms + 1] = param
   else
      error("GPU subset does not admit scalar ABI parameters", 0)
   end
end

line(0, "#include <metal_stdlib>")
line(0, "using namespace metal;")
line(0, "#pragma clang fp contract(off)")
line(0, "")
for _, layout in ipairs(program.layouts or {}) do
   line(0, "struct " .. identifier(layout.name) .. " {")
   for _, field in ipairs(layout.fields) do
      assert(metalType(field.type), "GPU struct field must have fixed width")
      line(1, metalType(field.type) .. " " .. identifier(field.name) .. ";")
   end
   line(0, "};")
   line(0, "")
end
line(0, "struct NuppUniforms {")
line(1, "uint count;")
for _, param in ipairs(uniforms) do
   line(1, metalType(param.type) .. " " .. identifier(param.name) .. ";")
end
line(0, "};")
line(0, "")
line(0, "kernel void " .. identifier(program.symbol) .. "_gpu(")
local arguments = {"constant NuppUniforms& uniforms [[buffer(0)]]"}
local binding = 1
for _, param in ipairs(readonly) do
   arguments[#arguments + 1] = "device const " .. metalType(param.type) .. "* "
      .. identifier(param.name) .. " [[buffer(" .. binding .. ")]]"
   binding = binding + 1
end
for _, param in ipairs(writable) do
   arguments[#arguments + 1] = "device " .. metalType(param.type) .. "* "
      .. identifier(param.name) .. " [[buffer(" .. binding .. ")]]"
   binding = binding + 1
end
arguments[#arguments + 1] = "uint dispatch_index [[thread_position_in_grid]]"
for index, argument in ipairs(arguments) do
   line(1, argument .. (index < #arguments and "," or ""))
end
line(0, ") {")
line(1, "if (dispatch_index >= uniforms.count) return;")
statements(program.loop.statements, 1)
line(0, "}")

write(output, table.concat(lines, "\n") .. "\n")
io.write(("emitted %s from verified IR %d (%d read-only, %d writable, %d uniform)\n")
   :format(output, program.version, #readonly, #writable, #uniforms))
