local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local env = require("nupp.compiler.project.env").new(require("helpers.paths").tests .. "/..")
local gen = require("nupp.compiler.lua.gen")
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
    local code, problems = gen.generate(tree, "test.nupp")
    assert(#problems == 0)
    assert(assert(loadstring(code))() == "a12")
end

return M
