-- The SQLite declarations the native core binds by hand
-- (`nupp.runtime.core.sqlitecodec`) against the pinned header, as `nupp
-- import-c` reads it. A declared prototype that drifts from sqlite3.h calls
-- SQLite with the wrong arguments, and nothing else would notice until a
-- program did.
--
-- The codec declares every pointer opaquely, so prototypes are compared by
-- what the C ABI passes: each parameter and the result as a pointer or as its
-- exact scalar, and a variadic tail as such. The destructors the codec passes
-- as the word SQLITE_TRANSIENT is, and a narrow encoding passed as a 32-bit
-- integer, are the documented exceptions.
local importc = require("nupp.compiler.cinterop.importc")

local ROOT = require("helpers.paths").root

local M = {}

-- Parameters the codec declares otherwise than the header, by function and
-- position: what the header has and what the codec passes in its place.
local PASSED_AS = {
    -- SQLITE_TRANSIENT, a destructor pointer, as the word it is.
    sqlite3_bind_text64 = {[5] = {"pointer", "int64"}, [6] = {"uint8", "int32"}},
    sqlite3_bind_blob64 = {[5] = {"pointer", "int64"}},
}

local SCALARS = {
    int32 = "int32",
    uint32 = "uint32",
    int64 = "int64",
    uint64 = "uint64",
    uint8 = "uint8",
    float64 = "float64",
    -- import-c spells C's double as Nupp's float.
    float = "float64",
}

local function read(path)
    local file = assert(io.open(path, "rb"), "cannot read " .. path)
    local text = file:read("*a")
    file:close()

    return text
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>/dev/null"))
    local text = pipe:read("*a")
    local ok, _, code = pipe:close()

    return text, ok == true or ok == 0 or code == 0
end

-- What the ABI passes for a declared type: "pointer", a scalar's name, or
-- "nil" for no result.
local function class(declared)
    local text = declared:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("^borrows%s+", ""):gsub("^exclusive%s+", ""):gsub("^takes%s+", "")
    text = text:gsub("^const%s+", ""):gsub("%?$", "")
    if text == "" or text == "nil" then
        return "nil"
    elseif text:find("*", 1, true) or text:match("^function%(") or text == "voidptr" or text == "cstring"
        or text == "string"
    then
        return "pointer"
    end

    return SCALARS[text] or ("unknown " .. text)
end

-- Splits a parameter list at its top-level commas.
local function parameters(list)
    local found, depth, start = {}, 0, 1
    for index = 1, #list do
        local char = list:sub(index, index)
        if char == "(" then
            depth = depth + 1
        elseif char == ")" then
            depth = depth - 1
        elseif char == "," and depth == 0 then
            found[#found + 1] = list:sub(start, index - 1)
            start = index + 1
        end
    end
    if list:match("%S") then
        found[#found + 1] = list:sub(start)
    end
    local classes = {}
    for index, parameter in ipairs(found) do
        if parameter:match("^%s*%.%.%.%s*$") then
            classes[index] = "..."
        else
            classes[index] = class(assert(parameter:match(":%s*(.-)%s*$"), "untyped parameter " .. parameter))
        end
    end

    return classes
end

-- Every `cdef function sqlite3_*` in `text`, by name: its parameter classes
-- and its result's.
local function prototypes(text)
    local found = {}
    local at = 1
    while true do
        local start, stop, name = text:find("cdef function (sqlite3_[%w_]+)%(", at)
        if start == nil then
            break
        end
        local depth, close = 1, stop
        while depth > 0 do
            close = close + 1
            local char = text:sub(close, close)
            if char == "(" then
                depth = depth + 1
            elseif char == ")" then
                depth = depth - 1
            end
        end
        local list = text:sub(stop + 1, close - 1)
        local result = text:match("^%s*:%s*(.-)%s*from", close + 1) or ""
        found[name] = {parameters = parameters(list), result = class(result)}
        at = close + 1
    end

    return found
end

local function header()
    local prefix, ok = capture("sh '" .. ROOT .. "/scripts/toolchain' sqlite")
    assert(ok, "cannot provision the pinned SQLite library")

    return prefix:match("([^\r\n]+)%s*$") .. "/include/sqlite3.h"
end

function M.theCodecsPrototypesMatchThePinnedHeader()
    local imported, warnings = importc.import(header(), {module = "sqlite3", lib = "nuppsqlite"})
    assert(imported, "import-c refused sqlite3.h: " .. table.concat(warnings or {}, "; "))
    local expected = prototypes(imported)
    local declared = prototypes(read(ROOT .. "/src/nupp/runtime/core/sqlitecodec.nupp"))
    local problems, count = {}, 0
    for name, prototype in pairs(declared) do
        count = count + 1
        local upstream = expected[name]
        if upstream == nil then
            problems[#problems + 1] = name .. " is not in sqlite3.h"
        else
            if prototype.result ~= upstream.result then
                problems[#problems + 1] = ("%s answers %s, not %s"):format(name, prototype.result, upstream.result)
            end
            if #prototype.parameters ~= #upstream.parameters then
                problems[#problems + 1] = ("%s takes %d parameters, not %d"):format(
                    name,
                    #prototype.parameters,
                    #upstream.parameters
                )
            end
            for index, wanted in ipairs(upstream.parameters) do
                local got = prototype.parameters[index]
                local passed = PASSED_AS[name] and PASSED_AS[name][index]
                local allowed = passed ~= nil and passed[1] == wanted and passed[2] == got
                if got ~= nil and got ~= wanted and not allowed then
                    problems[#problems + 1] = ("%s parameter %d is %s, not %s"):format(name, index, got, wanted)
                end
            end
        end
    end
    assert(count >= 30, "the codec declares too few SQLite functions to be the subset: " .. count)
    table.sort(problems)
    assert(#problems == 0, "the codec drifted from sqlite3.h:\n  " .. table.concat(problems, "\n  "))
end

-- The comparison above, on a prototype that has drifted.
function M.aDriftedPrototypeIsReported()
    local header = prototypes('cdef function sqlite3_bind_int64(a: sqlite3_stmt*?, b: int32, c: int64): int32 from "x"')
    local drifted = prototypes('cdef function sqlite3_bind_int64(borrows a: voidptr, b: int32, c: int32): int32 from"x"')
    assert(header.sqlite3_bind_int64.parameters[3] == "int64")
    assert(drifted.sqlite3_bind_int64.parameters[1] == "pointer")
    assert(drifted.sqlite3_bind_int64.parameters[3] == "int32", "a narrowed integer reads as itself")
end

return M
