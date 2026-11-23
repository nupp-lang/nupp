-- What the sqlite library does before it calls SQLite: the arguments it
-- refuses, the error it raises rendered and named, and the checker refusing a
-- statement that would outlive its connection. SQLite itself is exercised on the
-- native core by the guest cases (tests/core/catalog-sqlite-*.nupp).
local json = require("testjson")

local HERE = require("helpers.paths").absoluteTests
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function raised(body, ...)
    local ok, problem = pcall(body, ...)
    assert(not ok, "it did not raise")

    return tostring(problem)
end

function M.optionsAreCheckedBeforeSQLiteIsCalled()
    local sqlite = require("sqlite")
    assert(raised(sqlite.open, 7):find("path must be a string", 1, true))
    assert(raised(sqlite.open, ":memory:", {journals = "wal"}):find('no option "journals"', 1, true))
    assert(raised(sqlite.open, ":memory:", {readonly = "yes"}):find("readonly must be a boolean", 1, true))
    assert(raised(sqlite.open, ":memory:", {journal = "truncate"}):find("delete, wal or memory", 1, true))
    assert(raised(sqlite.open, ":memory:", {busytimeout = 1.5}):find("milliseconds", 1, true))
    assert(raised(sqlite.blob, 1):find("bytes must be a string", 1, true))
    assert(sqlite.blob("\0x").bytes == "\0x")
end

function M.anErrorCarriesItsCodeAndNames()
    local contracts = require("sqlite.internal.contracts")
    local sqlite = require("sqlite")
    local failure = contracts.failure(2067, "UNIQUE constraint failed: shows.title", "insert", nil)
    assert(getmetatable(failure) == sqlite.Error)
    assert(failure.primary == sqlite.CONSTRAINT and failure.name == "SQLITE_CONSTRAINT_UNIQUE")
    assert(tostring(failure) == "SQLITE_CONSTRAINT_UNIQUE: UNIQUE constraint failed: shows.title", tostring(failure))
    local syntax = contracts.failure(1, 'near "frm": syntax error', "select 1 frm t", 9)
    assert(tostring(syntax) == 'SQLITE_ERROR: near "frm": syntax error (at byte 9)', tostring(syntax))
    assert(contracts.codename(sqlite.BUSY) == "SQLITE_BUSY")
    assert(contracts.codename(5 | (3 << 8)) == "SQLITE_BUSY_TIMEOUT")
    assert(contracts.codename(10 | (99 << 8)) == "SQLITE_IOERR(25354)")
end

function M.aStatementCannotOutliveItsConnection()
    local output = os.tmpname()
    local fixture = HERE .. "/stdlib/sqlite/fixtures/statementescape.nupp"
    os.execute(("cd %q && %q check --json %q > %q 2>/dev/null"):format(HERE .. "/..", NUPP, fixture, output))
    local file = assert(io.open(output, "rb"))
    local text = file:read("*a")
    file:close()
    os.remove(output)
    local checked = json.decode(text)
    local codes = {}
    for _, diagnostic in ipairs(checked.diagnostics or {}) do
        codes[#codes + 1] = diagnostic.code
    end
    assert(#codes > 0, "the checker accepted a statement that outlives its connection: " .. text)
    for _, code in ipairs(codes) do
        assert(code:match("^NUPP26"), "an ownership diagnostic, not " .. code .. ": " .. text)
    end
end

return M
