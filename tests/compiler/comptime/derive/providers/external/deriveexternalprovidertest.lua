local fixture = require("helpers.deriveprovider")
local process = fixture.process
local NUPP = fixture.NUPP
local STRICT = fixture.STRICT

local M = {}

-- The same example, checked and run from a directory it is not under, so it has no
-- module name. Its helper named its own module through that missing name, so the
-- provider was refused with NUPP2809 and the record never gained `label` (ER-018).
function M.runsAProviderNamingItsOwnModuleFromOutsideTheProject()
    local function scratch()
        local dir = os.tmpname()
        os.remove(dir)
        assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
        return dir
    end

    local home, elsewhere = scratch(), scratch()
    local source = assert(io.open(STRICT.custom, "rb")):read("*a")
    local file = assert(io.open(home .. "/main.nupp", "wb"))
    file:write(source)
    file:close()
    local path = home .. "/main.nupp"
    local nupp = NUPP:sub(1, 1) == "/" and NUPP or (assert(os.getenv("PWD")) .. "/" .. NUPP)
    local checked, checkOutput = process.capture({nupp, "check", path}, {cwd = elsewhere})
    local status, output = process.capture({nupp, "run", path}, {cwd = elsewhere})
    os.execute("rm -rf '" .. home .. "' '" .. elsewhere .. "'")
    assert(checked == 0, "the example checks from outside its directory:\n" .. checkOutput)
    assert(status == 0 and output == "<User>\n", "the example runs from outside its directory:\n" .. output)
end

return M
