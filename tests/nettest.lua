-- The platform-neutral socket state machine.
--
-- Driven by a fake backend, on purpose: what is checked here is the policy above
-- the Rust-backed provider -- the three-state read, the bounded send queue, what
-- a direction view's close does -- so the test supplies the platform and the
-- module supplies the behaviour. `netnativetest.lua` is the other half, where
-- real sockets check that the provider means what this one assumes.
local net = require("nupp.io.net")
local io_ = require("nupp.io")
local native = require("nupp.compiler.native")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

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
      state.reusePort = reusePort
      state.backlog = backlog
      return {host = host, port = port}
   end

   function self:listenerPort(listener)
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

   function self:closeListener(listener)
      state.closedListeners = state.closedListeners + 1
   end

   function self:connect(host, port, timeoutMs)
      state.connectTimeout = timeoutMs
      if script.connectFails then
         return nil, "nupp: could not connect: " .. script.connectFails
      end
      return {host = host, port = port}
   end

   function self:connectPoll(request)
      state.connectPolls = (state.connectPolls or 0) + 1
      if state.connectPolls < (script.connectAfter or 1) then
         return nil
      end
      return {which = "connected"}
   end

   function self:closeConnect(request) state.closedConnect = true end

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
      state.written[#state.written + 1] = bytes
      -- A fake peer that never drains is how the high-water path is exercised.
      state.pending = state.pending + (script.drains == false and #bytes or 0)
      return #bytes
   end

   function self:pending(stream) return state.pending end

   function self:writeFailed(stream) return script.writeFails == true end

   function self:shuttingDown(stream) return state.shuttingDown == true end

   function self:shutdownWrite(stream)
      state.shutdown = true
      -- A real platform takes the request and finishes it later; the fake
      -- finishes it on the next turn of the reactor, so a caller that waits for
      -- it makes progress rather than spinning.
      state.shuttingDown = script.shutdownPends == true
      return true
   end

   function self:closeStream(stream) state.closedStreams = state.closedStreams + 1 end

   function self:bindDatagram(host, port, reusePort)
      if script.bindFails then
         return nil, "nupp: could not bind: " .. script.bindFails
      end
      state.datagramReusePort = reusePort
      return {host = host, port = port}
   end

   function self:datagramPort(socket)
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

   function self:sendTo(socket, host, port, bytes)
      state.sent = state.sent or {}
      state.sent[#state.sent + 1] = {host = host, port = port, bytes = bytes}
      return true
   end

   function self:closeDatagram(socket)
      state.closedDatagrams = (state.closedDatagrams or 0) + 1
   end

   function self:run(timeoutMs)
      state.runs = state.runs + 1
      -- Draining one queued write per turn, so a caller waiting on the send
      -- bound makes progress rather than spinning forever.
      if state.pending > 0 and script.drainsOnRun then
         state.pending = 0
      end
      state.shuttingDown = false
   end

   return self, state
end

local function connected(script)
   local backend, state = fakeBackend(script or {})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   return stream, state
end

local M = {}

function M.aQuietConnectionIsNotTheEnd()
   -- The whole point of the three-state read: a gap in the middle of a stream
   -- must not read as end of stream, or a parser stops on the first lull.
   local stream, state = connected({arriving = {"ab", false, "cd"}})
   assertEq(assert(stream:read(8)), "ab", "the first bytes arrive")
   assertEq(assert(stream:read(8)), "cd", "and so do the ones after the gap")
   assertEq(assert(stream:read(8)), "", "only a finished stream reads empty")
   assertTrue(state.runs > 0, "the gap drove the reactor rather than spinning")
   stream:close()
end

function M.emptyIsOnlyEverTheEnd()
   local stream = connected({arriving = {"x"}})
   assertEq(assert(stream:read(4)), "x", "the byte arrives")
   assertEq(assert(stream:read(4)), "", "then the end")
   assertTrue(stream:isEnded(), "and the stream says so")
   stream:close()
end

function M.readReportsWhyItCouldNotRead()
   local stream = connected({readFails = "connection reset"})
   local got, why = stream:read(4)
   assertEq(got, nil, "a failed read answers nil")
   assertTrue(why ~= nil and why:find("connection reset", 1, true) ~= nil,
      "and carries what the platform said")
   stream:close()
end

function M.writeCompletesTheWholeValue()
   local stream, state = connected({})
   assertTrue(stream:write("payload"), "the write completes")
   assertEq(table.concat(state.written), "payload", "and everything landed")
   stream:close()
end

function M.writeLargerThanTheBoundStillProceeds()
   -- The bound governs how much is queued at one time, not how much may be
   -- sent. An input larger than the high-water mark must not deadlock.
   local backend, state = fakeBackend({drains = false, drainsOnRun = true})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80, sendHighWater = 4}))
   assertTrue(stream:write("0123456789"), "a value larger than the bound is written")
   assertEq(table.concat(state.written), "0123456789", "in pieces, all of them")
   assertTrue(#state.written > 1, "and it really was more than one piece")
   stream:close()
end

function M.writeRefusesAfterTheSendingHalfIsClosed()
   local stream, state = connected({})
   assertTrue(stream:shutdownWrite(), "the sending half closes")
   assertTrue(state.shutdown, "which reaches the platform")
   local wrote, why = stream:write("late")
   assertEq(wrote, false, "a write after it is refused")
   assertTrue(why ~= nil, "and says why")
   stream:close()
end

function M.pendingIsALocalFact()
   local stream, state = connected({drains = false})
   assertTrue(stream:write("four"), "the write completes locally")
   assertEq(stream:pending(), 4, "and the bytes are still this process's")
   stream:close()
end

function M.closingTheWriterViewHalfCloses()
   -- The departure from process.asWriter that the proposal records: a socket has
   -- one handle with two halves, so closing the writing view ends a direction
   -- rather than returning a resource.
   local stream, state = connected({})
   local writer = net.asWriter(stream)
   writer:close()
   assertTrue(state.shutdown, "closing the writer view half-closes")
   assertEq(state.closedStreams, 0, "and leaves the connection open")
   stream:close()
   assertEq(state.closedStreams, 1, "which the owner still has to close")
end

function M.closingTheReaderViewLeavesTheConnection()
   local stream, state = connected({arriving = {"ab"}})
   local reader = net.asReader(stream)
   assertEq(assert(reader:read(4)), "ab", "the view reads")
   reader:close()
   local got, why = reader:read(4)
   assertEq(got, nil, "a closed reader view refuses")
   assertTrue(why ~= nil, "and says why")
   assertEq(state.closedStreams, 0, "without touching the connection")
   assertEq(state.shutdown, false, "and without ending the sending half")
   stream:close()
end

function M.aViewReadsThroughTheSharedContract()
   local stream = connected({arriving = {"shared"}})
   local reader = net.asReader(stream)
   assertEq(assert(reader:read(6)), "shared", "a view is a Reader")
   reader:close()
   stream:close()
end

function M.acceptWaitsForAConnection()
   local backend, state = fakeBackend({acceptAfter = 3})
   net.useBackend(backend)
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   local stream = assert(listener:accept())
   assertEq(state.accepted, 3, "a quiet listener came back for it")
   assertTrue(state.runs > 0, "driving the reactor while it waited")
   stream:close()
   listener:close()
end

function M.aListenerReportsThePortItGot()
   local backend = fakeBackend({})
   net.useBackend(backend)
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   assertEq(listener:port(), 54321, "asking for zero answers what was chosen")
   listener:close()
end

function M.reusePortIsPassedThroughRatherThanAssumed()
   local backend, state = fakeBackend({})
   net.useBackend(backend)
   local listener = assert(net.listen({host = "127.0.0.1", port = 0, reusePort = true}))
   assertEq(state.reusePort, true, "the request reaches the platform")
   listener:close()
   local plain = assert(net.listen({host = "127.0.0.1", port = 0}))
   assertEq(state.reusePort, false, "and is off unless asked for")
   plain:close()
end

function M.listenReportsWhyItCouldNotBind()
   net.useBackend((fakeBackend({listenFails = "address already in use"})))
   local listener, why = net.listen({host = "127.0.0.1", port = 80})
   assertEq(listener, nil, "a refused bind answers nil")
   assertTrue(why ~= nil and why:find("address already in use", 1, true) ~= nil,
      "and carries what the platform said")
end

function M.connectReportsWhyItCouldNotConnect()
   net.useBackend((fakeBackend({connectFails = "connection refused"})))
   local stream, why = net.connect({host = "example", port = 80})
   assertEq(stream, nil, "a refused connect answers nil")
   assertTrue(why ~= nil and why:find("connection refused", 1, true) ~= nil,
      "and carries what the platform said")
end

function M.connectWaitsForTheHandshake()
   local backend, state = fakeBackend({connectAfter = 3})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   assertEq(state.connectPolls, 3, "the connect was come back for")
   assertTrue(state.closedConnect, "and the request was released after it")
   stream:close()
end

function M.closingIsIdempotent()
   local stream, state = connected({})
   stream:close()
   assertEq(state.closedStreams, 1, "the first close releases")
   assertEq(stream:isReleased(), true, "and the stream says so")
end

function M.aDatagramCarriesItsPeerAndItsLength()
   local backend, state = fakeBackend({datagrams = {{bytes = "ping", host = "10.0.0.7", port = 9001}}})
   net.useBackend(backend)
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   local buffer = io_.newBuffer(64)
   local message = assert(socket:receiveFrom(buffer, 64))
   assertEq(message.length, 4, "the length is what landed")
   assertEq(buffer:getString(0, 4), "ping", "and the bytes went into the storage offered")
   assertEq(message.address.host, "10.0.0.7", "the peer's address comes with it")
   assertEq(message.address.port, 9001, "and its port")
   assertEq(message.truncated, false, "a whole datagram is not truncated")
   buffer:close()
   socket:close()
end

function M.aTruncatedDatagramSaysSo()
   -- The security-relevant one: parsing the first part of a larger message
   -- without being told is parsing something nobody sent.
   local backend = fakeBackend({datagrams = {{bytes = "0123456789"}}})
   net.useBackend(backend)
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   local buffer = io_.newBuffer(64)
   local message = assert(socket:receiveFrom(buffer, 4))
   assertEq(message.length, 4, "only what there was room for landed")
   assertEq(message.truncated, true, "and the caller is told the rest is gone")
   buffer:close()
   socket:close()
end

function M.anEmptyDatagramIsAMessageNotAnAbsence()
   -- A quiet socket comes back for more; an empty datagram is delivered. A
   -- receive that could not tell them apart would make a live peer look silent.
   local backend, state = fakeBackend({
      datagrams = {false, false, {bytes = "", host = "10.0.0.9", port = 7}},
   })
   net.useBackend(backend)
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   local buffer = io_.newBuffer(64)
   local message = assert(socket:receiveFrom(buffer, 64))
   assertEq(message.length, 0, "an empty datagram is zero bytes")
   assertEq(message.address.port, 7, "and still carries the peer that sent it")
   assertTrue(state.receives >= 3, "the quiet polls before it were not messages")
   buffer:close()
   socket:close()
end

function M.sendingNamesThePeer()
   local backend, state = fakeBackend({})
   net.useBackend(backend)
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   assertTrue(socket:sendTo({host = "10.0.0.3", port = 4242}, "reply"), "the send is taken")
   assertEq(state.sent[1].host, "10.0.0.3", "to the address named")
   assertEq(state.sent[1].port, 4242, "and its port")
   assertEq(state.sent[1].bytes, "reply", "with the bytes given")
   socket:close()
end

function M.aDatagramSocketReportsItsPort()
   net.useBackend((fakeBackend({})))
   local socket = assert(net.bind({host = "0.0.0.0", port = 0}))
   assertEq(socket:port(), 41234, "asking for zero answers what was chosen")
   socket:close()
end

function M.bindReportsWhyItCouldNotBind()
   net.useBackend((fakeBackend({bindFails = "address already in use"})))
   local socket, why = net.bind({host = "0.0.0.0", port = 53})
   assertEq(socket, nil, "a refused bind answers nil")
   assertTrue(why ~= nil and why:find("address already in use", 1, true) ~= nil,
      "and carries what the platform said")
end

function M.flushWaitsForTheQueueToEmpty()
   local backend, state = fakeBackend({drains = false, drainsOnRun = true})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   assertTrue(stream:write("queued"), "the write completes locally")
   assertEq(stream:pending(), 6, "and the bytes are still held")
   assertTrue(stream:flush(), "the flush waits for them to leave")
   assertEq(stream:pending(), 0, "so nothing is left")
   stream:close()
end

function M.flushReportsAWriteThatFailedAfterItWasAccepted()
   -- A failed write leaves nothing pending, so an empty queue is not by itself
   -- success: without asking about the failure a caller sees success at the
   -- exact moment its bytes were lost.
   local backend = fakeBackend({writeFails = true})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   assertTrue(stream:write("gone"), "the platform accepted it")
   local ok, why = stream:flush()
   assertEq(ok, false, "but the flush does not report success")
   assertTrue(why ~= nil, "and says a write did not reach the platform")
   stream:close()
end

function M.closingAWritingViewWaitsForTheDirectionToEnd()
   -- The shutdown request carries no bytes, so waiting on the byte count would
   -- return the moment the writes landed and leave the end of the direction
   -- exactly as cancellable as before.
   local backend, state = fakeBackend({shutdownPends = true})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   local writer = net.asWriter(stream)
   assertTrue(writer:write("last"), "the view writes")
   writer:close()
   assertTrue(state.shutdown, "the direction was ended")
   assertEq(state.shuttingDown, false, "and the close waited for it to finish")
   stream:close()
end

function M.endingTheSendingHalfWaitsForIt()
   -- The public operation, not only the view's close: a caller that writes,
   -- ends its sending half and then closes must not cancel either.
   local backend, state = fakeBackend({shutdownPends = true})
   net.useBackend(backend)
   local stream = assert(net.connect({host = "example", port = 80}))
   assertTrue(stream:write("before the end"), "the write completes")
   assertTrue(stream:shutdownWrite(), "the sending half is ended")
   assertTrue(state.shutdown, "which reached the platform")
   assertEq(state.shuttingDown, false, "and was waited for rather than submitted")
   stream:close()
end

function M.portsAreChecked()
   net.useBackend((fakeBackend({})))
   local ok = pcall(function() return net.listen({host = "127.0.0.1", port = 99999}) end)
   assertEq(ok, false, "a port outside the range is a mistake at the call site")
   local also = pcall(function() return net.connect({host = "example", port = -1}) end)
   assertEq(also, false, "and so is a negative one")
   local datagram = pcall(function() return net.bind({host = "0.0.0.0", port = 70000}) end)
   assertEq(datagram, false, "on a datagram socket too")
end

function M.netAndTlsSelectTheUnifiedRustProvider()
   local netFeature = assert(native.feature("native.net"))
   assertEq(netFeature.provider, "nupp_native_v2", "network provider")
   assertEq(netFeature.providerDriver, "native-rust", "network provider driver")
   assertEq(netFeature.providerFeature, "net", "network provider feature")
   assertEq(netFeature.library, "nupp_native_v2", "network provider library")
   local tlsFeature = assert(native.feature("native.tls"))
   assertEq(tlsFeature.provider, "nupp_native_v2", "TLS provider")
   assertEq(tlsFeature.providerDriver, "native-rust", "TLS provider driver")
   assertEq(tlsFeature.providerFeature, "tls", "TLS provider feature")
   assertEq(tlsFeature.library, "nupp_native_v2", "TLS provider library")
   local expanded = native.expand({["native.tls"] = true})
   assertTrue(expanded["native.net"], "TLS omitted its Rust transport")
   assertTrue(expanded["runtime.native_v2"], "networking omitted the ABI-v2 runtime")
end

return M
