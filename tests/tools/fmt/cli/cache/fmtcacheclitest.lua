local fixture = require("helpers.formatcli")
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local lines = fixture.lines
local UNFORMATTED = fixture.UNFORMATTED
local FORMATTED = fixture.FORMATTED

local M = {}

-- Asking twice has to give the same answer as asking once, because the second
-- ask does not format anything: whether a file already formats to itself is
-- kept between runs. Both answers are kept, which is the half worth testing --
-- a project that is unformatted is the normal case for a gate, and the run
-- that says so must go on saying so.
function M.theProjectAnswerIsTheSameWarmAsCold()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/messy.nupp"] = UNFORMATTED,
        ["src/tidy.nupp"] = FORMATTED,
    })
    local cold, coldOk = run(dir, "fmt")
    local warm, warmOk = run(dir, "fmt")
    assert(not coldOk and not warmOk, "both runs fail on an unformatted project")
    assert(
        lines(cold) == lines(warm),
        ("warm answer differs from cold:\n  cold: %s\n  warm: %s"):format(lines(cold), lines(warm))
    )
    assert(lines(warm) == "src/messy.nupp", "and it is the right answer")

    -- Fixing the file has to be noticed, which is the failure a stored verdict
    -- would otherwise cause: the answer is keyed on the bytes, so new bytes
    -- are a new question.
    local fixed = assert(io.open(dir .. "/src/messy.nupp", "wb"))
    fixed:write(FORMATTED)
    fixed:close()
    local after, afterOk = run(dir, "fmt")
    assert(afterOk, "a formatted project passes: " .. after)

    -- And breaking one again is noticed too.
    local broken = assert(io.open(dir .. "/src/tidy.nupp", "wb"))
    broken:write(UNFORMATTED)
    broken:close()
    local again, againOk = run(dir, "fmt")
    assert(not againOk, "breaking a file fails again")
    assert(lines(again) == "src/tidy.nupp", "and names it: " .. lines(again))

    -- A damaged store is a slow run, never a wrong one.
    local damaged = assert(io.open(dir .. "/build/cache/format.buf", "wb"))
    damaged:write("not a buffer")
    damaged:close()
    local corrupt, corruptOk = run(dir, "fmt")
    assert(
        not corruptOk and lines(corrupt) == "src/tidy.nupp",
        "a damaged store gives the same answer: " .. lines(corrupt)
    )

    os.execute("rm -rf '" .. dir .. "'")
end

-- `--write` cannot act on a stored "not formatted": it needs the formatted
-- bytes, which a verdict is not. It has to format the file anyway.
function M.writeStillRewritesAFileAlreadyKnownToBeUnformatted()
    local dir = tempProject({["nupp.lua"] = 'return { include = { "src" } }\n', ["src/messy.nupp"] = UNFORMATTED,})
    local _, reportedOk = run(dir, "fmt")
    assert(not reportedOk, "the verdict is recorded by the reporting run")
    local out, ok = run(dir, "fmt -w")
    assert(ok, "writing succeeds: " .. out)
    assert(
        readFile(dir .. "/src/messy.nupp") == FORMATTED,
        "and the file is actually rewritten, not merely known to be wrong"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.bindsProjectModuleAndTypeReferencesByDefault()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = {"src"} }\n',
        [
            "src/lib/tools.nupp"
        ] = 'module lib.tools\nexport type Count = integer\nexport function count(): integer\nreturn 1\nend\n',
        ["src/app.nupp"] = 'module app\nexport function count(): lib.tools.Count\nreturn lib.tools.count()\nend\n',
    })
    local out, ok = run(dir, "fmt --write src/app.nupp")
    assert(ok, out)
    local result = readFile(dir .. "/src/app.nupp")
    assert(result:find('const {type Count} = require("lib.tools")', 1, true), result)
    assert(result:find('const tools = require("lib.tools")', 1, true), result)
    assert(result:find('function count(): Count', 1, true), result)
    assert(result:find('return tools.count()', 1, true), result)
    local checked, valid = run(dir, "check src/app.nupp")
    assert(valid, checked)
    local again, settled = run(dir, "fmt --check src/app.nupp")
    assert(settled and again == "", again)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.importVerdictsExpireWhenAProjectAddsAModule()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = {"src"} }\n',
        ["src/app.nupp"] = 'return library.tools.count()\n',
    })
    local first, initiallyFormatted = run(dir, "fmt --check src/app.nupp")
    assert(initiallyFormatted, first)
    assert(os.execute("mkdir -p '" .. dir .. "/src/library'") == 0)
    local module = assert(io.open(dir .. "/src/library/tools.nupp", "wb"))
    module:write('module library.tools\nexport function count(): integer\nreturn 1\nend\n')
    module:close()
    local after, stillFormatted = run(dir, "fmt --check src/app.nupp")
    assert(not stillFormatted and after:find("src/app.nupp", 1, true), after)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.preservesAnExplicitTypeModuleBindingWithItsCanonicalName()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = {"src"} }\n',
        ["src/shapes.nupp"] = 'module shapes\nexport record Point\nx: number\nend\n',
        ["src/app.nupp"] = 'local shapes = require("shapes")\nlocal value: shapes.Point = nil as any\nreturn value\n',
    })
    local out, ok = run(dir, "fmt --write src/app.nupp")
    assert(ok, out)
    local result = readFile(dir .. "/src/app.nupp")
    assert(not result:find('const {type Point}', 1, true), result)
    assert(result:find('value: shapes.Point', 1, true), result)
    os.execute("rm -rf '" .. dir .. "'")
end

return M
