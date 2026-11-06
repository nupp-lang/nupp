local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local env = require("nupp.compiler.project.env").new(require("helpers.paths").tests .. "/..")
local program = require("program")
local M = {}

function M.theRetiredNamespaceIsNotDeclared()
    local tree = parser.parse("return string.buffer.new()", "test.nupp")
    local found = false
    for _, diagnostic in ipairs(check.check(tree, "test.nupp", env)) do
        found = found or diagnostic.severity == "error"
    end
    assert(found)
    assert(require("nupp.compiler.bundled").source("/decls/stringbuffer.d.nupp") == nil)
end

function M.theCanonicalBufferWorksWithoutARequire()
    local tree = parser.parse([[local b = io.Buffer.create()
b:put("a", 12)
return b:tostring()]], "test.nupp")
    for _, diagnostic in ipairs(check.check(tree, "test.nupp", env)) do
        assert(diagnostic.severity ~= "error", diagnostic.msg)
    end
    assert(program.run(tree, "buffer_namespace_test", "test.nupp") == "a12")
end

function M.theRetiredTextFacadeIsUnavailable()
    local tree = parser.parse("return nupp.text.newbuffer()\n", "test.nupp")
    assert(#tree.errors == 0)
    local found = false
    for _, diagnostic in ipairs(check.check(tree, "test.nupp", env)) do
        found = found or diagnostic.severity == "error"
    end
    assert(found, "the retired text facade is not a public namespace")
end

return M
