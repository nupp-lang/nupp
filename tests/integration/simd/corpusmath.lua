-- Correctness-only PRNG shared by LuaJIT and stock Lua 5.1. Park-Miller's
-- state*16807 is below 2^46, so every integer operation is exact in binary64.
-- Timing scripts retain their original math.random stream.
local M = setmetatable({}, {__index = math})
local state, seed, draws = 1, 1, 0
function M.randomseed(value)
    seed = math.floor(value) % 2147483647
    if seed == 0 then
        seed = 1
    end
    state, draws = seed, 0
end

function M.random(first, last)
    state = (state * 16807) % 2147483647
    draws = draws + 1
    local value = (state - 1) / 2147483646
    if first == nil then
        return value
    end
    if last == nil then
        first, last = 1, first
    end
    assert(first <= last and first == math.floor(first) and last == math.floor(last))

    return first + math.floor(value * (last - first + 1))
end

function M.fingerprint()
    return string.format("park-miller:%d:%d:%d", seed, draws, state)
end

-- The same fixed stream is checked when either VM loads this module.
M.randomseed(1)
local expected = {16807, 282475249, 1622650073, 984943658, 1144108930}
local bytes = {0, 33, 193, 117, 136}
for index, value in ipairs(expected) do
    assert(M.random(0, 255) == bytes[index], "portable PRNG byte " .. index)
    assert(M.fingerprint() == string.format("park-miller:1:%d:%d", index, value), "portable PRNG state " .. index)
end
M.randomseed(1)
return M
