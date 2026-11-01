local testAssert = require("assert")
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
                testAssert(key >= 1 and key <= #children and key % 1 == 0, "CST children have dense indices")
            end
        end
        testAssert.equal(numeric, #children, "CST children have no holes")
        snapshots[#snapshots + 1] = {node = node, children = children}
    end

    snapshot(result.root)
    testAssert(#snapshots > 50, "fixture covers nested syntax")
    for _, diagnostic in ipairs(check.check(result, "test.nupp", sharedEnv, {})) do
        testAssert(diagnostic.severity ~= "error", diagnostic.code .. ": " .. diagnostic.msg)
    end
    analysis.run(result)
    local body = result.root.blocks[1]
    local facts = analysis.queries(result.analysis).body(body)
    local definition = findName(body, "increment").definition
    testAssert(facts.uses(definition) > 0, "query walks names")
    facts.calledOnly(definition)
    for _, entry in ipairs(snapshots) do
        testAssert.equal(#entry.node, #entry.children, "analysis preserves child count")
        for index, child in ipairs(entry.children) do
            testAssert(rawequal(entry.node[index], child), "analysis preserves child identity and order")
        end
    end
end

function M.emitTypedWalkArtifactsWhenRequested()
    local directory = os.getenv("NUPP_TYPED_CST_ARTIFACTS")
    if not directory then
        return
    end
    local project = require("nupp.tools.vm.project")
    local fs = require("nupp.compiler.fs")
    local json = require("serde.json")
    local report = {}
    for _, module in ipairs({"analysis", "callfacts"}) do
        local relative = "src/nupp/compiler/" .. module .. ".nupp"
        local path = fs.absolute(relative)
        report[module] = {}
        for _, variant in ipairs({"numeric-baseline", "typed"}) do
            local source = variant == "typed" and path or directory .. "/numeric-baseline/" .. relative
            local functions, image = project.inspect(fs.absolute("."), path, assert(fs.readFile(source)))
            local file = assert(io.open(directory .. "/" .. module .. "-" .. variant .. ".listing", "wb"))
            file:write(image)
            file:close()
            local totals = {}
            local rows = {}
            for _, fn in ipairs(functions) do
                local counts = {}
                for _, instruction in ipairs(fn.instructions) do
                    counts[instruction.op] = (counts[instruction.op] or 0) + 1
                    totals[instruction.op] = (totals[instruction.op] or 0) + 1
                end
                rows[#rows + 1] = {name = fn.name, counts = counts}
            end
            report[module][variant] = {totals = totals, functions = rows}
        end
        local before = report[module]["numeric-baseline"].totals
        local after = report[module].typed.totals
        testAssert.equal((after.GetIdxI or 0) - (before.GetIdxI or 0), 8, "each cursor reaches integer indexing")
        testAssert.equal((before.GetIdx or 0) - (after.GetIdx or 0), 8, "generic child indexing disappears")
        testAssert.equal((after.ICmpSLe or 0) - (before.ICmpSLe or 0), 8, "each bound uses integer comparison")
    end
    local file = assert(io.open(directory .. "/mechanism.json", "wb"))
    file:write(json.encodeValue(report))
    file:close()
end

return M
