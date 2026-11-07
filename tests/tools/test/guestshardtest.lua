local planner = dofile("native/core/tests/guests/shardplan.lua")

local function names(count)
    local result = {}
    for index = 1, count do
        result[index] = ("case%02d"):format(index)
    end

    return result
end

local function coverage(selected, members)
    local seen = {}
    for _, shard in ipairs(members) do
        assert(#shard > 0, "empty shard would select every case")
        for _, name in ipairs(shard) do
            assert(not seen[name], "case scheduled twice")
            seen[name] = true
        end
    end
    for _, name in ipairs(selected) do
        assert(seen[name], "case missing from shards")
        seen[name] = nil
    end
    assert(next(seen) == nil, "unrequested case scheduled")
end

local function signature(members)
    local result = {}
    for index, shard in ipairs(members) do
        result[index] = table.concat(shard, ",")
    end

    return table.concat(result, ";")
end

return {
    missingAuditsDoNotReserveAShard = function()
        local selected = names(16)
        local members = planner.plan(selected, {["audit absent"] = 1000}, {absent = true}, 4)
        assert(#members == 4)
        coverage(selected, members)
        for _, shard in ipairs(members) do
            assert(#shard == 4)
        end
    end,
    zeroTimingsStillFillEveryShard = function()
        local selected, cost = names(16), {}
        for _, name in ipairs(selected) do
            cost[name] = 0
        end
        local members = planner.plan(selected, cost, {}, 4)
        assert(#members == 4)
        coverage(selected, members)
    end,
    auditedCasesStayTogetherWithoutEmptyPeers = function()
        local selected = names(16)
        local audited = {[selected[1]] = true, [selected[2]] = true, [selected[3]] = true}
        local members = planner.plan(selected, {["audit " .. selected[1]] = 1000}, audited, 4)
        assert(#members == 4)
        coverage(selected, members)
        local first = {}
        for _, name in ipairs(members[1]) do
            first[name] = true
        end
        for name in pairs(audited) do
            assert(first[name])
        end
    end,
    allAuditedCasesUseOneProcess = function()
        local selected, audited = names(16), {}
        for _, name in ipairs(selected) do
            audited[name] = true
        end
        local members = planner.plan(selected, {}, audited, 4)
        assert(#members == 1)
        coverage(selected, members)
    end,
    smallSelectionsStayInTheCallingProcess = function()
        local selected = names(7)
        local members = planner.plan(selected, {}, {}, 4)
        assert(#members == 1)
        coverage(selected, members)
        assert(#planner.plan({}, {}, {}, 4) == 0)
    end,
    planningIsStableAndLeavesInputsAlone = function()
        local selected = names(16)
        local original = table.concat(selected, ",")
        local cost, audited = {[selected[1]] = 100}, {absent = true}
        local a = planner.plan(selected, cost, audited, 4)
        assert(table.concat(selected, ",") == original)
        local reversed = {}
        for index = #selected, 1, -1 do
            reversed[#reversed + 1] = selected[index]
        end
        local b = planner.plan(reversed, cost, audited, 4)
        assert(signature(a) == signature(b))
        assert(cost[selected[1]] == 100 and audited.absent == true)
        coverage(selected, a)
    end,
}
