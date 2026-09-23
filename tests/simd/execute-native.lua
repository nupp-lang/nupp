-- Runs in a fresh LuaJIT process after an exact-tier native build.
-- Forward the actual FFI entry upvalue, not a wrapper whose presence alone
-- would permit an interpreted fallback to pass this test.
local function read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local root = assert(read("execution.json"):match('"root"%s*:%s*"([^"]+)"'))
local decode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local encode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()
local config = decode(read("execution.json"))
local corpus = decode(read("corpus.json"))
package.path = config.directory .. "/build/native/?.lua;" .. root .. "/build/?.lua;" .. package.path
jit.off()
local registry = assert(rawget(_G, "__nuppAotCompiled") or {})
local calls, symbols, probes = {}, {}, 0
local observed = {}

local function pack(...)
    return {n = select("#", ...), ...}
end

local function forward(fn, at, native, key)
    debug.setupvalue(fn, at, function(...)
        local result = pack(native(...))
        calls[key] = (calls[key] or 0) + 1
        return unpack(result, 1, result.n)
    end)
end

for module, names in pairs(corpus.probes) do
    local exports = require(module)
    local binding = read(assert(package.searchpath(module, package.path)))
    registry = assert(rawget(_G, "__nuppAotCompiled"), "no native replacement registry")
    for _, name in ipairs(names) do
        local fn = assert(exports[name], "missing probe " .. module .. "." .. name)
        local key = module .. "." .. name
        assert(registry[fn], key .. " was not replaced with compiled code")
        local found = false
        for at = 1, 128 do
            local upname, value = debug.getupvalue(fn, at)
            if not upname then
                break
            end
            if upname:match("^ks_.*_native$") and type(value) == "cdata" then
                local symbol = assert(
                    binding:match("local%s+" .. upname .. "%s*=%s*([%w_]+)"),
                    "missing emitted native binding"
                )
                local suffix = "__" .. config.tier
                assert(symbol:sub(-#suffix) == suffix, "native binding uses unexpected tier")
                assert(not symbol:find("_forced_scalar__", 1, true), "native route resolved the forced-scalar twin")
                forward(fn, at, value, key)
                symbols[key] = symbol
                found = true
            end
        end
        assert(found, key .. " has no FFI entry to observe")
        observed[#observed + 1] = key
        probes = probes + 1
    end
end
assert(probes > 0, "empty native probe inventory")
local checked = require(corpus.entry).run()
assert(type(checked) == "number" and checked > 0, "corpus checked no cases")
local total = 0
for _, key in ipairs(observed) do
    assert((calls[key] or 0) > 0, key .. " never executed its native C entry")
    total = total + calls[key]
end
local report = {
    ok = true,
    tier = config.tier,
    probes = probes,
    cases = checked,
    nativeCalls = total,
    calls = calls,
    symbols = symbols,
}
local file = assert(io.open("result.json", "wb"))
file:write(encode(report), "\n")
file:close()
print(encode(report))
