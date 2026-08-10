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
   assertEq(select(2, code:gsub("entity%.body", "")), 1,
      "the shared path is read once:\n" .. code)
   local positionTemp = code:match(
      "const (__nuppT%d+)= __nuppT%d+%.position")
   assert(positionTemp, code)
   assert(code:find(positionTemp .. ".x", 1, true), code)
   assert(code:find(positionTemp .. ".y", 1, true), code)
   assert(not code:match("const __nuppT%d+= " .. positionTemp .. "%.[xy]"),
      "one-use leaf projections should stay in the call:\n" .. code)
end

function M.sharedPrefixesAreBoundWithoutOneUseLeafTemporaries()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Body",
      "   position: Vec3",
      "   velocity: Vec3",
      "end",
      "local record Entity",
      "   body: Body",
      "end",
      "local events = ''",
      "local function note(value: string): nil events = events .. value end",
      "local position = setmetatable({}, {__index = function(_, key)",
      "   note(key == 'x' and 'x' or 'y')",
      "   return key == 'x' and 1 or 2",
      "end}) as Vec3",
      "local velocity = setmetatable({}, {__index = function(_, key)",
      "   note(key == 'x' and 'X' or 'Y')",
      "   return key == 'x' and 3 or 4",
      "end}) as Vec3",
      "local body = setmetatable({}, {__index = function(_, key)",
      "   note(key == 'position' and 'P' or 'V')",
      "   return key == 'position' and position or velocity",
      "end}) as Body",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   note('B')",
      "   return body",
      "end}) as Entity",
      "local function head(): string note('H') return 'h' end",
      "local function tail(): string note('T') return 't' end",
      "local function update(head: string, px: number, py: number,",
      "   vx: number, vy: number, tail: string): nil",
      "   note('U')",
      "end",
      "update(head(), ...entity.body.position, ...entity.body.velocity, tail = tail())",
      "return events",
   }, "\n"))
   assertEq(answer, "HBPVxyXYTU")
   assertEq(select(2, code:gsub("entity%.body", "")), 1,
      "the common entity.body prefix is bound once:\n" .. code)
   assert(not code:find("(function()", 1, true),
      "a statement call should use locals, not a wrapper:\n" .. code)
   assert(not code:match("const __nuppT%d+= update"),
      "a named callee should remain direct:\n" .. code)
   assert(not code:match("const __nuppT%d+= tail"),
      "the trailing argument suffix should remain direct:\n" .. code)
   assertEq(select(2, code:gsub("const __nuppT%d+= __nuppT%d+%.[xyXY]", "")), 0,
      "projected leaves should remain direct call arguments:\n" .. code)
end

function M.nestedExpansionUsesDirectProjectionsWithoutAWrapper()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local reads = 0",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   reads = reads + 1",
      "   return position",
      "end}) as Entity",
      "local function draw(x: number, y: number): boolean return true end",
      "local enabled = false",
      "local skipped = enabled and draw(...entity.position)",
      "enabled = true",
      "local called = enabled and draw(...entity.position)",
      "return reads",
   }, "\n"))
   assertEq(answer, 2)
   assert(not code:find("(function()", 1, true),
      "a nested expansion must not allocate a wrapper:\n" .. code)
end

function M.nestedSafeExpansionUsesTheNativeSafeCallWithoutAWrapper()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local reads = 0",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   reads = reads + 1",
      "   return position",
      "end}) as Entity",
      "local function add(x: number, y: number): number return x + y end",
      "local maybe: function(number, number) | nil = nil",
      "local skipped = maybe?.(...entity.position)",
      "maybe = add",
      "local called = maybe?.(...entity.position)",
      "return tostring(reads) .. tostring(skipped) .. tostring(called)",
   }, "\n"))
   assertEq(answer, "2nil3")
   assert(code:find("?.", 1, true), code)
   assert(not code:find("(function()", 1, true), code)
end

function M.safeCallStatementUsesGuardsWithoutAnExpressionWrapper()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local reads = 0",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   reads = reads + 1",
      "   return position",
      "end}) as Entity",
      "local function take(x: number, y: number): nil end",
      "local maybe: function(number, number) | nil = nil",
      "maybe?.(...entity.position)",
      "maybe = take",
      "maybe?.(...entity.position)",
      "return reads",
   }, "\n"))
   assertEq(answer, 1)
   assert(code:find("~=nil then", 1, true), code)
   assert(not code:find("(function()", 1, true), code)
end

function M.returnedSafeExpansionUsesEarlyReturnsWithoutAWrapper()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local function add(x: number, y: number): number return x + y end",
      "local maybe: function(number, number) | nil = add",
      "local position = new Vec3 {x = 5, y = 6, z = 7}",
      "local entity = new Entity {position = position}",
      "return maybe?.(...entity.position)",
   }, "\n"))
   assertEq(answer, 11)
   assert(code:find("==nil then return nil", 1, true), code)
   assert(not code:find("(function()", 1, true), code)
end

function M.safeReceiverAndMethodExpansionUsesStagedGuards()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local record Drawer",
      "   draw: function(self: Drawer, x: number, y: number) | nil",
      "end",
      "local reads = 0",
      "local calls = 0",
      "local position = new Vec3 {x = 2, y = 3, z = 4}",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   reads = reads + 1",
      "   return position",
      "end}) as Entity",
      "local drawer: Drawer | nil = nil",
      "drawer?.:draw?.(...entity.position)",
      "drawer = new Drawer {draw = function(_, x: number, y: number): number",
      "   calls = calls + 1",
      "   return x + y",
      "end}",
      "drawer?.:draw?.(...entity.position)",
      "return reads * 10 + calls",
   }, "\n"))
   assertEq(answer, 11)
   assert(code:find("~=nil then", 1, true), code)
   assert(not code:find("(function()", 1, true), code)
end

function M.constructorCallsReuseTheSameExpansionPlan()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local record Point",
      "   x: number",
      "   y: number",
      "   constructor(x: number, y: number)",
      "      self.x = x",
      "      self.y = y",
      "   end",
      "end",
      "local position = new Vec3 {x = 7, y = 8, z = 9}",
      "local entity = new Entity {position = position}",
      "local point = new Point(...entity.position)",
      "return point.x * 10 + point.y",
   }, "\n"))
   assertEq(answer, 78)
   assertEq(select(2, code:gsub("entity%.position", "")), 1, code)
end

function M.callableObjectsReuseTheOrdinaryExpansionPlan()
   local answer = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local record Adder",
      "   metamethod __call: function(self, x: number, y: number): number",
      "end",
      "local adder = setmetatable({}, {__call = function(_, x: number, y: number): number",
      "   return x + y",
      "end}) as Adder",
      "local position = new Vec3 {x = 4, y = 5, z = 6}",
      "local entity = new Entity {position = position}",
      "return adder(...entity.position)",
   }, "\n"))
   assertEq(answer, 9)
end

function M.methodReceiverAndDottedOperandAreEachEvaluatedOnce()
   local answer = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local record Drawer",
      "   function draw(self, x: number, y: number): nil end",
      "end",
      "local receiverReads = 0",
      "local positionReads = 0",
      "local drawer = new Drawer {}",
      "local position = new Vec3 {x = 1, y = 2, z = 3}",
      "local entity = setmetatable({}, {__index = function(_, _)",
      "   positionReads = positionReads + 1",
      "   return position",
      "end}) as Entity",
      "local function getDrawer(): Drawer",
      "   receiverReads = receiverReads + 1",
      "   return drawer",
      "end",
      "getDrawer():draw(...entity.position)",
      "return receiverReads * 10 + positionReads",
   }, "\n"))
   assertEq(answer, 11)
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

function M.aNestedExpansionPreservesItsTrailingResultPack()
   local answer, code = run(vector .. "\n" .. table.concat({
      "local record Entity",
      "   position: Vec3",
      "end",
      "local function pair(): number, number return 3, 4 end",
      "local function total(a: number, b: number, c: number, d: number): number",
      "   return a + b + c + d",
      "end",
      "local position = new Vec3 {x = 1, y = 2, z = 9}",
      "local entity = new Entity {position = position}",
      "return tostring(total(...entity.position, pair()))",
   }, "\n"))
   assertEq(answer, "10")
   assert(not code:find("(function()", 1, true), code)
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
