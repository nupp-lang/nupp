-- Emit a checked Win64 leaf without executing target code. Run from this
-- project with ../../../bin/nupp run emit-win64-leaf.lua OUTPUT.
local builder = require("nupp.core.win64leaf")
local root = assert(os.getenv("NUPP_COMPILER_ROOT"))
local module = "nupp.core.win64leafunits"
local path = root .. "/tests/core/units/nupp/core/win64leafunits.nupp"
local include = {"tests/core/units"}

local bundle = builder.build(root, include, module, path, "choose")
local rejected, message = pcall(builder.build, root, include, module, path, "unsupported")
assert(not rejected and tostring(message):find("unsupported operation imul", 1, true), tostring(message))
assert(bundle:sub(1, 8) == "NUPPCORE")

local function word(index)
    local value = 0
    for byte = 0, 7 do
        value = value | (bundle:byte(9 + index * 8 + byte) << (byte * 8))
    end

    return value
end

local bytes = word(3)
assert(word(0) == 1 and word(1) == 2 and word(2) == 0)
assert(word(4) == 0 and word(5) == 0 and word(6) == 1 and word(7) == 0)
assert(bytes == #bundle - 72)

local output = assert(io.open(assert(arg[1], "output path required"), "wb"))
assert(output:write(bundle))
assert(output:close())
print(("checked Win64 leaf: %d code bytes"):format(bytes))
