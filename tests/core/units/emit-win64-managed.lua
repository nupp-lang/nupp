-- Emit the fixed Win64 services from the reviewed startup snapshot.
-- Run from the checkout root with NUPP_COMPILER_ROOT naming the staged sources.
local nativegraph = require("nupp.compiler.s0.nativegraph")
local json = require("serde.json")
local out = assert(arg[1], "output directory required")
local generated = nativegraph.emitWin64Startup()
local count = 0
for _ in pairs(generated.entries) do
    count = count + 1
end
assert(count == 12, "Win64 startup entry count changed")
assert(#generated.imports == 20, "Win64 startup import count changed")
local detach = {nupp_http_scope_detach = false, nuppnetdetach = false}
for _, import in ipairs(generated.imports) do
    local name = import.name:match("[^%z]+$")
    if detach[name] ~= nil then
        detach[name] = true
    end
end
assert(detach.nupp_http_scope_detach and detach.nuppnetdetach, "Win64 startup is missing a scope detach import")

local function write(file, text)
    local output = assert(io.open(out .. "/" .. file, "wb"))
    assert(output:write(text))
    assert(output:close())
end

write("services.s", generated.assembly)
write("links.json", json.encodevalue({entries = generated.entries, imports = generated.imports}))
print(("emitted %d Win64 startup entries and %d external imports"):format(count, #generated.imports))
