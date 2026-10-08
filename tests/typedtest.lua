local testAssert = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local cst = require("nupp.compiler.syntax.cst")
local fmt = require("nupp.tools.fmt")

-- Parses src, asserts clean parse + byte round-trip, returns the result.
local function clean(src)
    local result = parser.parse(src)
    testAssert.equal(
        #result.errors,
        0,
        "unexpected errors for " .. (
            "%q"
        ):format(src) .. (result.errors[1] and (" (" .. result.errors[1].msg .. ")") or "")
    )
    testAssert.equal(cst.textOf(result.root), src, "round-trip")

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
    testAssert.equal(s.kind, "localStmt")
    testAssert.equal(cst.dump(s.types[1]), "(tname number)")
    -- annotation on a middle binding only
    local s2 = firstStat("local a, b: string, c = 1, 's', 2")
    testAssert.equal(s2.types[1], nil)
    testAssert.equal(cst.dump(s2.types[2]), "(tname string)")
    testAssert.equal(s2.types[3], nil)
    testAssert.equal(#s2.names, 3)
end

function M.typeExpressions()
    testAssert.equal(typeDump("integer?"), "(topt (tname integer) ?)")
    testAssert.equal(typeDump("S*?"), "(topt (tptr (tname S) *) ?)")
    testAssert.equal(typeDump("number | string | nil"), "(tunion (tname number) | (tname string) | (tname nil))")
    testAssert.equal(typeDump("{number}"), "(tarray { (tname number) })")
    testAssert.equal(typeDump("{number, string}"), "(ttuple { (tname number) , (tname string) })")
    testAssert.equal(typeDump("{[string]: number}"), "(tmap { [ (tname string) ] : (tname number) })")
    testAssert.equal(
        typeDump("{x: number, y: number}"),
        "(tshape { (tshapeField x : (tname number)) , " .. "(tshapeField y : (tname number)) })"
    )
    clean("local x: {@readonly value: string, @writeonly value: string | integer}")
    clean("local x: {@readonly [string]: string, @writeonly [string]: string | integer}")
    clean("local x: {name: string, [string]: string}")
    testAssert.equal(typeDump("a.b.C<K, V?>"), "(tname a . b . C < (tname K) , (topt (tname V) ?) >)")
end

function M.functionTypes()
    testAssert.equal(
        typeDump("function(number): boolean"),
        "(tfunc function ( (tfuncParam (tname number)) ) : (tname boolean))"
    )
    testAssert.equal(
        typeDump("function(x: number, ...: string): (number, string)"),
        "(tfunc function ( (tfuncParam x : (tname number)) , "
        .. "(tfuncParam ... : (tname string)) ) : "
        .. "( (tname number) , (tname string) ))"
    )
end

function M.functionStatementAnnotations()
    clean("function f(a: number, ...: string): boolean, {number} return true, {} end")
    clean("local function map<T, U>(xs: {T}, f: function(T): U): {U} return {} end")
    clean("function m.s:go(dt: number) end")
    -- return annotation stops before the body even when the body starts
    -- with an expression statement
    local r = clean("local function g(): number return 1 end")
    local body = r.root.blocks[1].stats[1].body
    testAssert.equal(cst.dump(body.rets[1]), "(tname number)")
end

function M.recordDeclarations()
    local src = table.concat(
        {
            "local record Point",
            "   x: number",
            "   y: number",
            "   type Alias = number",
            "   record Nested",
            "      v: boolean",
            "   end",
            "end",
        },
        "\n"
    )
    local s = firstStat(src)
    testAssert.equal(s.kind, "recordDecl")
    testAssert.equal(s.declKind, "record")
    testAssert.equal(#s.entries, 4)
    testAssert.equal(s.entries[4].kind, "recordDecl")
    clean("local interface Shape\n   area: function(Shape): number\nend")
    clean("local struct Vec3\n   x: float\n   y: float\n   z: float\nend")
    clean("local record Box<T>\n   value: T\nend")
    clean(
        table.concat(
            {
                "local interface Cell",
                "   @readonly value: string",
                "   @writeonly value: string | integer",
                "   @readonly [string]: string",
                "   @writeonly [string]: string | integer",
                "end",
            },
            "\n"
        )
    )
    local mixed = firstStat(
        table.concat({"local interface Opt", "   secret: string", "   [string]: integer", "end",}, "\n")
    )
    testAssert.equal(mixed.entries[1].kind, "fieldDecl")
    testAssert.equal(mixed.entries[2].kind, "indexerDecl")
end

function M.contractDeclarationsAndInlineMethods()
    local s = firstStat(
        table.concat(
            {
                "local record Box<T is Value> is Named, Serializable",
                "   metamethod __call: function(self, value: T): self",
                "   function describe(prefix: string): string",
                "      return prefix",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.equal(#s.generics.names, 1)
    testAssert.equal(s.generics.names[1].text, "T")
    testAssert.equal(cst.dump(s.generics.bounds[1]), "(tname Value)")
    testAssert.equal(#s.supertypes, 2)
    testAssert.equal(s.entries[1].kind, "metamethodDecl")
    testAssert.equal(s.entries[2].kind, "inlineMethod")
end

function M.literalUnionAndTypeAlias()
    local s = firstStat("local type Color = 'red' | 'green' | 'blue'")
    testAssert.equal(s.kind, "typeAlias")
    testAssert.equal(cst.dump(s.value), "(tunion (tliteral 'red') | (tliteral 'green') | (tliteral 'blue'))")
    local n = firstStat("local type EntityId = uint32")
    testAssert.equal(n.kind, "typeAlias")
    testAssert.equal(cst.dump(n.value), "(tname uint32)")
    assert(#parser.parse("def Legacy = uint32").errors > 0, "the former module alias syntax must be rejected")
end

function M.declarationVisibility()
    local private = firstStat("local type Private = string")
    testAssert.equal(private.visibility, "local")
    local exported = firstStat("type Exported = string")
    testAssert.equal(exported.kind, "typeAlias")
    testAssert.equal(exported.visibility, "module")
    local global = firstStat("global record Shared\n   value: number\nend")
    testAssert.equal(global.kind, "recordDecl")
    testAssert.equal(global.visibility, "global")
end

function M.contextualKeywordsStayNames()
    -- [CS-5]: none of the introducers are reserved words.
    testAssert.equal(firstStat("local record = 5").kind, "localStmt")
    testAssert.equal(firstStat("local def = 1").kind, "localStmt")
    testAssert.equal(firstStat("local type = 1").kind, "localStmt")
    testAssert.equal(firstStat("local newtype = 1").kind, "localStmt")
    testAssert.equal(firstStat("global = 1").kind, "assignStmt")
    testAssert.equal(firstStat("type(x)").kind, "callStmt")
    testAssert.equal(firstStat("local x = struct").kind, "localStmt")
    testAssert.equal(firstStat("local read = 1").kind, "localStmt")
    testAssert.equal(firstStat("local write = 1").kind, "localStmt")
    testAssert.equal(firstStat("local readonly = 1").kind, "localStmt")
    testAssert.equal(firstStat("local writeonly = 1").kind, "localStmt")
    clean("local record Words\n   readonly: string\n   writeonly: string\nend")
    local explicit = clean("local type; Alias = number")
    testAssert.equal(explicit.root.blocks[1].stats[1].kind, "localStmt")
    testAssert.equal(explicit.root.blocks[1].stats[3].kind, "assignStmt")
end

function M.optionalTypeVsTernary()
    -- [CS-8]: 'T?' in type position and '? :' in the initializer coexist.
    local s = firstStat("local x: T? = a ? b : c")
    testAssert.equal(cst.dump(s.types[1]), "(topt (tname T) ?)")
    testAssert.equal(s.exprs[1].kind, "ternary")
end

function M.castAndIs()
    local s = firstStat("local n = x as number + 1")
    testAssert.equal(cst.dump(s.exprs[1]), "(binop (castExpr (name x) as (tname number)) + (number 1))")
    local s2 = firstStat("if v is string then end")
    testAssert.equal(cst.dump(s2.clauses[1].cond), "(isExpr (name v) is (tname string))")
end

function M.contextualOpsNeedSameLine()
    -- [CS-6]: across a newline, 'is' stays a plain call statement.
    local r = clean("x = a\nis(b)")
    local stats = r.root.blocks[1].stats
    testAssert.equal(#stats, 2)
    testAssert.equal(stats[1].kind, "assignStmt")
    testAssert.equal(stats[2].kind, "callStmt")
    -- and as ordinary identifiers they are untouched
    testAssert.equal(firstStat("local as = 1").kind, "localStmt")
    clean("f(as, is)")
end

function M.pragmas()
    local s = firstStat("@jit local function hot() end")
    testAssert.equal(s.kind, "pragmaStmt")
    testAssert.equal(s.name.text, "jit")
    testAssert.equal(s.stat.kind, "localFuncStmt")
    clean("@nojit function m.f(cb: function(): nil) end")
end

function M.formattingTypedCode()
    local function fmt1(src)
        return (fmt.format(src))
    end

    testAssert.equal(fmt1("local x:number=1"), "local x: number = 1\n")
    testAssert.equal(fmt1("local m:{[string]:{number}}={}"), "local m: {[string]: {number}} = {}\n")
    testAssert.equal(
        fmt1("local function f< T >( x : T ) : T return x end"),
        "local function f<T>(x: T): T\n    return x\nend\n"
    )
    testAssert.equal(
        fmt1("local function f< A... , R... >( ... : A... ) : R... " .. "return ... end"),
        "local function f<A..., R...>(...: A...): R...\n    return ...\nend\n"
    )
    testAssert.equal(
        fmt1("local f:function(A...):( (true,R...) | (false,any) )"),
        "local f: function(A...): ((true, R...) | (false, any))\n"
    )
    testAssert.equal(fmt1("local f:function():... string"), "local f: function(): ...string\n")
    testAssert.equal(fmt1("local x : S * ? = nil"), "local x: S*? = nil\n")
    testAssert.equal(fmt1("@jit local function h() end"), "@jit\nlocal function h()\nend\n")
    testAssert.equal(fmt1("local record P\nx: number\nend"), "local record P\n    x: number\nend\n")
    testAssert.equal(
        fmt1(
            table.concat(
                {
                    "local record Box < T is Value > is Named , Serializable where true",
                    "metamethod __call:function(self,value:T):self",
                    "function describe(prefix:string):string",
                    "return prefix",
                    "end",
                    "end",
                },
                "\n"
            )
        ),
        table.concat(
            {
                "local record Box<T is Value> is Named, Serializable where true",
                "    metamethod __call: function(self, value: T): self",
                "    function describe(prefix: string): string",
                "        return prefix",
                "    end",
                "end",
                "",
            },
            "\n"
        )
    )
    -- idempotency on typed corpus
    for _, src in ipairs({
        "local x: number | nil = nil",
        "local record R<T>\n   v: {T}\n   type A = T?\nend",
        "local n = x as number",
        "if v is string then p(v) end",
    }) do
        local once = fmt1(src)
        testAssert.equal(fmt1(once), once, "not idempotent: " .. src)
    end
end

return M
