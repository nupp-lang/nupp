local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local fmt = require("nupp.compiler.fmt")

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
   for j, diagnostic in ipairs(check.check(result, "test.g.nupp")) do
      out[j] = diagnostic.code
   end
   return table.concat(out, " ")
end

local function clean(source)
   assertEq(diagnostics(source), "", "expected clean check for:\n" .. source)
end

local function run(source)
   local result = parsed(source)
   local checked = check.check(result, "test.g.nupp")
   assertEq(#checked, 0, checked[1] and checked[1].msg
      or "unexpected check diagnostic")
   local code, problems = gen.generate(result, "test.g.nupp")
   assertEq(#problems, 0, problems[1] and problems[1].msg
      or "unexpected generation diagnostic")
   local chunk, problem = loadstring(code, "@argument_expansion_test")
   assert(chunk, tostring(problem) .. "\n" .. code)
   return chunk(), code
end

local vector = table.concat({
   "local record Vec3",
   "   x: number",
   "   y: number",
   "   z: number",
   "   expands (x, y)",
   "   expands (x, y, z)",
   "end",
}, "\n")

local M = {}

function M.syntaxRoundTripsAndRecordsArgumentKinds()
   local source = vector .. "\ndraw(...position, color = 'red')"
   local result = parsed(source)
   assertEq(require("nupp.compiler.cst").textOf(result.root), source)
   local call = result.root.blocks[1].stats[2].expr
   assertEq(call.args.exprs[1].kind, "expandArg")
   assertEq(call.args.exprs[2].kind, "namedArg")
   assertEq(result.root.blocks[1].stats[1].entries[4].kind,
      "expansionDecl")
end

function M.expansionAndNamedSuffixEraseToAPositionalCall()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local function draw(x: number, y: number, color: string?): string",
      "   return tostring(x) .. tostring(y) .. (color or '')",
      "end",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "return draw(...position, color = 'r')",
   }, "\n"))
   assertEq(answer, "12r")
   assert(code:find("draw ( position .x , position .y , 'r' )", 1, true),
      code)
   assert(not code:find("expands", 1, true), code)
end

function M.dottedPlaceExpansionLowersThroughEmbeddedRecords()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Body",
      "   position: Vec3",
      "end",
      "local record Entity",
      "   body: Body",
      "end",
      "local function draw(x: number, y: number, color: string?): string",
      "   return tostring(x) .. tostring(y) .. (color or '')",
      "end",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "local body = new Body {position = position}",
      "local entity = new Entity {body = body}",
      "return draw(...entity.body.position, color = 'r')",
   }, "\n"))
   assertEq(answer, "12r")
   assert(code:find(
      "draw ( entity . body . position .x , entity . body . position .y , 'r' )",
      1,
      true
   ), code)
end

function M.expansionRejectsEffectfulAndComputedPlaceOperands()
   local declaration = vector .. "\n" .. table.concat({
      "local function draw(x: number, y: number): nil end",
      "local function make(): Vec3",
      "   return new Vec3 {x = 1, y = 2, z = 3}",
      "end",
   }, "\n")
   assertEq(diagnostics(declaration .. "\ndraw(...make())"), "NUPP2006")
   assertEq(diagnostics(declaration .. "\n" .. table.concat({
      "local positions: {Vec3} = {make()}",
      "draw(...positions[1])",
   }, "\n")), "NUPP2006")
end

function M.namedArgumentsCanFillAnOptionalGap()
   local answer = run(table.concat({
      "local function label(value: number, prefix: string?, suffix: string?): string",
      "   return tostring(prefix) .. tostring(value) .. tostring(suffix)",
      "end",
      "return label(value = 2, suffix = '!')",
   }, "\n"))
   assertEq(answer, "nil2!")
end

function M.namedSuffixSelectsOneOfSeveralExpansionArities()
   clean(vector .. "\n" .. table.concat({
      "local function consume(x: number, y: number, z: number?): nil end",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "consume(...position, z = 9)",
   }, "\n"))
   assertEq(diagnostics(vector .. "\n" .. table.concat({
      "local function consume(x: number, y: number, z: number?): nil end",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "consume(...position)",
   }, "\n")), "NUPP2126")
end

function M.aTrailingOrdinaryCallStillExpandsItsResultPack()
   local answer = run(vector .. "\n" .. table.concat({
      "local function pair(): number, number return 3, 4 end",
      "local function total(a: number, b: number, c: number, d: number): number",
      "   return a + b + c + d",
      "end",
      "local position = new Vec3 {x = 1, y = 2, z = 9}",
      "return total(...position, pair())",
   }, "\n"))
   assertEq(answer, 10)
end

function M.interfacesExposeInheritedExpansionCapabilitiesToGenerics()
   clean(table.concat({
      "local interface XY",
      "   readonly x: number",
      "   readonly y: number",
      "   expands (x, y)",
      "end",
      "local interface XYZ is XY",
      "   readonly z: number",
      "   expands (x, y, z)",
      "end",
      "local record Point is XYZ",
      "   x: number",
      "   y: number",
      "   z: number",
      "end",
      "local function draw(x: number, y: number, color: string?): nil end",
      "local function render<T is XY>(point: T, color: string): nil",
      "   draw(...point, color = color)",
      "end",
   }, "\n"))
end

function M.namedLabelsParticipateInOverloadSelection()
   clean(table.concat({
      "local type Parse = function(value: number): string",
      "   & function(text: string): boolean",
      "local parse: Parse = nil as any",
      "local word: string = parse(value = 1)",
      "local accepted: boolean = parse(text = 'yes')",
   }, "\n"))
end

function M.namedLabelsSelectMethodBodiesWithoutADispatcher()
   local answer = run(table.concat({
      "local record Decoder",
      "   function decode(self, value: number): string return 'n' end",
      "   function decode(self, text: string): string return 's' end",
      "end",
      "local decoder = new Decoder {}",
      "return decoder:decode(value = 1) .. decoder:decode(text = 'x')",
   }, "\n"))
   assertEq(answer, "ns")
end

function M.staticInterfaceViewHidesUndeclaredArities()
   assertEq(diagnostics(table.concat({
      "local interface XY",
      "   x: number",
      "   y: number",
      "   expands (x, y)",
      "end",
      "local function take3(x: number, y: number, z: number): nil end",
      "local point: XY = {x = 1, y = 2}",
      "take3(...point)",
   }, "\n")), "NUPP2125")
end

function M.invalidDeclarationsAndArgumentBindingAreRejected()
   assertEq(diagnostics(table.concat({
      "local record Bad",
      "   x: number",
      "   expands (x, x)",
      "end",
   }, "\n")), "NUPP2118")
   assertEq(diagnostics(table.concat({
      "local function f(x: number, y: number): nil end",
      "f(y = 2, x = 1)",
   }, "\n")), "NUPP2125")
   assertEq(diagnostics(table.concat({
      "local function f(x: number): nil end",
      "f(nope = 1)",
   }, "\n")), "NUPP2125")
   assertEq(diagnostics("unknown(x = 1)"), "NUPP2006")
end

function M.formattingKeepsExpansionTightAndNamesReadable()
   assertEq(fmt.format("draw( ... position,color='red')"),
      "draw(...position, color = 'red')\n")
   assertEq(fmt.format("local record P\nx:number\ny:number\nexpands(x,y)\nend"),
      "local record P\n    x: number\n    y: number\n    expands (x, y)\nend\n")
   assertEq(fmt.format("draw(...entity.body.position,color='red')"),
      "draw(...entity.body.position, color = 'red')\n")
end

return M
