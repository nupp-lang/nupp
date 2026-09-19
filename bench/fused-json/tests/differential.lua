-- Run the repository's independent JSON and first-error corpus against the
-- compiled benchmark decoder, including every byte offset across vector tails.
local module = "nupp.codec.json.internal.decoder.fusedbench"
local fused = require(module)
local reached, seen = false, {}
local registered = rawget(_G, "__nuppAotCompiled") or {}

local function inspect(fn)
    if seen[fn] then
        return
    end
    seen[fn] = true
    reached = reached or registered[fn] == true
    for index = 1, 64 do
        local name, value = debug.getupvalue(fn, index)
        if not name then
            break
        end
        if type(value) == "function" then
            inspect(value)
        end
    end
end

inspect(fused.decodeEager)
assert(reached, "the decoder under test has no compiled entry")
package.loaded["nupp.codec.json.internal.decoder.fused"] = fused
package.loaded["nupp.codec.json.aot"] = nil
local suite = dofile("../../tests/jsonfuseddifferentialtest.lua")
local names = {}
for name in pairs(suite) do
    names[#names + 1] = name
end
table.sort(names)
for _, name in ipairs(names) do
    suite[name]()
    print("passed " .. name)
end
print(("%d compiled decoder differential tests passed"):format(#names))
