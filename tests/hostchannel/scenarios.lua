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
    local made = host.call("test.make", 8 * 1024 * 1024 + 3, 11)
    local empty = host.call("test.make", 0, 1)
    return {
        small = length == #small and total == sum(small) and bytesOf(back) == small,
        large = largeLength == #large and largeTotal == sum(large),
        three = count == 3 * 1024 * 1024,
        made = lengthOf(made) == 8 * 1024 * 1024 + 3 and bytesOf(made) == pattern(8 * 1024 * 1024 + 3, 11),
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
            return host.call("test.resource", 12 * 1024 * 1024)
        end):await()
    end)
    time.sleep(100)
    local after = host.call("test.make", 16 * 1024 * 1024, 2)
    return {cancelled = not ok, live = host.call("test.live"), after = lengthOf(after)}
end

-- Four results that each fill the guest's reassembly budget are admitted one at
-- a time and all arrive.
function scenarios.concurrentLargeResults()
    local sizes = {}
    local scope = tasks.open()
    local children = {}
    for index = 1, 4 do
        children[index] = scope:spawn(function()
            local made = host.call("test.make", 16 * 1024 * 1024, index)
            return lengthOf(made)
        end)
    end
    for index = 1, 4 do
        sizes[index] = children[index]:await()
    end
    scope:close()
    local tooLarge = failure(host.call, "test.makeMany", 2, 9 * 1024 * 1024)
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

-- Natively, with no suspension handler around it, a call the host does not
-- answer at once is refused rather than left to block the host's own call.
function scenarios.unansweredWithoutAHandler()
    local problem = failure(host.call, "test.slow", span.fromString("x"), 10)
    local echoed = host.call("test.echo", "answered at once")
    return {problem = problem, echoed = echoed}
end

return scenarios
