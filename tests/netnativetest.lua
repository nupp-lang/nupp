-- Real sockets, against the libuv-backed provider.
--
-- The other half of `nettest.lua`: that one drives the state machine with a fake
-- platform, and this one checks that the platform means what the state machine
-- assumes. Everything here is loopback and an ephemeral port, so nothing depends
-- on a fixed port being free or on anything outside this machine.
local net = require("nupp.io.net")
local io_ = require("nupp.io")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

-- A listener, a connection to it, and the connection it accepted.
local function pair()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   local bound = listener:port()
   assertTrue(bound > 0, "an ephemeral bind reports the port it got")
   local client = assert(net.connect({host = "127.0.0.1", port = bound}))
   local served = assert(listener:accept())
   return listener, client, served
end

local M = {}

function M.bytesCrossALoopbackConnection()
   local listener, client, served = pair()
   assertTrue(client:write("hello sockets"), "the client writes")
   assertEq(assert(served:read(64)), "hello sockets", "and the server reads them back")
   served:close()
   client:close()
   listener:close()
end

function M.aHalfCloseIsTheEndInOneDirectionOnly()
   -- The three-state read, against a real peer: after the client half-closes the
   -- server reads empty, and the server can still write back.
   local listener, client, served = pair()
   assertTrue(client:shutdownWrite(), "the client ends its sending half")
   assertEq(assert(served:read(64)), "", "which the server reads as the end")
   assertTrue(served:isEnded(), "and the server says the peer is done")
   assertTrue(served:write("bye"), "while the other direction still writes")
   assertEq(assert(client:read(64)), "bye", "and the client still reads")
   served:close()
   client:close()
   listener:close()
end

function M.aLargeValueCrossesInPieces()
   -- Larger than the send bound and larger than one read, so both the write
   -- loop and the read loop have to come back for the rest.
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   local client = assert(net.connect({
      host = "127.0.0.1", port = listener:port(), sendHighWater = 4096,
   }))
   local served = assert(listener:accept())

   local payload = ("abcdefgh"):rep(32768)
   assertTrue(client:write(payload), "a 256 KiB value is written whole")
   assertTrue(client:shutdownWrite(), "and the sending half is ended")

   local parts = {}
   while true do
      local chunk = assert(served:read(65536))
      if #chunk == 0 then break end
      parts[#parts + 1] = chunk
   end
   assertEq(#table.concat(parts), #payload, "every byte arrived")
   assertEq(table.concat(parts), payload, "and in order")
   served:close()
   client:close()
   listener:close()
end

function M.aReaderViewReadsARealConnection()
   local listener, client, served = pair()
   assertTrue(client:write("through the contract"), "the client writes")
   local reader = net.asReader(served)
   assertEq(assert(reader:read(64)), "through the contract",
      "a borrowed view reads through the shared Reader contract")
   reader:close()
   served:close()
   client:close()
   listener:close()
end

function M.closingTheWriterViewEndsOneDirection()
   local listener, client, served = pair()
   local writer = net.asWriter(client)
   assertTrue(writer:write("last"), "the view writes")
   writer:close()
   assertEq(assert(served:read(64)), "last", "the bytes still arrived")
   assertEq(assert(served:read(64)), "", "and the peer saw the end")
   assertTrue(served:isEnded(), "which is what closing the writer view means")
   -- The connection itself is untouched: the server can still answer.
   assertTrue(served:write("ack"), "the other half is still open")
   assertEq(assert(client:read(64)), "ack", "and the client still reads it")
   served:close()
   client:close()
   listener:close()
end

function M.connectingNowhereReportsWhy()
   -- Port 1 on the loopback is refused rather than filtered, so this fails fast
   -- instead of depending on a timeout.
   local stream, why = net.connect({host = "127.0.0.1", port = 1})
   assertEq(stream, nil, "a refused connect answers nil")
   assertTrue(why ~= nil, "and says why")
end

function M.aNameThatDoesNotResolveReportsWhy()
   local stream, why = net.connect({
      host = "invalid.invalid.example.test", port = 80,
   })
   assertEq(stream, nil, "an unresolvable name answers nil")
   assertTrue(why ~= nil, "and says why")
end

function M.bindingAPrivilegedPortReportsWhyRatherThanRaising()
   -- Port 1 needs privilege this test does not have, which is the ordinary
   -- refusal path. Skipped where the test happens to be running as root.
   local listener, why = net.listen({host = "127.0.0.1", port = 1})
   if listener ~= nil then
      listener:close()
      return
   end
   assertTrue(why ~= nil, "a refused bind says why rather than raising")
end

function M.manyConnectionsAreAcceptedInTurn()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   local bound = listener:port()
   local clients, servers = {}, {}
   for index = 1, 8 do
      clients[index] = assert(net.connect({host = "127.0.0.1", port = bound}))
      assertTrue(clients[index]:write("n" .. index), "each client writes")
   end
   for index = 1, 8 do
      servers[index] = assert(listener:accept())
   end
   local seen = {}
   for index = 1, 8 do
      seen[assert(servers[index]:read(16))] = true
   end
   for index = 1, 8 do
      assertTrue(seen["n" .. index], "every connection's bytes arrived")
      servers[index]:close()
      clients[index]:close()
   end
   listener:close()
end

function M.aClosedConnectionRefusesRatherThanCrashing()
   local listener, client, served = pair()
   served:close()
   local got, why = served:read(8)
   assertEq(got, nil, "a read on a closed connection answers nil")
   assertTrue(why ~= nil, "and says why")
   local wrote = served:write("x")
   assertEq(wrote, false, "and so does a write")
   client:close()
   listener:close()
end

-- Two datagram sockets on the loopback, each on a port the platform chose.
local function datagrams()
   local a = assert(net.bind({host = "127.0.0.1", port = 0}))
   local b = assert(net.bind({host = "127.0.0.1", port = 0}))
   assertTrue(a:port() > 0 and b:port() > 0 and a:port() ~= b:port(),
      "each socket got its own ephemeral port")
   return a, b
end

function M.aDatagramCrossesWithItsPeer()
   local a, b = datagrams()
   local buffer = io_.newBuffer(2048)
   assertTrue(a:sendTo({host = "127.0.0.1", port = b:port()}, "ping"), "a sends")
   local message = assert(b:receiveFrom(buffer, 2048))
   assertEq(message.length, 4, "b receives the whole datagram")
   assertEq(buffer:getString(0, 4), "ping", "into the storage it offered")
   assertEq(message.address.port, a:port(), "carrying the peer that sent it")
   assertEq(message.truncated, false, "and it was not truncated")
   buffer:close()
   b:close()
   a:close()
end

function M.aDatagramLargerThanTheStorageIsReportedTruncated()
   -- Against a real socket, because this is the one a protocol must not get
   -- wrong: parsing the first part of a larger message nobody sent.
   local a, b = datagrams()
   local buffer = io_.newBuffer(2048)
   assertTrue(a:sendTo({host = "127.0.0.1", port = b:port()}, ("x"):rep(600)), "a sends 600 bytes")
   local message = assert(b:receiveFrom(buffer, 100))
   assertEq(message.length, 100, "b takes what it offered room for")
   assertEq(message.truncated, true, "and is told the rest is gone")
   buffer:close()
   b:close()
   a:close()
end

function M.anEmptyDatagramArrivesAsAMessage()
   local a, b = datagrams()
   local buffer = io_.newBuffer(2048)
   assertTrue(a:sendTo({host = "127.0.0.1", port = b:port()}, ""), "a sends an empty datagram")
   local message = assert(b:receiveFrom(buffer, 2048))
   assertEq(message.length, 0, "which arrives as zero bytes")
   assertEq(message.address.port, a:port(), "still carrying its peer")
   assertEq(message.truncated, false, "and nothing was dropped")
   buffer:close()
   b:close()
   a:close()
end

function M.datagramsKeepTheirBoundaries()
   -- The property that makes this a message transport rather than a stream one:
   -- three sends are three receives, never one run of bytes.
   local a, b = datagrams()
   local buffer = io_.newBuffer(2048)
   for index = 1, 3 do
      assertTrue(a:sendTo({host = "127.0.0.1", port = b:port()}, ("m%d"):format(index)),
         "each send is its own datagram")
   end
   local seen = {}
   for _ = 1, 3 do
      local message = assert(b:receiveFrom(buffer, 2048))
      assertEq(message.length, 2, "each receive is one whole message")
      seen[buffer:getString(0, 2)] = true
   end
   for index = 1, 3 do
      assertTrue(seen[("m%d"):format(index)], "every message arrived separately")
   end
   buffer:close()
   b:close()
   a:close()
end

function M.sendingNowhereReportsWhyRatherThanRaising()
   local a = assert(net.bind({host = "127.0.0.1", port = 0}))
   -- Port zero is not a destination; the platform refuses it.
   local sent, why = a:sendTo({host = "127.0.0.1", port = 0}, "nowhere")
   if sent then
      a:close()
      return
   end
   assertTrue(why ~= nil, "a refused send says why")
   a:close()
end

function M.aConnectGivesUpOnItsDeadline()
   -- A blackholed address: the handshake goes out and nothing ever answers, so
   -- without a deadline this hangs. 203.0.113.0/24 is reserved for documentation
   -- and is not routed, which is what makes it reliably silent.
   local started = os.clock()
   local stream, why = net.connect({
      host = "203.0.113.1", port = 9, timeoutMs = 250,
   })
   assertEq(stream, nil, "the connect gives up rather than hanging")
   assertTrue(why ~= nil, "and says why")
   assertTrue(os.clock() - started < 10, "well before anything else would time it out")
end

function M.aConnectDeadlineStartsWhenTheConnectionDoes()
   -- libuv's clock is cached. Work outside its reactor must not make the next
   -- connection's freshly armed deadline look as though it has already passed.
   local listener, client, served = pair()
   served:close()
   client:close()
   listener:close()

   local until_ = os.clock() + 0.25
   while os.clock() < until_ do end

   listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   client = assert(net.connect({
      host = "127.0.0.1", port = listener:port(), timeoutMs = 100,
   }))
   served = assert(listener:accept())
   served:close()
   client:close()
   listener:close()
end

function M.loadBalancingReuseIsRefusedCleanlyWhereItIsUnsupported()
   -- macOS and Windows have no load-balancing port reuse, and libuv refuses it
   -- rather than giving different semantics. Either answer is correct here; what
   -- must not happen is a raise or a silent downgrade.
   local first, why = net.listen({host = "127.0.0.1", port = 0, reusePort = true})
   if first == nil then
      assertTrue(why ~= nil, "an unsupported request is refused with a reason")
      return
   end
   -- Where it is supported, a second listener may share the port.
   local second = net.listen({host = "127.0.0.1", port = first:port(), reusePort = true})
   if second ~= nil then second:close() end
   first:close()
end

-- A local stream name unique to this run: a filesystem socket on POSIX and a
-- named pipe in the namespace libuv requires on Windows.
local function socketPath(label)
   if jit.os == "Windows" then
      return "\\\\.\\pipe\\nupp-net-" .. label .. "-" .. tostring(os.time())
   end
   local base = os.getenv("TMPDIR") or "/tmp/"
   if base:sub(-1) ~= "/" then base = base .. "/" end
   return base .. "nupp-net-" .. label .. "-" .. tostring(os.time()) .. ".sock"
end

function M.aUnixSocketCarriesBytesLikeATcpOne()
   local path = socketPath("bytes")
   os.remove(path)
   local listener = assert(net.listen({path = path}))
   local client = assert(net.connect({path = path}))
   local served = assert(listener:accept())

   assertTrue(client:write("over a path"), "the client writes")
   assertEq(assert(served:read(64)), "over a path", "and the server reads it back")

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

   assertTrue(client:shutdownWrite(), "the client ends its sending half")
   assertEq(assert(served:read(64)), "", "which the server reads as the end")
   assertTrue(served:isEnded(), "and says the peer is done")
   assertTrue(served:write("ack"), "while the other direction still writes")
   assertEq(assert(client:read(64)), "ack", "and is still read")

   served:close()
   client:close()
   listener:close()
   os.remove(path)
end

function M.aUnixListenerHasNoPort()
   local path = socketPath("noport")
   os.remove(path)
   local listener = assert(net.listen({path = path}))
   assertEq(listener:port(), -1, "a listener bound to a name has no port to report")
   listener:close()
   os.remove(path)
end

function M.connectingToAPathThatIsNotThereReportsWhy()
   local stream, why = net.connect({path = socketPath("absent")})
   assertEq(stream, nil, "a connect to a name nobody is listening on answers nil")
   assertTrue(why ~= nil, "and says why")
end

function M.namingBothFormsIsAMistakeAtTheCallSite()
   -- A listener binds an address or a filesystem name. Naming both says two
   -- different things at once, so it is refused where it is written rather than
   -- one of them being silently preferred.
   local both = pcall(function()
      return net.listen({host = "127.0.0.1", port = 0, path = "/tmp/x.sock"})
   end)
   assertEq(both, false, "naming a host and a path together is refused")
   local neither = pcall(function() return net.listen({backlog = 8}) end)
   assertEq(neither, false, "and so is naming neither")
   local connectBoth = pcall(function()
      return net.connect({host = "127.0.0.1", port = 1, path = "/tmp/x.sock"})
   end)
   assertEq(connectBoth, false, "connecting is the same")
end

function M.aConnectionKnowsWhoIsAtTheOtherEnd()
   -- What a server needs for logging, rate limiting and access control, and
   -- what a listener cannot infer: it knows the address it bound and nothing
   -- about who reached it.
   local listener, client, served = pair()
   local peer = served:peerAddress()
   assertTrue(peer ~= nil, "an accepted connection knows its peer")
   assertEq(peer.host, "127.0.0.1", "which is where it came from")
   assertEq(peer.port, client:localAddress().port,
      "and the port is the one the client is using")
   assertEq(client:peerAddress().port, listener:port(),
      "and the client's peer is the listener")
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
   assertEq(served:peerAddress(), nil,
      "a filesystem name is not a peer address, and none is invented for it")
   served:close()
   client:close()
   listener:close()
   os.remove(path)
end

function M.socketOptionsAreSetOnRealConnections()
   local listener, client, served = pair()
   assertTrue(served:setNoDelay(true), "Nagle can be turned off")
   assertTrue(served:setNoDelay(false), "and back on")
   assertTrue(served:setKeepAlive(true, 30), "keepalive probing can be turned on")
   assertTrue(served:setKeepAlive(false, 1), "and off")
   -- Still a working connection afterwards.
   assertTrue(client:write("after options"), "the connection still writes")
   assertEq(assert(served:read(64)), "after options", "and still reads")
   served:close()
   client:close()
   listener:close()
end

function M.optionsOnAClosedConnectionReportRatherThanCrash()
   local listener, client, served = pair()
   served:close()
   local ok, why = served:setNoDelay(true)
   assertEq(ok, false, "an option on a released connection is refused")
   assertTrue(why ~= nil, "with a reason")
   client:close()
   listener:close()
end

function M.datagramOptionsAreSet()
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   assertTrue(socket:setBroadcast(true), "broadcast can be allowed")
   assertTrue(socket:setMulticastTTL(1), "a hop limit can be set")
   assertTrue(socket:setMulticastLoop(false), "and loopback turned off")
   local bad = pcall(function() return socket:setMulticastTTL(0) end)
   assertEq(bad, false, "a hop limit outside 1 through 255 is a mistake at the call site")
   socket:close()
end

function M.aMulticastGroupCanBeJoinedAndLeft()
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   -- 239.0.0.0/8 is administratively scoped and safe to use on a LAN. Joining
   -- can legitimately fail on a machine with no multicast-capable interface, so
   -- either answer is accepted; what must not happen is a raise.
   local joined, why = socket:joinMulticast("239.255.42.99")
   if joined then
      assertTrue(socket:leaveMulticast("239.255.42.99"), "and left again")
   else
      assertTrue(why ~= nil, "a refused join says why rather than raising")
   end
   socket:close()
end

function M.linesComeOffAConnectionThroughTheSharedReader()
   -- The thing text protocols do all day, and it works over a socket because it
   -- is written against Reader rather than against sockets.
   local listener, client, served = pair()
   assertTrue(client:write("first\r\nsecond\nthird without a terminator"),
      "the client writes three lines, two of them terminated")
   assertTrue(client:shutdownWrite(), "and ends its sending half")

   local lines = io_.newLines(net.asReader(served))
   assertEq(assert(lines:read()), "first", "CRLF ends a line and is not part of it")
   assertEq(assert(lines:read()), "second", "and so does a bare LF")
   assertEq(assert(lines:read()), "third without a terminator",
      "and what is left at the end is still a line")
   assertEq(lines:read(), nil, "then the end")
   lines:close()

   served:close()
   client:close()
   listener:close()
end

function M.anOverlongLineIsRefusedRatherThanBuffered()
   -- A line that never ends is not a line, and growing until it does is how a
   -- peer takes the process down.
   local listener, client, served = pair()
   assertTrue(client:write(("x"):rep(4096)), "the client sends a very long line")
   local lines = io_.newLines(net.asReader(served), 64)
   local line, why = lines:read()
   assertEq(line, nil, "the read is refused")
   assertTrue(why ~= nil and why:find("longer than the limit", 1, true) ~= nil,
      "and says the line was too long")
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
   assertTrue(client:write(("x"):rep(100) .. "\n"), "a 100-byte line arrives whole")
   local lines = io_.newLines(net.asReader(served), 64)
   local line, why = lines:read()
   assertEq(line, nil, "and is still refused against a 64-byte limit")
   assertTrue(why ~= nil and why:find("longer than the limit", 1, true) ~= nil,
      "with the same reason as one that arrived in pieces")
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
   assertTrue(client:write(payload), "a value is written")
   assertTrue(client:flush(), "and the flush waits for it")
   assertEq(client:pending(), 0, "so nothing this process held is left")
   assertEq(assert(served:read(#payload)), payload, "and it all arrived")
   served:close()
   client:close()
   listener:close()
end

function M.aSendBoundOfZeroIsRefused()
   -- Zero satisfies the declared type and makes every write wait on a condition
   -- that can never hold, so it is refused where it is written.
   local ok = pcall(function()
      return net.connect({host = "127.0.0.1", port = 1, sendHighWater = 0})
   end)
   assertEq(ok, false, "a bound of zero is a mistake at the call site")
   local negative = pcall(function()
      return net.connect({host = "127.0.0.1", port = 1, sendHighWater = -1})
   end)
   assertEq(negative, false, "and so is a negative one")
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
   local block = ("abcdefgh"):rep(1024)          -- 8 KiB
   local rounds = 400                             -- 3.2 MiB, well past the mark
   local total = rounds * #block
   local got = 0
   for _ = 1, rounds do
      assertTrue(client:write(block), "the sender keeps writing")
      while got < total do
         local chunk = assert(served:read(65536))
         if #chunk == 0 then break end
         got = got + #chunk
         if got % #block == 0 then break end
      end
   end
   assertTrue(client:shutdownWrite(), "the sending half is ended")
   while true do
      local chunk = assert(served:read(65536))
      if #chunk == 0 then break end
      got = got + #chunk
   end
   assertEq(got, total, "and every byte arrived despite the pauses")

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
   assertTrue(stream:write("through the second address"), "the connection works")
   assertEq(assert(served:read(64)), "through the second address", "and carries bytes")
   served:close()
   stream:close()
   listener:close()
end

function M.aLineOfExactlyTheLimitIsAccepted()
   -- Neither terminator byte belongs to the line, so counting the carriage
   -- return against the limit would refuse a line of exactly the allowed
   -- length.
   local listener, client, served = pair()
   assertTrue(client:write(("y"):rep(64) .. "\r\n"), "a 64-byte line ends with CRLF")
   local lines = io_.newLines(net.asReader(served), 64)
   assertEq(assert(lines:read()), ("y"):rep(64), "and is accepted at a 64-byte limit")
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
      read = function(_self, _count)
         if at >= #chunks then
            return ""
         end
         at = at + 1
         return chunks[at]
      end,
      close = function(_self) end,
   }
end

function M.aLimitLengthLineSplitBeforeItsLineFeedIsStillAccepted()
   -- The same bytes `aLineOfExactlyTheLimitIsAccepted` sends, with the CRLF
   -- terminator split across reads. A held trailing carriage return may be
   -- half of a terminator, so it must not count against the limit before the
   -- next chunk says which it was: a line's acceptance cannot depend on where
   -- its bytes happened to fall.
   local lines = io_.newLines(chunkedReader({"abcde\r", "\n"}), 5)
   assertEq(assert(lines:read()), "abcde", "the line is accepted at a 5-byte limit")
   assertEq(lines:read(), nil, "and then the stream ends")
   lines:close()
end

function M.aTrailingCarriageReturnCountsAgainstTheLimitAtTheEnd()
   -- At the end of the stream a carriage return with no line feed after it is
   -- line content, so the byte of grace granted while more could still arrive
   -- is taken back once nothing more can.
   local lines = io_.newLines(chunkedReader({"abcde\r"}), 5)
   local line, why = lines:read()
   assertEq(line, nil, "a 6-byte unterminated tail is refused at a 5-byte limit")
   assertTrue(why ~= nil and why:find("longer than the limit", 1, true) ~= nil,
      "for being longer than the limit")
   lines:close()
end

function M.aCarriageReturnWithinTheLimitIsContentAtTheEnd()
   -- The bytes after the last terminator are a line, carriage return included:
   -- with nothing following it, it terminated nothing.
   local lines = io_.newLines(chunkedReader({"abcd\r"}), 5)
   assertEq(assert(lines:read()), "abcd\r",
      "an unterminated tail keeps its carriage return")
   assertEq(lines:read(), nil, "and then the stream ends")
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
   local writer = net.asWriter(client)
   assertTrue(writer:write("through the view"), "the view writes")
   assertTrue(writer:flush(), "and can wait for it to leave")
   assertEq(client:pending(), 0, "so nothing is left held")
   writer:close()
   client:close()

   assertEq(assert(served:read(64)), "through the view", "the bytes arrived")
   assertEq(assert(served:read(64)), "", "and the peer saw the direction end")
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
   for _ = 1, 200 do                              -- 1.6 MiB through a 2-byte window
      assertTrue(client:write(block), "the sender keeps writing")
      local taken = 0
      while taken < #block do
         local chunk = assert(served:read(2))
         if #chunk == 0 then break end
         taken = taken + #chunk
      end
   end
   assertTrue(client:shutdownWrite(), "the sender finishes")
   served:close()
   client:close()
   listener:close()
end

function M.aPartiallyConsumedStreamDoesNotGrowWithTraffic()
   -- Capacity is not on the Lua surface and should not be, so the measurement
   -- happens in a fixture linked against the provider directly. What is checked
   -- here is that it still holds, and it is checked in the suite so that it
   -- keeps being checked.
   local root = HERE .. "/.."
   local out = os.tmpname()

   -- Built through the toolchain rather than by assembling a compiler command
   -- here. Which compiler this repository uses and which libraries each
   -- platform needs are decided in one place, and a test that spelled them out
   -- again would be a second copy that only this machine's platform proves.
   -- The subcommand requires the pinned libuv rather than building it, so it
   -- takes no component lock and cannot stall the other shards.
   local built = os.execute((
      "'%s/scripts/toolchain' fixture '%s/fixtures/net-buffer.c' '%s' >/dev/null 2>&1"
   ):format(root, HERE, out))
   assertEq(built, 0,
      "the receive-buffer fixture builds; run scripts/toolchain libuv if it did not")

   -- The fixture's own verdict is read from its output rather than its exit
   -- status: `popen`'s close answers true here whatever the program returned,
   -- so an assertion on it could never fail.
   local run = assert(io.popen("'" .. out .. "' 2>&1"))
   local said = run:read("*a")
   run:close()
   os.remove(out)
   assertTrue(said:find("\nok\n", 1, true) ~= nil or said:sub(-3) == "ok\n",
      "the receive buffer did not grow with total traffic:\n" .. said)
end

return M
