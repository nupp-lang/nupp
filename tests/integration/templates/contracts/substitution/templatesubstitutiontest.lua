local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template

local M = {}

function M.substitutionFillsDeclaredNames()
    local got = assert(template.substitute("${a}-${b}", {a = "one", b = "two"}, "x"))
    testAssert.eq(got, "one-two", "both names were filled")
end

function M.aDoubledDollarIsALiteralOpener()
    local got = assert(template.substitute("$${name} and ${name}", {name = "x"}, "y"))
    testAssert.eq(got, "${name} and x", "the escape is not re-read as an opener")
end

function M.anUndeclaredNameIsRefusedWithItsFile()
    local got, err = template.substitute("${nope}", {name = "x"}, "src/main.nupp")
    testAssert.eq(got, nil, "an undeclared name substitutes to nothing")
    assert(err:find("src/main.nupp", 1, true), err)
    assert(err:find("${nope}", 1, true), err)
end

return M
