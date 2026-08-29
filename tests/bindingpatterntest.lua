local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")
local cst = require("nupp.compiler.cst")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function parsed(source)
   local result = parser.parse(source, "test.g.nupp")
   assertEq(#result.errors, 0, result.errors[1] and result.errors[1].msg
      or "unexpected syntax error")
   return result
end

local function diagnostics(source)
   local result = parsed(source)
   local out = {}
   for index, diagnostic in ipairs(check.check(result, "test.g.nupp")) do
      out[index] = diagnostic.code
   end
   return table.concat(out, " ")
end

local function run(source)
   local result = parsed(source)
   local checked = check.check(result, "test.g.nupp")
   assertEq(#checked, 0, checked[1] and checked[1].msg
      or "unexpected check diagnostic")
   local code, problems = gen.generate(result, "test.g.nupp")
   assertEq(#problems, 0, problems[1] and problems[1].msg
      or "unexpected generation diagnostic")
   local chunk, problem = loadstring(code, "@binding_pattern_test")
   assert(chunk, tostring(problem) .. "\n" .. code)
   return chunk(), code
end

local pair = table.concat({
   "local record Pair",
   "   x: number",
   "   y: number",
   "end",
}, "\n")

local M = {}

function M.syntaxRoundTripsAndRecordsAliasesAndAnnotations()
   local source = pair .. "\nconst {x: number, y as vertical: number} = point"
   local result = parsed(source)
   assertEq(cst.textOf(result.root), source)
   local declaration = result.root.blocks[1].stats[2]
   assertEq(declaration.kind, "localStmt")
   assertEq(declaration.isConst, true)
   assertEq(#declaration.pattern, 2)
   assertEq(declaration.pattern[1].sourceName.text, "x")
   assertEq(declaration.pattern[2].sourceName.text, "y")
   assertEq(declaration.pattern[2].alias.text, "vertical")
   assertEq(declaration.names[2].text, "vertical")
   assert(declaration.types[1] and declaration.types[2])
end

function M.sourceAndFieldsEvaluateOnceFromLeftToRight()
   local answer, code = run(pair .. "\n" .. table.concat({
      "local calls = 0",
      "local fields = ''",
      "local point = setmetatable({}, {__index = function(_, key)",
      "   fields = fields .. key",
      "   return key == 'x' and 3 or 4",
      "end}) as Pair",
      "local function source(): Pair calls += 1 return point end",
      "local {x, y as vertical} = source()",
      "return tostring(calls) .. fields .. tostring(x) .. tostring(vertical)",
   }, "\n"))
   assertEq(answer, "1xy34")
   assertEq(select(2, code:gsub("= source %( %)", "")), 1, code)
   assert(code:match(
      "local%s+x%s*,%s*vertical%s*=%s*__nuppT%d+%.x%s*,%s*__nuppT%d+%.y"), code)
end

function M.constBindingsStayImmutableAndKeepTheirFieldTypes()
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local point = new Pair(x = 1, y = 2)",
      "const {x, y as vertical} = point",
      "x = 3",
      "vertical = 4",
   }, "\n")), "NUPP2008 NUPP2008")
end

function M.annotationsCheckTheSelectedField()
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local point = new Pair(x = 1, y = 2)",
      "const {x: string} = point",
   }, "\n")), "NUPP2001")
end

function M.missingAndRepeatedSelectionsAreDiagnosed()
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local point = new Pair(x = 1, y = 2)",
      "local {z} = point",
   }, "\n")), "NUPP2004")
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local point = new Pair(x = 1, y = 2)",
      "local {x, x as other} = point",
   }, "\n")), "NUPP2006")
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local point = new Pair(x = 1, y = 2)",
      "local {x as value, y as value} = point",
   }, "\n")), "NUPP2006")
end

function M.patternsDoNotPartiallyMoveOwnedContainers()
   assertEq(diagnostics(pair .. "\n" .. table.concat({
      "local function close(takes value: Pair): nil end",
      "local function open(): affine(Pair, close)",
      "   return new Pair(x = 1, y = 2)",
      "end",
      "const owned = open()",
      "local {x} = owned",
      "print(x)",
      "drop(owned)",
   }, "\n")), "NUPP2603")
end

function M.formattingUsesReadableBraces()
   assertEq(fmt.format("const{x,y as vertical}=point"),
      "const {x, y as vertical} = point\n")
   assertEq(fmt.format("draw({x,y}=point,color='blue')"),
      "draw({x, y} = point, color = 'blue')\n")
end

function M.oldAndAliasedPlucksCarryWholeFixes()
   local old = parser.parse("draw((x, y) = point)", "test.g.nupp")
   assertEq(#old.errors, 1)
   assertEq(old.errors[1].code, "NUPP1002")
   assertEq(old.errors[1].fixes[1].title, "use a braced pluck")
   assertEq(old.errors[1].fixes[1].edits[1].newText, "{")
   assertEq(old.errors[1].fixes[1].edits[2].newText, "}")

   local aliased = parser.parse("draw({y as color} = point)", "test.g.nupp")
   assertEq(#aliased.errors, 1)
   assertEq(aliased.errors[1].code, "NUPP1002")
   assertEq(aliased.errors[1].fixes[1].title, "use a named argument")
   assertEq(aliased.errors[1].fixes[1].edits[1].newText,
      "color = point.y")
end

return M
