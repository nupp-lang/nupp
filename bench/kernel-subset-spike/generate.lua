-- Compile one Nupp `@kernel` source file into the spike's private artifacts.

local here = assert(debug.getinfo(1, "S").source:match("^@(.*[/\\])"))
local compiler = dofile(here .. "kernel_compiler.lua")
local input = assert(arg[1], "usage: generate.lua INPUT.nupp OUTPUT_DIR")
local output = assert(arg[2], "usage: generate.lua INPUT.nupp OUTPUT_DIR")

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

local artifacts, diagnostics = compiler.compile(read(input), input)
if not artifacts then
   for _, problem in ipairs(diagnostics) do
      io.stderr:write(compiler.renderDiagnostic(problem), "\n")
   end
   os.exit(1)
end

write(output .. "/kernel.ir", artifacts.irText)
write(output .. "/kernel.c", artifacts.c)
write(output .. "/checked.nupp", artifacts.binding)
