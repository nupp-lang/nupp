-- Execute a generated browser bundle in the host LuaJIT while routing its
-- independent Wasm kernels through the Rust Wasmtime test host.
local ffi = require("ffi")

local project, library, route = assert(arg[1]), assert(arg[2]), arg[3] or "simd"
assert(route == "simd" or route == "scalar-c", "route must be simd or scalar-c")

local source = assert(debug.getinfo(1, "S").source:match("^@(.*)$")):gsub("\\", "/")
local root = source:match("^(.*)/tests/simd/run%-wasmtime%-guest.lua$") or "."
if root:sub(1, 1) ~= "/" and not root:match("^%a:") then
    local pipe = assert(io.popen("pwd"))
    root = assert(pipe:read("*l")) .. "/" .. root
    pipe:close()
end
root = root:gsub("/%.$", "")
local nativeRoot = root:gsub("^/(%a)/", "%1:/")
project = project:gsub("\\", "/"):gsub("^/(%a)/", "%1:/")
library = library:gsub("\\", "/"):gsub("^/(%a)/", "%1:/")

local function read(path)
    local handle = assert(io.open(path, "rb"), "cannot read " .. path)
    local value = assert(handle:read("*a"))
    handle:close()
    return value
end

local function exists(path)
    local handle = io.open(path, "rb")
    if handle then
        handle:close()
        return true
    end

    return false
end

local function write(path, value)
    local handle = assert(io.open(path, "wb"), "cannot write " .. path)
    handle:write(value)
    handle:close()
end

local encode = assert(loadfile(nativeRoot .. "/src/nupp/runtime/vendor/lunajson/encoder.lua"))()()
local decode = assert(loadfile(nativeRoot .. "/src/nupp/runtime/vendor/lunajson/decoder.lua"))()()
local corpus = decode(read(project .. "/corpus.json"))
local manifest = decode(read(project .. "/dist/aot/units.json"))
assert(manifest.schemaVersion == 3 and manifest.target == "wasm32-unknown-emscripten", "invalid Wasm units manifest")

local function dualNumberLoops()
    for cursor = -0.0, 0 do
        return 1 / cursor > 0
    end

    return false
end

jit.off(dualNumberLoops, true)
local hostNumericForRuntime = dualNumberLoops() and "luajit-dual" or "luajit-single"

local function loadApplication()
    local path = project .. "/dist/app.lua"
    local application = read(path)
    local bridged = 0
    if hostNumericForRuntime == "luajit-dual" then
        assert(
            corpus.probes.simdcounted == nil,
            "runtime-sensitive counted loops require the real single-number browser guest"
        )
        application, bridged = application:gsub(
            'if ([%w_]+_loop_runtime) %( %) ~= false then\nerror %( "AOT numeric%-for runtime mismatch %(expected luajit%-single%)" , 0 %)',
            'if %1 ( ) ~= true then\nerror ( "Wasmtime oracle numeric-for runtime mismatch (expected luajit-dual)" , 0 )'
        )
        assert(
            not application:find("AOT numeric-for runtime mismatch (expected luajit-single)", 1, true),
            "dual-number Wasmtime oracle left a single-number numeric-for guard unadapted"
        )
    end

    return assert(loadstring(application, "@" .. path)), bridged
end

ffi.cdef[[
typedef struct nupp_wasmtime_host nupp_wasmtime_host;
typedef struct {
    const char *name;
    size_t offset;
    size_t bytes;
} nupp_wasmtime_host_field;
typedef struct {
    uint8_t *data;
    size_t bytes;
    size_t stride;
    size_t count;
    uint8_t writable;
    const nupp_wasmtime_host_field *fields;
    size_t fields_len;
} nupp_wasmtime_host_span;
uint32_t nupp_wasmtime_host_abi(void);
nupp_wasmtime_host *nupp_wasmtime_host_open(const char *manifest_path, const char *module_root);
int32_t nupp_wasmtime_host_call(nupp_wasmtime_host *host, const char *unit, const char *symbol,
    uint8_t *arguments, size_t arguments_len, uint8_t *results, size_t results_len,
    nupp_wasmtime_host_span *spans, size_t spans_len);
const char *nupp_wasmtime_host_error(nupp_wasmtime_host *host);
void nupp_wasmtime_host_close(nupp_wasmtime_host *host);
]]

local hostLibrary = ffi.load(library)
assert(hostLibrary.nupp_wasmtime_host_abi() == 1, "unsupported Wasmtime host ABI")
local hostManifest = os.getenv("NUPP_SIMD_HOST_MANIFEST")
if hostManifest == nil or hostManifest == "" then
    hostManifest = project .. "/dist/aot/units.json"
end
local host = hostLibrary.nupp_wasmtime_host_open(hostManifest, project .. "/dist/aot")
assert(host ~= nil, ffi.string(hostLibrary.nupp_wasmtime_host_error(nil)))

local scalarTypes = {
    bool = "bool",
    f32 = "float",
    f64 = "double",
    i32 = "int32_t",
    u32 = "uint32_t",
    i64 = "int64_t",
    u64 = "uint64_t"
}
local registrations, callCounts = {}, {}

local function kernel(unit, symbol, descriptor)
    -- Wasmtime runs SIMD128, so the widest of a tier list is the one taken.
    if type(unit) == "table" then
        unit = unit[1]
    end
    local params, results = descriptor.params, descriptor.results
    local countCount = 1
    if descriptor.independentCounts then
        countCount = 0
        for _, param in ipairs(params) do
            if param.kind == "read_span" or param.kind == "write_span" then
                countCount = countCount + 1
            end
        end
    end
    registrations[unit] = registrations[unit] or {}
    assert(registrations[unit][symbol] == nil, "duplicate Wasm kernel registration")

    local function bound(...)
        local values = {...}
        local arguments = ffi.new("uint64_t[?]", math.max(1, #params + countCount))
        local returned = ffi.new("uint64_t[?]", math.max(1, #results))
        local spanCount = 0
        for _, param in ipairs(params) do
            if param.kind == "read_span" or param.kind == "write_span" then
                spanCount = spanCount + 1
            end
        end
        local spans = ffi.new("nupp_wasmtime_host_span[?]", math.max(1, spanCount))
        local spanFields = {}
        local nextSpan, countIndex = 0, #params + 1
        for index, param in ipairs(params) do
            if param.kind == "read_span" or param.kind == "write_span" then
                local count = values[countIndex]
                assert(type(count) == "number" and count >= 0 and count % 1 == 0, "invalid Wasm span count")
                local layout = param.layout
                local stride
                if layout then
                    stride = layout.size
                    local fields = ffi.new("nupp_wasmtime_host_field[?]", math.max(1, #layout.fields))
                    for position, field in ipairs(layout.fields) do
                        fields[position - 1].name = field.name
                        fields[position - 1].offset = field.offset
                        fields[position - 1].bytes = field.size
                    end
                    spanFields[#spanFields + 1] = fields
                    spans[nextSpan].fields = fields
                    spans[nextSpan].fields_len = #layout.fields
                else
                    local ctype = scalarTypes[param.type]
                    if param.sourceType == "uint8"
                        or param.sourceType == "int8"
                        or param.sourceType == "uint16"
                        or param.sourceType == "int16"
                    then
                        ctype = param.sourceType .. "_t"
                    end
                    stride = ffi.sizeof(assert(ctype, "unknown Wasm span type"))
                end
                spans[nextSpan].data = ffi.cast("uint8_t *", values[index])
                spans[nextSpan].bytes = count * stride
                spans[nextSpan].stride = stride
                spans[nextSpan].count = count
                spans[nextSpan].writable = param.kind == "write_span" and 1 or 0
                nextSpan = nextSpan + 1
                ffi.cast("uint32_t *", arguments + countIndex - 1)[0] = count
                if descriptor.independentCounts then
                    countIndex = countIndex + 1
                end
            else
                ffi.cast(
                    assert(scalarTypes[param.type], "unknown Wasm scalar type") .. " *",
                    arguments + index - 1
                )[0] = values[index]
            end
        end
        local ok = hostLibrary.nupp_wasmtime_host_call(
            host,
            unit,
            symbol,
            ffi.cast("uint8_t *", arguments),
            (#params + countCount) * 8,
            ffi.cast("uint8_t *", returned),
            #results * 8,
            spans,
            spanCount
        )
        assert(ok == 1, ffi.string(hostLibrary.nupp_wasmtime_host_error(host)))
        local key = unit .. "\0" .. symbol
        callCounts[key] = (callCounts[key] or 0) + 1
        local valuesOut = {}
        for index, kind in ipairs(results) do
            local value = ffi.cast(scalarTypes[kind] .. " *", returned + index - 1)[0]
            if kind == "i64" or kind == "u64" or kind == "bool" then
                valuesOut[index] = value
            else
                valuesOut[index] = tonumber(value)
            end
        end

        return unpack(valuesOut, 1, #results)
    end

    registrations[unit][symbol] = bound

    return bound
end

_G.__nuppBrowser = {
    config = {mode = "application", runtime = "wasmtime"},
    kernel = kernel,
    now = function()
        return os.clock() * 1000
    end
}
_G.__nuppWasmBeforeRun = function()
    -- The application has now loaded bindings and verified its LuaJIT runtime
    -- contract. Interpret the oracle that observes Rust-host span writes.
    jit.off()
end

local function lowered(name)
    return (name:gsub("%u", function(letter)
        return "_" .. letter:lower()
    end):gsub("_+", "_"))
end

local function endsWith(value, suffix)
    return value:sub(-#suffix) == suffix
end

local function resolveInventory()
    local symbols, entries, calls = {}, {}, 0
    for module, names in pairs(corpus.probes) do
        local matches = {}
        for _, unit in ipairs(manifest.units) do
            local sourceName = unit.source or ""
            if endsWith(sourceName, "/" .. module .. ".simd128.ll")
                or endsWith(sourceName, "/" .. module .. ".g.simd128.ll")
                or sourceName == module .. ".simd128.ll"
                or sourceName == module .. ".g.simd128.ll"
            then
                matches[#matches + 1] = unit
            end
        end
        assert(#matches == 1, "missing unique independent Wasm unit for " .. module)
        local unit = matches[1]
        for _, name in ipairs(names) do
            local candidates = {}
            for _, entry in ipairs(assert(unit.bridge).entries) do
                if endsWith(entry.symbol, "_" .. name) or endsWith(entry.symbol, "_" .. lowered(name)) then
                    candidates[#candidates + 1] = entry
                end
            end
            assert(#candidates == 1, "missing unique independent Wasm entry for " .. module .. "." .. name)
            local entry = candidates[1]
            local count = callCounts[unit.unit .. "\0" .. entry.symbol] or 0
            assert(count > 0, "independent Wasm entry did not execute: " .. module .. "." .. name)
            local key = module .. "." .. name
            symbols[key] = entry.symbol
            entries[
                #entries + 1
            ] = {key = key, symbol = entry.symbol, unit = unit.unit, entryMode = "kernel", calls = count,}
            calls = calls + count
        end
    end

    return symbols, entries, calls
end

local ok, answer = xpcall(
    function()
        local app, numericForGuardBridges = loadApplication()
        local body = coroutine.create(app)
        local resumed, value = coroutine.resume(body)
        assert(resumed, debug.traceback(body, tostring(value)))
        assert(coroutine.status(body) == "dead", "Wasmtime SIMD corpus yielded a browser effect")
        local result = decode(value)
        assert(type(result.cases) == "number" and result.cases > 0, "SIMD corpus returned no cases")
        local symbols, entries, calls = resolveInventory()
        local scalarSelectionPath = project .. "/scalar-selection.json"
        local report = {
            ok = true,
            tier = "simd128",
            executionPath = route,
            runtime = "Wasmtime 48 embedded host",
            cases = result.cases,
            probes = #entries,
            nativeCalls = calls,
            callCountFloor = false,
            oracleNumericForRuntime = hostNumericForRuntime,
            oracleNumericForGuardBridges = numericForGuardBridges,
            symbols = symbols,
            entries = entries,
            randomFingerprint = result.randomFingerprint,
            coverage = corpus.coverage,
            scalarSelection = exists(scalarSelectionPath) and decode(read(scalarSelectionPath)) or nil
        }
        write(project .. "/result.json", encode(report) .. "\n")
        print(encode(report))
    end,
    debug.traceback
)

hostLibrary.nupp_wasmtime_host_close(host)
_G.__nuppBrowser = nil
if not ok then
    error(answer, 0)
end
