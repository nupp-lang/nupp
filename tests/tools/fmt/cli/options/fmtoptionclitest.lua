local fixture = require("helpers.formatcli")
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local UNFORMATTED = fixture.UNFORMATTED
local FORMATTED = fixture.FORMATTED
local WIDE_SIGNATURE = fixture.WIDE_SIGNATURE

local M = {}

-- A method call left in its sugar form gets its parens back by default, which
-- --no-method-parens turns off, leaving the sugar as written.
function M.methodCallParensAreOnByDefaultAndTheFlagTurnsThemOff()
    local dir = tempProject({["nupp.lua"] = 'return { include = { "src" } }\n', ["src/sugar.nupp"] = "obj:m{a = 1}\n",})
    local out, ok = run(dir, "fmt --check --no-method-parens")
    assert(ok and out == "", "already-formatted sugar passes the check: " .. out)

    out, ok = run(dir, "fmt -w")
    assert(ok, "formatting succeeds: " .. out)
    assert(readFile(dir .. "/src/sugar.nupp") == "obj:m({a = 1})\n", "the sugar-form call gains its parens")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A manifest can turn it off for the whole project, without a flag on every
-- invocation, and the flag over that manifest is redundant but not a conflict.
function M.manifestCanTurnMethodParensOffProjectWide()
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" }, ' .. 'fmt = { methodParens = false } }\n',
        ["src/sugar.nupp"] = "obj:m{a = 1}\n",
    })
    local out, ok = run(dir, "fmt --check")
    assert(ok and out == "", "the manifest default leaves the sugar formatted: " .. out)
    out, ok = run(dir, "fmt --check --no-method-parens")
    assert(ok and out == "", "and the flag agrees with it: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

-- --width changes the column a line breaks past, and what counts as formatted moves
-- with it: a line that fits at the default 120 and is left alone there breaks once
-- asked to fit 60, and the broken form is then what --check wants back.
function M.widthBreaksALineOverTheGivenWidth()
    local dir = tempProject({["nupp.lua"] = 'return { include = { "src" } }\n', ["src/wide.nupp"] = WIDE_SIGNATURE,})
    local atDefault, defaultOk = run(dir, "fmt --check")
    assert(defaultOk and atDefault == "", "the signature already fits 120 columns: " .. atDefault)

    local narrow, narrowOk = run(dir, "fmt --width 60 --check")
    assert(not narrowOk and narrow:find("wide.nupp", 1, true), "the same signature does not fit 60: " .. narrow)

    local out, ok = run(dir, "fmt --width 60 -w")
    assert(ok, "formatting at width 60 succeeds: " .. out)
    assert(readFile(dir .. "/src/wide.nupp") ~= WIDE_SIGNATURE, "the parameter list broke onto its own lines")

    local stillNarrow, stillNarrowOk = run(dir, "fmt --width 60 --check")
    assert(stillNarrowOk and stillNarrow == "", "and formatting it again at width 60 changes nothing: " .. stillNarrow)

    local nowDefault, nowDefaultOk = run(dir, "fmt --check")
    assert(
        not nowDefaultOk and nowDefault:find("wide.nupp", 1, true),
        "but the width-60 form is not the width-120 form: " .. nowDefault
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.widthRejectsATooSmallOrNonNumericValue()
    local dir = tempProject({["nupp.lua"] = 'return { include = { "src" } }\n', ["src/x.nupp"] = FORMATTED,})
    local out, ok = run(dir, "fmt --width 5 --check")
    assert(not ok, "a width under 20 is refused")
    assert(out:find("at least 20", 1, true), "and says why: " .. out)
    out, ok = run(dir, "fmt --width columns --check")
    assert(not ok, "a non-numeric width is refused")
    assert(out:find("whole number", 1, true), "and says why: " .. out)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A file that does not parse is reported and nothing is written, whether it was
-- named or reached through the project.
function M.refusesToFormatWhatItCannotParse()
    local broken = "local x = = 1\n"
    local dir = tempProject({
        ["nupp.lua"] = 'return { include = { "src" } }\n',
        ["src/broken.nupp"] = broken,
        ["src/messy.nupp"] = UNFORMATTED,
    })
    local out, ok = run(dir, "fmt -w")
    assert(not ok, "a project with a file that does not parse fails")
    assert(out:find("broken.nupp", 1, true), "and says which file: " .. out)
    assert(readFile(dir .. "/src/broken.nupp") == broken, "the broken file is left exactly as it is")
    assert(readFile(dir .. "/src/messy.nupp") == FORMATTED, "and the rest of the project is still formatted")
    os.execute("rm -rf '" .. dir .. "'")
end

return M
