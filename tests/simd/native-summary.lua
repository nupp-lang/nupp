local inventory = require("tests.simd.native-inventory")
local M = {}

function M.summarize(selection, rows)
    inventory.selection(selection)
    local expected, groups, seen = {}, {}, {}

    local function key(compiler, tier, family, element)
        return table.concat({compiler, tier, family, element}, "\t")
    end

    for compiler in ipairs(selection.compilers) do
        for _, tier in ipairs(selection.tiers) do
            local group = key(tostring(compiler), tier, "-", "-")
            groups[group] = {}

            local function add(family, element)
                local id = key(tostring(compiler), tier, family, element)
                expected[
                    id
                ] = {
                    compiler = tostring(compiler),
                    tier = tier,
                    family = family,
                    element = element,
                    status = "failed",
                    reason = "Requested execution row is missing"
                }
                groups[group][#groups[group] + 1] = id
            end

            for _, family in ipairs(selection.families) do
                for _, element in ipairs(selection.types) do
                    add(family, element)
                end
            end
            for _, algorithm in ipairs(selection.algorithms) do
                add("algorithms", algorithm)
            end
        end
    end
    local executed, unavailable, failures = 0, 0, 0
    for _, row in ipairs(rows) do
        local id = key(row.compiler, row.tier, row.family, row.element)
        local group = groups[id]
        local ok, err = pcall(function()
            assert(not seen[id], "duplicate matrix execution row")
            seen[id] = true
            if group then
                assert(row.status == "not-executed" or row.status == "failed", "invalid whole-tier status")
                for _, child in ipairs(group) do
                    assert(not seen[child], "whole-tier row conflicts with execution row");
                    seen[child] = true
                end
            else
                assert(expected[id], "matrix row was not requested")
                assert(row.status == "executed" or row.status == "failed", "invalid execution status")
                if row.status == "executed" then
                    inventory.row(row, selection)
                end
            end
        end)
        if not ok then
            row.status, row.reason = "failed", tostring(err)
        end
        if row.status == "executed" then
            executed = executed + 1
        elseif row.status == "not-executed" then
            unavailable = unavailable + 1
        else
            failures = failures + 1
        end
    end
    local missing = {}
    for id, row in pairs(expected) do
        if not seen[id] then
            missing[#missing + 1] = {id = id, row = row}
        end
    end
    table.sort(missing, function(a, b)
        return a.id < b.id
    end)
    for _, item in ipairs(missing) do
        rows[#rows + 1] = item.row;
        failures = failures + 1
    end

    return {
        schemaVersion = 2,
        selection = selection,
        rows = rows,
        executed = executed,
        unavailable = unavailable,
        failed = failures,
        available_execution_pass = failures == 0 and executed > 0,
        requested_native_matrix_complete = failures == 0 and unavailable == 0 and executed > 0,
        outcome = failures > 0 and "failed" or executed > 0 and "executed" or "not-executed",
    }
end

return M
