-- Lua twin of catalog-threads-close.nupp.

-- coroutine.close: a suspended thread's affine owners are destroyed, the
-- innermost first, and a protected call in it does not take the closing;
-- a fresh or finished one closes at once, and one an error ended answers it.
local closed = 0
local order = 0

local closes = {__close = function(self)
    closed = closed + 1
    order = order * 10 + self.id
end}
local function File(id)
    return setmetatable({id = id}, closes)
end






local score = 0

-- Owners in the yielding frame and in the frame waiting on it.
local function nested()
    local f <close> = File(2)
    coroutine.yield()
    order = order * 10 + 8
end

local co = coroutine.create(function()
    local f <close> = File(1)
    nested()
    order = order * 10 + 9
end)
coroutine.resume(co)
local ok, err = coroutine.close(co)
if ok and err == nil and closed == 2 and order == 21 and coroutine.status(co) == "dead" then
    score = score + 1
end
local again, why = coroutine.resume(co)
if not again and why == "cannot resume dead coroutine" then
    score = score + 2
end

-- A protected call around the yield lets the closing pass.
order = 0
local guarded = coroutine.create(function()
    local f <close> = File(3)
    pcall(function()
        coroutine.yield()
    end)
    order = order * 10 + 9
end)
coroutine.resume(guarded)
local guardedOk = coroutine.close(guarded)
if guardedOk and order == 3 then
    score = score + 4
end

-- The yielding frame owns nothing; the frame waiting on it does.
order = 0

local function plain()
    coroutine.yield()
end

local waiting = coroutine.create(function()
    local f <close> = File(4)
    plain()
end)
coroutine.resume(waiting)
local waitingOk = coroutine.close(waiting)
if waitingOk and order == 4 then
    score = score + 8
end

-- Fresh, suspended without owners, and finished threads close at once.
local fresh = coroutine.create(function()
end)
local bare = coroutine.create(function()
    coroutine.yield()
end)
coroutine.resume(bare)
local done = coroutine.create(function()
end)
coroutine.resume(done)
if coroutine.close(fresh) and coroutine.close(bare) and coroutine.close(done) and coroutine.status(fresh) == "dead" then
    score = score + 16
end

-- One an error ended answers that error once.
local failed = coroutine.create(function()
    error("boom", 0)
end)
coroutine.resume(failed)
local first, firstError = coroutine.close(failed)
local second = coroutine.close(failed)
if not first and firstError == "boom" and second then
    score = score + 32
end

-- A normal thread cannot be closed, nor the main one; a running one closes
-- itself, as Lua 5.5 has it, and its resumer gets true and no values.
local outer = nil
local inner = coroutine.create(function()
    local fine = pcall(function()
        coroutine.close(outer)
    end)
    return fine
end)
outer = coroutine.create(function()
    local _, innerFine = coroutine.resume(inner)
    return innerFine
end)
local _, innerFine = coroutine.resume(outer)
local main = coroutine.running()
local mainFine = pcall(function()
    if main then
        coroutine.close(main)
    end
end)
order = 0

local function closeSelf()
    local me = coroutine.running()
    if me then
        coroutine.close(me)
    end
    order = order * 10 + 9
end

local selfish = coroutine.create(function()
    local f <close> = File(5)
    closeSelf()
    return 7
end)
local selfOk, selfValue = coroutine.resume(selfish)
if innerFine == false
    and not mainFine
    and selfOk
    and selfValue == nil
    and order == 5
    and coroutine.status(selfish) == "dead"
then
    score = score + 64
end
return score
