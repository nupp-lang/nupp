-- What a core binary's package stages of the C libraries its bundle binds.
--
-- A standard binding's library and a builtin's notices are staged beside a bundle
-- only when the bundle names the library (`@lib/FILE`): never copied in with the
-- runtime host's own sidecars, so a program that binds nothing carries nothing.
-- `nupp build --json` says which builtins a target carries. These build two core
-- binaries over a fixture builtin on the pinned ISA-L CRC library, one calling it
-- and one not. The bridge itself links no builtin's library on any platform, which
-- is read from the scripts that build it.
local json = require("testjson")
local closure = require("tools.packaging.builtinclosure")

local ROOT = require("helpers.paths").root
local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/packaging/fixtures/builtinclosure"

local M = {}

-- The fixture builtin: the closure fixtures' `crcfixture` module over nuppcrc.
local ENTRY = {
    modules = {"crcfixture", "crcfixture.*"},
    owned = {},
    libraries = {{name = "nuppcrc", file = "nupp_crc", notices = {"ISA-L-LICENSE.txt", "ISA-L-CRC-LICENSE.txt"}}},
    hosts = {"native"},
}

local function read(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local pipe = assert(io.popen(command))
    local text = pipe:read("*a")
    local ok, _, code = pipe:close()

    return text, ok == true or ok == 0 or code == 0
end

local function scratch()
    local directory = os.tmpname()
    os.remove(directory)
    capture("mkdir -p " .. quote(directory))

    return directory
end

local function project(name)
    local directory = scratch()
    capture("cp -R " .. quote(FIXTURES .. "/" .. name) .. "/. " .. quote(directory))

    return directory
end

local function generation(directory, report)
    local launcher = assert(read(directory .. "/" .. report.artifact), "no launcher at " .. tostring(report.artifact))
    local relative = assert(launcher:match('bundle="%$here"/\'([^\']+)\''), launcher)

    return directory .. "/" .. (report.artifact:match("^(.*)/[^/]+$") or ".") .. "/" .. relative
end

local function fixture()
    local path = scratch() .. "/builtins.json"
    write(path, json.encode({crcfixture = ENTRY}))

    return path
end

function M.aBundleThatBindsTheLibraryStagesItWithItsNotices()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local directory = project("uses")
    local report, built, errors = closure.build(directory, "", fixture())
    assert(built, errors:sub(-2000))
    local at = generation(directory, report)
    local crc = closure.filename("nupp_crc")
    assert(read(at .. "/lib/" .. crc), "the CRC library is staged")
    assert(read(at .. "/notices/ISA-L-LICENSE.txt") and read(at .. "/notices/ISA-L-CRC-LICENSE.txt"), "with its notices")
    assert(read(at .. "/runtime") or read(at .. "/runtime.exe"), "beside the runtime")
    local text = capture(quote(directory .. "/" .. report.artifact))
    assert(text:find("907060870", 1, true), "the program calls the library: " .. text)
    assert(#report.builtins == 1, json.encode(report.builtins))
    local carried = report.builtins[1]
    assert(carried.name == "crcfixture")
    assert(#carried.modules == 1 and carried.modules[1] == "crcfixture", json.encode(carried.modules))
    assert(#carried.libraries == 1, json.encode(carried.libraries))
    assert(carried.libraries[1].library == "nuppcrc" and carried.libraries[1].file == "lib/" .. crc)
    local libraryBytes = #read(at .. "/lib/" .. crc)
    assert(carried.libraries[1].bytes == libraryBytes, json.encode(carried.libraries[1]))
    assert(#carried.notices == 2, json.encode(carried.notices))
    local noticeBytes = #read(at .. "/notices/ISA-L-LICENSE.txt") + #read(at .. "/notices/ISA-L-CRC-LICENSE.txt")
    assert(carried.bytes == libraryBytes + noticeBytes, json.encode(carried))
    assert(json.isArray(report.without) and #report.without == 0, json.encode(report.without))
    capture("rm -rf " .. quote(directory))
end

function M.aBundleThatBindsNothingStagesNoneOfIt()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local directory = project("hello")
    local report, built, errors = closure.build(directory, "", fixture())
    assert(built, errors:sub(-2000))
    local at = generation(directory, report)
    -- Neither the CRC library, which the compiler beside the runtime also
    -- binds, nor zlib's, which only the standard binding stages.
    for _, base in ipairs({"nupp_crc", "z"}) do
        assert(read(at .. "/lib/" .. closure.filename(base)) == nil, closure.filename(base) .. " is not staged")
    end
    assert(read(at .. "/notices/ISA-L-LICENSE.txt") == nil, "nor its notice")
    -- The runtime's own sidecars still are.
    assert(read(at .. "/runtime") or read(at .. "/runtime.exe"), "the runtime is staged")
    assert(json.isArray(report.builtins) and #report.builtins == 0, json.encode(report.builtins))
    local text = capture(quote(directory .. "/" .. report.artifact))
    assert(text:find("hello", 1, true), text)
    capture("rm -rf " .. quote(directory))
end

function M.theReportFieldsAreInTheSchema()
    local text = capture(quote(ROOT .. "/bin/nupp") .. " build --schema")
    local schema = json.decode(text)
    assert(schema.properties.builtins and schema.properties.builtins.items.required, "builtins is documented")
    assert(schema.properties.without and schema.properties.without.items.type == "string", "without is documented")
end

-- Every registered builtin's library, as its logical name and file base name.
local function registeredLibraries()
    local found = {}
    for _, builtin in pairs(require("nupp.compiler.project.builtins").REGISTRY) do
        for _, library in ipairs(builtin.libraries) do
            found[#found + 1] = library
        end
    end
    -- The fixture's library stands in until a real one is registered, so the
    -- reading below is shown to look for something.
    found[#found + 1] = {name = "nuppseeded", file = "nupp_seeded"}

    return found
end

function M.theBridgeLinksNoBuiltinLibrary()
    local scripts = {
        "scripts/core-bridge",
        "scripts/core-bridge-windows.sh",
        "scripts/core-http-linux-sdk.sh",
        "scripts/core-http-windows-sdk.sh",
    }
    for _, script in ipairs(scripts) do
        local text = read(ROOT .. "/" .. script)
        if text ~= nil then
            for _, library in ipairs(registeredLibraries()) do
                for _, name in ipairs({library.name, library.file}) do
                    assert(not text:find(name, 1, true), script .. " names builtin library " .. name)
                end
            end
        end
    end
end

function M.theBridgeRefusesToStageABuiltinsLibrary()
    if package.config:sub(1, 1) == "\\" then
        return require("assert").suite.skip("the refusal is read by sh from POSIX paths")
    end
    local directory = scratch()
    local registry = directory .. "/builtins.nupp"
    write(registry, table.concat({
        "-- A seeded registry for the bridge's refusal.",
        "export const REGISTRY = {",
        "    seeded = {",
        '        modules = {"seeded"},',
        '        libraries = {{name = "nuppseeded", file = "nupp_seeded", notices = {"seeded-LICENSE.txt"}}},',
        "    },",
        "}",
        "",
    }, "\n"))
    local check = "sh " .. quote(ROOT .. "/scripts/core-bridge-builtins") .. " " .. quote(directory .. "/stage") .. " "
        .. quote(registry) .. " 2>&1"
    capture("mkdir -p " .. quote(directory .. "/stage/lib") .. " " .. quote(directory .. "/stage/notices"))
    write(directory .. "/stage/lib/libuv.dylib", "")
    local text, ok = capture(check)
    assert(ok, "a stage with no builtin library passes: " .. text)
    write(directory .. "/stage/lib/" .. closure.filename("nupp_seeded"), "")
    text, ok = capture(check)
    assert(not ok and text:find("lib/" .. closure.filename("nupp_seeded"), 1, true), text)
    os.remove(directory .. "/stage/lib/" .. closure.filename("nupp_seeded"))
    write(directory .. "/stage/notices/seeded-LICENSE.txt", "")
    text, ok = capture(check)
    assert(not ok and text:find("notices/seeded-LICENSE.txt", 1, true), text)
    -- The real registry passes over what this checkout's bridge staged.
    local bridge = ROOT .. "/build/c-core-bridge"
    if read(bridge .. "/nupp-core") ~= nil then
        text, ok = capture("sh " .. quote(ROOT .. "/scripts/core-bridge-builtins") .. " " .. quote(bridge) .. " 2>&1")
        assert(ok, text)
    end
    capture("rm -rf " .. quote(directory))
end

return M
