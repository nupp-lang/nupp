-- Reuse the authored corpus against each emitted scalar-C twin. Resolve its
-- declaration from the binding actually loaded, preserving the private ABI.
local ffi = require("ffi")

local function read(path)
    local file = assert(io.open(path, "rb"))
    local value = file:read("*a")
    file:close()
    return value
end

local root = assert(read("execution.json"):match('"root"%s*:%s*"([^"]+)"'))
local decode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local encode = assert(loadfile(root .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()
local config, corpus = decode(read("execution.json")), decode(read("corpus.json"))
package.path = config.directory .. "/build/native/?.lua;" .. root .. "/build/?.lua;" .. package.path
jit.off()
local calls, symbols, probes = {}, {}, 0

local function pack(...)
    return {n = select("#", ...), ...}
end

local function observe(fn, index, native, key)
    debug.setupvalue(fn, index, function(...)
        local result = pack(native(...))
        calls[key] = (calls[key] or 0) + 1
        return unpack(result, 1, result.n)
    end)
end

for module, names in pairs(corpus.probes) do
    local exports = require(module)
    local binding = read(assert(package.searchpath(module, package.path)))
    local registry = assert(rawget(_G, "__nuppAotCompiled"))
    for _, name in ipairs(names) do
        local fn = assert(exports[name])
        local key = module .. "." .. name
        assert(registry[fn], "probe lacks compiled replacement: " .. key)
        local found = false
        for index = 1, 128 do
            local upname, value = debug.getupvalue(fn, index)
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
                local scalar = symbol:sub(1, -#suffix - 1) .. "_forced_scalar" .. suffix
                local declaration
                for literal in binding:gmatch('pcall%(__nuppFfi.cdef,%s*"(.-)"%)') do
                    local text = assert(loadstring('return "' .. literal .. '"'))()
                    declaration = text:match("([^;]+%s" .. symbol .. "%([^;]*;)") or declaration
                end
                assert(declaration, "missing emitted ABI for " .. symbol)
                ffi.cdef((declaration:gsub(symbol .. "%(", scalar .. "(")))
                local native
                for library in pairs(assert(rawget(_G, "__nuppLibraryRoots"))) do
                    local ok, entry = pcall(function()
                        return library[scalar]
                    end)
                    if ok then
                        native = entry;
                        break
                    end
                end
                assert(type(native) == "cdata", "missing compiled scalar twin " .. scalar)
                observe(fn, index, native, key)
                symbols[key], found = scalar, true
            end
        end
        assert(found, "unobserved scalar twin " .. key)
        probes = probes + 1
    end
end
assert(probes > 0, "empty scalar-C inventory")
local cases = require(corpus.entry).run()
local total = 0
for key in pairs(symbols) do
    assert((calls[key] or 0) > 0, "scalar-C twin never returned: " .. key)
    total = total + calls[key]
end
assert(cases > 0)
local report = {
    ok = true,
    tier = config.tier,
    route = "scalar-C",
    probes = probes,
    cases = cases,
    nativeCalls = total,
    calls = calls,
    symbols = symbols
}
local file = assert(io.open("scalar-result.json", "wb"))
file:write(encode(report), "\n")
file:close()
print(encode(report))
