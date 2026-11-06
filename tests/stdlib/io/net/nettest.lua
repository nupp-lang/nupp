local testAssert = require("assert")
-- The platform-neutral socket state machine.
--
-- Driven by a fake backend, on purpose: what is checked here is the policy above
-- the Rust-backed provider -- the three-state read, the bounded send queue, what
-- a direction view's close does -- so the test supplies the platform and the
-- module supplies the behaviour. `netnativetest.lua` is the other half, where
-- real sockets check that the provider means what this one assumes.
local net

local function install(provider)
    net = require("helpers.providerstate").load("net", provider)
end

local io_ = require("io")
local native = require("nupp.compiler.native")

-- A backend whose connection is a script. Nothing here blocks, which is the
-- contract a real backend also has. The interesting cases are the ones where a
-- read makes no progress and the caller must come back for it, so `arriving` is
-- a list of what each successive poll produces: false means nothing yet.
local function fakeBackend(script)
    local state = {
        runs = 0,
        written = {},
        pending = 0,
        shutdown = false,
        closedStreams = 0,
        closedListeners = 0,
        accepted = 0,
    }
    local arriving = script.arriving or {}
    local at = 1
    local self = {}

    function self:listen(host, port, backlog, reusePort)
        if script.listenFails then
            return nil, "nupp: could not listen: " .. script.listenFails
        end
        state.reuseport = reusePort
        state.backlog = backlog

        return {host = host, port = port}
    end

    function self:listenerport(listener)
        return listener.port == 0 and 54321 or listener.port
    end

    function self:accept(listener)
        state.accepted = state.accepted + 1
        if script.acceptFails then
            return nil, "nupp: could not accept: " .. script.acceptFails
        end
        if state.accepted < (script.acceptAfter or 1) then
            return nil
        end

        return {which = "accepted"}
    end

    function self:closelistener(listener)
        state.closedListeners = state.closedListeners + 1
    end

    function self:connect(host, port, timeoutMs)
        state.connectTimeout = timeoutMs
        if script.connectFails then
            return nil, "nupp: could not connect: " .. script.connectFails
        end

        return {host = host, port = port}
    end

    function self:connectpoll(request)
        state.connectPolls = (state.connectPolls or 0) + 1
        if state.connectPolls < (script.connectAfter or 1) then
            return nil
        end

        return {which = "connected"}
    end

    function self:closeconnect(request)
        state.closedConnect = true
    end

    function self:read(stream, wanted)
        if script.readFails then
            return nil, "nupp: could not read: " .. script.readFails
        end
        local next = arriving[at]
        at = at + 1
        if next == nil or next == false then
            return ""
        end

        return next:sub(1, wanted)
    end

    function self:ended(stream)
        -- The end is only ever after the script has run out, which is what makes a
        -- gap in the middle of it a quiet connection rather than a finished one.
        return at > #arriving and script.ends ~= false
    end

    function self:write(stream, bytes)
        if script.backpressureOnce and not state.backpressured then
            state.backpressured = true
            state.pending = script.backendPending or 1
            return 0
        end
        state.written[#state.written + 1] = bytes
        -- A fake peer that never drains is how the high-water path is exercised.
        state.pending = state.pending + (script.drains == false and #bytes or 0)

        return #bytes
    end

    function self:pending(stream)
        return state.pending
    end

    function self:writefailed(stream)
        return script.writeFails == true
    end

    function self:shuttingdown(stream)
        return state.shuttingdown == true
    end

    function self:shutdownwrite(stream)
        state.shutdown = true
        -- A real platform takes the request and finishes it later; the fake
        -- finishes it on the next turn of the reactor, so a caller that waits for
        -- it makes progress rather than spinning.
        state.shuttingdown = script.shutdownPends == true
        return true
    end

    function self:keepalive(stream, enabled, delayMs)
        state.keepalive = {enabled = enabled, delayMs = delayMs}
        return true
    end

    function self:closestream(stream)
        state.closedStreams = state.closedStreams + 1
    end

    function self:binddatagram(host, port, reusePort)
        if script.bindFails then
            return nil, "nupp: could not bind: " .. script.bindFails
        end
        state.datagramReusePort = reusePort

        return {host = host, port = port}
    end

    function self:datagramport(socket)
        return socket.port == 0 and 41234 or socket.port
    end

    function self:receive(socket, maximum)
        state.receives = (state.receives or 0) + 1
        if script.receiveFails then
            return nil, nil, nil, nil, "nupp: could not receive: " .. script.receiveFails
        end
        local next = (script.datagrams or {})[state.receives]
        if next == nil or next == false then
            return nil
        end
        local bytes = next.bytes:sub(1, maximum)

        return bytes, next.host or "10.0.0.1", next.port or 5000, #bytes < #next.bytes
    end

    function self:sendto(socket, host, port, bytes)
        state.sent = state.sent or {}
        state.sent[#state.sent + 1] = {host = host, port = port, bytes = bytes}
        return true
    end

    function self:closedatagram(socket)
        state.closedDatagrams = (state.closedDatagrams or 0) + 1
    end

    function self:run(timeoutMs)
        state.runs = state.runs + 1
        -- Draining one queued write per turn, so a caller waiting on the send
        -- bound makes progress rather than spinning forever.
        if state.pending > 0 and script.drainsOnRun then
            state.pending = 0
        end
        state.shuttingdown = false
    end

    return self, state
end

local function connected(script)
    local backend, state = fakeBackend(script or {})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    return stream, state
end

local M = {}

function M.publicNetworkImportDoesNotInitializeTls()
    local underlying = {
        connect = function()
        end
    }
    local load = require("helpers.providerstate").instance({["io.net"] = true}, {["nupp.io.net"] = underlying,}, {
        ["io.net.internal.tls"] = function()
            error("plain network import initialized TLS")
        end,
    })
    local api = load("io.net")
    assert(api.connect == underlying.connect)
    assert(type(api.tlsclient) == "function" and type(api.tlsserver) == "function")
    assert(api.tls == nil and api.client == nil and api.server == nil)
end

function M.aQuietConnectionIsNotTheEnd()
    -- The whole point of the three-state read: a gap in the middle of a stream
    -- must not read as end of stream, or a parser stops on the first lull.
    local stream, state = connected({arriving = {"ab", false, "cd"}})
    testAssert.eq(assert(stream:read(8)), "ab", "the first bytes arrive")
    testAssert.eq(assert(stream:read(8)), "cd", "and so do the ones after the gap")
    testAssert.eq(assert(stream:read(8)), "", "only a finished stream reads empty")
    assert(state.runs > 0, "the gap drove the reactor rather than spinning")
    stream:close()
end

function M.emptyIsOnlyEverTheEnd()
    local stream = connected({arriving = {"x"}})
    testAssert.eq(assert(stream:read(4)), "x", "the byte arrives")
    testAssert.eq(assert(stream:read(4)), "", "then the end")
    assert(stream:isended(), "and the stream says so")
    stream:close()
end

function M.readReportsWhyItCouldNotRead()
    local stream = connected({readFails = "connection reset"})
    local got, why = stream:read(4)
    testAssert.eq(got, nil, "a failed read answers nil")
    assert(why ~= nil and why:find("connection reset", 1, true) ~= nil, "and carries what the platform said")
    stream:close()
end

function M.writeCompletesTheWholeValue()
    local stream, state = connected({})
    assert(stream:write("payload"), "the write completes")
    testAssert.eq(table.concat(state.written), "payload", "and everything landed")
    stream:close()
end

function M.writeLargerThanTheBoundStillProceeds()
    -- The bound governs how much is queued at one time, not how much may be
    -- sent. An input larger than the high-water mark must not deadlock.
    local backend, state = fakeBackend({drains = false, drainsOnRun = true})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80, sendhighwater = 4}))
    assert(stream:write("0123456789"), "a value larger than the bound is written")
    testAssert.eq(table.concat(state.written), "0123456789", "in pieces, all of them")
    assert(#state.written > 1, "and it really was more than one piece")
    stream:close()
end

function M.aBackendMayApplyAStricterSendBound()
    -- The Rust transport owns a structural ceiling even when the caller chooses
    -- a larger policy bound. Zero acceptance means wait for the observed native
    -- queue to retire, not spin while it remains below the caller's bound.
    local backend, state = fakeBackend({backpressureOnce = true, backendPending = 4, drainsOnRun = true,})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80, sendhighwater = 16}))
    assert(stream:write("payload"), "the write resumes after native backpressure")
    testAssert.eq(table.concat(state.written), "payload", "and accepts every byte exactly once")
    assert(state.runs > 0, "native backpressure drove the reactor rather than spinning")
    stream:close()
end

function M.writeRefusesAfterTheSendingHalfIsClosed()
    local stream, state = connected({})
    assert(stream:shutdownwrite(), "the sending half closes")
    assert(state.shutdown, "which reaches the platform")
    local wrote, why = stream:write("late")
    testAssert.eq(wrote, false, "a write after it is refused")
    assert(why ~= nil, "and says why")
    stream:close()
end

function M.pendingIsALocalFact()
    local stream, state = connected({drains = false})
    assert(stream:write("four"), "the write completes locally")
    testAssert.eq(stream:pending(), 4, "and the bytes are still this process's")
    stream:close()
end

function M.closingTheWriterViewHalfCloses()
    -- The departure from a process stream's asWriter that the proposal records: a
    -- socket has one handle with two halves, so closing the writing view ends a
    -- direction rather than returning a resource.
    local stream, state = connected({})
    local writer = stream:aswriter()
    writer:close()
    assert(state.shutdown, "closing the writer view half-closes")
    testAssert.eq(state.closedStreams, 0, "and leaves the connection open")
    stream:close()
    testAssert.eq(state.closedStreams, 1, "which the owner still has to close")
end

function M.closingTheReaderViewLeavesTheConnection()
    local stream, state = connected({arriving = {"ab"}})
    local reader = stream:asreader()
    testAssert.eq(assert(reader:read(4)), "ab", "the view reads")
    reader:close()
    local got, why = reader:read(4)
    testAssert.eq(got, nil, "a closed reader view refuses")
    assert(why ~= nil, "and says why")
    testAssert.eq(state.closedStreams, 0, "without touching the connection")
    testAssert.eq(state.shutdown, false, "and without ending the sending half")
    stream:close()
end

function M.directionViewsExposeOnlyTheirOwnHalf()
    local stream = connected({arriving = {"readable"}})
    local reader = stream:asreader()
    local wrote, writeWhy = reader:write("wrong way")
    testAssert.eq(wrote, false, "a reading view cannot write")
    assert(tostring(writeWhy):find("read-only", 1, true) ~= nil, "and says which direction it has")
    local flushed, flushWhy = reader:flush()
    testAssert.eq(flushed, false, "a reading view cannot flush writes")
    assert(tostring(flushWhy):find("read-only", 1, true) ~= nil, "and gives the same direction reason")
    reader:close()

    local writer = stream:aswriter()
    local bytes, readWhy = writer:read(1)
    testAssert.eq(bytes, nil, "a writing view cannot read")
    assert(tostring(readWhy):find("write-only", 1, true) ~= nil, "and says which direction it has")
    writer:close()
    stream:close()
end

function M.aViewReadsThroughTheSharedContract()
    local stream = connected({arriving = {"shared"}})
    local reader = stream:asreader()
    testAssert.eq(assert(reader:read(6)), "shared", "a view is a Reader")
    reader:close()
    stream:close()
end

function M.acceptWaitsForAConnection()
    local backend, state = fakeBackend({acceptAfter = 3})
    install(backend)
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local stream = assert(listener:accept())
    testAssert.eq(state.accepted, 3, "a quiet listener came back for it")
    assert(state.runs > 0, "driving the reactor while it waited")
    stream:close()
    listener:close()
end

function M.aListenerReportsThePortItGot()
    local backend = fakeBackend({})
    install(backend)
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    testAssert.eq(listener:port(), 54321, "asking for zero answers what was chosen")
    listener:close()
end

function M.reusePortIsPassedThroughRatherThanAssumed()
    local backend, state = fakeBackend({})
    install(backend)
    local listener = assert(net.listen({host = "127.0.0.1", port = 0, reuseport = true}))
    testAssert.eq(state.reuseport, true, "the request reaches the platform")
    listener:close()
    local plain = assert(net.listen({host = "127.0.0.1", port = 0}))
    testAssert.eq(state.reuseport, false, "and is off unless asked for")
    plain:close()
end

function M.listenReportsWhyItCouldNotBind()
    install((fakeBackend({listenFails = "address already in use"})))
    local listener, why = net.listen({host = "127.0.0.1", port = 80})
    testAssert.eq(listener, nil, "a refused bind answers nil")
    assert(
        why ~= nil and tostring(why):find("address already in use", 1, true) ~= nil,
        "and carries what the platform said"
    )
end

function M.connectReportsWhyItCouldNotConnect()
    install((fakeBackend({connectFails = "connection refused"})))
    local stream, why = net.connect({host = "example", port = 80})
    testAssert.eq(stream, nil, "a refused connect answers nil")
    assert(
        why ~= nil and tostring(why):find("connection refused", 1, true) ~= nil,
        "and carries what the platform said"
    )
    testAssert.eq(why.kind, "refused", "as a refusal a caller can branch on")
end

function M.connectWaitsForTheHandshake()
    local backend, state = fakeBackend({connectAfter = 3})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    testAssert.eq(state.connectPolls, 3, "the connect was come back for")
    assert(state.closedConnect, "and the request was released after it")
    stream:close()
end

function M.aConnectPolledAgainBeforeItRunsResumesOnce()
    -- A host that polls every frame can reach the connect's source again after it
    -- resumed the connect and before the connect runs. That once resumed it twice.
    local backend, state = fakeBackend({connectAfter = 2})
    install(backend)
    local suspension = require("coroutine.sus")
    local suspensionHost = require("coroutine.sus.host")
    local installation = suspensionHost.install({
        park = function(_, waiting)
            while not waiting:ready() do
                suspension.poll()
            end
            suspension.poll()
        end,
        canpark = function()
            return true
        end,
    })
    local connected, stream = pcall(net.connect, {host = "example", port = 80})
    installation:close()
    assert(connected, "the connect completed: " .. tostring(stream))
    testAssert.eq(state.connectPolls, 2, "the finished request was not polled again")
    stream:close()
end

function M.abandoningAConnectReleasesItsRequest()
    local backend, state = fakeBackend({connectAfter = 2})
    install(backend)
    local suspension = require("coroutine.sus")
    local suspensionHost = require("coroutine.sus.host")
    local installation = suspensionHost.install({
        park = function()
        end,
        canpark = function()
            return false
        end,
    })
    local connected, why = pcall(net.connect, {host = "example", port = 80})
    installation:close()
    testAssert.eq(connected, false, "a forbidden park refuses the connect")
    assert(tostring(why):find("cannot suspend", 1, true) ~= nil, "and reports the refused suspension")
    assert(state.closedConnect, "and releases the in-flight connection request")
end

function M.aFailedConnectPollReleasesItsRequest()
    local backend, state = fakeBackend({})
    backend.connectpoll = function()
        error("broken poll")
    end
    install(backend)
    local connected, why = pcall(net.connect, {host = "example", port = 80})
    testAssert.eq(connected, false, "a provider exception refuses the connect")
    assert(tostring(why):find("broken poll", 1, true) ~= nil, "and preserves the provider failure")
    assert(state.closedConnect, "and releases the in-flight connection request")
end

function M.closingIsIdempotent()
    local stream, state = connected({})
    stream:close()
    testAssert.eq(state.closedStreams, 1, "the first close releases")
    testAssert.eq(stream:isreleased(), true, "and the stream says so")
end

function M.aDatagramCarriesItsPeerAndItsLength()
    local backend, state = fakeBackend({datagrams = {{bytes = "ping", host = "10.0.0.7", port = 9001}}})
    install(backend)
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    local buffer = io_.Buffer.create(64)
    local message = assert(socket:receivefrom(buffer, 64))
    testAssert.eq(message.len, 4, "the length is what landed")
    testAssert.eq(buffer:readstring(0, 4), "ping", "and the bytes went into the storage offered")
    testAssert.eq(message.address.host, "10.0.0.7", "the peer's address comes with it")
    testAssert.eq(message.address.port, 9001, "and its port")
    testAssert.eq(message.truncated, false, "a whole datagram is not truncated")
    buffer:close()
    socket:close()
end

function M.aTruncatedDatagramSaysSo()
    -- The security-relevant one: parsing the first part of a larger message
    -- without being told is parsing something nobody sent.
    local backend = fakeBackend({datagrams = {{bytes = "0123456789"}}})
    install(backend)
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    local buffer = io_.Buffer.create(64)
    local message = assert(socket:receivefrom(buffer, 4))
    testAssert.eq(message.len, 4, "only what there was room for landed")
    testAssert.eq(message.truncated, true, "and the caller is told the rest is gone")
    buffer:close()
    socket:close()
end

function M.anEmptyDatagramIsAMessageNotAnAbsence()
    -- A quiet socket comes back for more; an empty datagram is delivered. A
    -- receive that could not tell them apart would make a live peer look silent.
    local backend, state = fakeBackend({datagrams = {false, false, {bytes = "", host = "10.0.0.9", port = 7}},})
    install(backend)
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    local buffer = io_.Buffer.create(64)
    local message = assert(socket:receivefrom(buffer, 64))
    testAssert.eq(message.len, 0, "an empty datagram is zero bytes")
    testAssert.eq(message.address.port, 7, "and still carries the peer that sent it")
    assert(state.receives >= 3, "the quiet polls before it were not messages")
    buffer:close()
    socket:close()
end

function M.sendingNamesThePeer()
    local backend, state = fakeBackend({})
    install(backend)
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    assert(socket:sendto({host = "10.0.0.3", port = 4242}, "reply"), "the send is taken")
    testAssert.eq(state.sent[1].host, "10.0.0.3", "to the address named")
    testAssert.eq(state.sent[1].port, 4242, "and its port")
    testAssert.eq(state.sent[1].bytes, "reply", "with the bytes given")
    socket:close()
end

function M.aDatagramSocketReportsItsPort()
    install((fakeBackend({})))
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    testAssert.eq(socket:port(), 41234, "asking for zero answers what was chosen")
    socket:close()
end

function M.bindReportsWhyItCouldNotBind()
    install((fakeBackend({bindFails = "address already in use"})))
    local socket, why = net.bind({host = "0.0.0.0", port = 53})
    testAssert.eq(socket, nil, "a refused bind answers nil")
    assert(
        why ~= nil and tostring(why):find("address already in use", 1, true) ~= nil,
        "and carries what the platform said"
    )
end

function M.flushWaitsForTheQueueToEmpty()
    local backend, state = fakeBackend({drains = false, drainsOnRun = true})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    assert(stream:write("queued"), "the write completes locally")
    testAssert.eq(stream:pending(), 6, "and the bytes are still held")
    assert(stream:flush(), "the flush waits for them to leave")
    testAssert.eq(stream:pending(), 0, "so nothing is left")
    stream:close()
end

function M.flushReportsAWriteThatFailedAfterItWasAccepted()
    -- A failed write leaves nothing pending, so an empty queue is not by itself
    -- success: without asking about the failure a caller sees success at the
    -- exact moment its bytes were lost.
    local backend = fakeBackend({writeFails = true})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    assert(stream:write("gone"), "the platform accepted it")
    local ok, why = stream:flush()
    testAssert.eq(ok, false, "but the flush does not report success")
    assert(why ~= nil, "and says a write did not reach the platform")
    stream:close()
end

function M.closingAWritingViewWaitsForTheDirectionToEnd()
    -- The shutdown request carries no bytes, so waiting on the byte count would
    -- return the moment the writes landed and leave the end of the direction
    -- exactly as cancellable as before.
    local backend, state = fakeBackend({shutdownPends = true})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    local writer = stream:aswriter()
    assert(writer:write("last"), "the view writes")
    writer:close()
    assert(state.shutdown, "the direction was ended")
    testAssert.eq(state.shuttingdown, false, "and the close waited for it to finish")
    stream:close()
end

function M.endingTheSendingHalfWaitsForIt()
    -- The public operation, not only the view's close: a caller that writes,
    -- ends its sending half and then closes must not cancel either.
    local backend, state = fakeBackend({shutdownPends = true})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    assert(stream:write("before the end"), "the write completes")
    assert(stream:shutdownwrite(), "the sending half is ended")
    assert(state.shutdown, "which reached the platform")
    testAssert.eq(state.shuttingdown, false, "and was waited for rather than submitted")
    stream:close()
end

function M.portsAreChecked()
    install((fakeBackend({})))
    local ok = pcall(function()
        return net.listen({host = "127.0.0.1", port = 99999})
    end)
    testAssert.eq(ok, false, "a port outside the range is a mistake at the call site")
    local also = pcall(function()
        return net.connect({host = "example", port = -1})
    end)
    testAssert.eq(also, false, "and so is a negative one")
    local datagram = pcall(function()
        return net.bind({host = "0.0.0.0", port = 70000})
    end)
    testAssert.eq(datagram, false, "on a datagram socket too")
end

function M.listenerBacklogsAndPumpDelaysAreChecked()
    local backend, state = fakeBackend({})
    install(backend)
    for _, backlog in ipairs({0, -1, 4294967296}) do
        local ok = pcall(net.listen, {host = "127.0.0.1", port = 0, backlog = backlog})
        testAssert.eq(ok, false, "an invalid backlog is refused")
    end
    testAssert.eq(state.backlog, nil, "invalid backlogs do not reach the provider")
    local ok = pcall(net.pump, -1)
    testAssert.eq(ok, false, "a negative pump delay is refused")
    testAssert.eq(state.runs, 0, "an invalid delay does not reach the provider")
    local stream = assert(net.connect({host = "example", port = 80}))
    ok = pcall(stream.setkeepalive, stream, true, 4294967296)
    testAssert.eq(ok, false, "a keepalive delay outside the native range is refused")
    testAssert.eq(state.keepalive, nil, "an invalid keepalive delay does not reach the provider")
    stream:close()
end

function M.aSocketPathMayBeAPathValue()
    -- The filesystem names every other io facade accepts: text, a io.Path,
    -- or an application path. The platform receives the text either way.
    local backend, state = fakeBackend({})
    function backend:listenpath(path, backlog)
        state.listenedPath = path
        return {host = "", port = 0}
    end

    function backend:connectpath(path, timeoutMs)
        state.connectedPath = path
        return nil, "nobody there"
    end

    install(backend)
    local paths = require("io.internal.path")
    local listener = assert(net.listen({path = paths.newpath("/tmp/nupp-b04.sock")}))
    testAssert.eq(state.listenedPath, "/tmp/nupp-b04.sock", "a Path listens on its text")
    listener:close()
    local stream, why = net.connect({path = paths.newpath("/tmp/nupp-b04.sock")})
    testAssert.eq(stream, nil, "the fake refuses the connect")
    testAssert.eq(state.connectedPath, "/tmp/nupp-b04.sock", "after receiving the path's text")
    assert(why ~= nil, "and says why")
    local ok, problem = pcall(net.listen, {path = 42})
    testAssert.eq(ok, false, "a number is not a path")
    assert(tostring(problem):find("path", 1, true) ~= nil, tostring(problem))
end

function M.keepAliveDelayIsMilliseconds()
    -- Every other duration in the io facades is milliseconds; this one used to be
    -- seconds, so a caller who wrote 30000 asked for eight hours.
    local backend, state = fakeBackend({})
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    assert(stream:setkeepalive(true, 1500), "the option was set")
    testAssert.eq(state.keepalive.delayMs, 1500, "and the provider received milliseconds unchanged")
    stream:close()
end

function M.providerByteCountsCannotExceedTheRequest()
    local backend = fakeBackend({})
    backend.read = function()
        return "too many"
    end
    install(backend)
    local stream = assert(net.connect({host = "example", port = 80}))
    local bytes, why = stream:read(2)
    testAssert.eq(bytes, nil, "an oversized provider read is refused")
    assert(tostring(why):find("more bytes", 1, true) ~= nil, "and says which contract was broken")
    stream:close()

    backend = fakeBackend({})
    backend.write = function(_, _, bytes)
        return #bytes + 1
    end
    install(backend)
    stream = assert(net.connect({host = "example", port = 80}))
    local wrote, writeWhy = stream:write("short")
    testAssert.eq(wrote, false, "an oversized provider write count is refused")
    assert(tostring(writeWhy):find("invalid write count", 1, true) ~= nil, "and says which contract was broken")
    stream:close()

    backend = fakeBackend({})
    backend.receive = function()
        return "payload", nil, nil, nil
    end
    install(backend)
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    local destination = io_.Buffer.create()
    local message, datagramWhy = socket:receivefrom(destination, 4)
    testAssert.eq(message, nil, "an oversized datagram with no peer is refused")
    assert(tostring(datagramWhy):find("invalid datagram", 1, true) ~= nil, "and reports the malformed result")
    destination:close()
    socket:close()
end

function M.netAndTlsSelectTheUnifiedRustProvider()
    local netFeature = assert(native.feature("native.net"))
    testAssert.eq(netFeature.provider, "nupp_native", "network provider")
    testAssert.eq(netFeature.providerDriver, "native-rust", "network provider driver")
    testAssert.eq(netFeature.providerFeature, "net", "network provider feature")
    testAssert.eq(netFeature.library, "nupp_native", "network provider library")
    local tlsFeature = assert(native.feature("native.tls"))
    testAssert.eq(tlsFeature.provider, "nupp_native", "TLS provider")
    testAssert.eq(tlsFeature.providerDriver, "native-rust", "TLS provider driver")
    testAssert.eq(tlsFeature.providerFeature, "tls", "TLS provider feature")
    testAssert.eq(tlsFeature.library, "nupp_native", "TLS provider library")
    local expanded = native.expand({["native.tls"] = true})
    assert(expanded["native.net"], "TLS omitted its Rust transport")
    assert(expanded["runtime.native"], "networking omitted the native ABI runtime")
end

return M
