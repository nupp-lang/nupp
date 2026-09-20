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
for index, request in ipairs(requests) do
    local response
    if request.kind == "hover" then
        response = session:hover(request.offset)
    else
        local options = request.options or {}
        options.dialect = options.dialect or "luajit"
        response = session[request.kind](session, request.source, request.filename, options)
    end
    if request.expect then
        local codes, seen = {}, {}
        for _, diagnostic in ipairs(response.diagnostics or {}) do
            if diagnostic.severity == nil or diagnostic.severity == "error" then
                if not seen[diagnostic.code] then
                    seen[diagnostic.code] = true
                    codes[#codes + 1] = diagnostic.code
                end
            end
        end
        table.sort(codes)
        local wanted = request.expect.errorCodes
        table.sort(wanted)
        local label = ("request %d (%s)"):format(index, request.filename or request.kind)
        assert(
            table.concat(codes, ",") == table.concat(wanted, ","),
            label .. ": expected error codes " .. encode(wanted) .. ", got " .. encode(codes)
        )
        if request.expect.generatedCode then
            assert(type(response.code) == "string" and response.code:match("%S"), label .. ": expected generated code")
        end
    end
    expected[#expected + 1] = response
end
local bytecode = string.dump(assert(loadfile(bundle, "tW")), "sd")
assert(#bytecode <= 7 * 1024 * 1024, "compiler exceeds startup mailbox")
write("compiler.ljbc", bytecode)
write("compiler-requests.json", fixture)
local json = require("nupp.runtime.provider.lunajson")
write("compiler-expected.json", json.encode(json.asArray(expected)))
