local score, bit = 0, 1

local function check(ok)
    if ok then
        score = score | bit
    end
    bit = bit << 1
end

local function fails(action, suffix)
    local ok, message = pcall(action)
    check(not ok and type(message) == 'string' and message:sub(-#suffix) == suffix)
end

local tmp = io.tmpfile
local f = assert(tmp())
fails(
    function()
        return f:read('x')
    end,
    "bad argument #1 to 'read' (invalid format)"
)
fails(
    function()
        return f.read(f, 'x')
    end,
    "bad argument #2 to 'read' (invalid format)"
)
local reader = f.read
fails(
    function()
        return reader(f, 'x')
    end,
    "bad argument #2 to 'reader' (invalid format)"
)
local ok, message = pcall(reader, f, 'x')
check(not ok and message == "bad argument #2 to '?' (invalid format)")
fails(
    function()
        return f:seek('bogus')
    end,
    "bad argument #1 to 'seek' (invalid option 'bogus')"
)
fails(
    function()
        return f.seek(f, 'bogus')
    end,
    "bad argument #2 to 'seek' (invalid option 'bogus')"
)
fails(
    function()
        return f:seek('set', {})
    end,
    "bad argument #2 to 'seek' (number expected, got table)"
)
fails(
    function()
        return f.seek(f, 'set', {})
    end,
    "bad argument #3 to 'seek' (number expected, got table)"
)
fails(
    function()
        return f:setvbuf('bogus')
    end,
    "bad argument #1 to 'setvbuf' (invalid option 'bogus')"
)
fails(
    function()
        return f.setvbuf(f, 'bogus')
    end,
    "bad argument #2 to 'setvbuf' (invalid option 'bogus')"
)
fails(
    function()
        return f:write({})
    end,
    "bad argument #1 to 'write' (string expected, got table)"
)
fails(
    function()
        return f.write(f, {})
    end,
    "bad argument #2 to 'write' (string expected, got table)"
)
local bad = {read = reader}
fails(
    function()
        return bad:read('x')
    end,
    "calling 'read' on bad self (FILE* expected, got table)"
)
fails(
    function()
        return bad.read(bad, 'x')
    end,
    "bad argument #1 to 'read' (FILE* expected, got table)"
)
-- Runtime argument validation crosses an intentionally dynamic callable.
local protectedOpen = io.open
ok, message = pcall(protectedOpen, false, 'r')
check(not ok and message == "bad argument #1 to 'io.open' (string expected, got boolean)")
local opener = io.open
fails(
    function()
        return opener(false, 'r')
    end,
    "bad argument #1 to 'opener' (string expected, got boolean)"
)
local before = io.input()
io.input(f)
fails(
    function()
        return io.read('x')
    end,
    "bad argument #1 to 'read' (invalid format)"
)
local globalReader = io.read
fails(
    function()
        return globalReader('x')
    end,
    "bad argument #1 to 'globalReader' (invalid format)"
)
local globalOk, globalMessage = pcall(globalReader, 'x')
check(not globalOk and globalMessage == "bad argument #1 to 'io.read' (invalid format)")

local function readFile(value)
    return globalReader(value)
end

fails(
    function()
        return readFile('x')
    end,
    "bad argument #1 to 'globalReader' (invalid format)"
)
io.input(before)
fails(
    function()
        local value = f:read('x');
        return value
    end,
    "bad argument #1 to 'read' (invalid format)"
)

local function identity(value)
    return value
end

ok, message = xpcall(reader, identity, f, 'x')
check(not ok and message == "bad argument #2 to '?' (invalid format)")
ok, message = xpcall(
    function()
        return f:read('x')
    end,
    identity
)
check(
    not ok
    and type(message) == 'string'
    and message:sub(-#"bad argument #1 to 'read' (invalid format)") == "bad argument #1 to 'read' (invalid format)"
)
ok, message = pcall(opener, false, 'r')
check(not ok and message == "bad argument #1 to 'io.open' (string expected, got boolean)")
fails(
    function()
        for value in f:lines('x') do
        end
        return nil
    end,
    "bad argument #2 to 'for iterator' (invalid format)"
)
f:close()
local popen = io.popen
local child = assert(popen('printf x', 'r'))
fails(
    function()
        return child:seek('bogus')
    end,
    "bad argument #1 to 'seek' (invalid option 'bogus')"
)
fails(
    function()
        return child.seek(child, 'bogus')
    end,
    "bad argument #2 to 'seek' (invalid option 'bogus')"
)
fails(
    function()
        return child:setvbuf('bogus')
    end,
    "bad argument #1 to 'setvbuf' (invalid option 'bogus')"
)
fails(
    function()
        return child.setvbuf(child, 'bogus')
    end,
    "bad argument #2 to 'setvbuf' (invalid option 'bogus')"
)
child:close()
return score
