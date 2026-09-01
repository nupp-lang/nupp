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

--- A directory as it can be spelled inside a colon-separated PATH.
---
--- A native Windows path cannot go in one: the shell splits `C:/x` into `C` and
--- `/x`, so the directory is never searched and whatever it was meant to shadow
--- wins instead. Which is what this suite is about, and what it was quietly
--- doing to itself -- the fake `cygpath` went unfound and the real one answered.
---
--- Rewritten here rather than asked of `cygpath`, in either process. Two
--- attempts went through one: this process is native on Windows and resolves a
--- different `cygpath` than the shell, and a command substitution in the shell
--- silently produced nothing, which emptied the entry and let the real
--- `cygpath` answer for the fake -- the failure both attempts were meant to fix,
--- reported identically each time.
---
--- A drive path has one spelling in a mount table that Git Bash gives `/c` for,
--- and these are temporary directories under it. Doing it by hand needs nothing
--- to be installed and answers the same on a machine with no `cygpath` at all.
local function forPath(directory)
   if package.config:sub(1, 1) ~= "\\" then
      return directory
   end
   local drive, rest = directory:match("^([A-Za-z]):(/.*)$")
   if drive == nil then
      return directory
   end

   return "/" .. drive:lower() .. rest
end

local function temporary()
   local path = os.tmpname()
   os.remove(path)
   assert(os.execute("mkdir -p " .. quote(path)) == 0)
   return path
end

--- Runs the driver with an environment, returning its exit status and output.
-- `PATH` is written for the shell to expand rather than quoted flat, so a value
-- can say `$PATH` and mean the one the shell already has. Lua's idea of it is
-- not usable here: on Windows this process is native, so `os.getenv("PATH")`
-- answers the semicolon-separated Windows spelling, and joining that with `:`
-- for a Git Bash command produced entries like `C` and `\Windows;C`. The shell
-- then had no `/usr/bin`, and the driver died on `dirname` before doing
-- anything this suite meant to test.
local function run(environment, arguments)
   local prefix = {}
   for name, value in pairs(environment) do
      if name == "PATH" then
         prefix[#prefix + 1] = name .. '="' .. value .. '"'
      else
         prefix[#prefix + 1] = name .. "=" .. quote(value)
      end
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

local function fakeWindowsUname(directory)
   local path = directory .. "/uname"
   write(path, [[#!/bin/sh
if [ "$1" = "-m" ]; then
   printf '%s\n' x86_64
else
   printf '%s\n' MINGW64_NT
fi
]])
   assert(os.execute("chmod +x " .. quote(path)) == 0)
end

local function fakeCygpath(directory)
   local path = directory .. "/cygpath"
   write(path, [[#!/bin/sh
case "$1" in
   -m) printf 'C:%s\n' "$2" ;;
   -u) printf '%s\n' "$NUPP_TEST_CYGPATH_U" ;;
   *) exit 2 ;;
esac
]])
   assert(os.execute("chmod +x " .. quote(path)) == 0)
end

-- Every pinned source has a version and a digest, and the digest is what the
-- driver refuses a mismatch against. A pin with one and not the other would be
-- fetched and compiled without anything checking what arrived.
function M.everyPinHasAVersionAndADigest()
   local recorded = pins()
   for _, component in ipairs({
      "LUAJIT", "LUAROCKS", "LPEG", "LUAUTF8", "MBEDTLS", "LIBUV",
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
      "mbedtls-LICENSE.txt", "libuv-LICENSE.txt",
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
      PATH = "$PATH",
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
      PATH = "$PATH",
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
      PATH = "$PATH",
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

-- Feature validation belongs to the driver's status, not merely its text. A
-- failing `provider_sources` once ran inside the expansion of a `for` loop, so
-- it exited only that subshell; the parent compiled the partial source list and
-- returned a provider path with success.
function M.anUnknownNativeFeatureStopsTheDriver()
   local directory = temporary()
   local compiler = fakeCompiler(directory, "fake-cc", "fake")
   local status, output = run({
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      NUPP_CC = compiler,
      NUPP_CXX = compiler,
      PATH = "$PATH",
   }, "native files,bogus")

   assert(status ~= 0, "an unknown native feature returned success:\n" .. output)
   assert(output:find("unknown native feature bogus", 1, true),
      "the refusal does not name the unknown feature:\n" .. output)
end

function M.migratedRustFeaturesAreNotBuildableInLegacyC()
   local directory = temporary()
   local compiler = fakeCompiler(directory, "fake-cc", "fake")
   for _, feature in ipairs({"gpu", "http", "uri", "uuid"}) do
      local status, output = run({
         NUPP_TOOLCHAIN_DIR = directory .. "/cache",
         NUPP_CC = compiler,
         NUPP_CXX = compiler,
         PATH = "$PATH",
      }, "native " .. feature)

      assert(status ~= 0,
         "the removed C " .. feature .. " provider returned success:\n" .. output)
      assert(output:find("unknown native feature " .. feature, 1, true),
         "the refusal does not establish the Rust-only provider boundary:\n" .. output)
   end
end

-- The fallback exists for installations where rustup itself is on PATH but
-- its Cargo and rustc proxies are not. `stable` moves, so an installed exact
-- channel gets first refusal. A stable alias which still names the exact
-- version remains usable, and the version check below refuses it after it moves.
function M.rustupFallbackSelectsThePinnedToolchain()
   local driver = read(ROOT .. "/scripts/toolchain")
   assert(driver:find('RUSTUP_TOOLCHAIN="$expected"', 1, true),
      "the rustup fallback does not try rust-toolchain.toml's exact channel")
   local exact = assert(driver:find('RUSTUP_TOOLCHAIN="$expected"', 1, true))
   local stable = assert(driver:find("RUSTUP_TOOLCHAIN=stable", exact, true))
   assert(exact < stable, "the moving stable alias is tried before the exact channel")
end

-- Cargo gives a macOS cdylib an absolute install name beneath target-dir by
-- default. The Rust provider's target directory is a content cache; recording
-- it would make a linked consumer reach back into that cache after the dylib
-- had been staged or packaged elsewhere.
function M.macOSRustProviderUsesARelocatableInstallName()
   local driver = read(ROOT .. "/scripts/toolchain")
   assert(driver:find("[ \"$PLATFORM\" = darwin ] && cargo_action=rustc", 1, true),
      "the macOS Rust provider is not built through cargo rustc")
   assert(driver:find("-install_name,@rpath/$filename", 1, true),
      "the macOS Rust provider records its content-cache path")
end

-- The dependency builds use GNU make. Windows' hosted clang targets MSVC, so
-- LuaJIT's makefile asks it to link Unix spellings such as `-lm` as MSVC
-- libraries and the cold bootstrap stops. MinGW GCC is the compatible default;
-- explicitly naming clang still remains the caller's choice.
function M.windowsDefaultsToTheGnuCompilerPair()
   local directory = temporary()
   fakeWindowsUname(directory)
   fakeCygpath(directory)
   fakeCompiler(directory, "gcc", "gnu-c")
   fakeCompiler(directory, "g++", "gnu-cxx")
   fakeCompiler(directory, "clang", "msvc-c")
   fakeCompiler(directory, "clang++", "msvc-cxx")
   local environment = {
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      PATH = forPath(directory) .. ":$PATH",
   }

   local status, automatic = run(environment, "--prefix")
   assert(status == 0, automatic)

   environment.NUPP_CC = "gcc"
   environment.NUPP_CXX = "g++"
   local gnuStatus, gnu = run(environment, "--prefix")
   assert(gnuStatus == 0, gnu)
   assert(automatic == gnu, "Windows did not select the MinGW compiler pair")

   environment.NUPP_CC = "clang"
   environment.NUPP_CXX = "clang++"
   local clangStatus, msvc = run(environment, "--prefix")
   assert(clangStatus == 0, msvc)
   assert(automatic ~= msvc, "Windows selected the MSVC-targeting clang pair")
end

-- The host runtime uses pthread ownership checks on every platform. MinGW GCC
-- links its runtime implicitly, while llvm-mingw's Clang requires the archive
-- to be named. Both the ordinary host linker and the relocatable pack linker
-- must carry it, or release-pack construction and installed standalone builds
-- fail at different stages with the same unresolved pthread symbols.
function M.windowsHostLinkersCarryPthread()
   local driver = read(ROOT .. "/scripts/toolchain")
   local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
   assert(driver:match('windows%)%s+platform_libraries="%-lpthread '),
      "the Windows host build does not link pthread")
   assert(driver:match('windows%)%s+set %-%- "?%$@"? %-lpthread '),
      "the Windows application host linker does not link pthread")
   assert(packLinker:match('#ifdef _WIN32%s+append%(&cursor, "%-lpthread"%);'),
      "the Windows compiler-pack host linker does not link pthread")
end

-- Native TLS reads the Windows ROOT stores through CryptoAPI. Every route that
-- links a host must therefore carry crypt32: the ordinary host, an installed
-- compiler pack's application host, and the relocatable pack linker.
function M.windowsHostLinkersCarryCryptoApi()
   local driver = read(ROOT .. "/scripts/toolchain")
   local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
   local _, ordinary = driver:gsub("%-lcrypt32", "")
   assert(ordinary >= 4,
      "not every Windows toolchain linker carries crypt32")
   assert(packLinker:match('append%(&cursor, "%-lcrypt32"%);'),
      "the Windows compiler-pack host linker does not link crypt32")
end

-- The same host routes carry the two macOS frameworks used to copy the
-- platform's trust anchors into mbedTLS.
function M.macOSHostLinkersCarryTheSecurityFramework()
   local driver = read(ROOT .. "/scripts/toolchain")
   local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
   local _, security = driver:gsub("%-framework Security", "")
   local _, foundation = driver:gsub("%-framework CoreFoundation", "")
   assert(security >= 4 and foundation >= 4,
      "not every macOS toolchain linker carries the trust-store frameworks")
   assert(packLinker:match('append%(&cursor, "Security"%);'),
      "the macOS compiler-pack host linker does not link Security.framework")
   assert(packLinker:match('append%(&cursor, "CoreFoundation"%);'),
      "the macOS compiler-pack host linker does not link CoreFoundation")
end

-- Rust provider exports are reached by name through LuaJIT FFI, so the native
-- linker sees no relocation that would pull their object files from an archive.
-- Every static-host route must both carry the selected archive and force-load
-- it, including the relocatable compiler pack used by installed builds.
function M.staticHostsForceLoadTheRustProvider()
   local driver = read(ROOT .. "/scripts/toolchain")
   local packer = read(ROOT .. "/scripts/compiler-pack")
   local packLinker = read(ROOT .. "/scripts/compiler-pack-link.c")
   assert(driver:find('cp "$rust_base" "$out/libnupp_native_v2.a"', 1, true),
      "a compiler-pack host does not retain its selected Rust provider")
   assert(driver:find('-Wl,--whole-archive "$rust_base"', 1, true),
      "a static host can discard Rust exports reached only through FFI")
   assert(driver:find('-Wl,-force_load,$rust_base', 1, true),
      "a macOS static host can discard Rust exports reached only through FFI")
   assert(packer:find('copy_library "$host_dir/libnupp_native_v2.a"', 1, true),
      "the compiler pack omits the Rust provider archive")
   assert(packLinker:find('host/lib/libnupp_native_v2.a', 1, true),
      "the compiler-pack linker omits the Rust provider archive")
   assert(packLinker:find('append(&cursor, "-Wl,--whole-archive")', 1, true),
      "the compiler-pack linker can discard Rust FFI exports")
end

-- Clang accepts --ld-path only while linking. Generated AOT compilation uses
-- -Werror, so putting it among compile flags makes a valid installed pack fail
-- before its linker can run.
function M.linuxCompilerPackKeepsTheLinkerOutOfCompiles()
   local packer = read(ROOT .. "/scripts/compiler-pack")
   local compileFlags = assert(packer:match("compile_flags='(%[[^\n]+%])'"))
   local linkFlags = assert(packer:match("link_flags='(%[[^\n]+%])'"))
   assert(not compileFlags:find("--ld-path", 1, true),
      "the Linux pack gives linker selection to compile-only commands")
   assert(linkFlags:find("--ld-path", 1, true),
      "the Linux pack does not select its bundled linker")
end

-- A path answered by Git Bash can be handed directly to the native compiler or
-- LuaJIT. Those processes do not understand its `/c/...` mount spelling.
function M.windowsAnswersNativePaths()
   local directory = temporary()
   fakeWindowsUname(directory)
   fakeCygpath(directory)
   fakeCompiler(directory, "gcc", "gnu-c")
   fakeCompiler(directory, "g++", "gnu-cxx")

   local status, prefix = run({
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      PATH = forPath(directory) .. ":$PATH",
   }, "--prefix")

   assert(status == 0, prefix)
   assert(prefix:match("^C:/"), "Windows answered an MSYS path: " .. prefix)
end

-- `native-rust` deliberately answers a drive-letter path for native compiler
-- arguments. That spelling cannot be inserted into Git Bash's colon-separated
-- PATH: its drive colon becomes a separator and the DLL is not found.
function M.windowsRustAbiSmokeConvertsTheDllSearchPath()
   local smoke = read(ROOT .. "/scripts/test-rust-abi")
   assert(smoke:find('SEARCH_DIRECTORY=$(cygpath -u "$DIRECTORY")', 1, true),
      "the Rust ABI smoke does not convert its native DLL directory for PATH")
   assert(smoke:find('PATH="$SEARCH_DIRECTORY:$PATH"', 1, true),
      "the Rust ABI smoke inserts the drive-letter directory into PATH")
end

-- The native spelling belongs in compiler arguments, but not in the colon-
-- separated PATH assembled by Git Bash. The selector converts that one use
-- back before looking for the staged interpreter.
function M.windowsNativeLuaJITPathIsConvertedForTheShellPath()
   local directory = temporary()
   local oldBin = directory .. "/old-bin"
   local staged = directory .. "/staged"
   local fakeRoot = directory .. "/root"
   assert(os.execute(("mkdir -p %s %s %s")
      :format(quote(oldBin), quote(staged .. "/bin"),
         quote(fakeRoot .. "/scripts"))) == 0)
   fakeWindowsUname(oldBin)
   fakeCygpath(oldBin)
   write(oldBin .. "/luajit", [[#!/bin/sh
echo 'LuaJIT 2.1.1'
]])
   write(staged .. "/bin/luajit", [[#!/bin/sh
echo 'LuaJIT 2.1.1784535650'
]])
   write(fakeRoot .. "/scripts/toolchain", [[#!/bin/sh
printf '%s\n' 'C:/staged'
]])
   assert(os.execute("chmod +x " .. quote(oldBin .. "/luajit") .. " "
      .. quote(staged .. "/bin/luajit") .. " "
      .. quote(fakeRoot .. "/scripts/toolchain")) == 0)

   local command = ('env PATH="%s:$PATH" NUPP_TEST_CYGPATH_U=%s sh -c %s')
      :format(forPath(oldBin), quote(staged),
         quote(". " .. quote(ROOT .. "/scripts/luajit.sh")
            .. "; if select_luajit " .. quote(fakeRoot)
            .. "; then command -v luajit; else exit 1; fi"))
   local pipe = assert(io.popen(command))
   local selected = pipe:read("*a")
   pipe:close()
   -- Compared in one spelling. What is under test is whether the staged
   -- interpreter was reached at all: a drive path that went into PATH unconverted
   -- is split there, and then nothing is found and `command -v` answers with the
   -- old one or with nothing. Which spelling the answer comes back in is the
   -- selector's business and not this assertion's, and matching one of them by
   -- hand made a passing selection read as a split path.
   local wanted = forPath(staged) .. "/bin/luajit"
   assert(forPath((selected:gsub("%s+$", ""))) == wanted,
      ("selected %q, wanted %q"):format(selected, wanted))
end

-- `NUPP_NATIVE_CC` named the C compiler before the toolchain names were
-- unified. It keeps working, and the primary name wins.
function M.theOldCCompilerNameStillSelects()
   local directory = temporary()
   local named = fakeCompiler(directory, "named-cc", "named")
   local aliased = fakeCompiler(directory, "aliased-cc", "aliased")
   local environment = {
      NUPP_TOOLCHAIN_DIR = directory .. "/cache",
      PATH = "$PATH",
      NUPP_NATIVE_CC = aliased,
   }

   local status, viaAlias = run(environment, "--prefix")
   assert(status == 0, viaAlias)

   environment.NUPP_CC = named
   local primaryStatus, viaPrimary = run(environment, "--prefix")
   assert(primaryStatus == 0, viaPrimary)

   assert(viaAlias ~= viaPrimary,
      "the primary names did not win over the aliases: " .. viaAlias)
end

return M
