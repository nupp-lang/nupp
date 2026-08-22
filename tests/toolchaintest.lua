-- `scripts/toolchain` is what a clean machine runs before anything else works,
-- so what is checked here is the part that has to be right before a compiler is
-- ever invoked: that the pins say what the host build says, that a digest which
-- does not match stops the build, and that the cache is keyed by the toolchain
-- rather than shared across compilers.
--
-- Nothing here compiles anything. Building LuaJIT takes half a minute and proves
-- something the whole suite proves by running at all.

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local pipe = assert(io.popen("pwd"))
   HERE = pipe:read("*l") .. "/" .. HERE
   pipe:close()
end
local ROOT = HERE .. "/.."
local DRIVER = ROOT .. "/scripts/toolchain"

local M = {}

local function quote(value)
   return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function read(path)
   local file = assert(io.open(path, "rb"), path .. " is missing")
   local text = file:read("*a")
   file:close()
   return text
end

local function write(path, text)
   local file = assert(io.open(path, "wb"))
   file:write(text)
   file:close()
end

local function temporary()
   local path = os.tmpname()
   os.remove(path)
   assert(os.execute("mkdir -p " .. quote(path)) == 0)
   return path
end

--- Runs the driver with an environment, returning its exit status and output.
local function run(environment, arguments)
   local prefix = {}
   for name, value in pairs(environment) do
      prefix[#prefix + 1] = name .. "=" .. quote(value)
   end
   table.sort(prefix)
   local command = ("env %s %s %s 2>&1; echo \"__exit__:$?\""):format(
      table.concat(prefix, " "), quote(DRIVER), arguments)
   local pipe = assert(io.popen(command))
   local output = pipe:read("*a")
   pipe:close()
   local status = tonumber(output:match("__exit__:(%d+)%s*$"))
   return status, (output:gsub("__exit__:%d+%s*$", ""))
end

local function pins()
   local text = read(ROOT .. "/scripts/toolchain.pins")
   local values = {}
   for name, value in text:gmatch("\n([A-Z0-9_]+)=([^\n]*)") do
      values[name] = (value:gsub("^'", ""):gsub("'$", ""))
   end
   return values
end

--- A compiler that answers `--version` and nothing else, for the cache key.
local function fakeCompiler(directory, name, version)
   local path = directory .. "/" .. name
   write(path, "#!/bin/sh\nprintf '%s\\n' " .. quote(version) .. "\n")
   assert(os.execute("chmod +x " .. quote(path)) == 0)
   return path
end

-- Every pinned source has a version and a digest, and the digest is what the
-- driver refuses a mismatch against. A pin with one and not the other would be
-- fetched and compiled without anything checking what arrived.
function M.everyPinHasAVersionAndADigest()
   local recorded = pins()
   for _, component in ipairs({
      "LUAJIT", "LPEG", "LUAUTF8", "SIMDJSON", "CURL", "MBEDTLS",
   }) do
      local marker = component == "LUAJIT" and "REV" or "VERSION"
      assert(recorded[component .. "_" .. marker],
         component .. " has no version or revision")
      local digest = recorded[component .. "_SHA256"]
      assert(digest and #digest == 64,
         component .. " has no SHA-256, or one that is not 64 characters")
      assert(digest:match("^%x+$"), component .. "'s digest is not hexadecimal")
   end
end

-- Each of these is redistributed under a licence that asks its notice to travel
-- along, and the driver refuses to build a source whose notice has drifted. A
-- pin for which no notice exists would make that check unreachable.
function M.everyPinnedSourceHasANotice()
   for _, notice in ipairs({
      "LuaJIT-COPYRIGHT.txt", "LPeg-LICENSE.txt", "luautf8-LICENSE.txt",
      "simdjson-LICENSE.txt", "curl-COPYING.txt", "mbedtls-LICENSE.txt",
   }) do
      assert(io.open(ROOT .. "/host/notices/" .. notice, "rb"),
         "host/notices/" .. notice .. " is missing")
   end
end

-- A mirror that served something else is refused rather than compiled, and the
-- message says both digests so the reader can tell a stale pin from a bad
-- download.
function M.aWrongDigestRefusesToBuild()
   local directory = temporary()
   local archives = directory .. "/archives"
   assert(os.execute("mkdir -p " .. quote(archives)) == 0)
   local revision = pins().LUAJIT_REV
   write(archives .. "/LuaJIT-" .. revision .. ".tar.gz", "not an archive")

   local status, output = run({
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      NUPP_HOST_SOURCE_DIR = archives,
      PATH = os.getenv("PATH"),
   }, "luajit")

   assert(status ~= 0, "a mismatched digest built anyway:\n" .. output)
   assert(output:find("expected " .. pins().LUAJIT_SHA256, 1, true),
      "the refusal does not say what was expected:\n" .. output)
end

-- Offline says which directory to put the archive in, because a builder with no
-- network has no way to discover that from a failed download.
function M.offlineNamesTheDirectoryToSupply()
   local directory = temporary()
   local status, output = run({
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      NUPP_HOST_SOURCE_DIR = directory .. "/empty",
      NUPP_HOST_OFFLINE = "1",
      PATH = os.getenv("PATH"),
   }, "luajit")

   assert(status ~= 0, "an offline build with no archive succeeded:\n" .. output)
   assert(output:find("NUPP_HOST_SOURCE_DIR", 1, true),
      "the refusal does not say where to put the archive:\n" .. output)
end

-- Two compilers are two answers. A cache that ignored which one asked would hand
-- a GCC build back to a Clang one, and the failure would be a link error a long
-- way from the cause.
function M.thePrefixFollowsTheToolchain()
   local directory = temporary()
   local first = fakeCompiler(directory, "first-cc", "one")
   local second = fakeCompiler(directory, "second-cc", "two")
   local environment = {
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      PATH = os.getenv("PATH"),
   }

   environment.NUPP_CC = first
   environment.NUPP_CXX = first
   local status, one = run(environment, "--prefix")
   assert(status == 0, one)

   environment.NUPP_CC = second
   environment.NUPP_CXX = second
   local againStatus, two = run(environment, "--prefix")
   assert(againStatus == 0, two)

   assert(one ~= two, "two compilers shared one prefix: " .. one)
   assert(one:find(directory, 1, true) and two:find(directory, 1, true),
      "the prefix ignored NUPP_TOOLCHAIN_DIR: " .. one .. " and " .. two)

   environment.NUPP_CC = first
   environment.NUPP_CXX = first
   local repeatStatus, again = run(environment, "--prefix")
   assert(repeatStatus == 0, again)
   assert(again == one, "the same toolchain answered two prefixes")
end

-- `NUPP_NATIVE_CC` and `NUPP_JSON_CC` named the C and the C++ compiler when each
-- build step chose its own. They keep working, and the primary names win.
function M.theOldCompilerNamesStillSelect()
   local directory = temporary()
   local named = fakeCompiler(directory, "named-cc", "named")
   local aliased = fakeCompiler(directory, "aliased-cc", "aliased")
   local environment = {
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      PATH = os.getenv("PATH"),
      NUPP_NATIVE_CC = aliased,
      NUPP_JSON_CC = aliased,
   }

   local status, viaAlias = run(environment, "--prefix")
   assert(status == 0, viaAlias)

   environment.NUPP_CC = named
   environment.NUPP_CXX = named
   local primaryStatus, viaPrimary = run(environment, "--prefix")
   assert(primaryStatus == 0, viaPrimary)

   assert(viaAlias ~= viaPrimary,
      "the primary names did not win over the aliases: " .. viaAlias)
end

return M
