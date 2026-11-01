-- Reference Lua 5.5 twin of catalog-calls-generic.nupp, without its types.
local function identity(x)
    return x
end

local function map(xs, f)
    local out = {}
    for i, v in ipairs(xs) do
        out[i] = f(v)
    end

    return out
end

local function swap(a, b)
    return b, a
end

local function count(xs, keep)
    local n = 0
    for _, v in ipairs(xs) do
        if keep(v) then
            n = n + 1
        end
    end

    return n
end

local lengths = map({"a", "bcd", "ef"}, function(s)
    return #s
end)
local doubled = map({1, 2, 3}, function(n)
    return n * 2
end)
local x, y = swap("text", 42)
local big = count(doubled, function(n)
    return n > 2
end)
return identity(
    lengths[1] + lengths[2] * 10 + lengths[3] * 100
) + doubled[3] * 1000 + x * 10000 + #y * 1000000 + big * 100000000
