local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template

local M = {}

function M.aBareNameIsABuiltIn()
    local source = assert(template.resolve("app"))
    testAssert.eq(source.kind, "builtin", "app is a built-in")
    testAssert.eq(source.name, "app", "and keeps its name")
end

function M.noArgumentIsTheDefaultTemplate()
    local source = assert(template.resolve(nil))
    testAssert.eq(source.kind, "builtin", "the default is a built-in")
    testAssert.eq(source.name, "app", "and it is app")
end

function M.anUnknownBareNameNamesTheBuiltInsRatherThanGuessing()
    local source, err = template.resolve("nosuchtemplate")
    testAssert.eq(source, nil, "an unknown name resolves to nothing")
    assert(err:find("no built-in template is called", 1, true), err)
    assert(err:find("app", 1, true), "the complaint lists what there is: " .. err)
end

function M.aLeadingDotOrSlashIsADirectory()
    for _, spelling in ipairs({"./here", "../there", "/abs/path"}) do
        local source = assert(template.resolve(spelling))
        testAssert.eq(source.kind, "directory", spelling .. " is a directory")
    end
end

function M.ownerRepoIsGitHub()
    local source = assert(template.resolve("nupp-lang/templates"))
    testAssert.eq(source.kind, "remote", "owner/repo is remote")
    testAssert.eq(source.url, "https://github.com/nupp-lang/templates", "expanded to GitHub")
    testAssert.eq(source.subdir, nil, "with no subdirectory")
end

function M.ownerRepoCarriesASubdirectoryAndARevision()
    local source = assert(template.resolve("tecs-engine/tecs/templates/game@v2.0"))
    testAssert.eq(source.url, "https://github.com/tecs-engine/tecs", "the repository")
    testAssert.eq(source.subdir, "templates/game", "the path within it")
    testAssert.eq(source.rev, "v2.0", "the revision")
end

function M.aFullUrlIsUsedAsGiven()
    local source = assert(template.resolve("git@github.com:owner/repo.git"))
    testAssert.eq(source.kind, "remote", "an ssh spelling is remote")
    testAssert.eq(source.url, "git@github.com:owner/repo.git", "and is not rewritten")
    -- An `@` is ordinary punctuation in a URL, so it is not read as a revision.
    testAssert.eq(source.rev, nil, "the @ in the URL is not a revision")
end

function M.aRevisionGivenTwiceIsRefused()
    local source, err = template.resolve("owner/repo@v1", nil, "v2")
    testAssert.eq(source, nil, "two revisions resolve to nothing")
    assert(err:find("given twice", 1, true), err)
end

function M.fromRefusesATemplateArgumentAndARevision()
    local _, both = template.resolve("app", "/some/dir")
    assert(both:find("one too many", 1, true), both)
    local _, rev = template.resolve(nil, "/some/dir", "v1")
    assert(rev:find("no meaning", 1, true), rev)
end

function M.aBuiltInHasNoRevisions()
    local source, err = template.resolve("app", nil, "v1")
    testAssert.eq(source, nil, "a pinned built-in resolves to nothing")
    assert(err:find("no revisions", 1, true), err)
end

return M
