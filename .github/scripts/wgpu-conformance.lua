-- Run the GPU provider cases directly on the verified compiler seed. Avoid
-- rebuilding the compiler project merely to run an isolated provider suite.
package.path = "tests/?.lua;tests/?/init.lua;" .. package.path
local memory = require("nupp.runtime.provider.wgpumemory")
local json = require("nupp.codec.json.provider")
local abiPath = assert(os.getenv("NUPP_WGPU_ABI"), "NUPP_WGPU_ABI is required")
local abiFile = assert(io.open(abiPath, "rb"))
local expected = assert(json.decode(abiFile:read("*a")))
abiFile:close()
for name, actual in pairs(memory.layoutinfo()) do
    local wanted = assert(expected[name], "missing header layout " .. name)
    assert(actual.size == wanted.size and actual.alignment == wanted.alignment, "GPU ABI size mismatch: " .. name)
    for field, offset in pairs(actual.fields) do
        assert(wanted.fields[field] == offset, "GPU ABI field mismatch: " .. name .. "." .. field)
    end
end
print("GPU ABI: all 33 layouts match pinned headers")
local suite = dofile("tests/stdlib/io/gpu/gpudevicetest.lua")
local names = {}
for name, body in pairs(suite) do
    if type(body) == "function" then
        names[#names + 1] = name
    end
end
assert(
    #names > 0 and type(suite.adapterComputeRoundTripWhenAvailable) == "function",
    "GPU conformance cases are missing"
)
table.sort(names)
local failures = 0
for _, name in ipairs(names) do
    local ok, message = pcall(suite[name])
    print((ok and "PASS " or "FAIL ") .. name .. (ok and "" or ": " .. tostring(message)))
    if not ok then
        failures = failures + 1
    end
end
assert(failures == 0, tostring(failures) .. " GPU conformance failures")
print("GPU conformance: " .. #names .. " passed")
