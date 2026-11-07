local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template
local write = fixture.write
local tempDirectory = fixture.tempDirectory
local remove = fixture.remove
local templateDirectory = fixture.templateDirectory
local planRefuses = fixture.planRefuses

local M = {}

function M.aValueHoldingASeparatorIsRefusedByName()
    planRefuses(
        {["template.lua"] = [[return {variables = {sub = {default = "a/b"}}}]], ["${sub}.txt"] = "x",},
        "a separator in a value produces no plan",
        "may not contain a path separator"
    )
end

function M.twoFilesBecomingOnePathIsRefused()
    planRefuses(
        {
            ["template.lua"] = [[return {variables = {a = {default = "same"}}}]],
            ["${a}.txt"] = "one",
            ["same.txt"] = "two",
        },
        "a collision produces no plan",
        "both become"
    )
end

function M.aDestinationIsFreeWhenItHoldsNothingButGit()
    local dir = templateDirectory({["template.lua"] = "return {}", ["a.txt"] = "x"})
    local source = {kind = "directory", path = dir}

    local empty = tempDirectory()
    os.execute("mkdir -p '" .. empty .. "'")
    assert(template.plan(source, empty), "init accepts a directory somebody has already made")

    local withGit = tempDirectory()
    os.execute("mkdir -p '" .. withGit .. "/.git'")
    assert(template.plan(source, withGit), "a directory holding only .git is the ordinary case")

    local occupied = tempDirectory()
    os.execute("mkdir -p '" .. occupied .. "'")
    write(occupied .. "/something.txt", "x")
    local no, occupiedErr = template.plan(source, occupied)
    testAssert.eq(no, nil, "a directory with a file in it is refused")
    assert(occupiedErr:find("not empty", 1, true), occupiedErr)

    remove(dir)
    remove(empty)
    remove(withGit)
    remove(occupied)
end

return M
