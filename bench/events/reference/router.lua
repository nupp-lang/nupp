-- The Teal router side of bench/events: the same scenarios as candidate.nupp,
-- over the tecs.events MessageBus, table pool and FFI event arena that
-- `nupp.events` replaces.
--
-- The Teal bus delivers an instance the caller already holds. Emission by
-- type, with pooled record storage or an arena row, lived in the Teal world
-- (`WorldImpl:emit` in src/tecs/internal/world/init.tl at the same revision),
-- so this file carries that method's body as `emitByType` with the world's
-- pool and FFI slice as its state. Two things the world did are left out: the
-- entity-id slot unpacking, which is id layout rather than routing, and the
-- once-per-frame `clearSlice`, which is done once per emission here instead
-- so the arena rewinds where the candidate's does and the allocation column
-- measures rows rather than pages.
local events = require("tecs.events")
local FFIEvents = require("tecs.internal.ffi.FFIEvents")
local pool = require("tecs.utils.pool")

local ADDRESSES = 10000

-- Event definitions, as a Teal program wrote them: a record with an `init`
-- and one registration each.
local Tick = {}
Tick.init = function(event, value)
    event.value = value
end
events.newEvent(Tick)

-- Defaults are the init's to apply: the Teal router had no field defaults.
local Damage = {}
Damage.init = function(event, amount, source, kind, critical, knockback)
    event.amount = amount
    event.source = source
    if kind == nil then
        event.kind = "physical"
    else
        event.kind = kind
    end
    if critical == nil then
        event.critical = false
    else
        event.critical = critical
    end
    event.knockback = knockback
end
events.newEvent(Damage)

local Contact = {}
events.newFFIEvent(Contact, {{"a", "double"}, {"b", "double"}, {"impulse", "float"}}, "BenchContact")

local Follow = {}
Follow.init = function(event, value)
    event.value = value
end
events.newEvent(Follow)

local GLOBAL_FFI_EVENTS = FFIEvents.global()

local router = {}

function router.make(name)
    local messages = events.newMessageBus()
    local eventPool = pool.newTablePool({clearOn = "acquire", maxSize = 32})
    local ffiSliceId = GLOBAL_FFI_EVENTS:acquireSlice()
    local checksum = 0
    local calls = 0
    local function read()
        local sum, count = checksum, calls
        checksum, calls = 0, 0
        return sum, count
    end
    local function tick(event)
        calls = calls + 1
        checksum = checksum + event.value
    end

    -- WorldImpl:emit, minus the slot unpacking.
    local function emitByType(address, eventOrType, ...)
        if type(eventOrType) == "table" and rawget(eventOrType, "init") ~= nil then
            if not messages:hasObservers(address, eventOrType) then
                return
            end
            if eventOrType.__tecs_ffi then
                local ffiEvent = GLOBAL_FFI_EVENTS:vendEvent(ffiSliceId, eventOrType)
                ffiEvent.eventId = eventOrType.eventId
                ffiEvent.typeId = eventOrType.__tecs_ffi_typeId
                eventOrType.init(ffiEvent, ...)
                messages:emit(address, ffiEvent)
                GLOBAL_FFI_EVENTS:clearSlice(ffiSliceId)
            else
                local eventId = eventOrType.eventId
                local eventTable = eventPool:acquire()
                eventTable.eventId = eventId
                setmetatable(eventTable, eventOrType.__tecs_mt)
                eventOrType.init(eventTable, ...)
                messages:emit(address, eventTable)
                eventPool:release(eventTable)
            end
        else
            messages:emit(address, eventOrType)
        end
    end

    if name == "no-observers" then
        messages:observe(1, Tick, tick)
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(2, Tick, index)
                end
            end,
            read = read,
        }
    elseif name == "observers-1" or name == "observers-4" or name == "observers-32" then
        local count = tonumber(name:match("%d+$"))
        for _ = 1, count do
            messages:observe(1, Tick, tick)
        end
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(1, Tick, index)
                end
            end,
            read = read,
        }
    elseif name == "addresses-10000" then
        for address = 1, ADDRESSES do
            messages:observe(address, Tick, tick)
        end
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(index % ADDRESSES + 1, Tick, index)
                end
            end,
            read = read,
        }
    elseif name == "record-pool" then
        messages:observe(1, Damage, function(event)
            calls = calls + 1
            checksum = checksum + event.amount + event.source + event.knockback + #event.kind
            if event.critical then
                checksum = checksum + 1
            end
        end)
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(1, Damage, index, 3, nil, nil, 0.5)
                end
            end,
            read = read,
        }
    elseif name == "struct-arena" then
        messages:observe(1, Contact, function(event)
            calls = calls + 1
            checksum = checksum + event.a + event.b + event.impulse
        end)
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(1, Contact, index, 2, 0.5)
                end
            end,
            read = read,
        }
    elseif name == "deliver" then
        messages:observe(1, Tick, tick)
        local held = Tick(0)
        return {
            run = function(n)
                for index = 1, n do
                    held.value = index
                    emitByType(1, held)
                end
            end,
            read = read,
        }
    elseif name == "nested" then
        messages:observe(1, Tick, function(event)
            calls = calls + 1
            checksum = checksum + event.value
            emitByType(2, Follow, event.value * 2)
        end)
        messages:observe(2, Follow, function(event)
            calls = calls + 1
            checksum = checksum + event.value
        end)
        return {
            run = function(n)
                for index = 1, n do
                    emitByType(1, Tick, index)
                end
            end,
            read = read,
        }
    elseif name == "once" then
        return {
            run = function(n)
                for index = 1, n do
                    messages:observeOnce(1, Tick, tick)
                    emitByType(1, Tick, index)
                end
            end,
            read = read,
        }
    elseif name == "churn" then
        return {
            run = function(n)
                for index = 1, n do
                    messages:observe(index, Tick, tick, "churn")
                    messages:stopObserving(index, Tick, "churn")
                end
            end,
            read = read,
        }
    end
    error("unknown scenario " .. tostring(name))
end

return router
