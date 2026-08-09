local parser = require("nupp.parser")
local cst = require("nupp.cst")
local check = require("fragment")
local envMod = require("nupp.env")
local T = require("nupp.types")
local relations = require("nupp.relations")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

local function diagnostics(source)
   env.loaded = {}
   local parsed = parser.parse(source, "test.g.nupp")
   assertEq(#parsed.errors, 0, "syntax: "
      .. (parsed.errors[1] and parsed.errors[1].msg or ""))
   return check.check(parsed, "test", env)
end

local function codes(source)
   local out = {}
   for j, diagnostic in ipairs(diagnostics(source)) do out[j] = diagnostic.code end
   return table.concat(out, " ")
end

local function clean(source)
   assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local M = {}

function M.parserGivesIntersectionHigherPrecedenceThanUnion()
   local parsed = parser.parse("local value: A | B & C", "test")
   assertEq(#parsed.errors, 0)
   local annotation = parsed.root.blocks[1].stats[1].types[1]
   assertEq(cst.dump(annotation),
      "(tunion (tname A) | (tintersection (tname B) & (tname C)))")
end

function M.intersectionsCanonicalizeAndRenderWithPrecedence()
   local a = T.intersection({T.string, T.number, T.string})
   local b = T.intersection({T.number, T.string})
   assertEq(a, b)
   assertEq(T.tostring(a), "number & string")
   assertEq(T.tostring(T.optional(a)), "(number & string)?")
   assertEq(T.tostring(T.intersection({T.union({T.string, T.nil_}), T.boolean})),
      "boolean & (string?)")
   assertEq(T.intersection({T.any, T.string}), T.string)
   assertEq(T.intersection({T.unknown, T.string}), T.string)
   assertEq(T.intersection({T.never, T.string}), T.never)
   local tv = T.typevar("T", "intersection-test")
   assertEq(T.tostring(require("nupp.generics").subst(
      T.intersection({tv, T.string}), {[tv] = T.literal("ok", T.string)})),
      '"ok" & string')
end

function M.intersectionsComposeStructuralCapabilities()
   clean(table.concat({
      "local type Both = {readonly count: number} & {readonly name: string}",
      "local function combined(value: Both): {count: number, name: string}",
      "   local count: number = value.count",
      "   local name: string = value.name",
      "   return {count = count, name = name}",
      "end",
   }, "\n"))
end

function M.intersectionSurfacesComposeReadsWritesAndIndexers()
   clean(table.concat({
      "local type ReadBoth = {readonly [string]: string}",
      "   & {readonly [integer]: integer}",
      "local reads: ReadBoth = nil as any",
      "local text: string? = reads['name']",
      "local count: integer? = reads[1]",
      "local type WriteBoth = {writeonly [string]: string}",
      "   & {writeonly [string]: integer}",
      "local writes: WriteBoth = nil as any",
      "writes['name'] = 'ready'",
      "writes['count'] = 1",
   }, "\n"))

   local left = T.shape({{name = "a", read = T.string}})
   local right = T.shape({{name = "b", read = T.number}})
   local both = T.shape({{name = "a", read = T.string},
      {name = "b", read = T.number}})
   assert(relations.isA(T.intersection({left, right}), both))
end

function M.provablyEmptyIntersectionsAreRejected()
   assertEq(codes("local value: string & number"), "NUPP2124")
   assertEq(codes("local value: {kind: 'a'} & {kind: 'b'}"), "NUPP2124")
   assertEq(relations.disjoint(T.string, T.number), "different runtime categories")
end

function M.callsSelectExactlyOneFunctionMember()
   clean(table.concat({
      "local type Parse = function(text: string): integer",
      "   & function(text: string, base: integer): string",
      "local parse: Parse = nil as any",
      "local value: integer = parse('10')",
      "local text: string = parse('10', 16)",
   }, "\n"))
end

function M.selectedOverloadsPreserveCompleteResultPacks()
   clean(table.concat({
      "local type Read = function(path: string): string",
      "   & function(path: string, offset: integer): (string, integer)",
      "local read: Read = nil as any",
      "local data, nextOffset = read('file', 0)",
      "local text: string = data",
      "local offset: integer = nextOffset",
   }, "\n"))
end

function M.methodsAndMetamethodsKeepTheirOverloadSets()
   clean(table.concat({
      "local type Methods = {readonly convert: function(self: any, value: string): string}",
      "   & {readonly convert: function(self: any, value: integer): integer}",
      "local methods: Methods = nil as any",
      "local text: string = methods:convert('ready')",
      "local count: integer = methods:convert(1)",
      "local interface CallsText",
      "   metamethod __call: function(self, value: string): string",
      "end",
      "local interface CallsNumber",
      "   metamethod __call: function(self, value: integer): integer",
      "end",
      "local callable: CallsText & CallsNumber = nil as any",
      "local calledText: string = callable('ready')",
      "local calledNumber: integer = callable(1)",
   }, "\n"))
end

function M.genericOverloadsSpecializeCandidatesIndependently()
   clean(table.concat({
      "local type Convert = function<T is string>(value: T): T",
      "   & function(value: integer): integer",
      "local convert: Convert = nil as any",
      "local text: string = convert('ready')",
      "local count: integer = convert(1)",
   }, "\n"))
end

function M.packGenericOverloadsPreserveHeterogeneousTails()
   clean(table.concat({
      "local type Forward = function<A...>(tag: 'many', A...): A...",
      "   & function(tag: 'none'): string",
      "local forward: Forward = nil as any",
      "local count, text = forward('many', 3, 'ready')",
      "local n: number = count",
      "local s: string = text",
      "local empty: string = forward('none')",
   }, "\n"))
end

function M.overloadFailuresAndAmbiguitiesHaveDedicatedDiagnostics()
   local prefix = table.concat({
      "local type F = function(value: integer): string",
      "   & function(value: number): boolean",
      "local f: F = nil as any",
   }, "\n")
   assertEq(codes(prefix .. "\nlocal value = f('no')"), "NUPP2125")
   assertEq(codes(prefix .. "\nlocal value = f(1)"), "NUPP2126")
end

return M
