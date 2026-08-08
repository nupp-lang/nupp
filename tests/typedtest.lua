local parser = require("nupp.parser")
local cst = require("nupp.cst")
local fmt = require("nupp.fmt")

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
         tostring(want), tostring(got)), 2)
   end
end

-- Parses src, asserts clean parse + byte round-trip, returns the result.
local function clean(src)
   local result = parser.parse(src)
   assertEq(#result.errors, 0, "unexpected errors for " .. ("%q"):format(src)
      .. (result.errors[1] and (" (" .. result.errors[1].msg .. ")") or ""))
   assertEq(cst.textOf(result.root), src, "round-trip")
   return result
end

local function firstStat(src)
   return clean(src).root.blocks[1].stats[1]
end

-- Dump of the type annotation on `local x: <TYPE>`.
local function typeDump(t)
   return cst.dump(firstStat("local x: " .. t).types[1])
end

local M = {}

function M.localAnnotations()
   local s = firstStat("local x: number = 1")
   assertEq(s.kind, "localStmt")
   assertEq(cst.dump(s.types[1]), "(tname number)")
   -- annotation on a middle binding only
   local s2 = firstStat("local a, b: string, c = 1, 's', 2")
   assertEq(s2.types[1], nil)
   assertEq(cst.dump(s2.types[2]), "(tname string)")
   assertEq(s2.types[3], nil)
   assertEq(#s2.names, 3)
end

function M.typeExpressions()
   assertEq(typeDump("integer?"), "(topt (tname integer) ?)")
   assertEq(typeDump("S*?"), "(topt (tptr (tname S) *) ?)")
   assertEq(typeDump("number | string | nil"),
      "(tunion (tname number) | (tname string) | (tname nil))")
   assertEq(typeDump("{number}"), "(tarray { (tname number) })")
   assertEq(typeDump("{number, string}"),
      "(ttuple { (tname number) , (tname string) })")
   assertEq(typeDump("{[string]: number}"),
      "(tmap { [ (tname string) ] : (tname number) })")
   assertEq(typeDump("{x: number, y: number}"),
      "(tshape { (tshapeField x : (tname number)) , "
      .. "(tshapeField y : (tname number)) })")
   clean("local x: {read value: string, write value: string | integer}")
   clean("local x: {read [string]: string, write [string]: string | integer}")
   clean("local x: {name: string, [string]: string}")
   assertEq(typeDump("a.b.C<K, V?>"),
      "(tname a . b . C < (tname K) , (topt (tname V) ?) >)")
end

function M.functionTypes()
   assertEq(typeDump("function(number): boolean"),
      "(tfunc function ( (tfuncParam (tname number)) ) : (tname boolean))")
   assertEq(typeDump("function(x: number, ...: string): (number, string)"),
      "(tfunc function ( (tfuncParam x : (tname number)) , "
      .. "(tfuncParam ... : (tname string)) ) : "
      .. "( (tname number) , (tname string) ))")
end

function M.functionStatementAnnotations()
   clean("function f(a: number, ...: string): boolean, {number} return true, {} end")
   clean("local function map<T, U>(xs: {T}, f: function(T): U): {U} return {} end")
   clean("function m.s:go(dt: number) end")
   -- return annotation stops before the body even when the body starts
   -- with an expression statement
   local r = clean("local function g(): number return 1 end")
   local body = r.root.blocks[1].stats[1].body
   assertEq(cst.dump(body.rets[1]), "(tname number)")
end

function M.recordDeclarations()
   local src = table.concat({
      "local record Point",
      "   x: number",
      "   y: number",
      "   type Alias = number",
      "   record Nested",
      "      v: boolean",
      "   end",
      "end",
   }, "\n")
   local s = firstStat(src)
   assertEq(s.kind, "recordDecl")
   assertEq(s.declKind, "record")
   assertEq(#s.entries, 4)
   assertEq(s.entries[4].kind, "recordDecl")
   clean("local interface Shape\n   area: function(Shape): number\nend")
   clean("local struct Vec3\n   x: float\n   y: float\n   z: float\nend")
   clean("local record Box<T>\n   value: T\nend")
   clean(table.concat({
      "local interface Cell",
      "   read value: string",
      "   write value: string | integer",
      "   read [string]: string",
      "   write [string]: string | integer",
      "end",
   }, "\n"))
end

function M.contractDeclarationsAndInlineMethods()
   local s = firstStat(table.concat({
      "local record Box<T is Value> is Named, Serializable",
      "   metamethod __call: function(self, value: T): self",
      "   function describe(prefix: string): string",
      "      return prefix",
      "   end",
      "end",
   }, "\n"))
   assertEq(#s.generics.names, 1)
   assertEq(s.generics.names[1].text, "T")
   assertEq(cst.dump(s.generics.bounds[1]), "(tname Value)")
   assertEq(#s.supertypes, 2)
   assertEq(s.entries[1].kind, "metamethodDecl")
   assertEq(s.entries[2].kind, "inlineMethod")
end

function M.literalUnionAndTypeAlias()
   local s = firstStat("local type Color = 'red' | 'green' | 'blue'")
   assertEq(s.kind, "typeAlias")
   assertEq(cst.dump(s.value),
      "(tunion (tliteral 'red') | (tliteral 'green') | (tliteral 'blue'))")
   local n = firstStat("local type EntityId = uint32")
   assertEq(n.kind, "typeAlias")
   assertEq(cst.dump(n.value), "(tname uint32)")
   assert(#parser.parse("def Legacy = uint32").errors > 0,
      "the former module alias syntax must be rejected")
end

function M.declarationVisibility()
   local private = firstStat("local type Private = string")
   assertEq(private.visibility, "local")
   local exported = firstStat("type Exported = string")
   assertEq(exported.kind, "typeAlias")
   assertEq(exported.visibility, "module")
   local global = firstStat("global record Shared\n   value: number\nend")
   assertEq(global.kind, "recordDecl")
   assertEq(global.visibility, "global")
end

function M.contextualKeywordsStayNames()
   -- [CS-5]: none of the introducers are reserved words.
   assertEq(firstStat("local record = 5").kind, "localStmt")
   assertEq(firstStat("local def = 1").kind, "localStmt")
   assertEq(firstStat("local type = 1").kind, "localStmt")
   assertEq(firstStat("local newtype = 1").kind, "localStmt")
   assertEq(firstStat("global = 1").kind, "assignStmt")
   assertEq(firstStat("type(x)").kind, "callStmt")
   assertEq(firstStat("local x = struct").kind, "localStmt")
   assertEq(firstStat("local read = 1").kind, "localStmt")
   assertEq(firstStat("local write = 1").kind, "localStmt")
   clean("local record Words\n   read: string\n   write: string\nend")
   local explicit = clean("local type; Alias = number")
   assertEq(explicit.root.blocks[1].stats[1].kind, "localStmt")
   assertEq(explicit.root.blocks[1].stats[3].kind, "assignStmt")
end

function M.optionalTypeVsTernary()
   -- [CS-8]: 'T?' in type position and '? :' in the initializer coexist.
   local s = firstStat("local x: T? = a ? b : c")
   assertEq(cst.dump(s.types[1]), "(topt (tname T) ?)")
   assertEq(s.exprs[1].kind, "ternary")
end

function M.castAndIs()
   local s = firstStat("local n = x as number + 1")
   assertEq(cst.dump(s.exprs[1]),
      "(binop (castExpr (name x) as (tname number)) + (number 1))")
   local s2 = firstStat("if v is string then end")
   assertEq(cst.dump(s2.clauses[1].cond),
      "(isExpr (name v) is (tname string))")
end

function M.contextualOpsNeedSameLine()
   -- [CS-6]: across a newline, 'is' stays a plain call statement.
   local r = clean("x = a\nis(b)")
   local stats = r.root.blocks[1].stats
   assertEq(#stats, 2)
   assertEq(stats[1].kind, "assignStmt")
   assertEq(stats[2].kind, "callStmt")
   -- and as ordinary identifiers they are untouched
   assertEq(firstStat("local as = 1").kind, "localStmt")
   clean("f(as, is)")
end

function M.pragmas()
   local s = firstStat("@jit local function hot() end")
   assertEq(s.kind, "pragmaStmt")
   assertEq(s.name.text, "jit")
   assertEq(s.stat.kind, "localFuncStmt")
   clean("@nojit function m.f(cb: function(): nil) end")
end

function M.formattingTypedCode()
   local function fmt1(src) return (fmt.format(src)) end
   assertEq(fmt1("local x:number=1"), "local x: number = 1\n")
   assertEq(fmt1("local m:{[string]:{number}}={}"),
      "local m: {[string]: {number}} = {}\n")
   assertEq(fmt1("local function f< T >( x : T ) : T return x end"),
      "local function f<T>(x: T): T return x end\n")
   assertEq(fmt1("local x : S * ? = nil"), "local x: S*? = nil\n")
   assertEq(fmt1("@jit local function h() end"), "@jit local function h() end\n")
   assertEq(fmt1("local record P\nx: number\nend"),
      "local record P\n    x: number\nend\n")
   assertEq(fmt1(table.concat({
      "local record Box < T is Value > is Named , Serializable where true",
      "metamethod __call:function(self,value:T):self",
      "function describe(prefix:string):string",
      "return prefix",
      "end",
      "end",
   }, "\n")), table.concat({
      "local record Box<T is Value> is Named, Serializable where true",
      "    metamethod __call: function(self, value: T): self",
      "    function describe(prefix: string): string",
      "        return prefix",
      "    end",
      "end",
      "",
   }, "\n"))
   -- idempotency on typed corpus
   for _, src in ipairs({
      "local x: number | nil = nil",
      "local record R<T>\n   v: {T}\n   type A = T?\nend",
      "local n = x as number",
      "if v is string then p(v) end",
   }) do
      local once = fmt1(src)
      assertEq(fmt1(once), once, "not idempotent: " .. src)
   end
end

return M
