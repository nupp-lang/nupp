-- Lua twin of catalog-gc-weak.nupp; a plain table stands for the storage
-- view, which is a collectable object as a table is.

local function count(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

-- Weak values: in the array and hash parts, an object nothing else holds
-- goes; a held one, a string, a number and a boolean stay.
local function weakValues(held)
    local t = setmetatable({}, {__mode = "v"})
    t[1] = {}
    t[2] = held
    t[3] = {}
    t.text = string.rep("t", 3)
    t.number = 42
    t.flag = true
    t.gone = {}
    return t
end

-- Weak keys: an entry whose key nothing else holds goes, value and all; a
-- held key's, a string key's and a number key's stay.
local function weakKeys(held)
    local t = setmetatable({}, {__mode = "k"})
    t[held] = {}
    t[{}] = {}
    t.name = {}
    t[7] = {}
    return t
end

-- An ephemeron chain: each value holds the next entry's key, and the first
-- key is held through `holder`.
local function chain(holder, length)
    local t = setmetatable({}, {__mode = "k"})
    local key = {}
    holder.first = key
    for _ = 1, length do
        local after = {}
        t[key] = {next = after}
        key = after
    end
    t[key] = {}
    return t
end

-- Values that reach only their own keys.
local function selfish()
    local t = setmetatable({}, {__mode = "k"})
    for _ = 1, 5 do
        local key = {}
        t[key] = {key}
    end
    return t
end

-- Both sides weak: either side dead takes the entry.
local function both(held)
    local t = setmetatable({}, {__mode = "kv"})
    t[{}] = held
    t[held] = {}
    t.name = held
    t[held] = "text" .. tostring(2)
    t[{}] = "kept only by a dead key"
    return t
end

-- A view of storage as a weak value: collectable, so cleared.
local function views(block)
    local t = setmetatable({}, {__mode = "v"})
    t[1] = {}
    t[2] = block
    return t
end

-- Any letters around "k": weak keys still.
local function lettered()
    local t = setmetatable({}, {__mode = "xk?"})
    t[{}] = 1
    return t
end

-- setmetatable(t, nil) makes a weak table strong again.
local function strengthened()
    local t = setmetatable({}, {__mode = "v"})
    t[1] = {}
    setmetatable(t, nil)
    return t
end

local score = 0
local held = {}
local values = weakValues(held)
local keys = weakKeys(held)
local holder = {}
local links = chain(holder, 20)
local own = selfish()
local sides = both(held)
local block = {}
local viewed = views(block)
local marked = lettered()
local strong = strengthened()
collectgarbage()
collectgarbage()
if values[1] == nil and values[2] == held and values[3] == nil and values.gone == nil
    and values.text == "ttt" and values.number == 42 and values.flag == true
then
    score = score + 1
end
if count(keys) == 3 and keys[held] ~= nil and type(keys.name) == "table" and type(keys[7]) == "table" then
    score = score + 2
end
if count(links) == 21 then
    score = score + 4
end
holder.first = nil
collectgarbage()
collectgarbage()
if count(links) == 0 then
    score = score + 8
end
if count(own) == 0 then
    score = score + 16
end
if count(sides) == 2 and sides.name == held and sides[held] == "text2" then
    score = score + 32
end
if viewed[1] == nil and viewed[2] == block then
    score = score + 64
end
if count(marked) == 0 then
    score = score + 128
end
if type(strong[1]) == "table" then
    score = score + 256
end
return score
