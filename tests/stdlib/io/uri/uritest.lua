-- `io.URI` through the real provider.
--
-- What is checked here is one table of URIs and one table of derivations, both
-- recorded from the implementation this replaced. A URI library's whole job is
-- to agree with everybody else about what a piece of text names, so the useful
-- test is not that each function does something reasonable but that the answers
-- have not moved. Everybody else is the WHATWG URL Standard: the native `url`
-- crate, the portable parser, and, where node is installed, a host `URL` read
-- the same seeded corpus and must agree.
--
-- The launcher's provider is reused when available, and otherwise one is built
-- for the suite, reached the way a generated program reaches it.
local test = require("assert")
local stdlib = require("nupp.compiler.stdlib")

local M = {}

local uri, previous, root
local installedBootstrap = false
local unavailable

local function temporaryRoot()
    local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
    base = base:gsub("\\", "/")
    -- Two workers sharding this suite can start in the same clock second and
    -- draw the same seeded random suffix, so a per-process address keeps one
    -- worker's teardown out of the other's root.
    local unique = tostring({}):match("(%x+)$") or "0"

    return (
        base:gsub("/$", "")
    ) .. "/nupp-uri-test-" .. tostring(os.time()) .. "-" .. unique .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
    installedBootstrap = false
    math.randomseed(os.time())
    root = temporaryRoot()
    os.execute("mkdir -p '" .. root .. "'")
    -- The VM carries its own provider: the facade reaches it the way a VM
    -- program does.
    uri = require("nupp.runtime.standardio").value
end

function M.afterAll()
    -- Restore only a bootstrap this suite replaced.
    if installedBootstrap then
        _G.nupp = previous
        installedBootstrap = false
    end
    if root then
        os.execute("rm -rf '" .. root .. "'")
    end
end

local function ready()
    if unavailable then
        error("skip: " .. unavailable, 0)
    end
    return uri
end

-- Each row is the text, then the normalized form and every component it
-- answers. `false` is "this component is absent", which a table cannot say
-- with nil.
local PARSED = {
    {
        "https://EXAMPLE.com/a/../b?q=1",
        "https://example.com/b?q=1",
        scheme = "https",
        authority = "example.com",
        username = "",
        password = false,
        host = "example.com",
        port = false,
        path = "/b",
        query = "q=1",
        fragment = false
    },
    {
        "https://user:pass@example.com:8443/api?q=1#top",
        "https://user:pass@example.com:8443/api?q=1#top",
        scheme = "https",
        authority = "user:pass@example.com:8443",
        username = "user",
        password = "pass",
        host = "example.com",
        port = 8443,
        path = "/api",
        query = "q=1",
        fragment = "top"
    },
    -- A special scheme has a mandatory host, a default port that is not written
    -- down, and a path that is `/` when the text gave none.
    {
        "http://example.com",
        "http://example.com/",
        scheme = "http",
        authority = "example.com",
        username = "",
        password = false,
        host = "example.com",
        port = false,
        path = "/",
        query = false,
        fragment = false
    },
    {"http://example.com:80/x", "http://example.com/x", port = false},
    {"https://example.com:443/x", "https://example.com/x", port = false},
    {"HTTPS://Example.COM", "https://example.com/", host = "example.com"},
    -- Without an authority the rest is opaque: no host, and nothing normalized
    -- away, because the scheme is what knows what those characters mean.
    {
        "mailto:someone@example.com",
        "mailto:someone@example.com",
        scheme = "mailto",
        authority = false,
        username = "",
        password = false,
        host = false,
        port = false,
        path = "someone@example.com",
        query = false,
        fragment = false
    },
    {"urn:isbn:0451450523", "urn:isbn:0451450523", path = "isbn:0451450523"},
    {"data:text/plain,hello", "data:text/plain,hello", path = "text/plain,hello"},
    -- An authority that is present and empty names no host, which is what a
    -- local file URL is.
    {"file:///tmp/x", "file:///tmp/x", authority = "", host = false, path = "/tmp/x"},
    {"ftp://ftp.example.com/pub/", "ftp://ftp.example.com/pub/", port = false},
    -- Any other scheme with an authority keeps its host's case, and its path is
    -- still a hierarchy: `.` and `..` resolve, and an empty segment stays.
    {"custom://Host.Example/a//b/./c/../d", "custom://Host.Example/a//b/d", host = "Host.Example", path = "/a//b/d"},
    -- Text that is already encoded stays as it was written, and text that has to
    -- be encoded is.
    {"https://example.com/%7euser/a b", "https://example.com/%7euser/a%20b", path = "/%7euser/a%20b"},
    -- An empty query and no query are different URIs.
    {"http://example.com/?#", "http://example.com/?#", query = "", fragment = ""},
    {"https://[::1]:8080/x", "https://[::1]:8080/x", authority = "[::1]:8080", host = "[::1]", port = 8080},
    {"https://[2001:db8::1]/x", "https://[2001:db8::1]/x", host = "[2001:db8::1]"},
    {"https://[1:2:3:4:5:6:7:8]/x", "https://[1:2:3:4:5:6:7:8]/x", host = "[1:2:3:4:5:6:7:8]"},
    {"http://user@example.com", "http://user@example.com/", username = "user", password = false},
    {
        "http://user@info@example.com/x",
        "http://user%40info@example.com/x",
        username = "user%40info",
        host = "example.com",
    },
    {
        "http://user name:pass word@example.com/x",
        "http://user%20name:pass%20word@example.com/x",
        username = "user%20name",
        password = "pass%20word",
    },
    {
        "http://example.com/a b?x y#z z",
        "http://example.com/a%20b?x%20y#z%20z",
        path = "/a%20b",
        query = "x%20y",
        fragment = "z%20z",
    },
    {
        "mailto:user name@example.com?subject=hello world#part one",
        "mailto:user name@example.com?subject=hello%20world#part%20one",
        path = "user name@example.com",
        query = "subject=hello%20world",
        fragment = "part%20one",
    },
    {"https://example.com/a?b=1&c=2#frag", "https://example.com/a?b=1&c=2#frag", query = "b=1&c=2", fragment = "frag"},
}

local COMPONENTS = {"scheme", "authority", "username", "password", "host", "port", "path", "query", "fragment",}

function M.rootIoUsesTheCanonicalUriAndNestedComponents()
    local api = ready()
    local parts = {scheme = "https", host = "example.com", path = "/status"}
    test.eq(type(api.URI.Components), "table")
    local address = assert(api.URI.of(parts))
    test.eq(address:host(), "example.com")
    test.eq(address:path(), "/status")
    test.eq(getmetatable(address), api.URI)
    test.eq(api.isuri, nil)
    local valid, why = api.validateuri("http://[")
    test.eq(valid, false)
    test.eq(type(why), "string")
end

function M.parsingAnswersTheRecordedComponents()
    local module = ready()
    for _, row in ipairs(PARSED) do
        local value, reason = module.URI.of(row[1])
        assert(value, row[1] .. ": " .. tostring(reason))
        test.eq(value:tostring(), row[2], row[1] .. " normalizes")
        for _, name in ipairs(COMPONENTS) do
            local wanted = row[name]
            if wanted ~= nil then
                local found = value[name](value)
                if wanted == false then
                    test.eq(found, nil, row[1] .. " has no " .. name)
                else
                    test.eq(found, wanted, row[1] .. " " .. name)
                end
            end
        end
    end
end

-- Bad text is an ordinary answer rather than an error, and the reason says
-- which rule the text broke.
function M.malformedTextAnswersAReason()
    local module = ready()
    for text, reason in pairs({
        ["http://["] = "invalid IPv6 address",
        [""] = "relative URL without a base",
        ["://x"] = "relative URL without a base",
        ["nonsense"] = "relative URL without a base",
        ["1http://x"] = "relative URL without a base",
        ["http:"] = "empty host",
    }) do
        local value, why = module.URI.of(text)
        test.eq(value, nil, "[" .. text .. "] does not parse")
        test.eq(why, reason, "[" .. text .. "] says why")
    end
end

function M.derivingReplacesOneComponentAtATime()
    local module = ready()
    local base = assert(module.URI.of("https://user:pass@example.com:8443/api/v1?q=1#top"))

    test.eq(base:withscheme("http"):tostring(), "http://user:pass@example.com:8443/api/v1?q=1#top")
    test.eq(base:withuserinfo(nil):tostring(), "https://example.com:8443/api/v1?q=1#top")
    test.eq(base:withuserinfo("u"):tostring(), "https://u@example.com:8443/api/v1?q=1#top")
    test.eq(base:withuserinfo("u:p"):tostring(), "https://u:p@example.com:8443/api/v1?q=1#top")
    test.eq(base:withhost("other.example"):tostring(), "https://user:pass@other.example:8443/api/v1?q=1#top")
    test.eq(base:withport(99):tostring(), "https://user:pass@example.com:99/api/v1?q=1#top")
    test.eq(base:withport(nil):tostring(), "https://user:pass@example.com/api/v1?q=1#top")
    test.eq(base:withpath("/x"):tostring(), "https://user:pass@example.com:8443/x?q=1#top")
    -- A path is a hierarchy under an authority, so one written without a leading
    -- separator gets one rather than running into the host.
    test.eq(base:withpath("x/y"):tostring(), "https://user:pass@example.com:8443/x/y?q=1#top")
    test.eq(base:withpath(""):tostring(), "https://user:pass@example.com:8443/?q=1#top")
    test.eq(base:withquery(nil):tostring(), "https://user:pass@example.com:8443/api/v1#top")
    test.eq(base:withquery("a=b"):tostring(), "https://user:pass@example.com:8443/api/v1?a=b#top")
    test.eq(base:withfragment(nil):tostring(), "https://user:pass@example.com:8443/api/v1?q=1")
    test.eq(base:withfragment("z"):tostring(), "https://user:pass@example.com:8443/api/v1?q=1#z")

    -- The original is untouched by all of it.
    test.eq(base:tostring(), "https://user:pass@example.com:8443/api/v1?q=1#top")

    local raised = select(
        2,
        pcall(function()
            return base:withport(70000)
        end)
    )
    assert(tostring(raised):find("0 through 65535", 1, true), "a port outside the range raises: " .. tostring(raised))
end

-- One separator between the two, whichever of them wrote it.
function M.concatenatingAPathAddsOneSeparator()
    local module = ready()
    local plain = assert(module.URI.of("https://api.example.com/v1"))
    local slashed = assert(module.URI.of("https://api.example.com/v1/"))
    test.eq(plain:concatpath("users"):path(), "/v1/users")
    test.eq(plain:concatpath("/users"):path(), "/v1/users")
    test.eq(slashed:concatpath("users"):path(), "/v1/users")
    test.eq(slashed:concatpath("/users"):path(), "/v1/users")
    test.eq(plain:concatpath(""), plain, "an empty suffix leaves the URI unchanged")
end

function M.removingAHostRemovesItsAuthority()
    local module = ready()
    local value = assert(module.URI.of("custom://user:pass@example.com:8080/path"))
    local without = value:withhost(nil)
    test.eq(without:tostring(), "custom:/path")
    test.eq(without:authority(), nil)
    test.eq(without:userinfo(), nil)
    test.eq(without:port(), nil)
end

-- A component holding a delimiter, or a path shaped like an authority, is
-- refused rather than assembled into text that reparses with the boundary
-- somewhere else.
function M.composingRefusesComponentsThatShiftBoundaries()
    local module = ready()
    local refused = {
        {{scheme = "https", host = "example.com", path = "status"}, 'path must be empty or begin with "/"'},
        {{scheme = "https", path = "//attacker.com/x"}, 'path cannot begin with "//"'},
        {
            {scheme = "https", host = "example.com", path = "/", query = "a=1#f"},
            "query cannot contain a component delimiter"
        },
        {{scheme = "https", host = "example.com", path = "/a#b"}, "path cannot contain a component delimiter"},
        {{scheme = "https", host = "example.com", path = "/a?b=1"}, "path cannot contain a component delimiter"},
        {{scheme = "https", host = "example.com/evil"}, "host cannot contain a component delimiter"},
        {{scheme = "https", host = "evil@example.com"}, "host cannot contain a component delimiter"},
        {
            {scheme = "https", userinfo = "u/v", host = "example.com", path = "/"},
            "userinfo cannot contain a component delimiter"
        },
    }
    for _, row in ipairs(refused) do
        local value, why = module.URI.of(row[1])
        test.eq(value, nil, row[2] .. ": refused")
        assert(tostring(why):find(row[2], 1, true), row[2] .. ": the reason says which rule, got " .. tostring(why))
    end

    -- The shapes the rules describe still compose.
    local accepted = {
        {{scheme = "https", host = "example.com", path = "/status"}, "https://example.com/status"},
        {{scheme = "https", host = "example.com", path = ""}, "https://example.com/"},
        {{scheme = "https", host = "example.com"}, "https://example.com/"},
        {{scheme = "mailto", path = "someone@example.com"}, "mailto:someone@example.com"},
    }
    for _, row in ipairs(accepted) do
        local value, why = module.URI.of(row[1])
        assert(value, row[2] .. ": " .. tostring(why))
        test.eq(value:tostring(), row[2], row[2] .. " composes")
    end
end

function M.resolvingFollowsTheReferenceRules()
    local module = ready()
    local page = assert(module.URI.of("https://example.com/docs/guide/index.html"))
    local expected = {
        {"../images/avatar.png", "https://example.com/docs/images/avatar.png"},
        {"/root.png", "https://example.com/root.png"},
        {"other.html", "https://example.com/docs/guide/other.html"},
        {"?x=1", "https://example.com/docs/guide/index.html?x=1"},
        {"#frag", "https://example.com/docs/guide/index.html#frag"},
        {"https://other.example/z", "https://other.example/z"},
        {"//other.example/z", "https://other.example/z"},
        {"", "https://example.com/docs/guide/index.html"},
        {"..", "https://example.com/docs/"},
        {"../..", "https://example.com/"},
        {"./a", "https://example.com/docs/guide/a"},
    }
    for _, row in ipairs(expected) do
        local resolved, reason = page:resolve(row[1])
        assert(resolved, "[" .. row[1] .. "]: " .. tostring(reason))
        test.eq(resolved:tostring(), row[2], "resolve [" .. row[1] .. "]")
    end
end

-- RFC 3986 section 5.4 against its own base. A reference repeating the base's
-- scheme without an authority, `http:g`, is relative, as browsers and the RFC's
-- non-strict reading resolve it; it used to be parsed on its own, where the
-- special-scheme parser made `g` the host. `//g` gains the root path every
-- special-scheme URI normalizes to.
function M.resolvingFollowsRfc3986Examples()
    local module = ready()
    local base = assert(module.URI.of("http://a/b/c/d;p?q"))
    local expected = {
        {"g:h", "g:h"},
        {"g", "http://a/b/c/g"},
        {"./g", "http://a/b/c/g"},
        {"g/", "http://a/b/c/g/"},
        {"/g", "http://a/g"},
        {"//g", "http://g/"},
        {"?y", "http://a/b/c/d;p?y"},
        {"g?y", "http://a/b/c/g?y"},
        {"#s", "http://a/b/c/d;p?q#s"},
        {"g#s", "http://a/b/c/g#s"},
        {"g?y#s", "http://a/b/c/g?y#s"},
        {";x", "http://a/b/c/;x"},
        {"g;x", "http://a/b/c/g;x"},
        {"g;x?y#s", "http://a/b/c/g;x?y#s"},
        {"", "http://a/b/c/d;p?q"},
        {".", "http://a/b/c/"},
        {"./", "http://a/b/c/"},
        {"..", "http://a/b/"},
        {"../", "http://a/b/"},
        {"../g", "http://a/b/g"},
        {"../..", "http://a/"},
        {"../../", "http://a/"},
        {"../../g", "http://a/g"},
        {"../../../g", "http://a/g"},
        {"../../../../g", "http://a/g"},
        {"/./g", "http://a/g"},
        {"/../g", "http://a/g"},
        {"g.", "http://a/b/c/g."},
        {".g", "http://a/b/c/.g"},
        {"g..", "http://a/b/c/g.."},
        {"..g", "http://a/b/c/..g"},
        {"./../g", "http://a/b/g"},
        {"./g/.", "http://a/b/c/g/"},
        {"g/./h", "http://a/b/c/g/h"},
        {"g/../h", "http://a/b/c/h"},
        {"g;x=1/./y", "http://a/b/c/g;x=1/y"},
        {"g;x=1/../y", "http://a/b/c/y"},
        {"g?y/./x", "http://a/b/c/g?y/./x"},
        {"g?y/../x", "http://a/b/c/g?y/../x"},
        {"g#s/./x", "http://a/b/c/g#s/./x"},
        {"g#s/../x", "http://a/b/c/g#s/../x"},
        {"http:g", "http://a/b/c/g"},
        {"HTTP:g", "http://a/b/c/g"},
        {"http:./x", "http://a/b/c/x"},
        {"http:?y", "http://a/b/c/d;p?y"},
        {"http:", "http://a/b/c/d;p?q"},
    }
    for _, row in ipairs(expected) do
        local resolved, reason = base:resolve(row[1])
        assert(resolved, "[" .. row[1] .. "]: " .. tostring(reason))
        test.eq(resolved:tostring(), row[2], "resolve [" .. row[1] .. "]")
    end
end

-- A `with` argument is one component. A scheme holding more than a scheme, or
-- a host holding a port, used to be spliced into the text and reparsed, so the
-- replacement moved the authority.
function M.derivingRefusesTextThatIsNotTheComponent()
    local module = ready()
    local base = assert(module.URI.of("https://example.com/x"))
    for _, scheme in ipairs({"http://evil/", "a:b", "", "1http", "ht tp", "http/"}) do
        test.raises(
            function()
                base:withscheme(scheme)
            end,
            "scheme"
        )
    end
    for _, host in ipairs({"h:1", "evil.example:1", "[::1]:80"}) do
        test.raises(
            function()
                base:withhost(host)
            end,
            "host"
        )
    end
    test.eq(base:withhost("[::1]"):host(), "[::1]")
    test.eq(base:withscheme("HTTP"):tostring(), "http://example.com/x")
    -- A scheme change that would move text into the authority is refused
    -- rather than letting the new parse find a host the old URI did not have.
    local mail = assert(module.URI.of("mailto:evil.example"))
    test.raises(
        function()
            mail:withscheme("http")
        end,
        "scheme"
    )
end

-- The endpoint says where to go and the receiver says what to ask for, which is
-- what reroutes a request through a configured address.
function M.rerootingKeepsThePathQueryAndFragment()
    local module = ready()
    local request = assert(module.URI.of("https://service.example/v1/items?a=1#f"))
    test.eq(
        request:withendpoint(assert(module.URI.of("http://127.0.0.1:8080/prefix"))):tostring(),
        "http://127.0.0.1:8080/prefix/v1/items?a=1#f"
    )
    test.eq(
        request:withendpoint(assert(module.URI.of("http://127.0.0.1:8080/"))):tostring(),
        "http://127.0.0.1:8080/v1/items?a=1#f"
    )
end

function M.portableParserAgreesOnPortableUriComponents()
    local portable = require("nupp.io.uri.whatwg")
    local browser = require("nupp.runtime.browser.uri")
    for _, parser in ipairs({portable, browser}) do
        for _, row in ipairs(PARSED) do
            local parts, reason = parser.parse(row[1])
            assert(parts, tostring(reason))
            test.eq(parts.text, row[2], row[1] .. " portable normalization")
            for _, name in ipairs(COMPONENTS) do
                if row[name] ~= nil then
                    local expected = row[name]
                    if expected == false then
                        expected = nil
                    end
                    test.eq(parts[name], expected, row[1] .. " portable " .. name)
                end
            end
        end
    end
end

-- A percent-encoded dot is a dot: WHATWG lists %2e among the dot segments. The
-- native parser removed `%2e%2e` and the portable one kept it, so a prefix
-- check on the path held on one target and not the other.
function M.encodedDotSegmentsAreRemovedByEveryParser()
    local module = ready()
    local portable = require("nupp.io.uri.whatwg")
    local rows = {
        {"https://ex.com/a/%2e%2e/secret", "/secret"},
        {"https://ex.com/a/%2E%2E/secret", "/secret"},
        {"https://ex.com/a/.%2e/secret", "/secret"},
        {"https://ex.com/a/%2e./secret", "/secret"},
        {"https://ex.com/a/%2e/b", "/a/b"},
        {"https://ex.com/a/b/%2e%2e", "/a/"},
        {"https://ex.com/a/%2e%2e%2e/b", "/a/%2e%2e%2e/b"},
        {"https://ex.com/a/x%2e%2e/b", "/a/x%2e%2e/b"},
        {"https://ex.com/a\\%2e%2e\\secret", "/secret"},
    }
    for _, row in ipairs(rows) do
        local native = assert(module.URI.of(row[1]))
        test.eq(native:path(), row[2], row[1] .. " native path")
        local parts, reason = portable.parse(row[1])
        assert(parts, tostring(reason))
        test.eq(parts.path, row[2], row[1] .. " portable path")
    end
    local page = assert(module.URI.of("https://ex.com/public/index.html"))
    test.eq(assert(page:resolve("%2e%2e/secret")):path(), "/secret")
    test.eq(assert(page:resolve("..\\..\\secret")):path(), "/secret")
end

function M.portableParserRefusesMalformedHosts()
    local portable = require("nupp.io.uri.whatwg")
    for text, reason in pairs({
        ["http://[::::]/"] = "invalid IPv6 address",
        ["http://[1:2:3:4:5:6:7:8:9]/"] = "invalid IPv6 address",
        ["http://[1:2:3:4:5:6:7]/"] = "invalid IPv6 address",
        ["http://[::1.2.3.04]/"] = "invalid IPv6 address",
        ["http://exa%mple.com/x"] = "invalid domain character",
        ["http://exa mple.com/x"] = "invalid domain character",
        ["http://127.0.0.999/x"] = "invalid IPv4 address",
        ["http://1.2.3.4.5/x"] = "invalid IPv4 address",
        ["http://09/x"] = "invalid IPv4 address",
        ["http://0x100000000/x"] = "invalid IPv4 address",
        -- Past 32 bits in decimal too: strtoul saturates there on Windows.
        ["http://4294967296/x"] = "invalid IPv4 address",
        ["file://h:8080/x"] = "invalid domain character",
        ["http://example.com:65536/"] = "invalid port number",
        ["http://example.com/\0suffix"] = "URI contains a NUL byte",
        ["http://example.com/\255"] = "URI is not valid UTF-8",
    }) do
        local value, why = portable.parse(text)
        test.eq(value, nil, text .. " is refused")
        test.eq(why, reason, text .. " explains its refusal")
    end
end

-- The six STDLIB-06 rows. Each provider used to answer them differently; every
-- provider now answers what the URL Standard does.
local STANDARD_ROWS = {
    {"https://ex.com/a/%2e%2e/secret", "https://ex.com/secret", path = "/secret"},
    {
        "https://ex.com/caf\195\169?q=\195\169",
        "https://ex.com/caf%C3%A9?q=%C3%A9",
        path = "/caf%C3%A9",
        query = "q=%C3%A9"
    },
    {"http://user:@h/", "http://user@h/", username = "user", password = false},
    {"http://0x7f.1/", "http://127.0.0.1/", host = "127.0.0.1"},
    {"file://h:8080/x", false},
    {"https://ex.com/a ", "https://ex.com/a", path = "/a"},
}

local function checkStandardRow(label, parts, reason, row)
    if row[2] == false then
        test.eq(parts, nil, label .. " " .. row[1] .. " is refused")
        assert(reason, label .. " " .. row[1] .. " says why")
        return
    end
    assert(parts, label .. " " .. row[1] .. ": " .. tostring(reason))
    test.eq(parts.text, row[2], label .. " " .. row[1])
    for _, name in ipairs(COMPONENTS) do
        if row[name] ~= nil then
            local expected = row[name]
            if expected == false then
                expected = nil
            end
            test.eq(parts[name], expected, label .. " " .. row[1] .. " " .. name)
        end
    end
end

function M.standardRowsAgreeOnEveryProvider()
    ready()
    local native = require("nupp.runtime.provider.nativeuri")
    local portable = require("nupp.io.uri.whatwg")
    for _, row in ipairs(STANDARD_ROWS) do
        local parts, reason = native.parse(row[1])
        checkStandardRow("native", parts, reason, row)
        parts, reason = portable.parse(row[1])
        checkStandardRow("portable", parts, reason, row)
    end
end

-- A special scheme's host that ends in a number is an IPv4 address, in any of
-- the forms the standard reads: fewer than four parts, hexadecimal, octal.
function M.ipv4NumberFormsAreAddresses()
    ready()
    local native = require("nupp.runtime.provider.nativeuri")
    local portable = require("nupp.io.uri.whatwg")
    for text, host in pairs({
        ["http://0x7f.1/"] = "127.0.0.1",
        ["http://127.1/"] = "127.0.0.1",
        ["http://2130706433/"] = "127.0.0.1",
        ["http://0177.0.0.1/"] = "127.0.0.1",
        ["http://127.00.0.1/"] = "127.0.0.1",
        ["http://0x/"] = "0.0.0.0",
        ["http://4294967295/"] = "255.255.255.255",
        ["http://1.2.3./"] = "1.2.0.3",
    }) do
        for label, parser in pairs({native = native, portable = portable}) do
            local parts, reason = parser.parse(text)
            assert(parts, label .. " " .. text .. ": " .. tostring(reason))
            test.eq(parts.host, host, label .. " " .. text)
        end
    end
    -- Only a special scheme's host is a domain, so another scheme keeps it.
    test.eq(assert(portable.parse("foo://0x7f.1/")).host, "0x7f.1")
end

-- The portable parser carries no IDNA tables, so a special-scheme host that
-- needs them is refused with a reason rather than guessed at. A host that is
-- not a domain is only percent-encoded, as the standard says.
function M.portableParserRefusesInternationalHosts()
    ready()
    local native = require("nupp.runtime.provider.nativeuri")
    local portable = require("nupp.io.uri.whatwg")
    for _, text in ipairs({
        "https://caf\195\169.example/",
        "https://%C3%A9.example/",
        "https://xn--caf-dma.example/",
        "https://XN--CAF-DMA.example/",
        "https://www.xn--caf-dma.example/",
    }) do
        local parts, reason = portable.parse(text)
        test.eq(parts, nil, text .. " is refused by the portable parser")
        test.eq(reason, "internationalized host needs a host URL parser", text)
        assert(native.parse(text), text .. " is mapped by the native parser")
    end
    test.eq(assert(portable.parse("foo://\195\177.test/")).host, "%C3%B1.test")
    test.eq(assert(native.parse("foo://\195\177.test/")).host, "%C3%B1.test")
end

-- A page host with its own `URL` is asked, and its canonical text is read back,
-- so the host's IDNA mapping reaches the components.
function M.browserHostUrlIsReadBack()
    local previousHost = rawget(_G, "__nuppBrowser")
    local previousModule = package.loaded["nupp.runtime.browser.uri"]
    local asked = {}
    rawset(_G, "__nuppBrowser", {
        url = function(text)
            asked[#asked + 1] = text
            if text == "https://caf\195\169.example/a b" then
                return {href = "https://xn--caf-dma.example/a%20b"}
            end

            return {error = "Invalid URL"}
        end,
    })
    package.loaded["nupp.runtime.browser.uri"] = nil
    local ok, problem = pcall(function()
        local browser = require("nupp.runtime.browser.uri")
        local parts = assert(browser.parse("https://caf\195\169.example/a b"))
        test.eq(parts.text, "https://xn--caf-dma.example/a%20b")
        test.eq(parts.host, "xn--caf-dma.example")
        test.eq(parts.path, "/a%20b")
        local value, reason = browser.parse("http://[")
        test.eq(value, nil)
        test.eq(reason, "Invalid URL")
        -- What every provider refuses never reaches the host.
        value, reason = browser.parse("http://example.com/\0")
        test.eq(value, nil)
        test.eq(reason, "URI contains a NUL byte")
        test.eq(#asked, 2)
    end)
    rawset(_G, "__nuppBrowser", previousHost)
    package.loaded["nupp.runtime.browser.uri"] = previousModule
    assert(ok, problem)
end

----------------------------------------------------------------------------
-- A seeded corpus, read by every provider
----------------------------------------------------------------------------

local CORPUS_SCHEMES = {"http", "https", "ws", "wss", "ftp", "file", "foo", "mailto", "HTTP", "sc"}
local CORPUS_HOSTS = {
    "example.com",
    "EXAMPLE.com",
    "127.0.0.1",
    "0x7f.1",
    "1.2.3",
    "017.1",
    "[::1]",
    "[1:0:0:2:0:0:0:3]",
    "[::ffff:1.2.3.4]",
    "a_b.test",
    "h%41.test",
    "",
    "u@h",
    "u:p@h",
    "u:@h",
    "h:8080",
    "h:80",
    "h:",
    "a%2eb",
    "h.",
    "1.2.3.4.5",
}
local CORPUS_PIECES = {
    "a",
    "b",
    "/",
    "/",
    "\\",
    ".",
    "..",
    "%2e",
    "%2E%2e",
    "%",
    "%41",
    "?",
    "#",
    "@",
    ":",
    "[",
    "]",
    "'",
    '"',
    "<",
    ">",
    "`",
    "{",
    "}",
    "~",
    "&",
    "=",
    ";",
    ",",
    "!",
    "$",
    "\t",
    "C:",
    "//",
    "x y",
}

local function corpus(seed, count)
    local state = seed

    local function pick(n)
        -- The product stays below 2^53, so LuaJIT and the VM draw the same rows.
        state = (state * 48271 + 12345) % 2147483647
        return state % n + 1
    end

    local texts = {}
    for index = 1, count do
        local parts = {CORPUS_SCHEMES[pick(#CORPUS_SCHEMES)], ":"}
        local shape = pick(4)
        if shape <= 2 then
            parts[#parts + 1] = "//" .. CORPUS_HOSTS[pick(#CORPUS_HOSTS)]
        elseif shape == 3 then
            parts[#parts + 1] = "/"
        end
        for _ = 1, pick(8) - 1 do
            parts[#parts + 1] = CORPUS_PIECES[pick(#CORPUS_PIECES)]
        end
        texts[index] = table.concat(parts)
    end

    return texts
end

-- What a browser's own `URL` answers for each text, or nil where node, whose
-- URL follows the same standard, is not installed.
local function hostHrefs(texts, bases)
    local probe = io.popen("node --version 2>/dev/null")
    local version = probe and probe:read("*a") or ""
    if probe then
        probe:close()
    end
    if not version:match("^v%d") then
        return nil
    end
    local json = require("serde.json")
    local path = root .. "/corpus.json"
    local file = assert(io.open(path, "wb"))
    file:write(json.encodevalue({texts = texts, bases = bases or json.EMPTY_ARRAY}))
    file:close()
    local script = [[
const {texts, bases} = JSON.parse(require('fs').readFileSync(process.argv[2], 'utf8'));
process.stdout.write(JSON.stringify(texts.map((text, index) => {
  try { return new URL(text, bases[index]).href; } catch (error) { return null; }
})));
]]
    local scriptPath = root .. "/corpus.cjs"
    file = assert(io.open(scriptPath, "wb"))
    file:write(script)
    file:close()
    local node = assert(io.popen("node '" .. scriptPath .. "' '" .. path .. "'"))
    local answer = node:read("*a")
    node:close()
    local hrefs = json.decodevalue(answer, json.NULL)
    for index = 1, #texts do
        if hrefs[index] == json.NULL then
            hrefs[index] = false
        end
    end

    return hrefs
end

function M.portableFilePathsPreserveRepeatedLeadingSlashes()
    local portable = require("nupp.io.uri.whatwg")
    local firstText = 'file:////@//">]'
    local first = assert(portable.parse(firstText))
    test.eq(first.text, "file:////@//%22%3E]")
    test.eq(first.path, "//@//%22%3E]")

    local reference = "//%2E%2e//" .. string.char(9) .. "{?:"
    local baseText = "file:///C:/dir/file"
    local second = assert(portable.parse(reference, assert(portable.parse(baseText))))
    test.eq(second.text, "file://..//%7B?:")
    test.eq(second.path, "//%7B")

    local firstHost = hostHrefs({firstText})
    local secondHost = hostHrefs({reference}, {baseText})
    if firstHost ~= nil and secondHost ~= nil then
        test.eq(first.text, firstHost[1])
        test.eq(second.text, secondHost[1])
    end
end

-- Exact frozen-provider differences. Node agrees with the portable parser.
local FROZEN_PROVIDER_CASES = {
    {
        kind = "corpus",
        input = "file://h.b\\/<!\\",
        base = false,
        native = "file://h.b/%3C!/",
        portable = "file://h.b//%3C!/"
    },
    {kind = "corpus", input = "file://h.///<", base = false, native = "file://h./%3C", portable = "file://h.///%3C"},
    {kind = "corpus", input = "file:/%2e//%2e", base = false, native = "file:///", portable = "file:////"},
    {
        kind = "corpus",
        input = "file:///\\///}%2e",
        base = false,
        native = "file:///%7D%2e",
        portable = "file:///////%7D%2e"
    },
    {kind = "corpus", input = "sc://u@h%2eC:\9\\~<'", base = false, native = "sc://u@h%2eC/\\~%3C'", portable = false},
    {kind = "corpus", input = "file:////", base = false, native = "file:///", portable = "file:////"},
    {
        kind = "corpus",
        input = "file://a_b.test%2E%2e},'///;",
        base = false,
        native = "file://a_b.test..},'/;",
        portable = "file://a_b.test..},'///;"
    },
    {
        kind = "corpus",
        input = "file:/.//\"~ax y",
        base = false,
        native = "file:///%22~ax%20y",
        portable = "file:////%22~ax%20y"
    },
    {
        kind = "reference",
        input = "//127.0.0.1'//",
        base = "file:///C:/dir/file",
        native = "file://127.0.0.1'/",
        portable = "file://127.0.0.1'//"
    },
    {
        kind = "reference",
        input = "//017.1//",
        base = "file:///C:/dir/file",
        native = "file://15.0.0.1/",
        portable = "file://15.0.0.1//"
    },
    {
        kind = "reference",
        input = "//1.2.3///",
        base = "file:///C:/dir/file",
        native = "file://1.2.0.3/",
        portable = "file://1.2.0.3///"
    },
    {
        kind = "reference",
        input = "//a%2eb{//\9",
        base = "file:///C:/dir/file",
        native = "file://a.b{/",
        portable = "file://a.b{//"
    },
    {
        kind = "reference",
        input = "//a%2eb/%2E%2e/\\[,\"",
        base = "file:///C:/dir/file",
        native = "file://a.b/[,%22",
        portable = "file://a.b//[,%22"
    },
}

local function frozenProviderCase(kind, input, base)
    for _, case in ipairs(FROZEN_PROVIDER_CASES) do
        if case.kind == kind and case.input == input and case.base == base then
            return case
        end
    end

    return nil
end

function M.seededCorpusAgreesAcrossProviders()
    ready()
    local native = require("nupp.runtime.provider.nativeuri")
    local portable = require("nupp.io.uri.whatwg")
    local texts = corpus(20260929, 3000)
    local hrefs = hostHrefs(texts)
    local refusedInternational = 0
    local frozenCount = 0
    for index, text in ipairs(texts) do
        local expected, expectedReason = native.parse(text)
        local found, reason = portable.parse(text)
        local frozen = frozenProviderCase("corpus", text, false)
        local unavailable = found == nil and reason == "internationalized host needs a host URL parser"
        if frozen then
            frozenCount = frozenCount + 1
            test.eq(expected and expected.text or false, frozen.native, ("%q frozen native"):format(text))
            test.eq(found and found.text or false, frozen.portable, ("%q frozen portable"):format(text))
        elseif unavailable then
            refusedInternational = refusedInternational + 1
        else
            test.eq(found and found.text, expected and expected.text, ("%q portable text"):format(text))
            if expected and found then
                for _, name in ipairs(COMPONENTS) do
                    test.eq(found[name], expected[name], ("%q portable %s"):format(text, name))
                end
            end
            test.eq(found == nil, expected == nil, ("%q acceptance: %s"):format(text, tostring(expectedReason)))
        end
        if hrefs ~= nil and not unavailable then
            test.eq(found and found.text or false, hrefs[index], ("%q portable host URL"):format(text))
        end
    end
    test.eq(frozenCount, 8)
    assert(refusedInternational < 30, "the corpus is mostly ASCII hosts")
    if hrefs == nil then
        error("skip: node is not installed, so the host URL leg did not run", 0)
    end
end

-- Resolution is the standard's parser with a base on every provider, so the
-- portable reading of a reference agrees with a browser's.
function M.seededReferencesResolveAsTheHostDoes()
    local module = ready()
    local portable = require("nupp.io.uri.whatwg")
    local bases = {
        "http://a/b/c/d;p?q",
        "https://example.com/docs/guide/",
        "file:///C:/dir/file",
        "foo://host/a/b",
        "foo:/a/b",
        "mailto:x@y",
    }
    local references = corpus(424242, 1500)
    local extra = {"g", "../g", "//g", "\\\\g\\h", "?y", "#s", "", "..", "/./g", "http:g", "foo:g", "C|/x", "..\\x"}
    for _, value in ipairs(extra) do
        references[#references + 1] = value
    end
    local texts, baseTexts = {}, {}
    for index, reference in ipairs(references) do
        -- Relative references are what resolution is for, so the scheme is
        -- dropped from most of the corpus.
        texts[index] = index % 3 == 0 and reference or (reference:gsub("^[%a]+:", "", 1))
        baseTexts[index] = bases[(index % #bases) + 1]
    end
    local hrefs = hostHrefs(texts, baseTexts)
    local frozenCount = 0
    for index, text in ipairs(texts) do
        local base = assert(module.URI.of(baseTexts[index]))
        local resolved = base:resolve(text)
        local parts = portable.parse(text, assert(portable.parse(baseTexts[index])))
        local label = ("%q against %s"):format(text, baseTexts[index])
        local frozen = frozenProviderCase("reference", text, baseTexts[index])
        local portableUnavailable = parts == nil and resolved ~= nil and text:find("[\128-\255]")
        if frozen then
            frozenCount = frozenCount + 1
            test.eq(resolved and resolved:tostring() or false, frozen.native, label .. " frozen native")
            test.eq(parts and parts.text or false, frozen.portable, label .. " frozen portable")
        elseif not portableUnavailable then
            test.eq(parts and parts.text, resolved and resolved:tostring(), label .. " portable")
        end
        if hrefs ~= nil and not portableUnavailable then
            test.eq(parts and parts.text or false, hrefs[index], label .. " portable host URL")
        end
    end
    test.eq(frozenCount, 5)
    if hrefs == nil then
        error("skip: node is not installed, so the host URL leg did not run", 0)
    end
end

return M
