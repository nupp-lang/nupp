local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local hash = fixture.hash
local json = fixture.json
local write = fixture.write
local read = fixture.read
local tempProject = fixture.tempProject
local remove = fixture.remove
local answerFrom = fixture.answerFrom

local M = {}

function M.exportedLayoutChangesInvalidateOnlyTheirReaders()
    local model = [[
local models = {}
struct models.Wire
    tag: int8
    value: int32
end
function models.body(): number return 1 end
return models
]]
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"},
   layoutTarget = "x86_64-unknown-linux-gnu"}}
]],
        ["src/main.nupp"] = [[
local models = require("models")
return comptime do return types.sizeof(models.Wire) end
]],
        ["src/models.nupp"] = model,
    })

    local cold = {}
    testAssert.eq(project.build(dir, {stats = cold}), 0)
    testAssert.eq(cold.checkedModules, 2, "the layout reader and declaration check cold")
    assert(read(dir .. "/out/main.lua"):find("return 8", 1, true), "the first layout was folded")

    write(dir .. "/src/models.nupp", model:gsub("return 1", "return 2"))
    local body = {}
    testAssert.eq(project.build(dir, {stats = body}), 0)
    testAssert.eq(body.checkedModules, 1, "a body edit checks only its module")
    testAssert.eq(body.reusedModules, 1, "the layout reader cuts off at the interface")

    write(dir .. "/src/models.nupp", model:gsub("value: int32", "value: number"))
    local changed = {}
    testAssert.eq(project.build(dir, {stats = changed}), 0)
    testAssert.eq(changed.checkedModules, 2, "a field layout edit rechecks its reader")
    assert(read(dir .. "/out/main.lua"):find("return 16", 1, true), "the changed layout replaced the old folded result")
    remove(dir)
end

return M
