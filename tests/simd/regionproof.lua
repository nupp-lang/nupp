-- Evidence for the authored regions in the generated conformance sources.
-- This is deliberately a reader of their restricted, line-oriented templates,
-- not a parser for arbitrary Nupp programs.
local M = {}

function M.inventory(files)
    local result = {}
    for filename, text in pairs(files) do
        local functions, current, line = {}, nil, 0
        for sourceLine in (text .. "\n"):gmatch("([^\n]*)\n") do
            line = line + 1
            local name = sourceLine:match("^local function ([%w_]+)%(")
            if name then
                current = name
            end
            if sourceLine:match("^%s*@simd[%s%(]") or sourceLine:match("^%s*@simd%s*$") then
                assert(current, filename .. ": authored region outside a named generated function")
                functions[current] = functions[current] or {}
                functions[current][#functions[current] + 1] = line
            end
        end
        if next(functions) then
            result["src/" .. filename] = functions
        end
    end

    return result
end

local function snake(name)
    return name:gsub("(%l)(%u)", "%1_%2"):lower()
end

function M.verify(inventory, units, tier, read)
    local proof = {tier = tier, regions = 0, functions = {}}
    for filename, functions in pairs(inventory) do
        local expected = filename:gsub("%.nupp$", "." .. tier .. ".c")
        local unit
        for _, candidate in ipairs(units.units) do
            if candidate.source == expected then
                assert(not unit, "duplicate region translation unit: " .. expected)
                unit = candidate
            end
        end
        assert(unit and unit.tier == tier and not unit.detector, "missing region translation unit: " .. expected)
        local text, bodies = read(unit.source), {}
        for symbol, body in text:gmatch("KS_API[^\n]- ([%w_]+)%([^\n]*%) (%b{})") do
            assert(not bodies[symbol], "duplicate emitted function: " .. symbol)
            bodies[symbol] = body
        end
        for name, lines in pairs(functions) do
            local suffix = "_" .. snake(name) .. "__" .. tier
            local selected, symbol
            for candidate, body in pairs(bodies) do
                if candidate:sub(-#suffix) == suffix and not candidate:find("_forced_scalar__", 1, true) then
                    assert(not selected, "ambiguous region entry: " .. name)
                    selected, symbol = body, candidate
                end
            end
            assert(selected, "missing compiled region entry: " .. name)
            local scalar = assert(
                bodies[symbol:gsub("__" .. tier .. "$", "_forced_scalar__" .. tier)],
                "missing independent scalar region entry: " .. name
            )
            local counters, prefixes = 0, {}
            for prefix in selected:gmatch("uint32_t ([%w_]+)_base1 = UINT32_C%(0%);") do
                assert(not prefixes[prefix], "duplicate region counter: " .. name)
                prefixes[prefix] = true
                counters = counters + 1
                local width = selected:match("ks_exp_mask_[%w]+x(%d+) " .. prefix .. "_active%d+")
                assert(width and tonumber(width) >= 2, name .. ": region lacks a vector tail mask")
                assert(
                    selected:find(prefix .. "_base1 + UINT32_C(" .. width .. ")", 1, true),
                    name .. ": region does not advance by its vector width"
                )
            end
            assert(counters == #lines, name .. ": authored/vector region count differs")
            assert(selected:find("ks_exp_", 1, true), name .. ": region has no explicit vector operations")
            assert(
                not scalar:find("ks_exp_", 1, true) and not scalar:find("_base1 = UINT32_C(0);", 1, true),
                name .. ": scalar oracle shares region lowering"
            )
            proof.regions = proof.regions + #lines
            proof.functions[
                #proof.functions + 1
            ] = {
                source = filename,
                name = name,
                annotations = lines,
                artifact = unit.source,
                symbol = symbol,
                regions = counters,
            }
        end
    end
    table.sort(proof.functions, function(a, b)
        return a.source .. a.symbol < b.source .. b.symbol
    end)

    return proof
end

return M
