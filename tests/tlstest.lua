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
      client, clientWhy = tls.client(clientSock, {hostname = "localhost", authority = ""})
      if client ~= nil then
         clientDone, clientWhy = shake(client, server)
      else
         clientDone = false
      end
      assertEq(clientDone, false, "an explicit empty authority does not use system roots")
      assertTrue(clientWhy ~= nil, "the explicit empty trust set is refused")
      if client ~= nil then client:close() end
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
   -- cannot decrypt it and Rustls must continue with a full handshake.
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

function M.closingDuringAHandshakeIsImmediateAndTerminal()
   local listener, clientSock, serverSock = sockets()
   local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))

   local done, why = client:step()
   assertEq(done, false, "one client pass leaves the handshake pending")
   assertEq(why, nil, "a pending handshake has not failed")
   client:close()
   assertEq(client:isReleased(), true, "closing releases the pending session")
   assertEq(client:isConnected(), false, "the closed session is terminal")
   local after, closedWhy = client:step()
   assertEq(after, nil, "a closed handshake cannot be driven again")
   assertTrue(closedWhy ~= nil, "the terminal result says why")

   server:close()
   serverSock:close()
   clientSock:close()
   listener:close()
end

function M.aPeerCloseDuringHandshakeBecomesAFailure()
   local listener, clientSock, serverSock = sockets()
   local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
   assertEq(client:step(), false, "the client emits its first handshake flight")
   serverSock:close()

   local done, why
   for _ = 1, 200 do
      done, why = client:step()
      if done == nil then break end
      net.pump(2)
   end
   assertEq(done, nil, "transport closure fails the pending handshake")
   assertTrue(why ~= nil, "the failed handshake reports its terminal reason")

   client:close()
   clientSock:close()
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









return M
