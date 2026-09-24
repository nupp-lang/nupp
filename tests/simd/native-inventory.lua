-- Compare completed C calls with the requested semantic inventory, independently
-- of the generator's descriptive coverage metadata.
local M = {}
local TYPES = {
    float = true,
    number = true,
    int8 = true,
    uint8 = true,
    int16 = true,
    uint16 = true,
    int32 = true,
    uint32 = true,
    int64 = true,
    uint64 = true
}
local TIERS = {baseline = true, avx2 = true, avx512f = true, neon = true}
local ALGORITHMS = {utf8simd = true, base64simd = true, ["simd-json"] = true, ["fused-json"] = true}

local function unique(values, allowed, label)
    assert(type(values) == "table" and #values > 0, "empty requested " .. label)
    local found = {}
    for _, value in ipairs(values) do
        assert(not found[value] and (not allowed or allowed[value]), "invalid or duplicate requested " .. label)
        found[value] = true
    end

    return found
end

function M.selection(value)
    unique(value.compilers, nil, "compilers")
    unique(value.tiers, TIERS, "tiers")
    unique(value.families, {primitives = true, reducers = true}, "families")
    unique(value.types, TYPES, "types")
    if #value.algorithms > 0 then
        unique(value.algorithms, ALGORITHMS, "algorithms")
    end
    local allowed = {preferred = true}
    for width = 2, 64 do
        allowed[width] = true
    end
    unique(value.lanes, allowed, "lanes")

    return value
end

local function positive(value)
    return type(value) == "number" and value > 0 and value % 1 == 0
end

function M.execution(execution, family, element, requested)
    assert(execution.ok and positive(execution.cases), "no completed semantic checks")
    local groups, probes, total = {}, 0, 0
    for key, count in pairs(assert(execution.calls, "missing completed-call inventory")) do
        assert(positive(count), "probe did not return: " .. key)
        probes, total = probes + 1, total + count
        local group, width
        if family == "primitives" then
            local module, operation = key:match("^simd_(%a+)_" .. element .. "_%d+%.([%w_]+)$")
            if operation then
                group, width = operation:match("^(%a+)_([%w]+)$")
            end
            local valid = {
                primitives = {probe = true},
                memory = {fields = true, indexed = true, interleaved = true},
                transpose = {transpose = true},
                conversions = {convert = true},
                integeredges = {edges = true},
                bitpatterns = {bits = true},
                bitmemory = {memorybits = true},
                masks = {masks = true},
                maps = {mapmath = true}
            }
            assert(module and valid[module] and valid[module][group], "unexpected primitive probe: " .. key)
        else
            width = key:match("^simd_reducers_" .. element .. "_%d+%.horizontal_" .. element .. "_([%w]+)$")
            if width then
                group = "horizontal"
            else
                width = key:match("^simd_masked_reducers_" .. element .. "_([%w]+)%.masked_[%w_]+$")
                if width then
                    group = "masked"
                elseif key:match("^simd_loop_reducers_" .. element .. "%.loop_[%w_]+$") then
                    group, width = "loop", "scalar"
                end
            end
            assert(group, "unexpected reducer probe: " .. key)
        end
        groups[group] = groups[group] or {}
        groups[group][width] = (groups[group][width] or 0) + 1
    end
    assert(
        probes == execution.probes and total == execution.nativeCalls and probes > 0,
        "completed-call counts disagree"
    )
    local widths, fixed = {}, {}
    for _, width in ipairs(requested) do
        widths[#widths + 1] = tostring(width);
        if width ~= "preferred" then
            fixed[#fixed + 1] = tostring(width)
        end
    end
    local expected
    if family == "primitives" then
        expected = {
            probe = {widths, 1},
            fields = {widths, 1},
            interleaved = {widths, 1},
            indexed = {
                (element == "int8" or element == "uint8" or element == "int16" or element == "uint16") and fixed
                or widths,
                1
            },
            convert = {widths, 1},
            transpose = {fixed, 1},
            masks = {widths, 1}
        }
        if element ~= "float" and element ~= "number" then
            expected.edges = {widths, 1}
        else
            expected.bits = {widths, 1}
            expected.memorybits = {widths, 1}
            expected.mapmath = {widths, 1}
        end
    else
        expected = {horizontal = {widths, 1}}
        if element == "number"
            or element == "int32"
            or element == "uint32"
            or element == "int64"
            or element == "uint64"
        then
            expected.masked = {widths, element == "number" and 14 or 7}
            expected.loop = {{"scalar"}, element == "number" and 21 or 9}
        end
    end
    for group, spec in pairs(expected) do
        local actual = groups[group] or {}
        for _, width in ipairs(spec[1]) do
            assert(
                actual[width] == spec[2],
                "incomplete executed " .. family .. "/" .. element .. "/" .. group .. "/" .. width
            );
            actual[width] = nil
        end
        assert(next(actual) == nil, "unexpected executed width")
        groups[group] = nil
    end
    assert(next(groups) == nil, "unexpected executed probe group")

    return probes
end

function M.row(row, selection)
    local execution = assert(row.execution, "missing execution report")
    assert(
        execution.ok and execution.tier == row.tier and positive(execution.nativeCalls) and positive(execution.cases),
        "invalid native execution proof"
    )
    local compiler = selection.compilers[tonumber(row.compiler)]
    assert((execution.compilerCommand or execution.compiler) == compiler, "execution compiler differs from request")
    if row.family == "algorithms" then
        assert(execution.algorithm == row.element, "wrong algorithm execution")
        return
    end
    M.execution(execution, row.family, row.element, selection.lanes)
    local scalar = assert(execution.scalarC, "missing scalar-C proof")
    assert(
        scalar.tier == row.tier
        and scalar.route == "scalar-C"
        and scalar.cases == execution.cases
        and scalar.probes == execution.probes,
        "scalar-C route/inventory mismatch"
    )
    M.execution(scalar, row.family, row.element, selection.lanes)
    for key in pairs(execution.calls) do
        assert(scalar.calls[key], "scalar-C probe differs from native probe")
        local symbol = scalar.symbols and scalar.symbols[key]
        assert(
            type(symbol) == "string" and symbol:match("_forced_scalar__" .. row.tier .. "$"),
            "scalar-C symbol does not name the selected twin"
        )
    end
end

return M
