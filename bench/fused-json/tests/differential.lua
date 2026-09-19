-- Run the repository's independent JSON and first-error corpus against the
-- compiled benchmark decoder, including every byte offset across vector tails.
local module = "nupp.codec.json.internal.decoder.fusedbench"
local fused = require(module)
local registered = assert(rawget(_G, "__nuppAotCompiled"), "compiled-entry registry missing")
local artifact = assert(package.searchpath(module, package.path))
local reached = false
local wasEnabled = jit.status()
jit.off()
debug.sethook(
    function()
        local frame = debug.getinfo(2, "fS")
        reached = reached or (frame and registered[frame.func] and frame.source == "@" .. artifact)
    end,
    "c"
)
local value, status = fused.decodeEager('["native proof",123]', nil, {}, {})
debug.sethook()
if wasEnabled then
    jit.on()
end
assert(status == 0 and value[1] == "native proof" and value[2] == 123, "native proof decode failed")
assert(reached, "the decoder under test did not execute compiled code")
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
