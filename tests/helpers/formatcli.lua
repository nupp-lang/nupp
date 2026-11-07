-- `nupp fmt` over a whole project, driven through the real binary.
--
-- Naming files formats those files; naming none asks about the project. The
-- second is the one with teeth: it decides which files a `-w` is allowed to
-- rewrite, and a tree holds plenty that nobody writes by hand.
local HERE = require("helpers.paths").absoluteTests
local NUPP = HERE .. "/../bin/nupp"

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
        end
        local f = assert(io.open(dir .. "/" .. name, "wb"))
        f:write(text)
        f:close()
    end

    return dir
end

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

--- Runs the binary in `dir` and returns its output and whether it succeeded.
-- With the store where the project keeps it. This suite is about that store --
-- what a warm run reuses, and what a damaged file costs -- so it has to be the
-- one the run reads, not whichever shared directory the whole test run named.
local function run(dir, argv)
    local outfile = os.tmpname()
    local status = os.execute(("cd '%s' && NUPP_CACHE_DIR= '%s' %s > '%s' 2>&1"):format(dir, NUPP, argv, outfile))
    local out = readFile(outfile)
    os.remove(outfile)

    return out, status == 0
end

local function lines(text)
    local out = {}
    for line in text:gmatch("([^\n]+)") do
        out[#out + 1] = line
    end
    table.sort(out)

    return table.concat(out, " ")
end

local UNFORMATTED = "local  x   =  1\n"
local FORMATTED = "local x = 1\n"

local WIDE_SIGNATURE = "function addAndDouble(firstNumber: integer, secondNumber: integer): integer\n"
    .. "    return (firstNumber + secondNumber) * 2\n"
    .. "end\n"

return {
    HERE = HERE,
    NUPP = NUPP,
    tempProject = tempProject,
    readFile = readFile,
    run = run,
    lines = lines,
    UNFORMATTED = UNFORMATTED,
    FORMATTED = FORMATTED,
    WIDE_SIGNATURE = WIDE_SIGNATURE,
}
