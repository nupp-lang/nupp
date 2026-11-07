local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template
local NUPP = fixture.NUPP
local exists = fixture.exists
local write = fixture.write
local tempDirectory = fixture.tempDirectory
local remove = fixture.remove
local shell = fixture.shell
local SCAFFOLD_STORE = fixture.SCAFFOLD_STORE
local repository = fixture.repository

local M = {}

function M.aRemoteScaffoldsIdenticallyToTheSameTreeOnDisk()
    local dir, url = repository({
        ["template.lua"] = [[return {variables = {who = {default = "world"}}}]],
        ["src/main.nupp"] = 'print("hello ${who} from ${name}")',
        [".gitignore"] = "/build/",
    })
    local fromDisk = tempDirectory()
    assert(template.write(assert(template.plan({kind = "directory", path = dir}, fromDisk, {name = "sample"}))))

    local scratch = tempDirectory()
    os.execute("mkdir -p '" .. scratch .. "'")
    local source = assert(template.resolve(url))
    assert(template.fetch(source, scratch))
    assert(source.commit and #source.commit == 40, "the fetch resolved a commit")
    local fetched = tempDirectory()
    assert(template.write(assert(template.plan(source, fetched, {name = "sample"}))))

    local _, diff = shell("diff -r '" .. fromDisk .. "' '" .. fetched .. "'")
    testAssert.eq(diff, "", "a fetched tree scaffolds exactly as the directory does")
    remove(dir)
    remove(scratch)
    remove(fromDisk)
    remove(fetched)
end

function M.aRemoteTemplateCanLiveInASubdirectory()
    local dir, url = repository({
        ["templates/game/template.lua"] = "return {}",
        ["templates/game/main.nupp"] = 'print("${name}")',
        ["README.md"] = "the repository, not the template",
    })
    local scratch = tempDirectory()
    os.execute("mkdir -p '" .. scratch .. "'")
    local source = {kind = "remote", url = url, subdir = "templates/game"}
    assert(template.fetch(source, scratch))
    local into = tempDirectory()
    local plan = assert(template.plan(source, into, {name = "mygame"}))
    testAssert.eq(#plan.files, 1, "only the subdirectory was taken")
    testAssert.eq(plan.files[1].output, "main.nupp", "and it is the template's own file")
    remove(dir)
    remove(scratch)
    remove(into)
end

function M.aTreeThatIsNotATemplateIsRefusedAfterFetching()
    local dir, url = repository({["README.md"] = "not a template"})
    local scratch = tempDirectory()
    os.execute("mkdir -p '" .. scratch .. "'")
    local fetched, err = template.fetch({kind = "remote", url = url}, scratch)
    testAssert.eq(fetched, nil, "a repository without a manifest is not a template")
    assert(err:find("template.lua", 1, true), err)
    remove(dir)
    remove(scratch)
end

function M.aRemoteTemplateNeverCausesItsOwnManifestToBeLoaded()
    -- The executable form of the boundary. The scaffolded `nupp.lua` writes a
    -- sentinel when it is loaded, and `check` is what loads it. A local template
    -- gets that step and a fetched one does not, so the sentinel is the evidence
    -- that a fetched tree ran nothing.
    local sentinel = tempDirectory()
    local files = {
        ["template.lua"] = [[return {after = {"check"}}]],
        [
            "nupp.lua"
        ] = (
            [[
         local f = io.open(%q, "w")
         if f then f:write("loaded") f:close() end
         return {include = {"src"}}
      ]]
        ):format(sentinel),
        ["src/mod.nupp"] = "return {}",
    }
    local dir, url = repository(files)

    local localPlan = assert(template.plan({kind = "directory", path = dir}, tempDirectory()))
    testAssert.eq(#localPlan.steps, 1, "a local template keeps its step")
    testAssert.eq(localPlan.steps[1], "check", "and it is check")
    testAssert.eq(#localPlan.dropped, 0, "with nothing dropped")

    local scratch = tempDirectory()
    os.execute("mkdir -p '" .. scratch .. "'")
    local source = assert(template.resolve(url))
    assert(template.fetch(source, scratch))
    local remotePlan = assert(template.plan(source, tempDirectory()))
    testAssert.eq(#remotePlan.steps, 0, "a fetched template keeps no step that loads it")
    testAssert.eq(remotePlan.dropped[1], "check", "and says which one it lost")

    -- And the step itself, run for real, is what would have written the sentinel.
    local into = tempDirectory()
    assert(template.write(assert(template.plan({kind = "directory", path = dir}, into))))
    assert(not exists(sentinel), "nothing has loaded the manifest yet")
    template.step("check", into, NUPP, {NUPP_CACHE_DIR = SCAFFOLD_STORE})
    assert(exists(sentinel), "the check step loads the scaffolded manifest, which is why a remote may not ask for it")

    remove(dir)
    remove(scratch)
    remove(into)
    os.remove(sentinel)
end

function M.gitIsTheOneStepARemoteKeeps()
    local dir, url = repository({
        ["template.lua"] = [[return {after = {"git", "check", "build", "test"}}]],
        ["a.txt"] = "x",
    })
    local scratch = tempDirectory()
    os.execute("mkdir -p '" .. scratch .. "'")
    local source = assert(template.resolve(url))
    assert(template.fetch(source, scratch))
    local plan = assert(template.plan(source, tempDirectory()))
    testAssert.eq(#plan.steps, 1, "one step survives")
    testAssert.eq(plan.steps[1], "git", "and it is the one that runs no supplied code")
    testAssert.eq(#plan.dropped, 3, "the other three are dropped")
    remove(dir)
    remove(scratch)
end

return M
