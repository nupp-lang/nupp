local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("nupp.compiler.check")
local envMod = require("nupp.compiler.project.env")
local analysis = require("nupp.compiler.analysis")
local cst = require("nupp.compiler.syntax.cst")
local sharedEnv = envMod.new(".")
local M = {}

local function findName(node, text)
    if cst.isToken(node) then
        return node.kind == "name" and node.text == text and node or nil
    end
    for _, child in ipairs(node) do
        local found = findName(child, text)
        if found then
            return found
        end
    end

    return nil
end

function M.denseChildrenRemainStableAcrossAnalysisAndQueries()
    local result = parser.parse(
        [[
local function increment(values: {number}, index: integer): number
   local alias = values
   if index >= 1 and index <= #alias then
      alias[index] = alias[index] + 1
      return alias[index]
   end
   return 0
end
local function forward(values: {number}, index: integer): number
   local function nested(): number
      return increment(values, index)
   end
   return nested()
end
return {increment = increment, forward = forward}
]],
        "test.nupp"
    )
    testAssert.equal(#result.errors, 0, "dense child fixture parses")
    local snapshots = {}

    local function snapshot(node)
        if cst.isToken(node) then
            return
        end
        local children = {}
        for index, child in ipairs(node) do
            children[index] = child
            snapshot(child)
        end
        local numeric = 0
        for key in pairs(node) do
            if type(key) == "number" then
                numeric = numeric + 1
                testAssert.assert(key >= 1 and key <= #children and key % 1 == 0, "CST children have dense indices")
            end
        end
        testAssert.equal(numeric, #children, "CST children have no holes")
        snapshots[#snapshots + 1] = {node = node, children = children}
    end

    snapshot(result.root)
    testAssert.assert(#snapshots > 50, "fixture covers nested syntax")
    for _, diagnostic in ipairs(check.check(result, "test.nupp", sharedEnv, {})) do
        testAssert.assert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    analysis.run(result)
    local body = result.root.blocks[1]
    local facts = analysis.queries(result.analysis).body(body)
    local definition = findName(body, "increment").definition
    testAssert.assert(facts.uses(definition) > 0, "query walks names")
    facts.calledOnly(definition)
    for _, entry in ipairs(snapshots) do
        testAssert.equal(#entry.node, #entry.children, "analysis preserves child count")
        for index, child in ipairs(entry.children) do
            testAssert.assert(rawequal(entry.node[index], child), "analysis preserves child identity and order")
        end
    end
end

return M
