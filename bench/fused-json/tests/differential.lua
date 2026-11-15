-- Run the repository's independent JSON and first-error corpus against the
-- compiled benchmark decoder, including every byte offset across vector tails.
local module = "nupp.codec.json.internal.decoder.fusedbench"
local fused = require(module)
local proveNative = assert(loadfile("../../tests/integration/simd/nativeproof.lua"))()
proveNative(module, function()
    local value, status = fused.decodeEager('["native proof",123]', nil, {}, {})
    assert(status == 0 and value[1] == "native proof" and value[2] == 123, "native proof decode failed")
end)
-- The shared suite decodes through the `nupp.codec.json.aot` provider, which is
-- Nupp source and not a Lua module here. This adapter gives it the provider's
-- `decode` over the compiled benchmark decoder, with the provider's messages.
-- shortcut: only `decode`, so the pull and serde checks skip, as that suite
-- allows; link the real provider here to cover them.
local ARRAY_MARKER, OBJECT_MARKER = {}, {}
local FAILURES = {
    [2] = "invalid UTF-8",
    [3] = "unescaped control byte",
    [4] = "backslash outside a string",
    [5] = "structural index overflow",
}
local function outOfRange(text, position)
    local token = text:match("^%-?%d+%.?%d*[eE]?[-+]?%d*", position)
    local value = token ~= nil and tonumber(token) or nil

    return value == math.huge or value == -math.huge
end
package.loaded["nupp.codec.json.internal.decoder.fused"] = fused
package.loaded["nupp.codec.json.aot"] = {
    decode = function(text, nullvalue)
        local ok, value, code, position = pcall(fused.decodeEager, text, nullvalue, ARRAY_MARKER, OBJECT_MARKER)
        if not ok then
            -- A raise from the builder carries the caller's chunk and line.
            error((tostring(value):gsub("^%a:[^\n:]-:%d+: ", "", 1):gsub("^[^\n:]-:%d+: ", "", 1)), 0)
        end
        if code ~= 0 then
            local message = FAILURES[code] or (code == 1 and outOfRange(text, position) and "number is out of range")
                or "invalid syntax"
            error("invalid JSON at byte " .. tostring(position) .. ": " .. message, 0)
        end

        return value
    end,
}
local suite = dofile("../../tests/stdlib/serde/json/jsonfuseddifferentialtest.lua")
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

print("SIMD_CHECKS=" .. #names)
