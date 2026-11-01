local test = require("assert")
local host = rawget(_G, "table")
local originalMove = rawget(host, "move")
local standard = require("nupp.runtime.standardtable")
local M = {}

function M.keepsTheHostTableAndExistingMove()
    test.equal(standard.value, host)
    if originalMove then
        test.equal(host.move, originalMove)
    end
    test.equal(require("table"), host)
    test.equal(standard.install(host), host)
    local existing = function()
        return "existing"
    end
    local custom = {move = existing, marker = 1}
    test.equal(standard.install(custom), custom)
    test.equal(custom.move, existing)
    test.equal(custom.marker, 1)
end

local function fallback()
    return standard.install({}).move
end

function M.forcedAbsencePreservesOverlapDestinationAndMissingValues()
    local move = fallback()
    local values = {1, 2, 3, 4}
    test.equal(move(values, 1, 3, 2), values)
    test.deepEqual(values, {1, 1, 2, 3})
    values = {1, 2, 3, 4}
    test.equal(move(values, 2, 4, 1, nil), values)
    test.deepEqual(values, {2, 3, 4, 4})
    local source, destination = {7, 8}, {1, 2, 3}
    test.equal(move(source, 1, 3, 2, destination), destination)
    test.deepEqual(source, {7, 8})
    test.deepEqual(destination, {1, 7, 8})
    test.equal(rawget(destination, 4), nil)
end

function M.forcedAbsencePreservesEmptyAndNegativeRanges()
    local move = fallback()
    local source, destination = {[-2] = 6, [-1] = 7, [0] = 8}, {1, 2, 3}
    test.equal(move(source, -2, 0, 4, destination), destination)
    test.deepEqual(destination, {1, 2, 3, 6, 7, 8})
    test.equal(move(source, 4, 3, 10, destination), destination)
    test.equal(rawget(destination, 10), nil)
    local converted = move({9}, "1", 1.8, 1)
    test.equal(converted[1], 9)
end

function M.forcedAbsenceUsesRawAccessLikeThePinnedHost()
    local reads, writes = 0, 0
    local source = setmetatable({}, {
        __index = function()
            reads = reads + 1;
            return 7
        end
    })
    local destination = setmetatable({}, {
        __newindex = function()
            writes = writes + 1
        end
    })
    local move = fallback()
    move(source, 1, 1, 1, destination)
    test.equal(reads, 0)
    test.equal(writes, 0)
    test.equal(rawget(destination, 1), nil)
    rawset(source, 1, 8)
    move(source, 1, 1, 1, destination)
    test.equal(rawget(destination, 1), 8)
    test.equal(writes, 0)
end

function M.forcedAbsenceRejectsInvalidArguments()
    local move = fallback()
    for _, arguments in ipairs({
        {false, 1, 1, 1},
        {{}, "bad", 1, 1},
        {{}, 1, "bad", 1},
        {{}, 1, 1, "bad"},
        {{}, 1, 1, 1, false}
    }) do
        local ok, problem = pcall(move, unpack(arguments))
        test.equal(ok, false)
        test.matches(tostring(problem), "expected")
    end
end

function M.forcedAbsenceHandlesLargeSingleKeysWithoutSteppingPastTheEnd()
    local move = fallback()
    local large = 9007199254740992
    local source, destination = {[large] = 17}, {}
    test.equal(move(source, large, large, large + 4, destination), destination)
    test.equal(rawget(destination, large + 4), 17)
    if large + 1 == large then
        local ok, problem = pcall(move, source, large, large + 2, 1, {})
        test.equal(ok, false)
        test.matches(tostring(problem), "cannot be represented")
    end
end

function M.forcedAbsenceRefusesNonfiniteIndices()
    local move = fallback()
    for _, value in ipairs({math.huge, -math.huge, 0 / 0}) do
        for position = 2, 4 do
            local arguments = {{}, 1, 1, 1}
            arguments[position] = value
            local ok, problem = pcall(move, unpack(arguments))
            test.equal(ok, false)
            test.matches(tostring(problem), "finite index expected")
        end
    end
end

return M
