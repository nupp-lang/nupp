-- Lua twin of catalog-process-execute.nupp.

-- Lua's os.execute on the core, as main answers it in Lua 5.1's form: the
-- wait status, an exit code in its high byte or a signal's number, for no
-- command, exits, signals, a command the shell cannot find, a command line
-- the shell parses, the argument error, and many commands in turn. Each
-- check is a bit of the score.
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

-- main's status form from whichever os.execute runs this twin: main's own,
-- or reference Lua 5.5's results.
local function execute(command)
    local ok, how, code = os.execute(command or "")
    if type(ok) == "number" then
        return ok
    elseif how == "signal" then
        return code
    elseif how == "exit" then
        return code << 8
    end
    return ok, how
end

-- With no command: an empty command line's status.
check(execute() == 0)

-- An exit's status, success and failure, in the status's high byte.
do
    check(execute("exit 0") == 0)
    check(execute("exit 3") == 3 << 8)
    check(execute("exit 255") == 255 << 8)
end

-- A signal's number, never 128 plus it.
do
    check(execute("kill -TERM $$") == 15)
    check(execute("kill -KILL $$") == 9)
end

-- A command the shell cannot find.
check(execute("no-such-command-anywhere 2>/dev/null") == 127 << 8)

-- A command line the shell parses: redirection, a pipeline, its own
-- environment, and a status that depends on what it ran.
do
    local base = (os.getenv("NUPP_GUEST_TEMP") or "/tmp") .. "/execute-" .. tostring(math.random(1, 1 << 40))
    check(execute("printf 'one\\ntwo\\n' | wc -l | tr -d ' ' > " .. base) == 0)
    local f = assert(io.open(base, "r"))
    check(f:read("a") == "2\n")
    f:close()
    check(execute("test \"$NUPP_GUEST_PROBE\" = core-environment") == 0)
    check(execute("rm " .. base .. " && test ! -e " .. base) == 0)
end

-- The argument must be a string or a number.
do
    local value = {}
    local ok, message = pcall(os.execute, value)
    check(not ok and ends(message, "(string expected, got table)"))
end

-- Many commands in turn, each its own child.
do
    local total = 0
    for index = 1, 30 do
        total = total + (execute("exit " .. tostring(index)) >> 8)
    end
    check(total == 465)
end

return score
