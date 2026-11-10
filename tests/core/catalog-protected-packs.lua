-- Lua twin of catalog-protected-packs.nupp: its affine resource is a
-- to-be-closed variable, closed after the returned values are staged.
local function pack(...)
    return {n = select("#", ...), ...}
end

local function values(...)
    return ...
end

local function protect(value, ...)
    return pcall(value, ...)
end

local function handle(value, ...)
    return xpcall(
        value,
        function(problem)
            return problem
        end,
        ...
    )
end

local empty = pack(protect(values))
assert(empty.n == 1 and empty[1] == true)
local one = pack(protect(values, nil))
assert(one.n == 2 and one[1] == true and one[2] == nil)

local arguments = {}
for index = 1, 24 do
    arguments[index] = index
end
arguments[12] = nil
local many = pack(protect(values, table.unpack(arguments, 1, 24)))
assert(many.n == 25 and many[1] == true and many[13] == nil and many[25] == 24)
local handledMany = pack(handle(values, table.unpack(arguments, 1, 24)))
assert(handledMany.n == 25 and handledMany[1] == true and handledMany[13] == nil and handledMany[25] == 24)

local function none()
end

local function explicit()
    return nil
end

assert(pack(protect(none)).n == 1)
assert(pack(protect(explicit)).n == 2)

local function fail(problem)
    error(problem, 0)
    return
end

local marker = {code = 99}
local failed = pack(protect(fail, marker))
assert(failed.n == 2 and failed[1] == false and failed[2] == marker)
-- Lua 5.5 replaces a nil error object with "<no error object>"; the core
-- keeps the nil, which the fixture asserts.
local nilFailure = pack(handle(fail, nil))
assert(nilFailure.n == 2 and nilFailure[1] == false and nilFailure[2] == "<no error object>")

local function zeroHandler(value, ...)
    return xpcall(
        value,
        function(problem)
            return 0.0
        end,
        ...
    )
end

local zero = pack(zeroHandler(fail, marker))
assert(zero.n == 2 and zero[1] == false and zero[2] == 0.0)

local wrapped = coroutine.wrap(values)
local wrappedPack = pack(protect(wrapped, 7, nil, 9))
assert(
    wrappedPack.n == 4
    and wrappedPack[1] == true
    and wrappedPack[2] == 7
    and wrappedPack[3] == nil
    and wrappedPack[4] == 9
)

local closed = 0

local function open()
    return setmetatable({value = 1}, {
        __close = function(resource)
            closed = closed + resource.value
        end,
    })
end

local function owned()
    local resource <close> = open()
    return pcall(values, 7, nil, 9)
end

local ownedPack = pack(owned())
assert(
    ownedPack.n == 4
    and ownedPack[1] == true
    and ownedPack[2] == 7
    and ownedPack[3] == nil
    and ownedPack[4] == 9
    and closed == 1
)

local function ownedNone()
    local resource <close> = open()
end

assert(pack(protect(ownedNone)).n == 1 and closed == 2)
return 1
