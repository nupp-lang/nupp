local evaluations = 0

local function optional(value)
    evaluations = evaluations + 1
    return value
end

local function choose(first, second)
    local seen = "outer"
    local firstValue = optional(first)
    if firstValue ~= nil then
        local seen = firstValue

        local function read()
            return seen
        end

        assert(read() == first)
        seen = second
        return read
    else
        local secondValue = optional(second)
        if secondValue ~= nil then
            local other = secondValue
            assert(seen == "outer")
            return function()
                return other
            end
        else
            return function()
                return seen
            end
        end
    end
end

local first = choose(false, 7)
assert(first() == 7 and evaluations == 1)
local second = choose(0, "")
assert(second() == "" and first() == 7 and evaluations == 2)
local third = choose("", false)
assert(third() == false and evaluations == 3)
assert(choose(nil, 0)() == 0 and evaluations == 5)
assert(choose(nil, nil)() == "outer" and evaluations == 7)
local outer = 42
do
    local value = optional(0)
    if value ~= nil then
        local outer = value
        assert(outer == 0)
        do
            local value = optional(false)
            if value ~= nil then
                local outer = value
                assert(outer == false)
            end
        end
        assert(outer == 0)
    end
end
assert(outer == 42 and evaluations == 9)
local closed = 0

local function guarded(value, fail)
    local bound = optional(value)
    if bound ~= nil then
        local guard = {id = 1}
        local ok, problem = pcall(function()
            assert(bound == value and guard.id == 1)
            if fail then
                error("binding cleanup", 0)
            end
        end)
        closed = closed + guard.id
        if not ok then
            error(problem, 0)
        end
    else
        assert(value == nil)
    end
end

guarded(false, false)
assert(closed == 1)
local ok, problem = pcall(guarded, 0, true)
assert(not ok and problem == "binding cleanup" and closed == 2)
guarded(nil, false)
assert(closed == 2 and evaluations == 12)
return true
