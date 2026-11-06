-- Lua twin of catalog-gc-finalizers.nupp.
-- Finalizers (`__gc`) as Lua 5.5 runs them. As in catalog-gc-weak, objects
-- are made in functions of their own and dropped through a table's field,
-- and each check holds whenever collections run: a finalizer runs once its
-- table is found dead, no later than the next full collection, those found
-- dead together newest first; a table it stores somewhere lives again, with
-- what it holds, and is not finalized again unless a metatable with __gc is
-- set on it again; a weak value naming it is gone when its finalizer runs,
-- and a weak key naming it stays until a later collection. A finalizer's
-- error is warned of and the others still run; inside one collectgarbage
-- answers nil and nothing yields across it. Any callable is a finalizer: a
-- table with __call and a wrapped coroutine's function too.
local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

local log = {}
local seen = {rescued = 0, after = 0, called = 0}

-- Five tables, held together, and their metatables, then marked in order
-- with nothing allocated between, so no collection runs while one is in a
-- register and not the others.
local function make(holder)
    local objects = {}
    local metatables = {}
    for i = 1, 5 do
        objects[i] = {}
        metatables[i] = {
            __gc = function()
                log[#log + 1] = i
            end
        }
    end
    holder.objects = objects
    holder.metatables = metatables
end

local function mark(holder)
    for i = 1, 5 do
        setmetatable(holder.objects[i], holder.metatables[i])
    end
end

local function reversed()
    if #log ~= 5 then
        return false
    end
    for i = 1, 5 do
        if log[i] ~= 6 - i then
            return false
        end
    end
    return true
end

-- A finalizer that stores its table, which lives again.
local rescue = {}
local rescuer = {
    __gc = function(o)
        seen.rescued = seen.rescued + 1
        rescue.object = o
    end
}

local function rescuable()
    setmetatable({name = "kept", child = {value = 7}}, rescuer)
end

local function rescued()
    local o = rescue.object
    return o ~= nil and o.name == "kept" and o.child.value == 7
end

local function remark()
    setmetatable(rescue.object, rescuer)
end

-- Weak tables as a finalizer finds them.
local weakvalues = setmetatable({}, {__mode = "v"})
local weakkeys = setmetatable({}, {__mode = "k"})

local function watched()
    local o = setmetatable({}, {
        __gc = function(x)
            seen.value = weakvalues[1] == nil
            seen.key = weakkeys[x] ~= nil
        end
    })
    weakvalues[1] = o
    weakkeys[o] = true
end

-- One finalizer raises (warned of); the other still runs.
local function failing()
    setmetatable({}, {
        __gc = function()
            seen.after = seen.after + 1
        end
    })
    setmetatable({}, {
        __gc = function()
            error("boom")
        end
    })
end

-- A table with __call and a wrapped coroutine's function as __gc.
local function callables()
    local callee = setmetatable({}, {
        __call = function(self, o)
            seen.called = seen.called + 1
        end
    })
    setmetatable({}, {__gc = callee})
    setmetatable({}, {
        __gc = coroutine.wrap(function(o)
            seen.wrapped = true
        end)
    })
end

-- Inside a finalizer: collectgarbage answers nil, nothing yields, and a
-- __gc that is no function is warned of.
local function inside()
    setmetatable({}, {
        __gc = function()
            seen.collect = collectgarbage() == nil
            seen.count = collectgarbage("count") == nil
            seen.yieldable = coroutine.isyieldable()
            seen.crossed = not pcall(function()
                coroutine.yield()
            end)
        end
    })
    local uncallable = true
    setmetatable({}, {__gc = uncallable})
end

local score = 0
local holder = {}
make(holder)
collectgarbage()
mark(holder)
holder.objects = nil
collectgarbage()
if reversed() then
    score = score + 1
end
rescuable()
collectgarbage()
if seen.rescued == 1 and rescued() then
    score = score + 2
end
rescue.object = nil
collectgarbage()
collectgarbage()
if seen.rescued == 1 then
    score = score + 4
end
rescuable()
collectgarbage()
remark()
rescue.object = nil
collectgarbage()
collectgarbage()
if seen.rescued == 3 and rescued() then
    score = score + 8
end
rescue.object = nil
watched()
collectgarbage()
collectgarbage()
if seen.value == true and seen.key == true then
    score = score + 16
end
if count(weakkeys) == 0 and count(weakvalues) == 0 then
    score = score + 32
end
failing()
collectgarbage()
if seen.after == 1 then
    score = score + 64
end
-- The finalizers run from a coroutine's collection, on its thread.
coroutine.wrap(function()
    inside()
    collectgarbage()
end)()
collectgarbage()
if seen.collect == true and seen.count == true and seen.yieldable == false and seen.crossed == true then
    score = score + 128
end
collectgarbage()
if seen.rescued == 3 then
    score = score + 256
end
callables()
collectgarbage()
if seen.called == 1 and seen.wrapped == true then
    score = score + 512
end
return score
