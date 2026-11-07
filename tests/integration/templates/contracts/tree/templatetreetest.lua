local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template
local exists = fixture.exists
local tempDirectory = fixture.tempDirectory
local remove = fixture.remove
local templateDirectory = fixture.templateDirectory
local planRefuses = fixture.planRefuses

local M = {}

function M.gitDirectoriesArePrunedAtEveryDepth()
    local dir = templateDirectory({
        ["template.lua"] = "return {}",
        ["keep.txt"] = "kept",
        [".git/config"] = "[core]",
        ["vendor/.git/config"] = "[core]",
        [".gitignore"] = "/build/",
    })
    local into = tempDirectory()
    local plan = assert(template.plan({kind = "directory", path = dir}, into))
    local seen = {}
    for _, file in ipairs(plan.files) do
        seen[file.output] = true
    end
    assert(seen["keep.txt"], "an ordinary file is carried")
    assert(seen[".gitignore"], "a .gitignore is carried, being a project file")
    assert(not seen[".git/config"], "the root repository store is pruned")
    assert(not seen["vendor/.git/config"], "and so is a nested one")
    remove(dir)
end

function M.aSymlinkIsReportedRatherThanFollowed()
    local dir = templateDirectory({["template.lua"] = "return {}", ["real.txt"] = "x"})
    os.execute("ln -s /etc/passwd '" .. dir .. "/link.txt'")

    -- Windows has no unprivileged symbolic link, and `ln -s` there copies the
    -- target rather than failing. That leaves an ordinary file, which the walk
    -- is right to carry -- so the case this names cannot be built there, and
    -- asserting on it would be asserting on the copy.
    local linked = false
    for name, kind in assert(require("io.internal.files").list(dir)) do
        linked = linked or (name == "link.txt" and kind == "symlink")
    end
    if not linked then
        remove(dir)
        return require("assert").suite.skip("this platform has no unprivileged symbolic link")
    end

    local into = tempDirectory()
    local plan, err = template.plan({kind = "directory", path = dir}, into)
    testAssert.eq(plan, nil, "a tree holding a link produces no plan")
    assert(err:find("symbolic link", 1, true), err)
    assert(not exists(into), "and nothing was written")
    remove(dir)
end

function M.aDirectoryWithoutATemplateManifestIsNotATemplate()
    local dir = templateDirectory({["some.txt"] = "x"})
    local plan, err = template.plan({kind = "directory", path = dir}, tempDirectory())
    testAssert.eq(plan, nil, "no manifest, no plan")
    assert(err:find("template.lua", 1, true), err)
    remove(dir)
end

function M.aPathLeavingTheDestinationIsRefused()
    -- A bare `..` carries no separator, so it gets past the value check and is
    -- caught by the path check. Both refusals are wanted; this is the one that
    -- only the assembled path can see.
    planRefuses(
        {["template.lua"] = [[return {variables = {up = {default = ".."}}}]], ["${up}/escaped.txt"] = "x",},
        "an escaping path produces no plan",
        "leaves the destination"
    )
end

return M
