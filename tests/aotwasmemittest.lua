local emitter = require("nupp.compiler.aot.wasmemit")

local M = {}

local function occurrences(source, needle)
    local count = 0
    local cursor = 1
    while true do
        local at = source:find(needle, cursor, true)
        if at == nil then
            return count
        end
        count = count + 1
        cursor = at + #needle
    end
end

local layout = {
    name = "Sample",
    cName = "KsSample",
    fields = {{name = "byte", type = "u32", sourceType = "uint8"}, {name = "wide", type = "f64"},},
}

local function kernel(symbol, body)
    return {
        entryMode = "kernel",
        name = symbol,
        symbol = symbol,
        params = {
            {kind = "write_span", name = "samples", type = "struct:Sample", spanModule = "nupp.mem.span"},
            {kind = "read_span", name = "bytes", type = "u32", sourceType = "uint8", spanModule = "nupp.mem.span"},
            {kind = "uniform", name = "enabled", type = "bool"},
            {kind = "uniform", name = "small", type = "f32"},
            {kind = "uniform", name = "signed", type = "i64"},
            {kind = "uniform", name = "unsigned", type = "u64"},
        },
        layouts = {layout},
        resultTypes = {"bool", "f32", "i64", "u64"},
        body = body,
    }
end

function M.emitsEveryHostBoundaryShapeDeterministically()
    local independent = kernel("ks_independent", {})
    local shared = kernel("ks_shared", nil)
    local source = emitter.registrar({independent, shared}, "u1234", "simd128")

    assert(source == emitter.registrar({independent, shared}, "u1234", "simd128"))
    assert(source:find("KsSample *p_samples", 1, true), source)
    assert(source:find("const uint8_t *p_bytes", 1, true), source)
    assert(source:find("size_t count_samples = ks_wasm_count(L, 7, \"samples\")", 1, true), source)
    assert(source:find("size_t count_bytes = ks_wasm_count(L, 8, \"bytes\")", 1, true), source)
    assert(source:find("bool p_enabled = (lua_toboolean(L, 3) != 0)", 1, true), source)
    assert(source:find("float p_small = (float)luaL_checknumber(L, 4)", 1, true), source)
    assert(source:find("int64_t p_signed = (int64_t)nupp_wasm_wide_bits(L, 5)", 1, true), source)
    assert(source:find("uint64_t p_unsigned = (uint64_t)nupp_wasm_wide_bits(L, 6)", 1, true), source)
    assert(source:find("count_samples, count_bytes)", 1, true), source)
    assert(source:find('size_t count = ks_wasm_count(L, 7, "shared")', 1, true), source)
    assert(source:find("nupp_wasm_push_wide(L, (uint64_t)(result.v3), 0)", 1, true), source)
    assert(source:find("nupp_wasm_push_wide(L, (uint64_t)(result.v4), 1)", 1, true), source)
    assert(occurrences(source, 'lua_setfield(L, -2, "layout:Sample")') == 1, source)
    assert(source:find("offsetof(KsSample, byte)", 1, true), source)
end

function M.rejectsSurfacesTheStockHostCannotRepresent()
    local program = kernel("ks_invalid", {})
    program.params[1].soa = {view = "rows", ordinal = 1}
    assert(emitter.validate({program}) == "SoA row-view parameters are supported only by native CPU AOT")

    program.params[1].soa = nil
    program.params[2].spanModule = "custom.span"
    assert(emitter.validate({program}) == "Wasm AOT kernel ks_invalid must use nupp.mem.span spans")
end

return M
