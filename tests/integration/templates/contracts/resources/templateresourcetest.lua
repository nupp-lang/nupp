local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template
local ROOT = fixture.ROOT
local write = fixture.write
local tempDirectory = fixture.tempDirectory
local remove = fixture.remove
local shell = fixture.shell

local M = {}

function M.everyBuiltInTemplateFileIsStagedByTheManifest()
    -- The resource list in nupp.lua is written by hand, and a template file added
    -- without a line there is one every released binary quietly lacks. This is
    -- the check that turns that into a failure here instead.
    local manifest = assert(loadfile(ROOT .. "/nupp.lua"))()
    local staged = {}
    for _, target in pairs(manifest.build.targets) do
        for _, resource in ipairs(target.resources or {}) do
            if type(resource) == "table" and resource.source:match("^templates/") then
                staged[resource.source] = true
            end
        end
    end
    -- A template is a project, and running one leaves the things running a project
    -- leaves: a dependency tree, a build directory. Opening the tree in a file
    -- browser leaves a `.DS_Store`. All of it is ignored by the repository and is
    -- nobody's template source, so the listing is what the repository would take:
    -- tracked files, and untracked ones the ignore rules do not exclude.
    local _, listing = shell("cd '" .. ROOT .. "' && git ls-files --cached --others --exclude-standard templates")
    local missing = {}
    for relative in listing:gmatch("[^\n]+") do
        if not staged[relative] then
            missing[#missing + 1] = relative
        end
    end
    testAssert.eq(
        #missing,
        0,
        "template files missing from the resource list in nupp.lua:\n  " .. table.concat(missing, "\n  ")
    )
end

function M.theBuiltInsAreTheTemplatesThatAreThere()
    local names = template.builtins()
    testAssert.eq(#names, 2, "two built-ins ship")
    testAssert.eq(names[1], "app", "app is one")
    testAssert.eq(names[2], "lib", "and lib is the other")
    assert(#template.builtinDescription("app") > 0, "each says what it is for")
end

function M.aBuiltInReadsTheSameFromTheCarriedTreeAsFromTheDirectory()
    -- The equivalence the whole design rests on: what a built-in scaffolds and
    -- what the same directory scaffolds through --from are the same bytes.
    local carried = tempDirectory()
    local fromDisk = tempDirectory()
    assert(template.write(assert(template.plan(assert(template.resolve("lib")), carried, {name = "sample"}))))
    assert(
        template.write(
            assert(
                template.plan({kind = "directory", path = ROOT .. "/templates/lib"}, fromDisk, {
                    name = "sample"
                })
            )
        )
    )
    local _, diff = shell("diff -r '" .. carried .. "' '" .. fromDisk .. "'")
    testAssert.eq(diff, "", "the carried tree and the directory scaffold identically")
    remove(carried)
    remove(fromDisk)
end

return M
