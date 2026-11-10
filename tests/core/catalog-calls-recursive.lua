-- Reference Lua 5.5 twin of catalog-calls-recursive.nupp, without its types.
-- Recursive local functions called by name inside their own bodies: with a
-- declared signature, with results left to inference, with no annotations
-- at all, with a `...` and several results, nested in another function,
-- mutually recursive through a forward-declared local, and recursive
-- through one.
local function fact(n)
    if n <= 1 then
        return 1
    end
    return n * fact(n - 1)
end

local function depth(n)
    if n == 0 then
        return 0
    end
    return depth(n - 1) + 1
end

local function sum(n)
    if n == 0 then
        return 0
    end
    return n + sum(n - 1)
end

local function spread(n, ...)
    if n == 0 then
        return select("#", ...), 0
    end
    local count, total = spread(n - 1, n, ...)
    return count, total + n
end

local function pair(n)
    if n == 0 then
        return 0, 1
    end
    local a, b = pair(n - 1)
    return b, a + b
end

local function tree(levels)
    local function nodes(level)
        if level == 0 then
            return 1
        end
        return 1 + 2 * nodes(level - 1)
    end
    return nodes(levels)
end

local odd

local function even(n)
    if n == 0 then
        return true
    end
    return odd(n - 1)
end

odd = function(n)
    if n == 0 then
        return false
    end
    return even(n - 1)
end

local gcd
gcd = function(a, b)
    if b == 0 then
        return a
    end
    return gcd(b, a % b)
end

local score = 0
if fact(10) == 3628800 then
    score = score + 1
end
if depth(1000) == 1000 then
    score = score + 2
end
if sum(100) == 5050 then
    score = score + 4
end
local count, total = spread(20)
if count == 20 and total == 210 then
    score = score + 8
end
local f30, f31 = pair(30)
if f30 == 832040 and f31 == 1346269 then
    score = score + 16
end
if tree(10) == 2047 then
    score = score + 32
end
if even(10) and odd(7) and not even(7) and not odd(10) then
    score = score + 64
end
if gcd(1071, 462) == 21 then
    score = score + 128
end
return score * 1000000 + fact(12) % 1000000 + depth(17)
