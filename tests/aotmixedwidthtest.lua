local M = {}
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"));
    HERE = pipe:read("*l") .. "/" .. HERE;
    pipe:close()
end

local function write(path, value)
    local f = assert(io.open(path, "wb"));
    f:write(value);
    f:close()
end

local function read(path)
    local f = assert(io.open(path, "rb"));
    local value = f:read("*a");
    f:close();
    return value
end

function M.mapAndExplicitWidthsShareOneTranslationUnit()
    local dir = os.tmpname();
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir .. "/src")) == 0)
    write(
        dir .. "/src/mixed.nupp",
        [[
local span = require("nupp.mem.span")
local simd = require("nupp.simd")
local array = require("nupp.mem.array")
@aot
local function map(exclusive output: span.WriteSpan<number>, borrows input: span.Span<number>): nil
    assert(#output == #input)
    for i = 1, #input do output[i] = input[i] + 1 end
end
@aot
local function fixed(exclusive output: span.WriteSpan<int32>, borrows input: span.Span<int32>): nil
    local species = assert(simd.species(array.int32, 3))
    local value = species:load(input, 1, species:tail(#input))
    species:store(output, 1, value:reverse(), species:tail(#output))
end
return {map = map, fixed = fixed}
]]
    )
    write(
        dir .. "/nupp.lua",
        [[return {include={"src"}, build={targets={native={kind="modules",entries={"mixed"},outDir="build/native",aot="require"}}}}]]
    )
    local status = os.execute(
        ("cd %q && %q build --target native > %q 2>&1"):format(dir, HERE .. "/../bin/nupp", dir .. "/build.log")
    )
    assert(status == 0, dir .. ": " .. read(dir .. "/build.log"))
    write(
        dir .. "/run.lua",
        [[
package.path="build/native/?.lua;" .. package.path
local m, ffi, span = require("mixed"), require("ffi"), require("nupp.mem.span")
assert(__nuppAotCompiled[m.map] and __nuppAotCompiled[m.fixed])
for count = 0, 35 do
    local input, output = ffi.new("double[36]"), ffi.new("double[36]")
    for i=0,35 do input[i]=i*0.125; output[i]=-99 end
    m.map(span.writeCarray(output,count),span.fromCarray(input,count))
    for i=0,count-1 do assert(output[i]==input[i]+1) end
    for i=count,35 do assert(output[i]==-99) end
end
local input, output = ffi.new("int32_t[3]", {11,22,33}), ffi.new("int32_t[4]", {0,0,0,-99})
m.fixed(span.writeCarray(output,3),span.fromCarray(input,3))
assert(output[0]==33 and output[1]==22 and output[2]==11 and output[3]==-99)
]]
    )
    status = os.execute(("cd %q && luajit run.lua > %q 2>&1"):format(dir, dir .. "/run.log"))
    assert(status == 0, dir .. ": " .. read(dir .. "/run.log"))
end

return M
