local testAssert = require("nupp.test")
-- TLS over real loopback connections.
--
-- Real connections check whether a handshake completes, a certificate is
-- verified, and an unverifiable peer is refused. Two narrow fake-provider cases
-- check the facade's bounds without pretending to implement TLS.
local net = require("nupp.io.net")
local tls = require("nupp.io.tls")

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
            if done == nil then
                clientWhy = why
            else
                clientDone = done
            end
        end
        if not serverDone and serverWhy == nil then
            local done, why = server:step()
            if done == nil then
                serverWhy = why
            else
                serverDone = done
            end
        end
        if (clientDone or clientWhy) and (serverDone or serverWhy) then
            break
        end
        require("nupp.io.net").pump(2)
    end

    return clientDone, clientWhy, serverDone, serverWhy
end

local M = {}

local function boundarySession(provider)
    local facade = require("providerstate").tls(provider)
    local session = assert(facade.client({}, {verify = false}))
    assert(session:handshake(), "the boundary fixture handshake completes")

    return session
end

-- The platform roots are process-wide. A child whose environment names this
-- fixture can prove both sides of the nil-versus-empty contract without the
-- rest of this suite having initialized the real machine roots first.
if os.getenv("NUPP_TLS_SYSTEM_ROOTS_CHILD") == "1" then
    function M.omittedAuthorityUsesTheConfiguredSystemRoots()
        local listener, clientSock, serverSock = sockets()
        local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
        local client = assert(tls.client(clientSock, {hostname = "localhost"}))
        local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
        assert(clientDone, "the client trusts SSL_CERT_FILE: " .. tostring(clientWhy))
        assert(serverDone, "the server completes: " .. tostring(serverWhy))
        assert(client:isVerified(), "the system-root handshake is verified")
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
        testAssert.equal(clientDone, false, "an explicit empty authority does not use system roots")
        assert(clientWhy ~= nil, "the explicit empty trust set is refused")
        if client ~= nil then
            client:close()
        end
        server:close()
        serverSock:close()
        clientSock:close()
        listener:close()
    end

    return M
end

-- A peer that stops reading fills every buffer between the two ends. Closing
-- then drains for a bounded time rather than waiting for room that never comes.
function M.closeReturnsWhenThePeerHasStoppedReading()
    local listener, clientSock, serverSock = sockets()
    local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY}))
    local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
    local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
    assert(clientDone and serverDone, tostring(clientWhy or serverWhy))
    local provider = require("nupp.runtime.provider.nativetls")
    local chunk = string.rep("x", 16384)
    local pending = 0
    while pending < 200 do
        local accepted, why = provider:write(client._session, chunk)
        assert(why == nil, why)
        if accepted == nil then
            pending = pending + 1
            net.pump(1)
        end
    end
    local started = os.time()
    client:close()
    assert(os.time() - started <= 3, "close waited past its drain")
    server:close()
    serverSock:close()
    clientSock:close()
    listener:close()
end

function M.anOmittedAuthorityUsesThePlatformTrustStore()
    local source = debug.getinfo(1, "S").source:match("^@(.+)[/\\]tests[/\\]tlstest%.lua$")
    if source == nil then
        local current = assert(io.popen("pwd"))
        source = assert(current:read("*l"))
        current:close()
    end
    source = source:gsub("\\", "/")
    local command = (
        "cd %q && NUPP_TLS_SYSTEM_ROOTS_CHILD=1 "
        .. "SSL_CERT_FILE=%q SSL_CERT_DIR= %q tlstest --jobs=1 --no-color 2>&1; "
        .. "echo '__exit__:'$?"
    ):format(source, source .. "/tests/data/localhost-cert.pem", source .. "/build/nupp-test")
    local pipe = assert(io.popen(command))
    local output = pipe:read("*a")
    pipe:close()
    local status = tonumber(output:match("__exit__:(%d+)%s*$"))
    testAssert.equal(status, 0, "the isolated system-root run succeeds:\n" .. output)
    assert(output:find("1 tests, 1 passed", 1, true) ~= nil, "the isolated system-root case ran:\n" .. output)
end

function M.aClientResumesAStoredSession()
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

    local firstSock, firstServed = connectTo(listener)
    local firstServer = assert(tls.server(firstServed, {certificate = CERT, privateKey = KEY, protocols = {"h2"},}))
    local firstClient = assert(tls.client(firstSock, {hostname = "localhost", authority = CERT, protocols = {"h2"},}))
    assert((shake(firstClient, firstServer)), "the first handshake completes")
    assert(firstServer:write("ticket follows"), "the server writes after its ticket")
    testAssert.equal(
        assert(firstClient:read(64)),
        "ticket follows",
        "the client consumes the post-handshake ticket before the bytes"
    )
    firstClient:close()
    firstServer:close()
    firstServed:close()
    firstSock:close()

    local secondSock, secondServed = connectTo(listener)
    local secondServer = assert(tls.server(secondServed, {certificate = CERT, privateKey = KEY, protocols = {"h2"},}))
    local secondClient = assert(tls.client(secondSock, {hostname = "localhost", authority = CERT, protocols = {"h2"},}))
    local clientDone, clientWhy, serverDone, serverWhy = shake(secondClient, secondServer)
    assert(clientDone, "the resumed client finishes: " .. tostring(clientWhy))
    assert(serverDone, "the resumed server finishes: " .. tostring(serverWhy))
    assert(secondClient:isResumed(), "the client says cached key material was used")
    assert(secondClient:write("abbreviated"), "a resumed session carries bytes")
    testAssert.equal(assert(secondServer:read(64)), "abbreviated", "the server decrypts them")

    secondClient:close()
    secondServer:close()
    secondServed:close()
    secondSock:close()
    listener:close()
end

function M.resumptionCacheSeparatesProtocolsAndTrustMaterial()
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

    local firstSock, firstServed = connectTo(listener)
    local firstServer = assert(
        tls.server(firstServed, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"h2", "http/1.1"},
        })
    )
    local firstClient = assert(tls.client(firstSock, {hostname = "localhost", authority = CERT, protocols = {"h2"},}))
    assert((shake(firstClient, firstServer)), "the cache seed handshake completes")
    assert(firstServer:write("seed"), "the first server writes")
    testAssert.equal(assert(firstClient:read(16)), "seed", "and the client collects its ticket")
    firstClient:close()
    firstServer:close()
    firstServed:close()
    firstSock:close()

    local changedSock, changedServed = connectTo(listener)
    local changedServer = assert(
        tls.server(changedServed, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"h2", "http/1.1"},
        })
    )
    local changedClient = assert(
        tls.client(changedSock, {
            hostname = "localhost",
            authority = CERT,
            protocols = {"http/1.1"},
        })
    )
    assert((shake(changedClient, changedServer)), "the changed ALPN handshake completes")
    testAssert.equal(changedClient:protocol(), "http/1.1", "the changed protocol is negotiated")
    testAssert.equal(changedClient:isResumed(), false, "a ticket cached for another ALPN offer is not resumed")

    changedClient:close()
    changedServer:close()
    changedServed:close()
    changedSock:close()

    local trustSock, trustServed = connectTo(listener)
    local trustServer = assert(
        tls.server(trustServed, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"h2", "http/1.1"},
        })
    )
    local trustClient = assert(
        tls.client(trustSock, {
            hostname = "localhost",
            authority = CERT .. CERT,
            protocols = {"h2"},
        })
    )
    assert((shake(trustClient, trustServer)), "the changed trust handshake completes")
    testAssert.equal(trustClient:isResumed(), false, "a ticket cached under another certificate set is not resumed")

    trustClient:close()
    trustServer:close()
    trustServed:close()
    trustSock:close()
    listener:close()
end

function M.aRejectedTicketFallsBackToAFullHandshake()
    local listener = assert(net.listen({host = "127.0.0.1", port = 0}))

    local firstSock, firstServed = connectTo(listener)
    local firstServer = assert(
        tls.server(firstServed, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"h2", "http/1.1"},
        })
    )
    local firstClient = assert(tls.client(firstSock, {verify = false, protocols = {"h2", "http/1.1"},}))
    assert((shake(firstClient, firstServer)), "the cache seed handshake completes")
    assert(firstServer:write("seed"), "the first server writes")
    testAssert.equal(assert(firstClient:read(16)), "seed", "and the client collects its ticket")
    firstClient:close()
    firstServer:close()
    firstServed:close()
    firstSock:close()

    -- Server protocol order is part of its ticket-key identity. The client has
    -- the same endpoint key and offers its old ticket, but this configuration
    -- cannot decrypt it and Rustls must continue with a full handshake.
    local fallbackSock, fallbackServed = connectTo(listener)
    local fallbackServer = assert(
        tls.server(fallbackServed, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"http/1.1", "h2"},
        })
    )
    local fallbackClient = assert(tls.client(fallbackSock, {verify = false, protocols = {"h2", "http/1.1"},}))
    assert((shake(fallbackClient, fallbackServer)), "the fallback handshake completes")
    testAssert.equal(fallbackClient:isResumed(), false, "offering a rejected ticket is not reported as resumption")
    testAssert.equal(
        fallbackClient:protocol(),
        "http/1.1",
        "the replacement handshake negotiates the new server preference"
    )

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
    assert(clientDone, "the client finished the handshake: " .. tostring(clientWhy))
    assert(serverDone, "and so did the server")
    assert(client:isVerified(), "the client verified the peer's certificate")
    assert(client:isReady(), "and says the session is ready")

    assert(client:write("secret over the wire"), "the client writes plaintext")
    testAssert.equal(assert(server:read(64)), "secret over the wire", "the server reads it decrypted")
    assert(server:write("ack"), "the server answers")
    testAssert.equal(assert(client:read(64)), "ack", "and the client reads that")

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
    testAssert.equal(clientDone, false, "the handshake does not complete")
    assert(clientWhy ~= nil, "and the client says why")

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
    assert(clientDone, "an unverified handshake completes: " .. tostring(clientWhy))
    assert(serverDone, "on both sides")
    assert(client:write("plain trust"), "and carries bytes")
    testAssert.equal(assert(server:read(64)), "plain trust", "which the server reads")

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
    testAssert.equal(ok, false, "verifying with no hostname is refused")
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
    assert(clientDone, "the client handshake completes: " .. tostring(clientWhy))
    assert(serverDone, "the server handshake completes: " .. tostring(serverWhy))

    client:close()
    for _ = 1, 200 do
        require("nupp.io.net").pump(2)
    end
    testAssert.equal(assert(server:read(64)), "", "the peer's close_notify reads as the end")
    assert(server:isEnded(), "and the session says so")

    server:close()
    serverSock:close()
    clientSock:close()
    listener:close()
end

function M.readingBeforeTheHandshakeIsRefused()
    local listener, clientSock, serverSock = sockets()
    local client = assert(tls.client(clientSock, {verify = false}))
    local got, why = client:read(16)
    testAssert.equal(got, nil, "reading before the handshake answers nil")
    assert(why ~= nil, "and says why")
    local wrote, writeWhy = client:write("early")
    testAssert.equal(wrote, false, "and so does writing")
    assert(writeWhy ~= nil, "with a reason")
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
    testAssert.equal(done, false, "one client pass leaves the handshake pending")
    testAssert.equal(why, nil, "a pending handshake has not failed")
    client:close()
    testAssert.equal(client:isReleased(), true, "closing releases the pending session")
    testAssert.equal(client:isConnected(), false, "the closed session is terminal")
    local after, closedWhy = client:step()
    testAssert.equal(after, nil, "a closed handshake cannot be driven again")
    assert(closedWhy ~= nil, "the terminal result says why")

    server:close()
    serverSock:close()
    clientSock:close()
    listener:close()
end

function M.aPeerCloseDuringHandshakeBecomesAFailure()
    local listener, clientSock, serverSock = sockets()
    local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT}))
    testAssert.equal(client:step(), false, "the client emits its first handshake flight")
    serverSock:close()

    local done, why
    for _ = 1, 200 do
        done, why = client:step()
        if done == nil then
            break
        end
        require("nupp.io.net").pump(2)
    end
    testAssert.equal(done, nil, "transport closure fails the pending handshake")
    assert(why ~= nil, "the failed handshake reports its terminal reason")

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
    testAssert.equal(client:isConnected(), false, "a released session is not connected")
    testAssert.equal(client:isReleased(), true, "and says it was released")
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
    testAssert.equal(session, nil, "an unreadable certificate answers nil")
    assert(why ~= nil, "and says why")
    serverSock:close()
    clientSock:close()
    listener:close()
end

function M.alpnNegotiatesOneProtocol()
    local listener, clientSock, serverSock = sockets()
    local server = assert(
        tls.server(serverSock, {
            certificate = CERT,
            privateKey = KEY,
            protocols = {"http/1.1", "h2"},
        })
    )
    local client = assert(
        tls.client(clientSock, {
            hostname = "localhost",
            authority = CERT,
            protocols = {"h2", "http/1.1"},
        })
    )
    assert((shake(client, server)), "the handshake completes")

    testAssert.equal(client:protocol(), server:protocol(), "both sides agree on one protocol")
    -- The server picks, so its order decides even though the client asked for h2
    -- first. That is the whole reason the two lists are separate.
    testAssert.equal(client:protocol(), "http/1.1", "and it is the server's first choice")

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
    local server = assert(tls.server(serverSock, {certificate = CERT, privateKey = KEY, protocols = {"h2"},}))
    local client = assert(tls.client(clientSock, {hostname = "localhost", authority = CERT, protocols = {"http/1.1"},}))
    local clientDone, clientWhy, serverDone, serverWhy = shake(client, server)
    assert(not clientDone or not serverDone, "a handshake with no protocol in common does not complete")
    assert(clientWhy ~= nil or serverWhy ~= nil, "and one side says why")

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
    assert((shake(client, server)), "the handshake completes without ALPN")
    testAssert.equal(client:protocol(), nil, "and nothing was negotiated")
    testAssert.equal(server:protocol(), nil, "on either side")

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
    testAssert.equal(empty, false, "an empty protocol name is refused at the call site")
    local long = pcall(function()
        return tls.client(clientSock, {verify = false, protocols = {("x"):rep(256)}})
    end)
    testAssert.equal(long, false, "and so is one longer than a byte can count")
    serverSock:close()
    clientSock:close()
    listener:close()
end

function M.providerReadsCannotExceedTheRequestedCount()
    local session = boundarySession({
        wrap = function()
            return {}
        end,
        handshake = function()
            return true
        end,
        read = function()
            return "too many"
        end,
        connected = function()
            return true
        end,
        flushed = function()
            return true
        end,
        closeNotify = function()
            return true
        end,
        destroy = function()
        end,
    })
    local bytes, why = session:read(2)
    testAssert.equal(bytes, nil, "an oversized provider read is refused")
    testAssert.equal(why, "the TLS provider returned more bytes than requested", "the boundary failure is named")
    session:close()
end

function M.providerWritesMustMakeValidProgress()
    local writes = 0
    local session = boundarySession({
        wrap = function()
            return {}
        end,
        handshake = function()
            return true
        end,
        write = function()
            writes = writes + 1

            return writes == 1 and 0 or 3
        end,
        connected = function()
            return true
        end,
        flushed = function()
            return true
        end,
        closeNotify = function()
            return true
        end,
        destroy = function()
        end,
    })
    local wrote, why = session:write("abc")
    testAssert.equal(wrote, false, "an impossible provider write is refused")
    testAssert.equal(why, "the TLS provider returned an invalid write count", "the boundary failure is named")
    session:close()
end

function M.aClientNeedsNoOptionsTable()
    -- Every client option is optional, so the table is too. Verification stays on
    -- without one, and a verified session with no name to check is refused rather
    -- than trusting whoever answers.
    local wrapped = {}
    local facade = require("providerstate").tls({
        wrap = function(_self, _stream, isServer, hostname, _certificate, _key, _authority, _protocols, verify)
            wrapped[#wrapped + 1] = {isServer = isServer, hostname = hostname, verify = verify}
            return {}
        end,
        destroy = function()
        end,
    })
    local ok, why = pcall(facade.client, {})
    testAssert.equal(ok, false, "an unnamed verified client is refused")
    assert(tostring(why):find("needs a hostname", 1, true) ~= nil, "for want of a name: " .. tostring(why))
    testAssert.equal(#wrapped, 0, "before anything reached the provider")
    local session = assert(facade.client({}, {hostname = "example.com"}))
    testAssert.equal(wrapped[1].verify, true, "a named client verifies by default")
    testAssert.equal(wrapped[1].hostname, "example.com", "against the name it was given")
    session:close()
end

return M
