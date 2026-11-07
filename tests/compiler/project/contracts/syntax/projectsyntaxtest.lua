local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local deps = fixture.deps
local buildSyntax = fixture.buildSyntax
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.pkgConfigFlagsUseShellWordQuotingWithoutRunningAShell()
    local words = assert(buildSyntax.shellWords([[-I"include dir" '-DNAME=two words' plain\ flag "" ab"cd"'ef']]))
    testAssert.eq(
        table.concat(words, "\0"),
        table.concat({"-Iinclude dir", "-DNAME=two words", "plain flag", "", "abcdef"}, "\0")
    )
    testAssert.eq(#assert(buildSyntax.shellWords(" \t\n")), 0)
    local malformed = buildSyntax.shellWords([["unclosed]])
    testAssert.eq(malformed, nil)
end

function M.shellWordsRejectIncompleteQuotingAndEscapes()
    testAssert.eq(buildSyntax.shellWords("plain\\"), nil, "a trailing escape needs a byte")
    testAssert.eq(buildSyntax.shellWords("'unclosed"), nil, "a single quote needs its closing quote")
    testAssert.eq(buildSyntax.shellWords('"unclosed'), nil, "a double quote needs its closing quote")
    testAssert.eq(buildSyntax.shellWords('"unclosed\\'), nil, "an escape cannot close a double quote")
    local words = assert(buildSyntax.shellWords([["" '' a""b c''d]]))
    testAssert.eq(#words, 4, "empty quoted words are retained")
    testAssert.eq(table.concat(words, "\0"), table.concat({"", "", "ab", "cd"}, "\0"))
end

function M.makeDepfilesPreserveEscapedPathsAndContinuations()
    local paths = assert(buildSyntax.depfile("nupp_header: one.h two\\ three.h \\\n four\\#five.h one.h # ignored\n"))
    testAssert.eq(table.concat(paths, "\0"), table.concat({"one.h", "two three.h", "four#five.h", "one.h"}, "\0"))
    testAssert.eq(buildSyntax.depfile("not a depfile"), nil)
end

function M.makeDepfilesHandleEscapedTargetsCommentsAndCrLf()
    local paths = assert(buildSyntax.depfile("generated\\:header: one\\:name.h two\\#name.h # ignored.h\r\n"))
    testAssert.eq(table.concat(paths, "\0"), "one:name.h\0two#name.h", "only unescaped hash starts a comment")
    local continued = assert(buildSyntax.depfile("header: one.h\\\r\n two.h\r\n"))
    testAssert.eq(table.concat(continued, "\0"), "one.h\0two.h", "CRLF continuation is whitespace")
    testAssert.eq(buildSyntax.depfile("header: path\\"), nil, "a trailing dependency escape needs a byte")
end

function M.buildGlobsTreatDoubleStarAsZeroOrMoreDirectories()
    local component = buildSyntax.glob("src/*/file?.nupp")
    assert(component("src/one/file1.nupp"))
    assert(not component("src/one/two/file1.nupp"))
    assert(not component("src/one/file12.nupp"))
    local directories = buildSyntax.glob("src/**/file.nupp")
    assert(directories("src/file.nupp"))
    assert(directories("src/one/two/file.nupp"))
    assert(not directories("src/one/two/not-file.nupp"))

    local dir = tempProject({
        ["src/root.nupp"] = "return 1\n",
        ["src/nested/child.nupp"] = "return 2\n",
        ["src/nested/child.lua"] = "return 3\n",
    })
    local matches = deps.expandGlob(dir, "src/**/*.nupp")
    table.sort(matches)
    testAssert.eq(#matches, 2)
    testAssert.eq(matches[1], dir .. "/src/nested/child.nupp")
    testAssert.eq(matches[2], dir .. "/src/root.nupp")
    remove(dir)
end

return M
