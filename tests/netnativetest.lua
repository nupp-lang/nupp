local testAssert = require("assert")
-- Real sockets, against the Rust-backed provider.
--
-- The other half of `nettest.lua`: that one drives the state machine with a fake
-- platform, and this one checks that the platform means what the state machine
-- assumes. Everything here is loopback and an ephemeral port, so nothing depends
-- on a fixed port being free or on anything outside this machine.
local net = require("io.net")
local io_ = require("io")
local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

-- A listener, a connection to it, and the connection it accepted.
local function pair()
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local bound = listener:port()
    assert(bound > 0, "an ephemeral bind reports the port it got")
    local client = assert(net.connect({host = "127.0.0.1", port = bound}))
    local served = assert(listener:accept())

    return listener, client, served
end

local M = {}

function M.theModuleExampleConnectsItsOwnPeer()
    local path = HERE .. "/../src/io/net/init.nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local example = assert(source:match("```nupp\n(.-)\n```"), "the module has an opening example")
    local parser = require("nupp.compiler.syntax.parser")
    local parsed = parser.parse(example, "net-doc-example.nupp")
    test.eq(#parsed.errors, 0)
    local env = require("nupp.compiler.project.env").new(HERE .. "/..")
    for _, diagnostic in ipairs(require("fragment").check(parsed, "net-doc-example.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    local code, diagnostics = require("nupp.compiler.lua.gen").generate(parsed, "net-doc-example.nupp")
    test.eq(#diagnostics, 0)
    local output = {}
    local chunk = assert(loadstring(code))
    setfenv(
        chunk,
        setmetatable(
            {
                print = function(value)
                    output[#output + 1] = value
                end
            },
            {__index = _G}
        )
    )
    chunk()
    test.eq(table.concat(output, "\n"), "x")
end

function M.bytesCrossALoopbackConnection()
    local listener, client, served = pair()
    assert(client:write("hello sockets"), "the client writes")
    testAssert.eq(assert(served:read(64)), "hello sockets", "and the server reads them back")
    served:close()
    client:close()
    listener:close()
end

function M.aHalfCloseIsTheEndInOneDirectionOnly()
    -- The three-state read, against a real peer: after the client half-closes the
    -- server reads empty, and the server can still write back.
    local listener, client, served = pair()
    assert(client:shutdownwrite(), "the client ends its sending half")
    testAssert.eq(assert(served:read(64)), "", "which the server reads as the end")
    assert(served:isended(), "and the server says the peer is done")
    assert(served:write("bye"), "while the other direction still writes")
    testAssert.eq(assert(client:read(64)), "bye", "and the client still reads")
    served:close()
    client:close()
    listener:close()
end

function M.aLargeValueCrossesInPieces()
    -- Larger than the send bound and larger than one read, so both the write
    -- loop and the read loop have to come back for the rest.
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local client = assert(net.connect({host = "127.0.0.1", port = listener:port(), sendhighwater = 4096,}))
    local served = assert(listener:accept())

    local payload = ("abcdefgh"):rep(32768)
    assert(client:write(payload), "a 256 KiB value is written whole")
    assert(client:shutdownwrite(), "and the sending half is ended")

    local parts = {}
    while true do
        local chunk = assert(served:read(65536))
        if #chunk == 0 then
            break
        end
        parts[#parts + 1] = chunk
    end
    testAssert.eq(#table.concat(parts), #payload, "every byte arrived")
    testAssert.eq(table.concat(parts), payload, "and in order")
    served:close()
    client:close()
    listener:close()
end

function M.aReaderViewReadsARealConnection()
    local listener, client, served = pair()
    assert(client:write("through the contract"), "the client writes")
    local reader = served:asreader()
    testAssert.eq(
        assert(reader:read(64)),
        "through the contract",
        "a borrowed view reads through the shared Reader contract"
    )
    reader:close()
    served:close()
    client:close()
    listener:close()
end

function M.closingTheWriterViewEndsOneDirection()
    local listener, client, served = pair()
    local writer = client:aswriter()
    assert(writer:write("last"), "the view writes")
    writer:close()
    testAssert.eq(assert(served:read(64)), "last", "the bytes still arrived")
    testAssert.eq(assert(served:read(64)), "", "and the peer saw the end")
    assert(served:isended(), "which is what closing the writer view means")
    -- The connection itself is untouched: the server can still answer.
    assert(served:write("ack"), "the other half is still open")
    testAssert.eq(assert(client:read(64)), "ack", "and the client still reads it")
    served:close()
    client:close()
    listener:close()
end

function M.connectingNowhereReportsWhy()
    -- Port 1 on the loopback is refused rather than filtered, so this fails fast
    -- instead of depending on a timeout.
    local stream, why = net.connect({host = "127.0.0.1", port = 1})
    testAssert.eq(stream, nil, "a refused connect answers nil")
    assert(why ~= nil, "and says why")
    testAssert.eq(why.kind, "refused", "as a refusal, whatever words the platform used: " .. tostring(why))
    assert(("connect: " .. why):find(why.message, 1, true) ~= nil, "and it joins text as its message")
end

function M.aNameThatDoesNotResolveReportsWhy()
    local stream, why = net.connect({host = "invalid.invalid.example.test", port = 80,})
    testAssert.eq(stream, nil, "an unresolvable name answers nil")
    assert(why ~= nil, "and says why")
end

function M.bindingAPrivilegedPortReportsWhyRatherThanRaising()
    -- Port 1 needs privilege this test does not have, which is the ordinary
    -- refusal path. Skipped where the test happens to be running as root.
    local listener, why = net.listen({host = "127.0.0.1", port = 1})
    if listener ~= nil then
        listener:close()
        return
    end
    assert(why ~= nil, "a refused bind says why rather than raising")
end

function M.manyConnectionsAreAcceptedInTurn()
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local bound = listener:port()
    local clients, servers = {}, {}
    for index = 1, 8 do
        clients[index] = assert(net.connect({host = "127.0.0.1", port = bound}))
        assert(clients[index]:write("n" .. index), "each client writes")
    end
    for index = 1, 8 do
        servers[index] = assert(listener:accept())
    end
    local seen = {}
    for index = 1, 8 do
        seen[assert(servers[index]:read(16))] = true
    end
    for index = 1, 8 do
        assert(seen["n" .. index], "every connection's bytes arrived")
        servers[index]:close()
        clients[index]:close()
    end
    listener:close()
end

function M.aClosedConnectionRefusesRatherThanCrashing()
    local listener, client, served = pair()
    served:close()
    local got, why = served:read(8)
    testAssert.eq(got, nil, "a read on a closed connection answers nil")
    assert(why ~= nil, "and says why")
    local wrote = served:write("x")
    testAssert.eq(wrote, false, "and so does a write")
    client:close()
    listener:close()
end

-- Two datagram sockets on the loopback, each on a port the platform chose.
local function datagrams()
    local a = assert(net.bind({host = "127.0.0.1", port = 0}))
    local b = assert(net.bind({host = "127.0.0.1", port = 0}))
    assert(a:port() > 0 and b:port() > 0 and a:port() ~= b:port(), "each socket got its own ephemeral port")
    return a, b
end

function M.aDatagramCrossesWithItsPeer()
    local a, b = datagrams()
    local buffer = io_.newbuffer(2048)
    assert(a:sendto({host = "127.0.0.1", port = b:port()}, "ping"), "a sends")
    local message = assert(b:receivefrom(buffer, 2048))
    testAssert.eq(message.len, 4, "b receives the whole datagram")
    testAssert.eq(buffer:getstring(0, 4), "ping", "into the storage it offered")
    testAssert.eq(message.address.port, a:port(), "carrying the peer that sent it")
    testAssert.eq(message.truncated, false, "and it was not truncated")
    buffer:close()
    b:close()
    a:close()
end

function M.aDatagramLargerThanTheStorageIsReportedTruncated()
    -- Against a real socket, because this is the one a protocol must not get
    -- wrong: parsing the first part of a larger message nobody sent.
    local a, b = datagrams()
    local buffer = io_.newbuffer(2048)
    assert(a:sendto({host = "127.0.0.1", port = b:port()}, ("x"):rep(600)), "a sends 600 bytes")
    local message = assert(b:receivefrom(buffer, 100))
    testAssert.eq(message.len, 100, "b takes what it offered room for")
    testAssert.eq(message.truncated, true, "and is told the rest is gone")
    buffer:close()
    b:close()
    a:close()
end

function M.anEmptyDatagramArrivesAsAMessage()
    local a, b = datagrams()
    local buffer = io_.newbuffer(2048)
    assert(a:sendto({host = "127.0.0.1", port = b:port()}, ""), "a sends an empty datagram")
    local message = assert(b:receivefrom(buffer, 2048))
    testAssert.eq(message.len, 0, "which arrives as zero bytes")
    testAssert.eq(message.address.port, a:port(), "still carrying its peer")
    testAssert.eq(message.truncated, false, "and nothing was dropped")
    buffer:close()
    b:close()
    a:close()
end

function M.datagramsKeepTheirBoundaries()
    -- The property that makes this a message transport rather than a stream one:
    -- three sends are three receives, never one run of bytes.
    local a, b = datagrams()
    local buffer = io_.newbuffer(2048)
    for index = 1, 3 do
        assert(a:sendto({host = "127.0.0.1", port = b:port()}, ("m%d"):format(index)), "each send is its own datagram")
    end
    local seen = {}
    for _ = 1, 3 do
        local message = assert(b:receivefrom(buffer, 2048))
        testAssert.eq(message.len, 2, "each receive is one whole message")
        seen[buffer:getstring(0, 2)] = true
    end
    for index = 1, 3 do
        assert(seen[("m%d"):format(index)], "every message arrived separately")
    end
    buffer:close()
    b:close()
    a:close()
end

function M.sendingNowhereReportsWhyRatherThanRaising()
    local a = assert(net.bind({host = "127.0.0.1", port = 0}))
    -- Port zero is not a destination; the platform refuses it.
    local sent, why = a:sendto({host = "127.0.0.1", port = 0}, "nowhere")
    if sent then
        a:close()
        return
    end
    assert(why ~= nil, "a refused send says why")
    a:close()
end

function M.aConnectGivesUpOnItsDeadline()
    -- A blackholed address: the handshake goes out and nothing ever answers, so
    -- without a deadline this hangs. 203.0.113.0/24 is reserved for documentation
    -- and is not routed, which is what makes it reliably silent.
    local started = os.clock()
    local stream, why = net.connect({host = "203.0.113.1", port = 9, timeoutms = 250,})
    testAssert.eq(stream, nil, "the connect gives up rather than hanging")
    assert(why ~= nil, "and says why")
    testAssert.eq(why.kind, "timeout", "as a timeout: " .. tostring(why))
    assert(os.clock() - started < 10, "well before anything else would time it out")
end

function M.aConnectDeadlineStartsWhenTheConnectionDoes()
    -- Work outside the reactor must not make the next connection's freshly armed
    -- deadline look as though it has already passed.
    local listener, client, served = pair()
    served:close()
    client:close()
    listener:close()

    local until_ = os.clock() + 0.25
    while os.clock() < until_ do
    end

    listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    client = assert(net.connect({host = "127.0.0.1", port = listener:port(), timeoutms = 100,}))
    served = assert(listener:accept())
    served:close()
    client:close()
    listener:close()
end

function M.loadBalancingReuseIsRefusedCleanlyWhereItIsUnsupported()
    -- macOS and Windows have no load-balancing port reuse, and the provider
    -- refuses it rather than giving different semantics. Either answer is
    -- correct here; what must not happen is a raise or a silent downgrade.
    local first, why = net.listen({host = "127.0.0.1", port = 0, reuseport = true})
    if first == nil then
        assert(why ~= nil, "an unsupported request is refused with a reason")
        return
    end
    -- Where it is supported, a second listener may share the port.
    local second = net.listen({host = "127.0.0.1", port = first:port(), reuseport = true})
    if second ~= nil then
        second:close()
    end
    first:close()
end

-- A socket path under the system temporary directory, unique to this run.
local function socketPath(label)
    if jit.os == "Windows" then
        test.suite.skip("Unix domain sockets are unavailable on Windows")
    end
    local base = os.getenv("TMPDIR") or "/tmp/"
    if base:sub(-1) ~= "/" then
        base = base .. "/"
    end

    return base .. "nupp-net-" .. label .. "-" .. tostring(os.time()) .. ".sock"
end

function M.aUnixSocketCarriesBytesLikeATcpOne()
    local path = socketPath("bytes")
    os.remove(path)
    local listener = assert(net.listen({path = path}))
    local client = assert(net.connect({path = path}))
    local served = assert(listener:accept())

    assert(client:write("over a path"), "the client writes")
    testAssert.eq(assert(served:read(64)), "over a path", "and the server reads it back")

    served:close()
    client:close()
    listener:close()
    os.remove(path)
end

function M.aUnixSocketHalfClosesTheSameWay()
    -- The three-state read is a property of the module, not of TCP: a quiet Unix
    -- stream must park, and only a peer's half-close may read as the end.
    local path = socketPath("halfclose")
    os.remove(path)
    local listener = assert(net.listen({path = path}))
    local client = assert(net.connect({path = path}))
    local served = assert(listener:accept())

    assert(client:shutdownwrite(), "the client ends its sending half")
    testAssert.eq(assert(served:read(64)), "", "which the server reads as the end")
    assert(served:isended(), "and says the peer is done")
    assert(served:write("ack"), "while the other direction still writes")
    testAssert.eq(assert(client:read(64)), "ack", "and is still read")

    served:close()
    client:close()
    listener:close()
    os.remove(path)
end

function M.aUnixListenerHasNoPort()
    local path = socketPath("noport")
    os.remove(path)
    local listener = assert(net.listen({path = path}))
    testAssert.eq(listener:port(), -1, "a listener bound to a name has no port to report")
    listener:close()
    os.remove(path)
end

function M.connectingToAPathThatIsNotThereReportsWhy()
    local stream, why = net.connect({path = socketPath("absent")})
    testAssert.eq(stream, nil, "a connect to a name nobody is listening on answers nil")
    assert(why ~= nil, "and says why")
end

function M.namingBothFormsIsAMistakeAtTheCallSite()
    -- A listener binds an address or a filesystem name. Naming both says two
    -- different things at once, so it is refused where it is written rather than
    -- one of them being silently preferred.
    local both = pcall(function()
        return net.listen({host = "127.0.0.1", port = 0, path = "/tmp/x.sock"})
    end)
    testAssert.eq(both, false, "naming a host and a path together is refused")
    local neither = pcall(function()
        return net.listen({backlog = 8})
    end)
    testAssert.eq(neither, false, "and so is naming neither")
    local connectBoth = pcall(function()
        return net.connect({host = "127.0.0.1", port = 1, path = "/tmp/x.sock"})
    end)
    testAssert.eq(connectBoth, false, "connecting is the same")
end

function M.aConnectionKnowsWhoIsAtTheOtherEnd()
    -- What a server needs for logging, rate limiting and access control, and
    -- what a listener cannot infer: it knows the address it bound and nothing
    -- about who reached it.
    local listener, client, served = pair()
    local peer = served:peeraddress()
    assert(peer ~= nil, "an accepted connection knows its peer")
    testAssert.eq(peer.host, "127.0.0.1", "which is where it came from")
    testAssert.eq(peer.port, client:localaddress().port, "and the port is the one the client is using")
    testAssert.eq(client:peeraddress().port, listener:port(), "and the client's peer is the listener")
    served:close()
    client:close()
    listener:close()
end

function M.aUnixConnectionHasNoPeerAddress()
    local path = socketPath("nopeer")
    os.remove(path)
    local listener = assert(net.listen({path = path}))
    local client = assert(net.connect({path = path}))
    local served = assert(listener:accept())
    testAssert.eq(served:peeraddress(), nil, "a filesystem name is not a peer address, and none is invented for it")
    served:close()
    client:close()
    listener:close()
    os.remove(path)
end

function M.socketOptionsAreSetOnRealConnections()
    local listener, client, served = pair()
    assert(served:setnodelay(true), "Nagle can be turned off")
    assert(served:setnodelay(false), "and back on")
    assert(served:setkeepalive(true, 30000), "keepalive probing can be turned on")
    assert(served:setkeepalive(false, 1000), "and off")
    -- Still a working connection afterwards.
    assert(client:write("after options"), "the connection still writes")
    testAssert.eq(assert(served:read(64)), "after options", "and still reads")
    served:close()
    client:close()
    listener:close()
end

function M.optionsOnAClosedConnectionReportRatherThanCrash()
    local listener, client, served = pair()
    served:close()
    local ok, why = served:setnodelay(true)
    testAssert.eq(ok, false, "an option on a released connection is refused")
    assert(why ~= nil, "with a reason")
    client:close()
    listener:close()
end

function M.datagramOptionsAreSet()
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    assert(socket:setbroadcast(true), "broadcast can be allowed")
    assert(socket:setmulticastttl(1), "a hop limit can be set")
    assert(socket:setmulticastloop(false), "and loopback turned off")
    local bad = pcall(function()
        return socket:setmulticastttl(0)
    end)
    testAssert.eq(bad, false, "a hop limit outside 1 through 255 is a mistake at the call site")
    socket:close()
end

function M.aMulticastGroupCanBeJoinedAndLeft()
    local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
    -- 239.0.0.0/8 is administratively scoped and safe to use on a LAN. Joining
    -- can legitimately fail on a machine with no multicast-capable interface, so
    -- either answer is accepted; what must not happen is a raise.
    local joined, why = socket:joinmulticast("239.255.42.99")
    if joined then
        assert(socket:leavemulticast("239.255.42.99"), "and left again")
    else
        assert(why ~= nil, "a refused join says why rather than raising")
    end
    socket:close()
end

function M.linesComeOffAConnectionThroughTheSharedReader()
    -- The thing text protocols do all day, and it works over a socket because it
    -- is written against Reader rather than against sockets.
    local listener, client, served = pair()
    assert(
        client:write("first\r\nsecond\nthird without a terminator"),
        "the client writes three lines, two of them terminated"
    )
    assert(client:shutdownwrite(), "and ends its sending half")

    local lines = served:asreader():lines()
    testAssert.eq(assert(lines:read()), "first", "CRLF ends a line and is not part of it")
    testAssert.eq(assert(lines:read()), "second", "and so does a bare LF")
    testAssert.eq(assert(lines:read()), "third without a terminator", "and what is left at the end is still a line")
    testAssert.eq(lines:read(), nil, "then the end")
    lines:close()

    served:close()
    client:close()
    listener:close()
end

function M.anOverlongLineIsRefusedRatherThanBuffered()
    -- A line that never ends is not a line, and growing until it does is how a
    -- peer takes the process down.
    local listener, client, served = pair()
    assert(client:write(("x"):rep(4096)), "the client sends a very long line")
    local lines = served:asreader():lines(64)
    local line, why = lines:read()
    testAssert.eq(line, nil, "the read is refused")
    assert(why ~= nil and why:find("longer than the limit", 1, true) ~= nil, "and says the line was too long")
    lines:close()
    served:close()
    client:close()
    listener:close()
end

function M.anOverlongLineIsRefusedEvenWhenItsTerminatorArrivesWithIt()
    -- The bound has to be checked before the line is answered, not only before
    -- asking for more bytes: a terminator arriving in the same chunk would
    -- otherwise walk straight past it.
    local listener, client, served = pair()
    assert(client:write(("x"):rep(100) .. "\n"), "a 100-byte line arrives whole")
    local lines = served:asreader():lines(64)
    local line, why = lines:read()
    testAssert.eq(line, nil, "and is still refused against a 64-byte limit")
    assert(
        why ~= nil and why:find("longer than the limit", 1, true) ~= nil,
        "with the same reason as one that arrived in pieces"
    )
    lines:close()
    served:close()
    client:close()
    listener:close()
end

function M.flushWaitsForAcceptedBytesToLeave()
    -- `write` completes when the platform takes the bytes, which is not when it
    -- has sent them. A caller that writes, flushes and closes must not lose what
    -- was still queued, because closing cancels queued writes.
    --
    -- Small enough to fit the socket buffers unread: a value large enough to
    -- need the peer to drain would deadlock a test that reads afterwards, which
    -- is backpressure working rather than a fault.
    local listener, client, served = pair()
    local payload = ("payload"):rep(64)
    assert(client:write(payload), "a value is written")
    assert(client:flush(), "and the flush waits for it")
    testAssert.eq(client:pending(), 0, "so nothing this process held is left")
    testAssert.eq(assert(served:read(#payload)), payload, "and it all arrived")
    served:close()
    client:close()
    listener:close()
end

function M.aSendBoundOfZeroIsRefused()
    -- Zero satisfies the declared type and makes every write wait on a condition
    -- that can never hold, so it is refused where it is written.
    local ok = pcall(function()
        return net.connect({host = "127.0.0.1", port = 1, sendhighwater = 0})
    end)
    testAssert.eq(ok, false, "a bound of zero is a mistake at the call site")
    local negative = pcall(function()
        return net.connect({host = "127.0.0.1", port = 1, sendhighwater = -1})
    end)
    testAssert.eq(negative, false, "and so is a negative one")
end

function M.moreThanTheReceiveBoundStillArrivesWhole()
    -- Past the receive high-water mark this stops asking the platform for more
    -- until the program has taken what it has. Every byte must still arrive: the
    -- bound is backpressure, not a limit on how much may be received.
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local client = assert(net.connect({host = "127.0.0.1", port = listener:port()}))
    local served = assert(listener:accept())

    -- Interleaved on purpose. Writing 3 MiB before reading any of it would
    -- deadlock: past the mark the receiver stops asking for more, the kernel
    -- window closes behind it, and the sender waits for room that only a reader
    -- can make. That is the backpressure working, and it is why a single thread
    -- has to take turns.
    local block = ("abcdefgh"):rep(1024) -- 8 KiB
    local rounds = 400 -- 3.2 MiB, well past the mark
    local total = rounds * #block
    local got = 0
    for _ = 1, rounds do
        assert(client:write(block), "the sender keeps writing")
        while got < total do
            local chunk = assert(served:read(65536))
            if #chunk == 0 then
                break
            end
            got = got + #chunk
            if got % #block == 0 then
                break
            end
        end
    end
    assert(client:shutdownwrite(), "the sending half is ended")
    while true do
        local chunk = assert(served:read(65536))
        if #chunk == 0 then
            break
        end
        got = got + #chunk
    end
    testAssert.eq(got, total, "and every byte arrived despite the pauses")

    served:close()
    client:close()
    listener:close()
end

function M.connectingFallsBackToAWorkingAddress()
    -- `localhost` resolves to ::1 and then 127.0.0.1 on an ordinary machine. A
    -- listener bound only to 127.0.0.1 therefore refuses the first address and
    -- accepts the second, which is the case the retry exists for -- and the case
    -- that fails if a recovered-from failure is left set.
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
    local stream, why = net.connect({host = "localhost", port = listener:port()})
    if stream == nil then
        -- A machine whose `localhost` has no IPv6 answer never exercises the
        -- fallback; it must still connect rather than fail.
        error("connecting to localhost failed: " .. tostring(why))
    end
    local served = assert(listener:accept())
    assert(stream:write("through the second address"), "the connection works")
    testAssert.eq(assert(served:read(64)), "through the second address", "and carries bytes")
    served:close()
    stream:close()
    listener:close()
end

function M.aLineOfExactlyTheLimitIsAccepted()
    -- Neither terminator byte belongs to the line, so counting the carriage
    -- return against the limit would refuse a line of exactly the allowed
    -- length.
    local listener, client, served = pair()
    assert(client:write(("y"):rep(64) .. "\r\n"), "a 64-byte line ends with CRLF")
    local lines = served:asreader():lines(64)
    testAssert.eq(assert(lines:read()), ("y"):rep(64), "and is accepted at a 64-byte limit")
    lines:close()
    served:close()
    client:close()
    listener:close()
end

-- A reader answering a scripted run of chunks, then the end. A socket cannot
-- promise where a stream splits into reads, and the cases below are about
-- exactly that split, so the source is scripted rather than served.
local function chunkedReader(chunks)
    local at = 0
    return {
        lines = require("nupp.io.internal.bytes").Reader.lines,
        read = function(_self, _count)
            if at >= #chunks then
                return ""
            end
            at = at + 1

            return chunks[at]
        end,
        close = function(_self)
        end,
    }
end

function M.aLimitLengthLineSplitBeforeItsLineFeedIsStillAccepted()
    -- The same bytes `aLineOfExactlyTheLimitIsAccepted` sends, with the CRLF
    -- terminator split across reads. A held trailing carriage return may be
    -- half of a terminator, so it must not count against the limit before the
    -- next chunk says which it was: a line's acceptance cannot depend on where
    -- its bytes happened to fall.
    local lines = chunkedReader({"abcde\r", "\n"}):lines(5)
    testAssert.eq(assert(lines:read()), "abcde", "the line is accepted at a 5-byte limit")
    testAssert.eq(lines:read(), nil, "and then the stream ends")
    lines:close()
end

function M.aTrailingCarriageReturnCountsAgainstTheLimitAtTheEnd()
    -- At the end of the stream a carriage return with no line feed after it is
    -- line content, so the byte of grace granted while more could still arrive
    -- is taken back once nothing more can.
    local lines = chunkedReader({"abcde\r"}):lines(5)
    local line, why = lines:read()
    testAssert.eq(line, nil, "a 6-byte unterminated tail is refused at a 5-byte limit")
    assert(why ~= nil and why:find("longer than the limit", 1, true) ~= nil, "for being longer than the limit")
    lines:close()
end

function M.aCarriageReturnWithinTheLimitIsContentAtTheEnd()
    -- The bytes after the last terminator are a line, carriage return included:
    -- with nothing following it, it terminated nothing.
    local lines = chunkedReader({"abcd\r"}):lines(5)
    testAssert.eq(assert(lines:read()), "abcd\r", "an unterminated tail keeps its carriage return")
    testAssert.eq(lines:read(), nil, "and then the stream ends")
    lines:close()
end

function M.aBorrowedWriterFlushesTheSameQueue()
    -- The view writes into the connection's queue, so it has to be able to wait
    -- on it: a writer that reported success while bytes were queued would let a
    -- caller release the connection and cancel them.
    --
    -- The owner is released immediately after the view closes, before anything
    -- reads. Reading first would pump the reactor and let the shutdown complete
    -- on its own, which hides whether closing the view actually waited for it.
    local listener, client, served = pair()
    local writer = client:aswriter()
    assert(writer:write("through the view"), "the view writes")
    assert(writer:flush(), "and can wait for it to leave")
    testAssert.eq(client:pending(), 0, "so nothing is left held")
    writer:close()
    client:close()

    testAssert.eq(assert(served:read(64)), "through the view", "the bytes arrived")
    testAssert.eq(assert(served:read(64)), "", "and the peer saw the direction end")
    served:close()
    listener:close()
end

function M.aPartiallyConsumedStreamStillDeliversEverything()
    -- Correctness through a window far smaller than what arrives. Whether the
    -- buffer behind it stays bounded is a property of the allocation and is
    -- asserted where the capacity can be seen, in the provider's own harness;
    -- what this checks is that pausing, resuming and compacting lose nothing.
    local listener, client, served = pair()
    local block = ("z"):rep(8192)
    for _ = 1, 200 do -- 1.6 MiB through a 2-byte window
        assert(client:write(block), "the sender keeps writing")
        local taken = 0
        while taken < #block do
            local chunk = assert(served:read(2))
            if #chunk == 0 then
                break
            end
            taken = taken + #chunk
        end
    end
    assert(client:shutdownwrite(), "the sender finishes")
    served:close()
    client:close()
    listener:close()
end

-- A link-local IPv6 address this machine holds, as `address%interface`, or nil.
local function linkLocalAddress()
    local command = jit.os == "OSX" and "ifconfig lo0 inet6 2>/dev/null" or "ip -o -6 addr show scope link 2>/dev/null"
    local pipe = io.popen(command)
    if not pipe then
        return nil
    end
    local text = pipe:read("*a")
    pipe:close()
    if jit.os == "OSX" then
        return text:find("fe80::1%lo0", 1, true) and "fe80::1%lo0" or nil
    end
    local interface, address = text:match("%d+:%s+(%S+)%s+inet6%s+(fe80:[%x:]+)")

    return interface and (address .. "%" .. interface) or nil
end

function M.aLinkLocalPeerCanBeAnswered()
    -- N-4: a datagram from a link-local peer names its interface only through
    -- the scope it arrived with, so the reply has to carry it back.
    local zoned = linkLocalAddress()
    if not zoned then
        test.suite.skip("this machine holds no link-local IPv6 address")
    end
    local a = assert(net.bind({host = "::", port = 0}))
    local b = assert(net.bind({host = "::", port = 0}))
    local buffer = io_.newbuffer(64)
    assert(a:sendto({host = zoned, port = b:port()}, "ping"), "a sends to its own link-local address")
    local message = assert(b:receivefrom(buffer, 64))
    testAssert.eq(buffer:getstring(0, message.len), "ping", "b receives it")
    assert(message.address.host:find("%", 1, true) ~= nil, "the peer arrives with its scope")
    local replied, why = b:sendto(message.address, "pong")
    assert(replied, "b answers the peer it heard from: " .. tostring(why))
    local answer = assert(a:receivefrom(buffer, 64))
    testAssert.eq(buffer:getstring(0, answer.len), "pong", "and a receives the answer")
    buffer:close()
    b:close()
    a:close()
end

function M.aHostSleepingOnTheReadinessGenerationIsWokenByTheNetwork()
    -- The embedding shape: snapshot the one native readiness generation, drive the
    -- sources, and when nothing moved, wait from the snapshot. A wait that ran to its
    -- timeout means the network never advanced the generation the host sleeps on.
    local ffi = require("ffi")
    local suspension = require("coroutine.suspension")
    local suspensionHost = require("coroutine.suspension.host")
    local C = require("nupp.runtime.native").C
    local seen, found = ffi.new("uint64_t[1]"), ffi.new("uint64_t[1]")
    local sleeps = 0
    local host = {
        park = function(_self, waiting, cancel)
            while not waiting:ready() do
                assert(C.nuppNativePoll(seen) == 0)
                if suspension.poll() == 0 and not waiting:ready() then
                    sleeps = sleeps + 1
                    assert(C.nuppNativeWait(seen[0], 10000, found) == 0)
                    if found[0] == seen[0] or sleeps > 1000 then
                        cancel()
                        error(waiting.operation .. " never advanced the readiness generation", 0)
                    end
                end
            end
        end,
    }
    local installation = suspensionHost.install(host)
    local ok, problem = pcall(function()
        local listener, client, served = pair()
        assert(client:write("ping"), "the client writes")
        testAssert.eq(assert(served:read(4)), "ping", "and the server reads it")
        client:close()
        served:close()
        listener:close()
    end)
    installation:close()
    assert(ok, problem)
    -- A loopback connect completes on the provider's executor, never inside the
    -- call, so the host always sleeps at least once and the network wakes it.
    assert(sleeps > 0, "the host slept on the generation")
end

return M
