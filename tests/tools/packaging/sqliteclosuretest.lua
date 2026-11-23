-- The builtin closure harness (`builtinclosure.lua`) for SQLite: a program that
-- does not reach `sqlite` carries none of its modules, its library, its notice
-- or a symbol of SQLite's; one that does carries them all; and stripping it, or
-- building for a host that cannot provide it, fails naming the chain.
--
-- Set NUPP_BUILTIN_CLOSURE_RECORD to a path to keep the run's package sizes.
local closure = require("tools.packaging.builtinclosure")

local FIXTURES = require("helpers.paths").absoluteTests .. "/tools/packaging/fixtures/sqliteclosure"

local M = {}

local function quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function shell(command)
    local pipe = assert(io.popen(command))
    local text = pipe:read("*a")
    pipe:close()

    return text
end

function M.sqliteIsCarriedOnlyWhereItIsReached()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local result = closure.run({
        name = "sqlite",
        hello = FIXTURES .. "/hello",
        uses = FIXTURES .. "/uses",
        reaches = {"sqlite", "sqlite.internal.contracts", "nupp.runtime.provider.nativesqlite", "nupp.runtime.core.sqlitecodec"},
        chain = {"src/main.nupp", "src/app/store.nupp"},
        record = os.getenv("NUPP_BUILTIN_CLOSURE_RECORD"),
    })
    assert(#result.problems == 0, "the closure harness found:\n  " .. table.concat(result.problems, "\n  "))
    assert(result.sizes.uses > result.sizes.hello, "uses carries more than hello")
    io.stderr:write(
        ("sqlite closure: hello %d bytes, uses %d bytes, sqlite %d bytes\n"):format(
            result.sizes.hello,
            result.sizes.uses,
            result.sizes.difference
        )
    )
end

function M.aBrowserTargetThatReachesItFailsNamingTheHost()
    local why = closure.unavailable()
    if why then
        return require("assert").suite.skip(why)
    end
    local directory = os.tmpname()
    os.remove(directory)
    shell("mkdir -p " .. quote(directory) .. " && cp -R " .. quote(FIXTURES .. "/uses") .. "/. " .. quote(directory))
    local report, built = closure.build(directory, "--host browser", nil)
    shell("rm -rf " .. quote(directory))
    assert(not built, "a browser build reached sqlite")
    local diagnostic = (report.diagnostics or {})[1]
    assert(diagnostic ~= nil and diagnostic.code == "NUPP0006", "the browser build reported " .. tostring(diagnostic and diagnostic.code))
    assert(diagnostic.message:find("reaches sqlite, which host browser cannot provide", 1, true), diagnostic.message)
end

return M
