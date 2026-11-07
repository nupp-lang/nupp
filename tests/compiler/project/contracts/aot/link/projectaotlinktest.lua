local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local process = fixture.process
local json = fixture.json
local write = fixture.write
local read = fixture.read
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove
local libraryName = fixture.libraryName
local setEnvironment = fixture.setEnvironment

local M = {}

function M.standaloneBinaryLinksAotIntoItsOwnHost()
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do
      result = result + index
   end
   return result
end

print(triangular(4))
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "binary",
      stub = "nupp", standalone = true, aot = "require", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/app")
    )
    testAssert.eq(project.build(dir), 0)
    assert(exists(dir .. "/out/lib/libdefault_aot.a"), "standalone AOT emits a static archive")
    assert(not exists(dir .. "/out/lib/" .. libraryName("default_aot")), "standalone AOT emits no loadable sidecar")
    local code, text = process.capture({dir .. "/out/app"})
    testAssert.eq(code, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "10", "the executable resolves its AOT entry internally")
    remove(dir)
end

--- A standalone program with AOT code links from a link kit with lld in
--- process: no C compiler, system linker or SDK is run, and the program
--- carries no LLVM of its own.
function M.standaloneAotLinksFromAKitWithoutACToolchain()
    local posix = jit.os ~= "Windows"
    local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/") or "."
    local code, answer = process.capture(
        posix and {root .. "/scripts/toolchain", "kit", ""} or {"sh.exe", root .. "/scripts/toolchain", "kit", ""}
    )
    testAssert.eq(code, 0, answer)
    local kit = answer:match("([^\r\n]+)%s*$")
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do
      result = result + index
   end
   return result
end

print(triangular(4))
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "binary",
      stub = "nupp", standalone = true, aot = "require", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/app")
    )
    -- Every tool a C link would reach for fails, and says so.
    local fake = dir .. "/fakebin"
    assert(os.execute("mkdir -p '" .. fake .. "'") == 0)
    for _, tool in ipairs({
        "cc",
        "clang",
        "gcc",
        "ld",
        "ld.lld",
        "xcrun",
        "c++",
        "clang++",
        "ar",
        "ranlib",
        "libtool"
    }) do
        write(fake .. "/" .. tool, "#!/bin/sh\necho \"$0\" >> '" .. dir .. "/invoked'\nexit 99\n")
        assert(os.execute("chmod +x '" .. fake .. "/" .. tool .. "'") == 0)
    end
    local windows = package.config:sub(1, 1) == "\\"
    local path = os.getenv("PATH") or ""
    setEnvironment("PATH", fake .. (windows and ";" or ":") .. path)
    setEnvironment("NUPP_KIT_DIR", kit)
    local ok, built = pcall(project.build, dir)
    setEnvironment("PATH", path)
    setEnvironment("NUPP_KIT_DIR", nil)
    assert(ok, built)
    testAssert.eq(built, 0)
    assert(not exists(dir .. "/invoked"), "no C toolchain was run")
    local program = dir .. "/out/app"
    if windows and not exists(program) then
        program = program .. ".exe"
    end
    local ran, text = process.capture({program})
    testAssert.eq(ran, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "10", "the program runs its AOT entry")
    local _, symbols = process.capture({"nm", program})
    assert(not symbols:find("ZN4llvm", 1, true), "the program carries no LLVM")
    remove(dir)
end

--- A kit the stub catalog records is installed from its archive -- checked
--- against the catalog's digest, unpacked into the per-user cache -- and
--- linked from there; the next build needs neither the archive nor the network,
--- and an archive that does not match its record is refused.
function M.standaloneAotLinksFromACatalogKit()
    if jit.os ~= "OSX" and jit.os ~= "Linux" then
        return
    end
    local root = debug.getinfo(1, "S").source:match("^@(.*)/tests/") or "."
    local dir = tempProject({
        [
            "src/main.nupp"
        ] = [[
@aot
local function triangular(count: integer): number
   local result = 0.0
   for index = 1, count do
      result = result + index
   end
   return result
end

print(triangular(5))
]],
    })
    write(
        dir .. "/nupp.lua",
        (
            [=[return {include = {"src"}, build = {kind = "binary",
      stub = "nupp", standalone = true, aot = "require", outDir = %q,
      output = %q, entries = {"main"}}}]=]
        ):format(dir .. "/out", dir .. "/out/app")
    )
    assert(os.execute("mkdir -p '" .. dir .. "/kits'") == 0)
    local archive = dir .. "/kits/nupp-kit.tar.gz"
    local code, answer = process.capture({root .. "/scripts/toolchain", "kit-archive", "", archive})
    testAssert.eq(code, 0, answer)
    local bytes = read(archive)
    -- A release compiles the archive's digest into every nupp it builds, so the
    -- bytes are the kit's names and contents, not the clock, owner or umask of
    -- whoever archived it: the same kit touched, under another umask and zone,
    -- archives the same.
    local again = dir .. "/kits/again.tar.gz"
    assert(
        os.execute(
            (
                "kit=$(%q kit '' 2>/dev/null) && touch \"$kit\"/* && (umask 077; TZ=Asia/Tokyo %q kit-archive '' %q)"
            ):format(root .. "/scripts/toolchain", root .. "/scripts/toolchain", again)
        ) == 0
    )
    assert(read(again) == bytes, "archiving the same kit again writes the same bytes")
    os.remove(again)
    local host = assert(require("nupp.tools.build.platform").hostKey())
    local hostAbi = require("nupp.tools.build.package").hostAbiVersion

    local function catalog(digest)
        write(
            dir .. "/catalog.json",
            (
                [[{"catalogRelease": "test", "hostAbi": %d, "stubs": {}, "kits": {"%s": {
  "platform": "%s", "catalogRelease": "test", "hostAbi": %d, "artifact": "nupp-kit.tar.gz",
  "sha256": "%s", "size": %d, "hostFeatures": [], "url": "https://kits.invalid/nupp-kit.tar.gz"}}}]]
            ):format(hostAbi, host, host, hostAbi, digest, #bytes)
        )
    end

    catalog(require("nupp.compiler.hash").sha256(bytes))
    local names = {"NUPP_STUB_CATALOG", "NUPP_STUB_DIR", "NUPP_KIT_CACHE"}
    setEnvironment("NUPP_STUB_CATALOG", dir .. "/catalog.json")
    setEnvironment("NUPP_STUB_DIR", dir .. "/kits")
    setEnvironment("NUPP_KIT_CACHE", dir .. "/cache")

    local function build()
        local ok, built = pcall(project.build, dir)
        assert(ok, built)
        return built
    end

    local first = build()
    local installed = exists(
        dir .. "/cache/test/" .. host .. "/" .. require("nupp.compiler.hash").sha256(bytes) .. "/kit.json"
    )
    os.remove(archive)
    assert(os.execute("rm -rf '" .. dir .. "/out'") == 0)
    local second = build()
    local ran, text = process.capture({dir .. "/out/app"})
    -- The digest is what authenticates a kit, so one that does not match is
    -- refused before anything is unpacked.
    write(archive, bytes)
    catalog(string.rep("0", 64))
    assert(os.execute("rm -rf '" .. dir .. "/out'") == 0)
    local tampered = build()
    for _, name in ipairs(names) do
        setEnvironment(name, nil)
    end
    testAssert.eq(first, 0)
    assert(installed, "the kit is unpacked into the per-user cache")
    testAssert.eq(second, 0, "the cached kit serves without its archive")
    testAssert.eq(ran, 0, text)
    testAssert.eq(text:match("[^\r\n]+"), "15", "the program runs its AOT entry")
    assert(tampered ~= 0, "an archive that does not match its record is refused")
    remove(dir)
end

return M
