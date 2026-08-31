-- TLS over real loopback connections.
--
-- No fake platform here. What is worth checking about TLS is whether a
-- handshake actually completes, whether a certificate is actually verified, and
-- whether refusing an unverifiable peer actually refuses -- and a fake backend
-- would be asserting that the test's own idea of TLS matches itself.
local net = require("nupp.io.net")
local tls = require("nupp.io.tls")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function assertTrue(cond, label)
   if not cond then error(label or "expected true", 2) end
end

local function slurp(path)
   local f = assert(io.open(path, "rb"), "cannot open " .. path)
   local text = f:read("*a")
   f:close()
   return text
end

local CERT = slurp("tests/data/localhost-cert.pem")
local KEY = slurp("tests/data/localhost-key.pem")

-- A connected pair of sockets on the loopback.
local function sockets()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))
   local client = assert(net.connect({host = "127.0.0.1", port = listener:port()}))
   local served = assert(listener:accept())
   return listener, client, served
end

local function connectTo(listener)
   local client = assert(net.connect({host = "127.0.0.1", port = listener:port()}))
   local served = assert(listener:accept())
   return client, served
end

-- Two peers taking turns until both are done or one refuses. Answers what each
-- side ended up saying, so a test can assert on a refusal as easily as success.
local function shake(client, server)
   local clientDone, serverDone = false, false
   local clientWhy, serverWhy
   for _ = 1, 6000 do
      if not clientDone and clientWhy == nil then
         local done, why = client:step()
         if done == nil then clientWhy = why else clientDone = done end
      end
      if not serverDone and serverWhy == nil then
         local done, why = server:step()
         if done == nil then serverWhy = why else serverDone = done end
      end
      if (clientDone or clientWhy) and (serverDone or serverWhy) then break end
      net.pump(2)
   end
   return clientDone, clientWhy, serverDone, serverWhy
end

local M = {}

-- The platform roots are process-wide. A child whose environment names this
-- fixture can prove both sides of the nil-versus-empty contract without the
-- rest of this suite having initialized the real machine roots first.
if os.getenv("NUPP_TLS_SYSTEM_ROOTS_CHILD") == "1" then
   function M.omittedAuthorityUsesTheConfiguredSystemRoots()
      local listener, clientSock, serverSock = sockets()
      local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
      local client = assert(tls.client(clientSock, {hostname = "localhost"}))
      local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
      assertTrue(clientDone, "the client trusts SSL_CERT_FILE: " .. tostring(clientWhy))
      assertTrue(serverDone, "the server completes: " .. tostring(serverWhy))
      assertTrue(client:isVerified(), "the system-root handshake is verified")
      client:close()
      server:close()
      serverSock:close()
      clientSock:close()
      listener:close()

      listener, clientSock, serverSock = sockets()
      server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
      client = assert(tls.client(clientSock, {hostname = "localhost", authority = ""}))
      clientDone, clientWhy = shake(client, server)
      assertEq(clientDone, false, "an explicit empty authority does not use system roots")
      assertTrue(clientWhy ~= nil, "the explicit empty trust set is refused")
      client:close()
      server:close()
      serverSock:close()
      clientSock:close()
      listener:close()
   end

   return M
end

function M.anOmittedAuthorityUsesThePlatformTrustStore()
   local source = debug.getinfo(1, "S").source:match("^@(.+)[/\\]tests[/\\]tlstest%.lua$")
   if source == nil then
      local current = assert(io.popen("pwd"))
      source = assert(current:read("*l"))
      current:close()
   end
   source = source:gsub("\\", "/")
   local command = ("cd %q && NUPP_TLS_SYSTEM_ROOTS_CHILD=1 "
      .. "SSL_CERT_FILE=%q SSL_CERT_DIR= %q tlstest --jobs=1 --no-color 2>&1; "
      .. "echo '__exit__:'$?"):format(source,
         source .. "/tests/data/localhost-cert.pem", source .. "/build/nupp-test")
   local pipe = assert(io.popen(command))
   local output = pipe:read("*a")
   pipe:close()
   local status = tonumber(output:match("__exit__:(%d+)%s*$"))
   assertEq(status, 0, "the isolated system-root run succeeds:\n" .. output)
   assertTrue(output:find("1 tests, 1 passed", 1, true) ~= nil,
      "the isolated system-root case ran:\n" .. output)
end

function M.aClientResumesAStoredSession()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

   local firstSock, firstServed = connectTo(listener)
   local firstServer = assert(tls.server(firstServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2"},
   }))
   local firstClient = assert(tls.client(firstSock, {
      hostname = "localhost", authority = CERT, protocols = {"h2"},
   }))
   assertTrue((shake(firstClient, firstServer)), "the first handshake completes")
   assertTrue(firstServer:write("ticket follows"), "the server writes after its ticket")
   assertEq(assert(firstClient:read(64)), "ticket follows",
      "the client consumes the post-handshake ticket before the bytes")
   firstClient:close()
   firstServer:close()
   firstServed:close()
   firstSock:close()

   local secondSock, secondServed = connectTo(listener)
   local secondServer = assert(tls.server(secondServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2"},
   }))
   local secondClient = assert(tls.client(secondSock, {
      hostname = "localhost", authority = CERT, protocols = {"h2"},
   }))
   local clientDone, clientWhy, serverDone, serverWhy = shake(secondClient, secondServer)
   assertTrue(clientDone, "the resumed client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the resumed server finishes: " .. tostring(serverWhy))
   assertTrue(secondClient:isResumed(), "the client says cached key material was used")
   assertTrue(secondClient:write("abbreviated"), "a resumed session carries bytes")
   assertEq(assert(secondServer:read(64)), "abbreviated", "the server decrypts them")

   secondClient:close()
   secondServer:close()
   secondServed:close()
   secondSock:close()
   listener:close()
end

function M.resumptionCacheSeparatesProtocolsAndTrustMaterial()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

   local firstSock, firstServed = connectTo(listener)
   local firstServer = assert(tls.server(firstServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2", "http/1.1"},
   }))
   local firstClient = assert(tls.client(firstSock, {
      hostname = "localhost", authority = CERT, protocols = {"h2"},
   }))
   assertTrue((shake(firstClient, firstServer)), "the cache seed handshake completes")
   assertTrue(firstServer:write("seed"), "the first server writes")
   assertEq(assert(firstClient:read(16)), "seed", "and the client collects its ticket")
   firstClient:close()
   firstServer:close()
   firstServed:close()
   firstSock:close()

   local changedSock, changedServed = connectTo(listener)
   local changedServer = assert(tls.server(changedServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2", "http/1.1"},
   }))
   local changedClient = assert(tls.client(changedSock, {
      hostname = "localhost", authority = CERT, protocols = {"http/1.1"},
   }))
   assertTrue((shake(changedClient, changedServer)), "the changed ALPN handshake completes")
   assertEq(changedClient:protocol(), "http/1.1", "the changed protocol is negotiated")
   assertEq(changedClient:isResumed(), false,
      "a ticket cached for another ALPN offer is not resumed")

   changedClient:close()
   changedServer:close()
   changedServed:close()
   changedSock:close()

   local trustSock, trustServed = connectTo(listener)
   local trustServer = assert(tls.server(trustServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2", "http/1.1"},
   }))
   local trustClient = assert(tls.client(trustSock, {
      hostname = "localhost", authority = CERT .. CERT, protocols = {"h2"},
   }))
   assertTrue((shake(trustClient, trustServer)), "the changed trust handshake completes")
   assertEq(trustClient:isResumed(), false,
      "a ticket cached under another certificate set is not resumed")

   trustClient:close()
   trustServer:close()
   trustServed:close()
   trustSock:close()
   listener:close()
end

function M.aRejectedTicketFallsBackToAFullHandshake()
   local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

   local firstSock, firstServed = connectTo(listener)
   local firstServer = assert(tls.server(firstServed, {
      certificate = CERT, privateKey = KEY, protocols = {"h2", "http/1.1"},
   }))
   local firstClient = assert(tls.client(firstSock, {
      verify = false, protocols = {"h2", "http/1.1"},
   }))
   assertTrue((shake(firstClient, firstServer)), "the cache seed handshake completes")
   assertTrue(firstServer:write("seed"), "the first server writes")
   assertEq(assert(firstClient:read(16)), "seed", "and the client collects its ticket")
   firstClient:close()
   firstServer:close()
   firstServed:close()
   firstSock:close()

   -- Server protocol order is part of its ticket-key identity. The client has
   -- the same endpoint key and offers its old ticket, but this configuration
   -- cannot decrypt it and mbedTLS must continue with a full handshake.
   local fallbackSock, fallbackServed = connectTo(listener)
   local fallbackServer = assert(tls.server(fallbackServed, {
      certificate = CERT, privateKey = KEY, protocols = {"http/1.1", "h2"},
   }))
   local fallbackClient = assert(tls.client(fallbackSock, {
      verify = false, protocols = {"h2", "http/1.1"},
   }))
   assertTrue((shake(fallbackClient, fallbackServer)), "the fallback handshake completes")
   assertEq(fallbackClient:isResumed(), false,
      "offering a rejected ticket is not reported as resumption")
   assertEq(fallbackClient:protocol(), "http/1.1",
      "the replacement handshake negotiates the new server preference")

   fallbackClient:close()
   fallbackServer:close()
   fallbackServed:close()
   fallbackSock:close()
   listener:close()
end

function M.aVerifiedHandshakeCarriesBytesBothWays()
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))

   local clientDone, clientWhy, serverDone = shake(client, server)
   assertTrue(clientDone, "the client finished the handshake: " .. tostring(clientWhy))
   assertTrue(serverDone, "and so did the server")
   assertTrue(client:isVerified(), "the client verified the peer's certificate")
   assertTrue(client:isReady(), "and says the session is ready")

   assertTrue(client:write("secret over the wire"), "the client writes plaintext")
   assertEq(assert(server:read(64)), "secret over the wire", "the server reads it decrypted")
   assertTrue(server:write("ack"), "the server answers")
   assertEq(assert(client:read(64)), "ack", "and the client reads that")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.anUntrustedCertificateIsRefused()
   -- The property that makes verification worth having: the machine's ordinary
   -- roots must not trust this private self-signed fixture.
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost"}))

   local clientDone, clientWhy = shake(client, server)
   assertEq(clientDone, false, "the handshake does not complete")
   assertTrue(clientWhy ~= nil, "and the client says why")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.verificationCanBeTurnedOffDeliberately()
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {verify = false}))

   local clientDone, clientWhy, serverDone = shake(client, server)
   assertTrue(clientDone, "an unverified handshake completes: " .. tostring(clientWhy))
   assertTrue(serverDone, "on both sides")
   assertTrue(client:write("plain trust"), "and carries bytes")
   assertEq(assert(server:read(64)), "plain trust", "which the server reads")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.verifyingWithNoNameIsAMistakeAtTheCallSite()
   -- A certificate verified against no name is a certificate belonging to
   -- anybody, so asking for one is refused where it is written.
   local listener, clientSock, serverSock = sockets()
   local ok = pcall(function()
      return tls.client(clientSock, {authority = CERT})
   end)
   assertEq(ok, false, "verifying with no hostname is refused")
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.closeNotifyReadsAsTheEnd()
   -- TLS's end, which is not the socket's: a session that ends with
   -- close_notify has said so, and a truncated one has not.
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the client handshake completes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the server handshake completes: " .. tostring(serverWhy))

   client:close()
   for _ = 1, 200 do net.pump(2) end
   assertEq(assert(server:read(64)), "", "the peer's close_notify reads as the end")
   assertTrue(server:isEnded(), "and the session says so")

   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.readingBeforeTheHandshakeIsRefused()
   local listener, clientSock, serverSock = sockets()
   local client = assert(tls.client(clientSock, {verify = false}))
   local got, why = client:read(16)
   assertEq(got, nil, "reading before the handshake answers nil")
   assertTrue(why ~= nil, "and says why")
   local wrote, writeWhy = client:write("early")
   assertEq(wrote, false, "and so does writing")
   assertTrue(writeWhy ~= nil, "with a reason")
   client:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.aSessionOutlivingItsConnectionIsRefused()
   -- The ordering the affine layer cannot prove across the module boundary. The
   -- session holds the connection's handle rather than the connection, so it can
   -- answer this without owning anything -- and must, because reaching for the
   -- owner to ask would release it.
   local listener, clientSock, serverSock = sockets()
   local client = assert(tls.client(clientSock, {verify = false}))
   clientSock:close()
   assertEq(client:isConnected(), false, "the session sees the connection go")
   local wrote, why = client:write("too late")
   assertEq(wrote, false, "and refuses to write through it")
   assertTrue(why ~= nil, "with a reason rather than a crash")
   client:close()
   serverSock:close()
   listener:close()
end

function M.aReleasedSessionAnswersItsQuestionsRatherThanCrashing()
   -- close() frees the native session, so every accessor has to answer from
   -- the record's own state afterwards: asking the backend about a released
   -- session is asking freed memory, which a plain-Lua caller can do however
   -- firmly the affine layer forbids it in typed code.
   local listener, clientSock, serverSock = sockets()
   local client = assert(tls.client(clientSock, {verify = false}))
   client:close()
   assertEq(client:isConnected(), false, "a released session is not connected")
   assertEq(client:isReleased(), true, "and says it was released")
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.aReleasedDatagramSessionAnswersItsQuestionsRatherThanCrashing()
   local serverSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local clientSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local client = assert(tls.dtlsClient(clientSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {verify = false}))
   client:close()
   assertEq(client:isConnected(), false, "a released DTLS session is not connected")
   assertEq(client:peer(), nil, "and no longer names a peer")
   clientSock:close()
   serverSock:close()
end

function M.aBadCertificateIsReportedRatherThanRaising()
   local listener, clientSock, serverSock = sockets()
   local session, why = tls.server(serverSock, {
      certificate = "-----BEGIN CERTIFICATE-----\nnot a certificate\n-----END CERTIFICATE-----\n",
      privateKey = KEY,
   })
   assertEq(session, nil, "an unreadable certificate answers nil")
   assertTrue(why ~= nil, "and says why")
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.alpnNegotiatesOneProtocol()
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {
      certificate = CERT, privateKey = KEY, protocols = {"http/1.1", "h2"},
   }))
   local client = assert(tls.client(clientSock, {
      hostname = "localhost", authority = CERT, protocols = {"h2", "http/1.1"},
   }))
   assertTrue((shake(client, server)), "the handshake completes")

   assertEq(client:protocol(), server:protocol(), "both sides agree on one protocol")
   -- The server picks, so its order decides even though the client asked for h2
   -- first. That is the whole reason the two lists are separate.
   assertEq(client:protocol(), "http/1.1", "and it is the server's first choice")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.alpnSharingNothingRefusesTheHandshake()
   -- Naming protocols is a commitment: a server that speaks only h2 does not
   -- quietly continue with a client that speaks only http/1.1.
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {
      certificate = CERT, privateKey = KEY, protocols = {"h2"},
   }))
   local client = assert(tls.client(clientSock, {
      hostname = "localhost", authority = CERT, protocols = {"http/1.1"},
   }))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(not clientDone or not serverDone,
      "a handshake with no protocol in common does not complete")
   assertTrue(clientWhy ~= nil or serverWhy ~= nil, "and one side says why")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.noProtocolsMeansNoNegotiation()
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
   assertTrue((shake(client, server)), "the handshake completes without ALPN")
   assertEq(client:protocol(), nil, "and nothing was negotiated")
   assertEq(server:protocol(), nil, "on either side")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.aProtocolNameIsChecked()
   local listener, clientSock, serverSock = sockets()
   local empty = pcall(function()
      return tls.client(clientSock, {verify = false, protocols = {""}})
   end)
   assertEq(empty, false, "an empty protocol name is refused at the call site")
   local long = pcall(function()
      return tls.client(clientSock, {verify = false, protocols = {("x"):rep(256)}})
   end)
   assertEq(long, false, "and so is one longer than a byte can count")
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.aTruncatedSessionIsAFailureAndNotAnEnd()
   -- The distinction TLS adds over a socket: a peer that stopped without
   -- close_notify sent the front of a stream, not the whole of one. Reporting
   -- that as a clean end is the truncation this module refuses.
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the client handshake completes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the server handshake completes: " .. tostring(serverWhy))

   assertTrue(server:write("half a mess"), "the server sends something")
   for _ = 1, 100 do net.pump(2) end
   assertEq(assert(client:read(64)), "half a mess", "which the client reads")

   -- The socket goes without the session ending.
   serverSock:close()
   for _ = 1, 200 do net.pump(2) end

   local got, why = client:read(64)
   assertEq(got, nil, "a truncated session does not read as the end")
   assertTrue(why ~= nil, "it reports a failure")
   assertEq(client:isEnded(), false, "and is not marked as ended")

   client:close()
   server:close()
   clientSock:close()
   listener:close()
end

function M.aFailedReadDoesNotRetryForever()
   -- Would-block and failure have to be distinct at the ABI, or a permanent
   -- failure is retried until something else gives up. A read against a
   -- released connection is the cheapest permanent failure there is.
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
   assertTrue((shake(client, server)), "the handshake completes")

   clientSock:close()
   local got, why = client:read(64)
   assertEq(got, nil, "the read returns rather than suspending")
   assertTrue(why ~= nil, "with a reason")

   client:close()
   server:close()
   serverSock:close()
   listener:close()
end

function M.dtlsPreservesMessagesAndVerifiesTheCookiePeer()
   local serverSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local clientSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local server = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))
   local client = assert(tls.dtlsClient(clientSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))

   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the DTLS client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the DTLS server finishes: " .. tostring(serverWhy))
   assertTrue(client:isVerified(), "the DTLS client verifies the certificate")
   assertEq(server:peer().host, "127.0.0.1", "the cookie-bound peer host")
   assertEq(server:peer().port, clientSock:port(), "the cookie-bound peer port")

   local emptySent, emptyWhy = client:send("")
   assertEq(emptySent, false, "an empty call cannot masquerade as a datagram")
   assertTrue(emptyWhy ~= nil, "the empty send explains its limit")

   local otherSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local otherServer = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))
   local otherClient = assert(tls.dtlsClient(otherSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))
   local otherClientDone, otherClientWhy, otherServerDone, otherServerWhy =
      shake(otherClient, otherServer)
   assertTrue(otherClientDone,
      "the second DTLS client finishes: " .. tostring(otherClientWhy))
   assertTrue(otherServerDone,
      "the second DTLS server finishes: " .. tostring(otherServerWhy))

   assertTrue(otherClient:send("other"), "the other peer queues its message first")
   assertTrue(client:send("first"), "the client sends one message")
   assertEq(assert(server:receive(64)), "first",
      "a session leaves another peer's earlier record queued")
   assertEq(assert(otherServer:receive(64)), "other",
      "the other session receives its own queued record")
   assertTrue(client:send("second"), "the client sends another message")
   assertEq(assert(server:receive(64)), "second", "the second boundary is kept")
   assertTrue(server:send("reply"), "the server sends a message")
   assertEq(assert(client:receive(64)), "reply", "the client decrypts the reply")

   otherClient:close()
   otherServer:close()
   otherSock:close()
   client:close()
   server:close()
   clientSock:close()
   serverSock:close()
end

function M.aDatagramLargerThanTheReceiveMaximumIsRefusedWhole()
   -- DTLS authenticates the datagram as one message. Handing over its first
   -- `maximum` bytes and keeping the rest for the next call would hand a later
   -- receive the tail of this message as though a peer had sent it.
   local serverSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local clientSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local server = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))
   local client = assert(tls.dtlsClient(clientSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the DTLS client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the DTLS server finishes: " .. tostring(serverWhy))

   assertTrue(client:send(("x"):rep(200)), "a 200 byte datagram is sent")
   local got, why = server:receive(64)
   assertEq(got, nil, "receiving it with a smaller maximum does not split it")
   assertTrue(why ~= nil, "the refusal says why")
   assertTrue(client:send("after"), "the next datagram is its own message")
   assertEq(assert(server:receive(64)), "after",
      "and arrives whole rather than as the remainder of the refused one")

   client:close()
   server:close()
   clientSock:close()
   serverSock:close()
end

function M.anAbandonedClientHelloDoesNotWedgeTheServer()
   local serverSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local server = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))

   -- A first hello whose sender never answers the cookie challenge. The
   -- address is real, but until the cookie comes back it has proved no more
   -- than a spoofed one, and the session must not stay bound to it.
   local spoofSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local spoof = assert(tls.dtlsClient(spoofSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))
   spoof:step()
   for _ = 1, 50 do
      net.pump(2)
      server:step()
   end
   spoof:close()
   spoofSock:close()

   local clientSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local client = assert(tls.dtlsClient(clientSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the honest client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the challenged server finishes: " .. tostring(serverWhy))
   assertEq(server:peer().port, clientSock:port(),
      "and the session bound the peer that answered the cookie")

   client:close()
   server:close()
   clientSock:close()
   serverSock:close()
end

function M.aLearningSessionLeavesABoundPeersRecordsAlone()
   local serverSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local clientSock = assert(net.bind({host = "127.0.0.1", port = 0}))
   local server = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))
   local client = assert(tls.dtlsClient(clientSock, {
      host = "127.0.0.1", port = serverSock:port(),
   }, {hostname = "localhost", authority = CERT}))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the DTLS client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the DTLS server finishes: " .. tostring(serverWhy))

   -- A second session, still waiting for a first hello of its own, polls the
   -- shared socket while the bound peer's record is queued on it.
   local learner = assert(tls.dtlsServer(serverSock, {
      certificate = CERT, privateKey = KEY,
   }))
   assertTrue(client:send("mine"), "the bound peer sends a record")
   for _ = 1, 20 do
      net.pump(2)
      learner:step()
   end
   assertEq(learner:peer(), nil,
      "the learning session does not bind a peer already claimed")
   assertEq(assert(server:receive(64)), "mine",
      "and the bound session still receives its own record")

   learner:close()
   client:close()
   server:close()
   clientSock:close()
   serverSock:close()
end

function M.anOffloadRequestThatCannotEngageFallsBackToUserSpace()
   -- The contract: kernelOffload asks, isKernelOffloaded answers. On a host
   -- with no kernel TLS at all the request can never engage, so the handshake
   -- must still succeed on user-space records and say that offload did not
   -- happen -- a caller relying on sendfile semantics checks the answer.
   if tls.kernelOffloadSupported() then return end

   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {
      certificate = CERT, privateKey = KEY, kernelOffload = true,
   }))
   local client = assert(tls.client(clientSock, {
      hostname = "localhost", authority = CERT, kernelOffload = true,
   }))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the client falls back and finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the server falls back and finishes: " .. tostring(serverWhy))
   assertEq(client:isKernelOffloaded(), false,
      "the client reports that offload did not engage")
   assertEq(server:isKernelOffloaded(), false,
      "and so does the server")
   assertTrue(client:write("in user space"), "the fallback session writes plaintext")
   assertEq(assert(server:read(64)), "in user space", "and the peer decrypts it")

   client:close()
   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.kernelOffloadEngagesWhereThePlatformAllows()
   if not tls.kernelOffloadSupported() then return end

   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {
      certificate = CERT, privateKey = KEY, kernelOffload = true,
   }))
   local client = assert(tls.client(clientSock, {
      hostname = "localhost", authority = CERT, kernelOffload = true,
   }))
   local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
   assertTrue(clientDone, "the kTLS client finishes: " .. tostring(clientWhy))
   assertTrue(serverDone, "the kTLS server finishes: " .. tostring(serverWhy))
   assertTrue(client:isKernelOffloaded(), "the client handed both directions off")
   assertTrue(server:isKernelOffloaded(), "the server handed both directions off")
   assertTrue(client:write("in kernel"), "kernel TLS writes plaintext")
   assertEq(assert(server:read(64)), "in kernel", "kernel TLS decrypts it")

   client:close()
   server:close()
   clientSock:close()
   serverSock:close()
   listener:close()
end

return M
