-- Lua twin of catalog-threads-meta.nupp.

-- A wrapped coroutine's function serves as a metamethod: each use resumes
-- its thread with the metamethod's arguments, and what it yields answers
-- the operation, a comparison's as a boolean.
local reads = coroutine.wrap(function(t, k)
    local count = 0
    while true do
        count = count + 1
        t, k = coroutine.yield(k * 10 + count)
    end
end)
local sums = coroutine.wrap(function(a, b)
    while true do
        a, b = coroutine.yield((a["v"] or 0) + b)
    end
end)
local orders = coroutine.wrap(function(a, b)
    while true do
        a, b = coroutine.yield((a["v"] or 0) < (b["v"] or 0) and 1 or nil)
    end
end)
local proxy = setmetatable({}, {__index = reads})
local left = setmetatable({v = 3}, {__add = sums, __lt = orders})
local right = setmetatable({v = 5}, {__lt = orders})
local score = proxy[1] + proxy[2] * 100
score = score + (left + 4) * 10000
if left < right and not (right < left) then
    score = score + 1000000
end
return score
