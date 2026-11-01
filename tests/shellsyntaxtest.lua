local test = require("assert")
local syntax = require("nupp.compiler.shellsyntax")
local M = {}

function M.shellWordsPreserveQuotingAndEmptyArguments()
    test.deepeq(syntax.shellWords([[-I"include dir" '-DNAME=two words' plain\ flag "" ab"cd"'ef']]), {
        "-Iinclude dir",
        "-DNAME=two words",
        "plain flag",
        "",
        "abcdef"
    })
    test.deepeq(syntax.shellWords(" \t\r\n\v\f"), {})
    test.deepeq(syntax.shellWords("'a\\b' \"a\\b\" a\\\nb"), {"a\\b", "ab", "a\nb"})
    for _, source in ipairs({'"unclosed', "'unclosed", "trailing\\", '"trailing\\'}) do
        test.eq(syntax.shellWords(source), nil, source)
    end
end

function M.depfilesPreserveEscapedPathsAndContinuations()
    test.deepeq(syntax.depfile("nupp_header: one.h two\\ three.h \\\n four\\#five.h one.h # ignored\n"), {
        "one.h",
        "two three.h",
        "four#five.h",
        "one.h"
    })
    test.deepeq(syntax.depfile("escaped\\:target: \\\r\n first.h\\\n second.h"), {"first.h", "second.h"})
    test.deepeq(syntax.depfile(":"), {})
    test.eq(syntax.depfile("not a depfile"), nil)
    test.eq(syntax.depfile("target: trailing\\"), nil)
    test.eq(syntax.depfile("target: # comment\nextra"), nil)
end

function M.globsRespectPathSegments()
    local component = syntax.glob("src/*/file?.nupp")
    assert(component("src/one/file1.nupp"))
    assert(not component("src/one/two/file1.nupp"))
    assert(not component("src/one/file12.nupp"))
    local directories = syntax.glob("src/**/file.nupp")
    assert(directories("src/file.nupp"))
    assert(directories("src/one/two/file.nupp"))
    assert(not directories("src/one/two/not-file.nupp"))
    assert(syntax.glob("")("") and not syntax.glob("")("x"))
end

return M
