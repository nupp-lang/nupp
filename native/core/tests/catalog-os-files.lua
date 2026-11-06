-- Lua twin of catalog-os-files.nupp.

local unique = os.tmpname()

-- Lua's calls on file names on the core, as reference Lua 5.5 (built with
-- LUA_USE_POSIX) answers them: os.remove and os.rename with their results
-- and errors, os.tmpname's new file, io.tmpfile, and os.setlocale in the C
-- locale. Files go under NUPP_GUEST_TEMP. Each check is a bit of the score.
local base = (os.getenv("NUPP_GUEST_TEMP") or "/tmp") .. "/os-" .. string.sub(unique, -6)
os.remove(unique)
local score = 0
local bit = 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

local function ends(text, suffix)
    return type(text) == "string" and string.sub(text, -#suffix) == suffix
end

local function absent(path)
    local f, _ = io.open(path, "r")
    if f == nil then
        return true
    end
    f:close()

    return false
end

-- Renaming and removing.
do
    local f = assert(io.open(base .. "-a", "w"))
    f:write("moved")
    f:close()
    check(os.rename(base .. "-a", base .. "-b") == true and absent(base .. "-a"))
    local moved = assert(io.open(base .. "-b", "r"))
    check(moved:read("a") == "moved")
    moved:close()
    check(os.remove(base .. "-b") == true and absent(base .. "-b"))
    local gone, goneMessage, goneCode = os.remove(base .. "-b")
    check(gone == nil and goneMessage == base .. "-b: No such file or directory" and goneCode == 2)
    local lost, lostMessage, lostCode = os.rename(base .. "-b", base .. "-c")
    check(lost == nil and lostMessage == "No such file or directory" and lostCode == 2)
    local nested = assert(io.open(base .. "-d", "w"))
    nested:close()
    local notDirectory, notMessage, notCode = os.remove(base .. "-d/x")
    check(notDirectory == nil and notMessage == base .. "-d/x: Not a directory" and notCode == 20)
    check(os.remove(base .. "-d") == true)
    local noneOk, noneMessage = pcall(function()
        return (os.remove)()
    end)
    check(not noneOk and ends(noneMessage, ":55: bad argument #1 to 'remove' (string expected, got no value)"))
    local secondOk, secondMessage = pcall(function()
        return (os.rename)("x")
    end)
    check(not secondOk and ends(secondMessage, ":59: bad argument #2 to 'rename' (string expected, got no value)"))
    local tableOk, tableMessage = pcall(function()
        return (os.rename)(true, "x")
    end)
    check(not tableOk and ends(tableMessage, ":63: bad argument #1 to 'rename' (string expected, got boolean)"))
end

-- A temporary name is a new empty file under /tmp; a temporary file reads
-- back what it was given.
do
    local name = os.tmpname()
    check(string.match(name, "^/tmp/lua_......$") ~= nil and os.tmpname() ~= name)
    local made = assert(io.open(name, "r"))
    check(made:read("a") == "")
    made:close()
    check(os.remove(name) == true)
    local t = assert(io.tmpfile())
    check(
        string.match(tostring(t), "^file %(") ~= nil
        and t:write("abc", 12) == t
        and t:seek("set") == 0
        and t:read("a") == "abc12"
    )
    check(t:seek("end") == 5 and t:close() == true and tostring(t) == "file (closed)")
end

-- The C locale.
do
    local setlocale = (os).setlocale
    check(setlocale() == "C" and setlocale("C") == "C" and setlocale(nil, "numeric") == "C")
    check(setlocale("C", "time") == "C" and setlocale("no-such-locale") == nil)
    local categoryOk, categoryMessage = pcall(function()
        return setlocale("C", "bogus")
    end)
    check(not categoryOk and ends(categoryMessage, ":93: bad argument #2 to 'setlocale' (invalid option 'bogus')"))
end
return score
