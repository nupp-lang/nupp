-- `nupp.io.uri` through the real provider.
--
-- What is checked here is one table of URIs and one table of derivations, both
-- recorded from the implementation this replaced. A URI library's whole job is
-- to agree with everybody else about what a piece of text names, so the useful
-- test is not that each function does something reasonable but that the answers
-- have not moved.
--
-- The launcher's provider is reused when available, and otherwise one is built
-- for the suite, reached the way a generated program reaches it.
local test = require("assert")
local stdlib = require("nupp.compiler.stdlib")
local nativeStage = require("nupp.compiler.build.native")

local M = {}

local uri, previous, root
local unavailable

local function temporaryRoot()
   local base = os.getenv("TMPDIR") or os.getenv("TEMP") or "/tmp"
   base = base:gsub("\\", "/")
   return (base:gsub("/$", "")) .. "/nupp-uri-test-" .. tostring(os.time())
      .. "-" .. tostring(math.random(1, 1e9))
end

function M.beforeAll()
   math.randomseed(os.time())
   root = temporaryRoot()
   os.execute("mkdir -p '" .. root .. "'")
   local libraryPath = os.getenv("NUPP_NATIVE_LIBRARY")
   if not libraryPath then
      local staged, problem = nativeStage.build(root, "out", {["native.uri"] = true})
      if not staged then
         unavailable = tostring(problem)
         return
      end
      libraryPath = root .. "/out/lib/nupp_native"
   end
   local library = ("%q"):format(libraryPath)
   local source = stdlib.bootstrap({
      ["native.uri"] = true, ["stdlib.io"] = true,
   }):gsub('os%.getenv%("NUPP_NATIVE_LIBRARY"%)', function() return library end)
   previous = rawget(_G, "nupp")
   _G.nupp = nil
   assert(loadstring(source))()
   uri = require("nupp.io.uri")
end

function M.afterAll()
   if previous ~= nil or rawget(_G, "nupp") ~= nil then
      _G.nupp = previous
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
   {"https://EXAMPLE.com/a/../b?q=1", "https://example.com/b?q=1",
      scheme = "https", authority = "example.com", username = "",
      password = false, host = "example.com", port = false, path = "/b",
      query = "q=1", fragment = false},
   {"https://user:pass@example.com:8443/api?q=1#top",
      "https://user:pass@example.com:8443/api?q=1#top",
      scheme = "https", authority = "user:pass@example.com:8443",
      username = "user", password = "pass", host = "example.com", port = 8443,
      path = "/api", query = "q=1", fragment = "top"},
   -- A special scheme has a mandatory host, a default port that is not written
   -- down, and a path that is `/` when the text gave none.
   {"http://example.com", "http://example.com/",
      scheme = "http", authority = "example.com", username = "",
      password = false, host = "example.com", port = false, path = "/",
      query = false, fragment = false},
   {"http://example.com:80/x", "http://example.com/x", port = false},
   {"https://example.com:443/x", "https://example.com/x", port = false},
   {"HTTPS://Example.COM", "https://example.com/", host = "example.com"},
   -- Without an authority the rest is opaque: no host, and nothing normalized
   -- away, because the scheme is what knows what those characters mean.
   {"mailto:someone@example.com", "mailto:someone@example.com",
      scheme = "mailto", authority = false, username = "", password = false,
      host = false, port = false, path = "someone@example.com",
      query = false, fragment = false},
   {"urn:isbn:0451450523", "urn:isbn:0451450523", path = "isbn:0451450523"},
   {"data:text/plain,hello", "data:text/plain,hello", path = "text/plain,hello"},
   -- An authority that is present and empty names no host, which is what a
   -- local file URL is.
   {"file:///tmp/x", "file:///tmp/x",
      authority = "", host = false, path = "/tmp/x"},
   {"ftp://ftp.example.com/pub/", "ftp://ftp.example.com/pub/", port = false},
   -- Any other scheme with an authority keeps its host's case, and its path is
   -- still a hierarchy: `.` and `..` resolve, and an empty segment stays.
   {"custom://Host.Example/a//b/./c/../d", "custom://Host.Example/a//b/d",
      host = "Host.Example", path = "/a//b/d"},
   -- Text that is already encoded stays as it was written, and text that has to
   -- be encoded is.
   {"https://example.com/%7euser/a b", "https://example.com/%7euser/a%20b",
      path = "/%7euser/a%20b"},
   -- An empty query and no query are different URIs.
   {"http://example.com/?#", "http://example.com/?#",
      query = "", fragment = ""},
   {"https://[::1]:8080/x", "https://[::1]:8080/x",
      authority = "[::1]:8080", host = "[::1]", port = 8080},
   {"http://user@example.com", "http://user@example.com/",
      username = "user", password = false},
   {"https://example.com/a?b=1&c=2#frag", "https://example.com/a?b=1&c=2#frag",
      query = "b=1&c=2", fragment = "frag"},
}

local COMPONENTS = {
   "scheme", "authority", "username", "password", "host", "port", "path",
   "query", "fragment",
}

function M.parsingAnswersTheRecordedComponents()
   local module = ready()
   for _, row in ipairs(PARSED) do
      local value, reason = module.newURI(row[1])
      assert(value, row[1] .. ": " .. tostring(reason))
      test.equal(value:toString(), row[2], row[1] .. " normalizes")
      for _, name in ipairs(COMPONENTS) do
         local wanted = row[name]
         if wanted ~= nil then
            local found = value[name](value)
            if wanted == false then
               test.equal(found, nil, row[1] .. " has no " .. name)
            else
               test.equal(found, wanted, row[1] .. " " .. name)
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
      local value, why = module.newURI(text)
      test.equal(value, nil, "[" .. text .. "] does not parse")
      test.equal(why, reason, "[" .. text .. "] says why")
   end
end

function M.derivingReplacesOneComponentAtATime()
   local module = ready()
   local base = assert(module.newURI(
      "https://user:pass@example.com:8443/api/v1?q=1#top"))

   test.equal(base:withScheme("http"):toString(),
      "http://user:pass@example.com:8443/api/v1?q=1#top")
   test.equal(base:withUserInfo(nil):toString(),
      "https://example.com:8443/api/v1?q=1#top")
   test.equal(base:withUserInfo("u"):toString(),
      "https://u@example.com:8443/api/v1?q=1#top")
   test.equal(base:withUserInfo("u:p"):toString(),
      "https://u:p@example.com:8443/api/v1?q=1#top")
   test.equal(base:withHost("other.example"):toString(),
      "https://user:pass@other.example:8443/api/v1?q=1#top")
   test.equal(base:withPort(99):toString(),
      "https://user:pass@example.com:99/api/v1?q=1#top")
   test.equal(base:withPort(nil):toString(),
      "https://user:pass@example.com/api/v1?q=1#top")
   test.equal(base:withPath("/x"):toString(),
      "https://user:pass@example.com:8443/x?q=1#top")
   -- A path is a hierarchy under an authority, so one written without a leading
   -- separator gets one rather than running into the host.
   test.equal(base:withPath("x/y"):toString(),
      "https://user:pass@example.com:8443/x/y?q=1#top")
   test.equal(base:withPath(""):toString(),
      "https://user:pass@example.com:8443/?q=1#top")
   test.equal(base:withQuery(nil):toString(),
      "https://user:pass@example.com:8443/api/v1#top")
   test.equal(base:withQuery("a=b"):toString(),
      "https://user:pass@example.com:8443/api/v1?a=b#top")
   test.equal(base:withFragment(nil):toString(),
      "https://user:pass@example.com:8443/api/v1?q=1")
   test.equal(base:withFragment("z"):toString(),
      "https://user:pass@example.com:8443/api/v1?q=1#z")

   -- The original is untouched by all of it.
   test.equal(base:toString(), "https://user:pass@example.com:8443/api/v1?q=1#top")

   local raised = select(2, pcall(function() return base:withPort(70000) end))
   assert(tostring(raised):find("0 through 65535", 1, true),
      "a port outside the range raises: " .. tostring(raised))
end

-- One separator between the two, whichever of them wrote it.
function M.concatenatingAPathAddsOneSeparator()
   local module = ready()
   local plain = assert(module.newURI("https://api.example.com/v1"))
   local slashed = assert(module.newURI("https://api.example.com/v1/"))
   test.equal(plain:concatPath("users"):path(), "/v1/users")
   test.equal(plain:concatPath("/users"):path(), "/v1/users")
   test.equal(slashed:concatPath("users"):path(), "/v1/users")
   test.equal(slashed:concatPath("/users"):path(), "/v1/users")
end

function M.resolvingFollowsTheReferenceRules()
   local module = ready()
   local page = assert(module.newURI("https://example.com/docs/guide/index.html"))
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
      test.equal(resolved:toString(), row[2], "resolve [" .. row[1] .. "]")
   end
end

-- The endpoint says where to go and the receiver says what to ask for, which is
-- what reroutes a request through a configured address.
function M.rerootingKeepsThePathQueryAndFragment()
   local module = ready()
   local request = assert(module.newURI("https://service.example/v1/items?a=1#f"))
   test.equal(
      request:withEndpoint(assert(module.newURI("http://127.0.0.1:8080/prefix"))):toString(),
      "http://127.0.0.1:8080/prefix/v1/items?a=1#f")
   test.equal(
      request:withEndpoint(assert(module.newURI("http://127.0.0.1:8080/"))):toString(),
      "http://127.0.0.1:8080/v1/items?a=1#f")
end

return M
