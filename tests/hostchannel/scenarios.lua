-- Applications the host channel's contract suite runs, one per scenario name.
--
-- Each runs as the application's root coroutine under whatever drives it: the
-- browser guest emulator in `guest.lua`, or an embedding host. A scenario
-- returns a table the driver's test inspects; a contract violation is an error.

local host = require("nupp.host")
local span = require("nupp.mem.span")
local tasks = require("nupp.tasks")
local time = require("nupp.time")
local ffi = require("ffi")

local unpackValues = rawget(_G, "unpack") or table.unpack

local function packed(...)
    return {n = select("#", ...), ...}
end

local function bytesOf(view)
    local pointer, count = view:ref()
    return ffi.string(pointer, count)
end

-- LuaJIT honours no __len on a table, so a span's length is read through ref.
local function lengthOf(view)
    local _, count = view:ref()
    return count
end

local function pattern(size, seed)
    local buffer = ffi.new("uint8_t[?]", size)
    for index = 0, size - 1 do
        buffer[index] = (index * 31 + seed) % 251
    end
    return ffi.string(buffer, size)
end

local function sum(text)
    local total = 0
    local pointer = ffi.cast("const uint8_t *", text)
    for index = 0, #text - 1 do
        total = (total + pointer[index] * (index % 7 + 1)) % 2147483647
    end
    return total
end

local function failure(f, ...)
    local ok, problem = pcall(f, ...)
    assert(not ok, "expected a failure")
    return tostring(problem)
end

local function scoped(timeoutMs, body)
    local scope = tasks.open(nil, timeoutMs)
    local ok, problem = pcall(body, scope)
    local closed, closeProblem = pcall(scope.close, scope)
    return ok and closed, ok and closeProblem or problem
end

local scenarios = {}

function scenarios.arity()
    local echoed = packed(host.call("test.echo", 1, nil, "two", true, nil))
    local none = packed(host.call("test.echo"))
    local onlyNil = packed(host.call("test.echo", nil))
    local interior = packed(host.call("test.results"))
    return {
        echoed = {n = echoed.n, a = echoed[1], b = echoed[2], c = echoed[3], d = echoed[4], e = echoed[5]},
        none = none.n,
        onlyNil = onlyNil.n,
        interior = {n = interior.n, a = interior[1], b = interior[2], c = interior[3]},
    }
end

function scenarios.refusals()
    local refused = {}
    refused.nan = failure(host.call, "test.echo", 0 / 0)
    refused.infinity = failure(host.call, "test.echo", 1, math.huge)
    refused.text = failure(host.call, "test.echo", "\255\254")
    refused.long = failure(host.call, "test.echo", string.rep("x", 64 * 1024 + 1))
    refused.table = failure(host.call, "test.echo", {})
    refused.handler = failure(host.call, "test.echo", print)
    refused.reserved = failure(host.call, "nupp.secret")
    refused.kind = failure(host.call, "nodots")
    refused.unknown = failure(host.call, "test.nobody")
    refused.failed = failure(host.call, "test.fail", "why")
    return refused
end

function scenarios.bytes()
    local small = pattern(5000, 3)
    local large = pattern(3 * 1024 * 1024 + 17, 5)
    local length, total, back = host.call("test.digest", span.fromString(small))
    local largeLength, largeTotal = host.call("test.digest", span.fromString(large))
    local three = {pattern(1024 * 1024, 7), pattern(1024 * 1024, 8), pattern(1024 * 1024, 9)}
    local count = host.call("test.count", span.fromString(three[1]), span.fromString(three[2]), span.fromString(three[3]))
    local made = host.call("test.make", 8 * 1024 * 1024, 11)
    local empty = host.call("test.make", 0, 1)
    return {
        small = length == #small and total == sum(small) and bytesOf(back) == small,
        large = largeLength == #large and largeTotal == sum(large),
        three = count == 3 * 1024 * 1024,
        made = lengthOf(made) == 8 * 1024 * 1024 and bytesOf(made) == pattern(8 * 1024 * 1024, 11),
        empty = lengthOf(empty) == 0,
    }
end

-- A slow call holding its bytes must not hold the frame: a deadline beside it
-- fires on time, and the slow call still gets its whole answer.
function scenarios.slowCallBesideADeadline()
    local started = time.now()
    local firedAfter
    local slowAnswer
    local outer = tasks.open()
    local slow = outer:spawn(function()
        local length = host.call("test.slow", span.fromString(pattern(4096, 1)), 1000)
        return length
    end)
    outer:spawn(function()
        scoped(50, function()
            time.sleep(5000)
        end)
        firedAfter = time.now() - started
    end)
    slowAnswer = slow:await()
    outer:close()
    return {firedAfter = firedAfter, slow = slowAnswer}
end

local function openedRelease(id)
    host.post("test.close", id)
end

-- The open is answered after its caller gave up; `late` releases what it named.
function scenarios.lateReleases()
    local open = host.bind("test.open", function(id)
        openedRelease(id)
    end)
    local ok, problem = scoped(30, function(scope)
        scope:spawn(function()
            return open(200)
        end):await()
    end)
    -- Let the late answer arrive and the release ship.
    time.sleep(400)
    local live = host.call("test.live")
    return {cancelled = not ok and tostring(problem) or "not cancelled", live = live}
end

-- Two opens answered in the same pass resume both callers; the first to run
-- cancels the other before it runs. The answer that resumed the cancelled
-- caller was never taken, so it is `late`'s to release like any other.
function scenarios.answeredThenCancelled()
    local open = host.bind("test.open", function(id)
        openedRelease(id)
    end)
    local lateRuns = 0
    local counted = host.bind("test.open", function(id)
        lateRuns = lateRuns + 1
        openedRelease(id)
    end)
    local ok = scoped(nil, function(scope)
        local function openThenCancel(bound)
            return function()
                local id = bound(0)
                openedRelease(id)
                scope:cancel("the first answer to run cancels the other")
            end
        end
        scope:spawn(openThenCancel(open))
        scope:spawn(openThenCancel(counted))
    end)
    time.sleep(100)
    return {cancelled = not ok, live = host.call("test.live")}
end

-- A late handler that would wait is refused, and other deliveries carry on. A
-- call the host answers at once never waits, so this one is answered later.
function scenarios.lateCannotWait()
    local open = host.bind("test.open", function(id)
        host.call("test.slow", "x", 10)
        host.post("test.close", id)
    end)
    scoped(30, function(scope)
        scope:spawn(function()
            return open(100)
        end):await()
    end)
    time.sleep(300)
    local echoed = host.call("test.echo", "still answering")
    return {echoed = echoed, live = host.call("test.live")}
end

-- Cancelled before its frame shipped, a request never reaches the page.
function scenarios.cancelBeforeShipping()
    local ok = scoped(0, function(scope)
        scope:spawn(function()
            host.call("test.count", "never")
        end):await()
    end)
    return {cancelled = not ok, seen = host.call("test.seen", "test.count")}
end

-- Cancelled while its bytes are being fetched, a result is the page's to release.
function scenarios.cancelMidFetch()
    local ok = scoped(40, function(scope)
        scope:spawn(function()
            return host.call("test.resource", 6 * 1024 * 1024)
        end):await()
    end)
    time.sleep(100)
    local after = host.call("test.make", 8 * 1024 * 1024, 2)
    -- The host releases what was abandoned on its own schedule, a hop later
    -- when a Worker relays to the page, so wait for it rather than race it.
    local live = host.call("test.live")
    for _ = 1, 40 do
        if live == 0 then
            break
        end
        time.sleep(50)
        live = host.call("test.live")
    end
    return {cancelled = not ok, live = live, after = lengthOf(after)}
end

-- Four results that each fill the guest's reassembly budget are admitted one at
-- a time and all arrive.
function scenarios.concurrentLargeResults()
    local sizes = {}
    local scope = tasks.open()
    local children = {}
    for index = 1, 4 do
        children[index] = scope:spawn(function()
            local made = host.call("test.make", 8 * 1024 * 1024, index)
            return lengthOf(made)
        end)
    end
    for index = 1, 4 do
        sizes[index] = children[index]:await()
    end
    scope:close()
    local tooLarge = failure(host.call, "test.makeMany", 2, 5 * 1024 * 1024)
    return {sizes = sizes, tooLarge = tooLarge, live = host.call("test.live")}
end

-- More small requests than one frame carries all ship and all answer.
function scenarios.manySmallCalls()
    local scope = tasks.open()
    local children = {}
    for index = 1, 600 do
        children[index] = scope:spawn(function()
            return host.call("test.echo", string.rep("y", 3000) .. index)
        end)
    end
    local correct = 0
    for index = 1, 600 do
        if children[index]:await() == string.rep("y", 3000) .. index then
            correct = correct + 1
        end
    end
    scope:close()
    return {correct = correct}
end

function scenarios.posts()
    for index = 1, 10 do
        host.post("test.note", index, span.fromString(pattern(100, index)))
    end
    local notes = host.call("test.notes")
    return {notes = notes}
end

-- Inbound messages become routed events under each route's policy, and
-- outbound ones ship under theirs. The host's pushes all happen inside one
-- handler, so one turn delivers them together, in the order they were pushed
-- whatever their kinds.
function scenarios.streams()
    local hostevents = require("hostevents")
    local events = require("nupp.events")
    local bus = events.newMessageBus()
    local moves, keys, order = {}, {}, {}
    bus:observe(1, hostevents.PointerMove, function(event)
        moves[#moves + 1] = event.x .. "," .. event.y
        order[#order + 1] = moves[#moves]
    end, "moves")
    bus:observe(1, hostevents.KeyPress, function(event)
        keys[#keys + 1] = event.key .. (event.down and "+" or "-")
        order[#order + 1] = keys[#keys]
    end, "keys")
    local moveRoute = host.route("test.move", hostevents.PointerMove, bus, 1, "dropOldest", 3)
    local keyRoute = host.route("test.key", hostevents.KeyPress, bus, 1, "latest")
    host.call("test.pushInput", 5)
    time.sleep(30)
    local packet = host.bindSend("test.packet", "latest")
    packet(span.fromString("aaa"))
    packet(span.fromString("bbbb"))
    local logged = host.bindSend("test.log", "dropOldest", 2)
    logged("one")
    logged("two")
    logged("three")
    local blocked = host.bindSend("test.block", "block", 2)
    blocked("x")
    blocked("y")
    blocked("z")
    time.sleep(30)
    local outbound = host.call("test.outbound")
    local dropped = moveRoute:dropped()
    moveRoute:close()
    keyRoute:close()
    return {
        moves = table.concat(moves, " "),
        keys = table.concat(keys, " "),
        order = table.concat(order, " "),
        dropped = dropped,
        outbound = outbound,
    }
end

-- An observer that raises costs only its own message: the failure is reported
-- and the rest of the pass is delivered in order.
function scenarios.streamObserverFails()
    local hostevents = require("hostevents")
    local events = require("nupp.events")
    local bus = events.newMessageBus()
    local order = {}
    bus:observe(1, hostevents.PointerMove, function(event)
        order[#order + 1] = event.x .. "," .. event.y
        if event.x == 3 then
            error("observer refused 3")
        end
    end, "moves")
    bus:observe(1, hostevents.KeyPress, function(event)
        order[#order + 1] = event.key .. (event.down and "+" or "-")
    end, "keys")
    local moveRoute = host.route("test.move", hostevents.PointerMove, bus, 1, "dropOldest", 16)
    local keyRoute = host.route("test.key", hostevents.KeyPress, bus, 1, "dropOldest", 16)
    host.call("test.pushInput", 5)
    time.sleep(30)
    moveRoute:close()
    keyRoute:close()
    return {order = table.concat(order, " ")}
end

-- Natively, with no suspension handler around it, a call the host does not
-- answer at once is refused rather than left to block the host's own call.
function scenarios.unansweredWithoutAHandler()
    local problem = failure(host.call, "test.slow", span.fromString("x"), 10)
    local echoed = host.call("test.echo", "answered at once")
    return {problem = problem, echoed = echoed}
end

return scenarios
