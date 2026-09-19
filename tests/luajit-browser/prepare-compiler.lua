-- Run from the repository root with the pinned LuaJIT after prelude-image luajit.
local bundle, destination = assert(arg[1]), assert(arg[2])

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = assert(file:read("*a"))
    assert(file:close())
    return value
end

local function write(name, value)
    local file = assert(io.open(destination .. "/" .. name, "wb"))
    assert(file:write(value))
    assert(file:close())
end

local decode = dofile("src/nupp/runtime/vendor/lunajson/decoder.lua")()
local encode = dofile("src/nupp/runtime/vendor/lunajson/encoder.lua")()
local fixture = read("tests/luajit-browser/compiler-requests.json")
local requests = decode(fixture)
local Browser = assert(loadfile(bundle))()
local session = Browser.new()
local expected = {}
for _, request in ipairs(requests) do
    if request.kind == "hover" then
        expected[#expected + 1] = session:hover(request.offset)
    else
        local options = request.options or {}
        options.dialect = options.dialect or "luajit"
        expected[#expected + 1] = session[request.kind](session, request.source, request.filename, options)
    end
end
local bytecode = string.dump(assert(loadfile(bundle, "tW")), "sd")
assert(#bytecode <= 7 * 1024 * 1024, "compiler exceeds startup mailbox")
write("compiler.ljbc", bytecode)
write("compiler-requests.json", fixture)
write("compiler-expected.json", encode(expected))
