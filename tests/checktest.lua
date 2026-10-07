local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local T = require("nupp.compiler.types")
local relations = require("nupp.compiler.types.relations")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

-- Runs the checker; returns the list of "CODE:line" strings.
local function checkedDiags(src, env)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax errors in test source: " .. (result.errors[1] and result.errors[1].msg or ""))
    local diags = check.check(result, "test.g.nupp", env)
    local out = {}
    for j, d in ipairs(diags) do
        out[j] = d.code .. ":" .. d.line
    end

    return table.concat(out, " "), diags
end

local function diagsOf(src)
    return checkedDiags(src)
end

local function assertClean(src)
    local got, diags = diagsOf(src)
    assertEq(got, "", "expected clean check for:\n" .. src .. (diags[1] and ("\nfirst: " .. diags[1].msg) or ""))
end

local function applyFix(source, fix)
    local edits = {}
    for _, edit in ipairs(fix.edits or {}) do
        edits[#edits + 1] = edit
    end
    table.sort(edits, function(a, b)
        return a.offset > b.offset
    end)
    for _, edit in ipairs(edits) do
        source = source:sub(1, edit.offset - 1) .. edit.newText .. source:sub(edit.offset + edit.length)
    end

    return source
end

local M = {}

---------------------------------------------------------------------------
-- types.lua interning
---------------------------------------------------------------------------

function M.interningIdentity()
    assert(T.array(T.number) == T.array(T.number), "arrays interned")
    assert(T.optional(T.string) == T.union({T.nil_, T.string}), "optional is canonical union")
    assert(T.union({T.number, T.string}) == T.union({T.string, T.number}), "unions canonicalized by order")
    assert(T.union({T.number}) == T.number, "singleton union unwraps")
    assert(
        T.union({
            T.number,
            T.union({
                T.string,
                T.number
            })
        }) == T.union({
            T.string,
            T.number
        }),
        "nested unions flatten+dedup"
    )
    assert(
        T.shape({
            {name = "x", type = T.number},
            {name = "y", type = T.number}
        }) == T.shape({
            {name = "y", type = T.number},
            {name = "x", type = T.number}
        }),
        "shapes canonicalized by field name"
    )
    assert(T.nominal("A", "record") ~= T.nominal("A", "record"), "nominals get fresh identity")
end

function M.functionInterningDerivesVarargFromItsPack()
    local base = T.func({T.any}, {T.nil_}, false)
    local sharedPack = T.pack({T.any}, {kind = "unknown", type = T.any})
    local unsaid = T.funcWith(base, {paramPack = sharedPack})
    local said = T.funcWith(base, {paramPack = sharedPack, vararg = true})
    assert(unsaid == said, "one pack interns one function, whichever spelling came first")
    assert(said.vararg, "a pack with a tail takes extra arguments")
    -- Binding `P...` to a fixed list leaves no tail, and what is left is the
    -- function a fixed signature spells, not a variadic twin of it.
    local packVar = T.packvar("P", "checktest:vararg-substitution")
    local callback = T.func({}, {T.nil_}, true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, T.pack({}, {
        kind = "generic",
        var = packVar,
    }))
    assert(callback.vararg, "a pack binder tail is variadic")
    local generics = require("nupp.compiler.types.generics")
    local bound = generics.materialize(callback, {[packVar] = T.pack({T.integer, T.string})})
    local written = T.funcWith(T.func({T.integer, T.string}, {T.nil_}, false), {})
    assert(bound == written, T.tostring(bound) .. " is not the written " .. T.tostring(written))
    assert(not bound.vararg, "the bound function is fixed")
end

function M.typeTostring()
    assertEq(T.tostring(T.optional(T.number)), "number?")
    assertEq(T.tostring(T.map(T.string, T.array(T.integer))), "{[string]: {integer}}")
    assertEq(T.tostring(T.func({T.number}, {T.boolean}, false)), "function(number): boolean")
    local packVar = T.packvar("A", "test-pack")
    local pack = T.pack({}, {kind = "generic", var = packVar})
    assertEq(
        T.tostring(
            T.func({}, {}, true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, pack, pack, {
                packVar
            })
        ),
        "function<A...>(A...): (A...)"
    )
    assertEq(
        T.tostring(T.indexer(T.string, T.string, T.string, T.number)),
        "{@readonly [string]: string, @writeonly [string]: number}"
    )
    assertEq(
        T.tostring(
            T.shape({
                {name = "value", read = T.string, write = T.number}
            })
        ),
        "{@readonly value: string, @writeonly value: number}"
    )
    assertEq(T.tostring(T.tuple({T.string})), "{string,}")
    assertEq(T.tostring(T.array(T.string)), "{string}")
end

function M.functionTypeTostringPreservesMixedGenericBinderOrder()
    local element = T.typevar("Element", "checktest:mixed-generic:type")
    local size = T.constvar("Size", "integer", "checktest:mixed-generic:const")
    local fn = T.funcWith(T.func({}, {}, false), {
        typeParams = {element},
        constParams = {size},
        paramKinds = {"const", "type"},
    })
    assertEq(T.tostring(fn), "function<const Size: integer, Element>()")
    local reversed = T.funcWith(fn, {paramKinds = {"type", "const"}})
    assert(fn ~= reversed, "binder order participates in function identity")
end

function M.reinternedGenericAliasRefreshesDeclarationMetadata()
    local element = T.typevar("Element", "checktest:alias-refresh")
    local firstDefault = {kind = "tname", value = "string"}
    local alias = T.genericAlias("Refreshable", element, {element}, {T.string}, nil, nil, {"type"}, {firstDefault})
    local secondDefault = {kind = "tname", value = "number"}
    local refreshed = T.genericAlias("Refreshable", element, {element}, {T.number}, nil, nil, {"type"}, {secondDefault})
    assert(alias == refreshed, "an incremental recheck retains alias identity")
    assert(refreshed.typeBounds[1] == T.number, "the recheck refreshes bounds")
    assert(refreshed.paramDefaults[1] == secondDefault, "the recheck refreshes defaults")
end

function M.cNamesOnlyTreatPointerShapedOptionalsAsNullableCValues()
    assertEq(T.cName(T.optional(T.number)), nil)
    assertEq(T.cName(T.optional(T.ptr(T.int32))), "int32_t *")
    assertEq(T.cName(T.optional(T.cstring)), "const char *")
end

-- A string literal's type is the string it denotes, not the source that spells
-- it, so a spelling is only ever a way of writing bytes: the annotation and the
-- initializer below are the same type because they are the same one byte. A type
-- is also printed -- into a diagnostic, into --json, into a hover -- so it is
-- rendered back as a spelling that stays on one line and in ASCII.
function M.aStringLiteralTypeIsTheBytesItDenotes()
    assertClean([[local a: "\65" = "A"]] .. "\nprint(a)")
    assertClean([[local b: "A" = "\65"]] .. "\nprint(b)")
    assertEq(
        diagsOf([[local c: "\65" = "\\65"]] .. "\nprint(c)"),
        "NUPP2001:1",
        "three characters are not the one byte they spell"
    )
    assertEq(T.tostring(T.literal("\1\255a\nb", T.string)), '"\\1\\255a\\nb"')
    assertEq(
        T.tostring(T.literal("\0" .. "12", T.string)),
        '"\\00012"',
        "a numeric escape is padded where a digit follows it"
    )
end

-- A literal is interned under its base's identity, not its base's tag: two nominals
-- share a tag, and a blueprint may hand either one in as the base.
function M.aLiteralIsInternedByItsBaseNotItsBaseTag()
    local first = T.nominal("First", "record")
    local second = T.nominal("Second", "record")
    assertEq(T.literal("a", first), T.literal("a", first))
    assert(T.literal("a", first) ~= T.literal("a", second), "two nominal bases keep two literals")
    assert(T.literal("a", first) ~= T.literal("a", T.string), "a nominal base is not the string base")
end

---------------------------------------------------------------------------
-- relations.lua
---------------------------------------------------------------------------

function M.subtypingRules()
    local isA = relations.isA
    assert(isA(T.integer, T.number))
    assert(not isA(T.int64, T.integer))
    assert(not isA(T.int64, T.number))
    assert(not isA(T.integer, T.int64))
    assert(not isA(T.int64, T.uint64))
    assert(not isA(T.number, T.integer))
    assert(isA(T.string, T.optional(T.string)))
    assert(isA(T.nil_, T.optional(T.string)))
    assert(not isA(T.optional(T.string), T.string))
    assert(not isA(T.array(T.integer), T.array(T.number)))
    assert(isA(T.array(T.number), T.table_))
    -- width subtyping: wider shape fits narrower
    local wide = T.shape({{name = "x", type = T.number}, {name = "y", type = T.number}})
    local narrow = T.shape({{name = "x", type = T.number}})
    assert(isA(wide, narrow))
    assert(not isA(narrow, wide))
    -- nominal-to-shape erosion, never the reverse
    local rec = T.nominal("P", "record")
    rec.byname = {x = T.number, y = T.number}
    rec.writeByname = {x = T.number, y = T.number}
    assert(isA(rec, narrow))
    assert(not isA(narrow, rec))
    -- functions: contravariant params, covariant returns
    local takesNum = T.func({T.number}, {T.integer}, false)
    local takesInt = T.func({T.integer}, {T.number}, false)
    assert(isA(takesNum, takesInt))
    assert(not isA(takesInt, takesNum))
end

-- An owner answers the methods of the type it owns, so a method the type does not
-- have is reported the way a field it does not have is, rather than checking clean
-- and calling nil. The terminal is reached through the owner and still resolves.
function M.anOwnerResolvesMethodsThroughItsUnderlyingType()
    local owner = table.concat({
        "local record Buffer",
        "    n: integer",
        "    function close(takes self): nil end",
        "    function size(self): integer return self.n end",
        "end",
        "local function open(): affine(Buffer, Buffer.close)",
        "    return new Buffer(n = 1)",
        "end",
        "local owner = open()",
    }, "\n")
    assertEq(diagsOf(owner .. "\nowner:frobnicate()\nowner:close()"), "NUPP2004:10")
    assertClean(owner .. "\nprint(owner:size())\nowner:close()")
end

-- An exported function is in scope from the top of its module, so one declared after
-- a binding of the same name would overwrite that binding rather than stand beside it:
-- the local read by the code between them became the function at run time.
function M.anExportedFunctionMayNotRedeclareAnEarlierName()
    assertEq(
        diagsOf(table.concat({
            "module shadowed",
            "local fired: integer = 0",
            "export function bump(): nil",
            "    fired = fired + 1",
            "end",
            "export function fired(): integer",
            "    return 1",
            "end",
        }, "\n")),
        "NUPP2008:6"
    )
    assertEq(
        diagsOf(table.concat({
            "module shadowed",
            "local record fired",
            "    n: integer",
            "end",
            "export function fired(): integer return 1 end",
        }, "\n")),
        "NUPP2008:5"
    )
    assertEq(
        diagsOf(table.concat({
            "module shadowed",
            "export function fired(): integer return 1 end",
            "export function fired(): integer return 2 end",
        }, "\n")),
        "NUPP2008:3",
        "two exports are reported once"
    )
    assertClean(table.concat({
        "module shadowed",
        "local count: integer = 0",
        "export function fired(): integer",
        "    count = count + 1",
        "    return count",
        "end",
    }, "\n"))
end

-- An absent member satisfies an optional one only when the source is known to lack
-- it: a fresh literal, a record or a struct, or a read indexer whose value fits. An
-- open shape may be a widened view of a value holding the member under another type,
-- so reading it through `{name: string?}` would hand back a number (CHECKER-04).
function M.absentOptionalMemberNeedsAClosedSource()
    assertEq(
        diagsOf(table.concat({
            "local full = {id = 1, name = 5}",
            "local narrow: {id: integer} = full",
            "local view: {@readonly name: string?} = narrow",
            "return view",
        }, "\n")),
        "NUPP2001:3"
    )
    local record = table.concat({
        "local record User",
        "    id: integer",
        "    name: integer",
        "end",
        "local function show(v: {@readonly name: string?}): nil",
        "    if v.name then print(v.name:upper()) end",
        "end",
    }, "\n")
    assertEq(
        diagsOf(table.concat({
            record,
            "local function forward(h: {@readonly id: integer}): nil show(h) end",
            "forward(new User(id = 1, name = 5))",
        }, "\n")),
        "NUPP2006:8"
    )
    local _, diags = diagsOf(record .. "\nlocal function forward(h: {@readonly id: integer}): nil show(h) end")
    assert(diags[1].msg:find("only a fresh table, a record or a struct may omit", 1, true), diags[1].msg)
    assertEq(
        diagsOf(table.concat({
            "local interface Named",
            "    id: integer",
            "end",
            "local function show(v: {@readonly name: string?}): nil end",
            "local function forward(h: Named): nil show(h) end",
            "return forward",
        }, "\n")),
        "NUPP2006:5"
    )
    assertEq(
        diagsOf(table.concat({
            "local function show(v: {@readonly name: string?}): nil end",
            "local function forward(h: {id: integer} & {[string]: number}): nil show(h) end",
            "return forward",
        }, "\n")),
        "NUPP2006:2"
    )
    assertClean(table.concat({
        "local record User",
        "    id: integer",
        "end",
        "local struct Point",
        "    x: number",
        "end",
        "local function show(v: {@readonly name: string?}): nil",
        "    if v.name then print(v.name:upper()) end",
        "end",
        "show({id = 1})",
        "show(new User(id = 1))",
        "local u: User = new User(id = 2)",
        "show(u)",
        "show(new Point(1))",
        "local function viaIndexer(h: {id: integer} & {[string]: string}): nil show(h) end",
        "return viaIndexer",
    }, "\n"))
end

-- The extra parameters of a callable stand where the target's extra arguments
-- arrive, so they compare against its vararg element type and mode the way any
-- parameter position does; an untyped `...` promises nothing about them.
function M.extraParametersCompareAgainstTheTargetsVararg()
    local takesTwo = "local function takesTwo(x: string, n: integer): string return x .. n end"
    assertEq(
        diagsOf(
            table.concat({takesTwo, "local f: function(x: string, ...: string): string = takesTwo", "return f",}, "\n")
        ),
        "NUPP2001:2"
    )
    assertEq(
        diagsOf(table.concat({takesTwo, "local f: function(x: string, ...): string = takesTwo", "return f",}, "\n")),
        "NUPP2001:2"
    )
    assertClean(
        table.concat({takesTwo, "local f: function(x: string, ...: integer): string = takesTwo", "return f",}, "\n")
    )
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local record R",
                    "   n: integer",
                    "end",
                    "local function consume(a: string, takes r: R): string return a end",
                    "local f: function(a: string, ...: R): string = consume",
                    "return f",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
end

-- A mode says what a callee does with an owner, and nothing owned ever reaches
-- a slot typed `any` or left untyped, so against such a tail the mode is moot:
-- `@sendable function(...: any): any` stands for any callable a worker may run,
-- taking parameters included.
function M.anExtraParametersModeIsMootAgainstAnAnyTail()
    local consume = table.concat(
        {
            "local record R",
            "   n: integer",
            "end",
            "local function consume(a: string, takes r: R): string return a end",
        },
        "\n"
    )
    assertClean(table.concat({consume, "local f: function(a: string, ...: any): string = consume", "return f",}, "\n"))
    assertEq(
        diagsOf(table.concat({consume, "local f: function(a: string, ...: R): string = consume", "return f",}, "\n")),
        "NUPP2001:5"
    )
end

-- An argument nobody passes reads nil, which is what an optional parameter's
-- type already says, so a trailing parameter that admits nil may be left
-- unsupplied by the target; one that does not still may not.
function M.anOmittedTrailingParameterMustAdmitNil()
    assertClean(
        table.concat(
            {
                "local function f(x: string, y: integer?): string return x .. tostring(y) end",
                "local g: function(x: string): string = f",
                "return g",
            },
            "\n"
        )
    )
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local function f(x: string, y: integer): string return x .. y end",
                    "local g: function(x: string): string = f",
                    "return g",
                },
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

-- A positional literal is a tuple of what it was written with wherever it is
-- checked in place: a return, an argument, a field, an element, an assignment.
-- Bound to a name it is the array it always was.
function M.aPositionalLiteralIsATupleWhereOneIsExpected()
    assertClean(
        table.concat(
            {
                "local record R",
                "   t: {number, string}",
                "end",
                "local function mk(): {number, string}",
                "   return {2, 'b'}",
                "end",
                "local function take(t: {number, string}): number",
                "   return t[1]",
                "end",
                "local x: {number, string} = {1, 'a'}",
                "x = {3, 'c'}",
                "local r = new R(t = {4, 'd'})",
                "r.t = {5, 'e'}",
                "local nested: {a: {number, string}} = {a = {6, 'f'}}",
                "local arr: {{number, string}} = {{7, 'g'}, {8, 'h'}}",
                "local function multi(): ({number, string}, integer)",
                "   return {9, 'i'}, 1",
                "end",
                "return {mk(), take({1, 'a'}), x, r, nested, arr, multi()}",
            },
            "\n"
        )
    )
    assertEq(
        diagsOf(
            table.concat(
                {"local function take(t: {number, string}): number", "   return t[1]", "end", "return take({'a', 1})",},
                "\n"
            )
        ),
        "NUPP2006:4"
    )
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local function take(t: {number, string}): number",
                    "   return t[1]",
                    "end",
                    "return take({1, 'a', 2})",
                },
                "\n"
            )
        ),
        "NUPP2006:4"
    )
    assertEq(
        diagsOf(table.concat({"local xs = {1, 'a'}", "local t: {number, string} = xs", "return t",}, "\n")),
        "NUPP2001:2"
    )
end

-- Through a mutable view a tuple's positions are held exactly: a wider view could
-- write what the narrower one's readers do not admit. A const view cannot write,
-- so it reads covariantly. A mutable array must preserve every position's writes.
function M.tuplesAreInvariantThroughAMutableView()
    assertEq(
        diagsOf(
            table.concat({"local t: {integer, string} = {1, 'a'}", "local u: {number, string} = t", "return u",}, "\n")
        ),
        "NUPP2001:2"
    )
    assertClean(
        table.concat(
            {
                "local t: {integer, string} = {1, 'a'}",
                "local u: const {number, string} = t",
                "local arr: const {string | integer} = t",
                "local same: {integer | string, string} = {1, 'a'}",
                "local pair: {integer, integer} = {1, 2}",
                "local ints: {integer} = pair",
                "return {u, arr, same, ints}",
            },
            "\n"
        )
    )
end

function M.mutableArraysPreserveTheirElementType()
    local decl = "local ints: {integer} = {1, 2}\n"
    assertEq(diagsOf(decl .. "local nums: {number} = ints\nnums[1] = 1.5"), "NUPP2001:2")
    assertEq(diagsOf(decl .. "local function fill(xs: {number}): nil xs[1] = 1.5 end\nfill(ints)"), "NUPP2006:3")
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local env = require("nupp.compiler.project.env").new(here .. "/..")
    assertEq(checkedDiags(decl .. "table.insert(ints, 1.5)", env), "NUPP2125:2")
    assertEq(checkedDiags(decl .. "table.insert(ints, 1, 1.5)", env), "NUPP2125:2")
    assertEq(checkedDiags(decl .. "table.insert(ints, 3)\ntable.insert(ints, 1, 4)", env), "")
    assertEq(checkedDiags("local xs: {integer} | {string} = {1}\nfor _, x in ipairs(xs) do print(x) end", env), "")
    assertEq(diagsOf("local nested = {{1}}\nlocal wider: {number} = nested[1]\nreturn wider"), "NUPP2001:2")
    assertEq(
        diagsOf("local holder = {const ints = {1}}\nlocal wider: {number} = holder.ints\nreturn wider"),
        "NUPP2001:2"
    )
    assertEq(
        checkedDiags("local record IntList\n{integer}\nend\nlocal ints = new IntList()\ntable.insert(ints, 1.5)", env),
        "NUPP2125:5"
    )
    assertClean(decl .. "local nums: const {number} = ints\nprint(nums[1])\nints[1] = 3")
    assertClean("local nums: {number} = {1, 2}\nnums[1] = 1.5\nreturn nums")
    assertClean(
        "local function one(): integer return 1 end\nlocal nums: {number} = {one()}\nnums[1] = 1.5\nreturn nums"
    )
    assertEq(
        diagsOf("local pair: {integer, string} = {1, 'a'}\nlocal xs: {integer | string} = pair\nreturn xs"),
        "NUPP2001:2"
    )
    assertEq(diagsOf("local nested: {{integer}} = {{1}}\nlocal wider: {{number}} = nested\nreturn wider"), "NUPP2001:2")
end

function M.directRecordConstructionRequiresFields()
    local decl = "local record Item\nname: string\ncount: integer = 0\nnote: string?\nend\n"
    assertEq(diagsOf(decl .. "local item = new Item()\nreturn item"), "NUPP2208:6")
    assertClean(decl .. "local item = new Item(name = 'ready')\nreturn item")
    assertEq(
        diagsOf("local record Box<T>\nvalue: T\nname: string\nend\nlocal box = new Box(value = 1)\nreturn box"),
        "NUPP2208:5"
    )
    assertEq(
        diagsOf("local record Handler\ncall: function(): nil\nend\nlocal handler = new Handler()\nreturn handler"),
        "NUPP2208:4"
    )
    assertEq(diagsOf("local record Box<T>\nvalue: T\nend\nlocal box = new Box()\nreturn box"), "NUPP2208:4")
    assertEq(diagsOf("local record Box<T>\nvalue: T?\nend\nlocal box = new Box()\nreturn box"), "NUPP2148:4")
    assertEq(
        diagsOf(
            "local interface Named\nname: string\nend\nlocal record Item is Named end\nlocal item = new Item()\nreturn item"
        ),
        "NUPP2208:5"
    )
    assertClean(
        "local record Item\nname: string\nfunction describe(self): string return self.name end\nend\nlocal item = new Item(name = 'ready')\nreturn item:describe()"
    )
    assertClean(
        table.concat(
            {
                "local record Handler",
                "call: function(self: Handler, value: string): nil & function(self: Handler, value: integer): nil",
                "end",
                "Handler.call = function(_self: Handler, _value: any): nil end",
                "local handler = new Handler()",
                "return handler",
            },
            "\n"
        )
    )
    assertEq(diagsOf("local record Handler\ncall: function(): nil\nconstructor(self) end\nend"), "NUPP2208:3")
    assertClean(
        "local record Item\nname: string\nconstructor(self, name: string) self.name = name end\nend\nlocal item = new Item('ready')\nreturn item"
    )
end

-- Through a writable map every field is a key somebody may write, so a field the
-- shape does not let anyone write, or lets them write only a narrower type, keeps
-- the shape out of the map. A read-only map asks nothing of the writes.
function M.aShapeFitsAWritableMapOnlyThroughWritableFields()
    assertEq(
        diagsOf(
            table.concat(
                {"local h: {@readonly name: string} = {name = 'x'}", "local m: {[string]: string?} = h", "return m",},
                "\n"
            )
        ),
        "NUPP2001:2"
    )
    assertEq(
        diagsOf(
            table.concat(
                {"local h: {name: string} = {name = 'x'}", "local m: {[string]: string?} = h", "return m",},
                "\n"
            )
        ),
        "NUPP2001:2"
    )
    assertClean(
        table.concat(
            {
                "local h: {name: string?} = {name = 'x'}",
                "local m: {[string]: string?} = h",
                "local r: {@readonly name: string} = {name = 'x'}",
                "local view: {@readonly [string]: string?} = r",
                "local literal: {[string]: string?} = {name = 'x'}",
                "return {m, view, literal}",
            },
            "\n"
        )
    )
end

-- An array is a map from integer to its element: read covariantly, and written
-- exactly, since what the map writes is what the array's readers find. A tuple
-- reads as a map to any of its positions and is written through no map.
function M.anArrayIsAnIntegerKeyedMap()
    assertClean(
        table.concat(
            {
                "local xs: {integer} = {1, 2}",
                "local same: {[integer]: integer} = xs",
                "local wider: {@readonly [integer]: number} = xs",
                "local t: {string, integer} = {'a', 1}",
                "local positions: {@readonly [integer]: string | integer} = t",
                "return {same, wider, positions}",
            },
            "\n"
        )
    )
    assertEq(
        diagsOf(table.concat({"local xs: {integer} = {1, 2}", "local m: {[integer]: number} = xs", "return m",}, "\n")),
        "NUPP2001:2"
    )
    assertEq(
        diagsOf(table.concat({"local xs: {integer} = {1, 2}", "local m: {[string]: integer} = xs", "return m",}, "\n")),
        "NUPP2001:2"
    )
    assertEq(
        diagsOf(
            table.concat(
                {"local t: {string, integer} = {'a', 1}", "local m: {[integer]: string | integer} = t", "return m",},
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

-- A dotted name is a string literal key, so an indexer keyed by literals admits
-- the names it lists and no other, the same as the bracketed spelling.
function M.aDottedNameIsALiteralKeyOfAnIndexer()
    assertClean(
        table.concat(
            {
                "local type K = 'a' | 'b'",
                "local m: {[K]: integer} = {}",
                "m.a = 1",
                "local v: integer? = m.b",
                "local w: integer? = m['a']",
                "return {v, w}",
            },
            "\n"
        )
    )
    assertEq(
        diagsOf(
            table.concat({"local type K = 'a' | 'b'", "local m: {[K]: integer} = {}", "m.c = 1", "return m.d",}, "\n")
        ),
        "NUPP2004:3 NUPP2004:4"
    )
end

function M.arrayCovarianceCannotLaunderFunctionEffects()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local safe: {@nosuspend function(number): number} = {math.floor}",
                    "local calls: {function(number): number} = safe",
                    "return calls",
                },
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

function M.unboundGenericParametersAreNotGradual()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local function readAsString<T>(value: T): string",
                    "   local text: string = value",
                    "   return text",
                    "end",
                    "local function invent<T>(): T",
                    "   return 5",
                    "end",
                    "return readAsString, invent",
                },
                "\n"
            )
        ),
        "NUPP2001:2 NUPP2002:6"
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local function id<T>(value: T): T return value end",
                    "local number: number = id(nil)",
                    "return number",
                },
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

function M.logicalOperatorsKeepTheSelectedFalsyValue()
    assertEq(
        diagsOf(
            table.concat(
                {"local flag: boolean = nil as any", "local text: string = flag and 'ready'", "return text",},
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

function M.assertRemovesFalseFromItsResult()
    -- the prelude's assert, which is the one that narrows
    local envMod = require("nupp.compiler.project.env")
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local result = parser.parse(
        table.concat({"local impossible: never = assert(false)", "return impossible",}, "\n"),
        "test.g.nupp"
    )
    local diags = check.check(result, "test.g.nupp", envMod.new(here .. "/.."))
    assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
end

function M.callsInvalidateNarrowingThroughMutationAndCapture()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local record Box",
                    "   name: string?",
                    "end",
                    "local function clear(box: Box): nil box.name = nil end",
                    "local box = new Box(name = 'ready')",
                    "if box.name then",
                    "   clear(box)",
                    "   local text: string = box.name",
                    "end",
                    "return box",
                },
                "\n"
            )
        ),
        "NUPP2001:8"
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local value: string? = 'ready'",
                    "local function clear(): nil value = nil end",
                    "if value then",
                    "   clear()",
                    "   local text: string = value",
                    "end",
                    "return value",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local value: string? = 'ready'",
                    "local clear = function(): nil value = nil end",
                    "if value then",
                    "   clear()",
                    "   local text: string = value",
                    "end",
                    "return value",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local record Box",
                    "   name: string?",
                    "end",
                    "function Box:clear(): nil self.name = nil end",
                    "local box = new Box(name = 'ready')",
                    "if box.name then",
                    "   box:clear()",
                    "   local text: string = box.name",
                    "end",
                    "return box",
                },
                "\n"
            )
        ),
        "NUPP2001:8"
    )
end

function M.aliasWritesInvalidateFieldNarrowing()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local record Box",
                    "   name: string?",
                    "end",
                    "local box = new Box(name = 'ready')",
                    "local alias = box",
                    "if box.name then",
                    "   alias.name = nil",
                    "   local text: string = box.name",
                    "end",
                    "return box",
                },
                "\n"
            )
        ),
        "NUPP2001:8"
    )
end

function M.unreifiedInterfaceTestsFailDuringCheck()
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local interface Drawable",
                    "   width: number",
                    "end",
                    "local value: any = nil",
                    "return value is Drawable",
                },
                "\n"
            )
        ),
        "NUPP3001:5"
    )
end

function M.erasedGenericTypeTestsFailDuringCheck()
    local codes, diagnostics = diagsOf(
        table.concat(
            {
                "local interface Named",
                "   name: string",
                "end",
                "local function recognizes<T is Named>(value: Named): boolean",
                "   return value is T",
                "end",
            },
            "\n"
        )
    )
    assertEq(codes, "NUPP3001:5")
    assertEq(diagnostics[1].msg, "a generic type parameter has no runtime identity to test")
end

function M.builtinTypeNamesCannotBindGenericParameters()
    local codes, diagnostics = diagsOf(table.concat({"local record Box<string>", "   value: string", "end",}, "\n"))
    assertEq(codes, "NUPP2145:1")
    assertEq(diagnostics[1].msg, 'type parameter "string" conflicts with the builtin type of the same name')
end

function M.constArraysRemainReadableViews()
    assertClean(
        table.concat(
            {
                "local values: const {string} = {'a', 'b'}",
                "local lookup: const {[string]: integer} = {a = 1}",
                "local count: integer = #values",
                "local first: string = values[1]",
                "for index, value in ipairs(values) do",
                "   local i: integer = index",
                "   local s: string = value",
                "end",
                "for key, value in pairs(lookup) do",
                "   local k: string = key",
                "   local n: integer = value",
                "end",
                "local found: integer? = lookup['a']",
                "return count, first, found",
            },
            "\n"
        )
    )
    assertEq(diagsOf(table.concat({"local values: const {string} = {'a'}", "values[1] = 'b'",}, "\n")), "NUPP2009:2")
end

function M.propertyCapabilities()
    assertClean(
        table.concat(
            {
                "local type Animal = string | integer",
                "local record Cell",
                "   @readonly value: string",
                "   @writeonly value: Animal",
                "   @readonly [string]: string",
                "   @writeonly [string]: Animal",
                "end",
                "local cell = new Cell(value = 'ready')",
                "cell.value = 1",
                "local value: string = cell.value",
                "cell['answer'] = 42",
                "local indexed: string? = cell['answer']",
                "local readView: {@readonly value: Animal} = cell",
                "local writeView: {@writeonly value: string} = cell",
                "return {value, indexed, readView, writeView}",
            },
            "\n"
        )
    )

    local denied, details = diagsOf(
        table.concat(
            {
                "local readView: {@readonly value: string} = {value = 'x'}",
                "local writeView: {@writeonly value: string} = {}",
                "readView.value = 'y'",
                "local value = writeView.value",
                "readView.value ..= 'z'",
            },
            "\n"
        )
    )
    assertEq(denied, "NUPP2009:3 NUPP2009:4 NUPP2009:5")
    assert(details[1].help and details[1].help:match("write access"))

    local variance = diagsOf(
        table.concat(
            {
                "local type Animal = string | integer",
                "local readString: {@readonly value: string} = {value = 'x'}",
                "local readAnimal: {@readonly value: Animal} = {value = 'x'}",
                "local writeString: {@writeonly value: string} = {}",
                "local writeAnimal: {@writeonly value: Animal} = {}",
                "local ordinaryString: {value: string} = {value = 'x'}",
                "local okRead: {@readonly value: Animal} = readString",
                "local okWrite: {@writeonly value: string} = writeAnimal",
                "local badRead: {@readonly value: string} = readAnimal",
                "local badWrite: {@writeonly value: Animal} = writeString",
                "local badOrdinary: {value: Animal} = ordinaryString",
            },
            "\n"
        )
    )
    assertEq(variance, "NUPP2001:9 NUPP2001:10 NUPP2001:11")

    assertClean(
        table.concat(
            {
                "local type Animal = string | integer",
                "local readIndex: {@readonly [string]: string} = {}",
                "local writeIndex: {@writeonly [string]: Animal} = {}",
                "local widerRead: {@readonly [string]: Animal} = readIndex",
                "local narrowerWrite: {@writeonly [string]: string} = writeIndex",
                "return {widerRead, narrowerWrite}",
            },
            "\n"
        )
    )

    assertEq(
        diagsOf(
            table.concat(
                {"local record Bad", "   @readonly value: string", "   @readonly value: integer", "end",},
                "\n"
            )
        ),
        "NUPP2118:3"
    )
    assertEq(diagsOf(table.concat({"local struct Bad", "   @readonly value: int32", "end",}, "\n")), "NUPP2118:2")

    assertClean(
        table.concat(
            {"local out: {@writeonly value: string} | {@writeonly value: string | integer}", "out.value = 'ready'",},
            "\n"
        )
    )
    assertEq(
        diagsOf(
            table.concat(
                {"local out: {@writeonly value: string} | {@writeonly value: string | integer}", "out.value = 42",},
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

function M.propertyAnnotationsAreStableAcrossRepeatedChecks()
    local result = parser.parse(
        table.concat(
            {"local interface Surface", "   @readonly value: string", "   @writeonly [string]: number", "end",},
            "\n"
        ),
        "repeated.g.nupp"
    )
    assertEq(#result.errors, 0, "property annotation syntax")
    for pass = 1, 2 do
        local diags = check.check(result, "repeated.g.nupp")
        assertEq(#diags, 0, ("check %d over the same parsed tree"):format(pass))
    end
end

function M.constTableFieldsAreReadOnly()
    assertClean(
        table.concat(
            {
                "local M = {}",
                "const M.bar = {",
                "   const BAZ = 123,",
                "   const nested = {const name = 'nupp'},",
                "}",
                "return M",
            },
            "\n"
        )
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local M = {}",
                    "const M.bar = {",
                    "   const BAZ = 123,",
                    "   const nested = {const name = 'nupp'},",
                    "}",
                    "M.bar.BAZ = 456",
                    "M.bar.nested.name = 'lua'",
                    "M.bar.BAZ += 1",
                    "return M",
                },
                "\n"
            )
        ),
        "NUPP2008:6 NUPP2008:7 NUPP2008:8"
    )

    assertEq(
        diagsOf(
            table.concat(
                {
                    "local M = {}",
                    "const... M.bar = {BAZ = 123, nested = {name = 'nupp'}}",
                    "M.bar.BAZ = 456",
                    "M.bar.nested.name = 'lua'",
                    "return M",
                },
                "\n"
            )
        ),
        "NUPP2008:3 NUPP2008:4"
    )
end

-- `unknown` is the top type: everything fits into it, but -- unlike `any` --
-- it does not fit anywhere else on its own. It is not gradual in `any`'s
-- sense; only the one direction is free.
function M.unknownIsTheTopType()
    local isA = relations.isA
    assert(isA(T.integer, T.unknown))
    assert(isA(T.string, T.unknown))
    assert(isA(T.nil_, T.unknown))
    assert(isA(T.func({T.number}, {T.boolean}, false), T.unknown))
    assert(not isA(T.unknown, T.integer))
    assert(not isA(T.unknown, T.string))
    assert(isA(T.unknown, T.unknown))
    -- any remains bidirectional, including against unknown
    assert(isA(T.any, T.unknown))
    assert(isA(T.unknown, T.any))
end

-- `never` is the bottom type: uninhabited, so it fits anywhere any type is
-- wanted, and nothing but itself fits into it.
function M.neverIsTheBottomType()
    local isA = relations.isA
    assert(isA(T.never, T.integer))
    assert(isA(T.never, T.string))
    assert(isA(T.never, T.unknown))
    assert(isA(T.never, T.never))
    assert(not isA(T.integer, T.never))
    assert(not isA(T.string, T.never))
    assert(not isA(T.nil_, T.never))
    -- a gradual source is not nothing either: `any` may be anything
    assert(not isA(T.any, T.never))
    assert(not isA(T.unknown, T.never))
    assertEq(
        diagsOf(
            table.concat(
                {"local function fail(): never", "   local x: any = 1", "   return x", "end", "print(fail)",},
                "\n"
            )
        ),
        "NUPP2002:3"
    )
end

---------------------------------------------------------------------------
-- checker
---------------------------------------------------------------------------

function M.andOrIdioms()
    assertClean("local flag: boolean\nlocal n: number = flag and 1 or 2")
    assertClean("local m: number?\nlocal n: number = m or 0")
    -- NOTE: "s and s .. '!' or 'none'" with s: string? needs narrowing to
    -- check cleanly; restored when the facts engine lands.
end

-- A computed key settles what a table constructor's type is -- a generic table --
-- and says nothing about the entries standing after it. Those used to go
-- unvisited, so anything wrong in one went unreported and anything the generator
-- needed the checker to resolve was never resolved.
function M.entriesAfterAComputedKeyAreStillChecked()
    assertEq((diagsOf("local t = {['a'] = 1, ['b'] = 'no' + 1}")), "NUPP2003:1")
    assertEq((diagsOf("local t = {['a'] = 1, b = 'no' + 1}")), "NUPP2003:1")
    assertEq((diagsOf("local t = {['a'] = 1, 'no' + 1}")), "NUPP2003:1")
    -- Every entry, not only the one after the first computed key.
    assertEq((diagsOf("local t = {['a'] = 1, ['b'] = 'no' + 1, ['c'] = 'no' + 1}")), "NUPP2003:1 NUPP2003:1")
    assertClean("local t = {['a'] = 1, ['b'] = 2}")
end

function M.cleanPrograms()
    assertClean("local x: number = 1 + 2")
    assertClean("local s: string = 'a' .. 1")
    assertClean("local n: integer = 7 // 2")
    assertClean("local b: boolean = 1 < 2")
    assertClean("local o: number? = nil")
    assertClean("local u: number | string = 'hi'")
    assertClean("local f = function(x: number): number return x * 2 end\nlocal y: number = f(3)")
    assertClean("local t: {number} = {1, 2, 3}")
    assertClean("local m: {[string]: number} = {}")
    assertClean("local p: {x: number, y: number} = {x = 1, y = 2}")
    assertClean("local a: any = 'whatever'\nlocal n: number = a")
    assertClean("local big: int64 = 10LL\nlocal same: int64 = big")
end

function M.inheritedContractsBoundsAndSelf()
    local src = table.concat(
        {
            "local interface Component",
            "   componentName: string",
            "   metamethod __call: function(self, ...: any): self",
            "end",
            "local interface Tagged",
            "   tag: string",
            "end",
            "local record Position is Component, Tagged",
            "   x: number",
            "end",
            -- the argument is the declaration's visible Type<C> witness;
            -- calling it runs the __call the bound declares and yields an instance
            "local function construct<C is Component>(c: Type<C>): C",
            "   local name: string = c.componentName",
            "   return c()",
            "end",
            "local made: Position = construct(Position)",
            "local tag: string = made.tag",
        },
        "\n"
    )
    assertClean(src)
    assertEq(
        (diagsOf(src .. table.concat({"", "local record Plain end", "local bad = construct(Plain)",}, "\n"))),
        "NUPP2116:18"
    )
end

function M.interfaceInheritanceRejectsCycles()
    assertEq(diagsOf("local interface Self is Self\nend"), "NUPP2117:1")
    assertEq(
        diagsOf(table.concat({"local interface A is B", "end", "local interface B is A", "end",}, "\n")),
        "NUPP2117:3"
    )
    assertEq(
        diagsOf(
            table.concat(
                {"local interface A is B", "end", "local interface B is C", "end", "local interface C is A", "end",},
                "\n"
            )
        ),
        "NUPP2117:5"
    )
    assertEq(diagsOf("local interface Recursive<T> is Recursive<{T}>\nend"), "NUPP2117:1")
end

function M.genericIndexContracts()
    assertClean(
        table.concat(
            {
                "local record Key<T> end",
                "local record Store",
                "   metamethod __index: function<T>(self, key: Key<T>): T",
                "   metamethod __newindex: function<T>(self, key: Key<T>, value: T)",
                "end",
                "local store: Store = new Store()",
                "local key = new Key<string>()",
                "local value: string = store[key]",
                "store[key] = 'saved'",
            },
            "\n"
        )
    )
end

function M.operatorContracts()
    local function binaryContract(metamethod, operator)
        assertClean(
            table.concat(
                {
                    "local record Result end",
                    "local record Right end",
                    "local record Left",
                    ("   metamethod %s: function(left: Left, right: Right): Result"):format(metamethod),
                    "end",
                    "local left, right: Left, Right = new Left(), new Right()",
                    ("local result: Result = left %s right"):format(operator),
                },
                "\n"
            )
        )
    end

    binaryContract("__add", "+")
    binaryContract("__sub", "-")
    binaryContract("__mul", "*")
    binaryContract("__div", "/")
    binaryContract("__mod", "%")
    binaryContract("__pow", "^")
    binaryContract("__concat", "..")

    assertClean(
        table.concat(
            {
                "local record Result end",
                "local record Operand",
                "   metamethod __unm: function(operand: Operand): Result",
                "end",
                "local operand: Operand = new Operand()",
                "local result: Result = -operand",
            },
            "\n"
        )
    )

    -- Lua consults the right operand when the left has no matching contract,
    -- but the contract still receives operands in source order.
    assertClean(
        table.concat(
            {
                "local record Result end",
                "local record Scale",
                "   metamethod __mul: function(left: number, right: Scale): Result",
                "end",
                "local scale: Scale = new Scale()",
                "local result: Result = 2 * scale",
            },
            "\n"
        )
    )

    local function comparisonContract(metamethod, operator, contractOnRight)
        local contract = (
            "   metamethod %s: function(left: %s, right: %s): boolean"
        ):format(metamethod, contractOnRight and "Right" or "Left", contractOnRight and "Left" or "Right")
        local left = contractOnRight and "local record Left end"
            or table.concat({"local record Left", contract, "end",}, "\n")
        local right = contractOnRight and table.concat({"local record Right", contract, "end",}, "\n")
            or "local record Right end"
        assertClean(
            table.concat(
                {
                    left,
                    right,
                    "local left, right: Left, Right = new Left(), new Right()",
                    ("local result: boolean = left %s right"):format(operator),
                },
                "\n"
            )
        )
    end

    comparisonContract("__lt", "<", false)
    comparisonContract("__lt", ">", true)
    comparisonContract("__le", "<=", false)
    comparisonContract("__le", ">=", true)

    -- Lua implements <= without __le as not (right < left), including the
    -- corresponding operand reversal.
    comparisonContract("__lt", "<=", true)

    assertEq((diagsOf("local n = #true")), "NUPP2003:1")
    assertEq(
        (diagsOf("local record A end\nlocal record B end\nlocal x: A = new A()\nlocal y: B = new B()\nprint(x < y)")),
        "NUPP2003:5"
    )
end

function M.metatableTypeIsACompilerKnownPhantom()
    assertClean(
        table.concat(
            {
                "local record R end",
                "local mt: metatable<R> = {__index = {}}",
                "local r: R = new R()",
                "setmetatable(r, mt)",
                "setmetatable(r, nil)",
            },
            "\n"
        )
    )
end

function M.inlineMethodsAreHoistedAndNestedAliasesAreQualified()
    assertClean(
        table.concat(
            {
                "local record Types",
                "   type Id = integer",
                "   record Counter",
                "      value: Types.Id",
                "      function even(self, n: integer): boolean",
                "         if n == 0 then return true end",
                "         return self:odd(n - 1)",
                "      end",
                "      function odd(self, n: integer): boolean",
                "         if n == 0 then return false end",
                "         return self:even(n - 1)",
                "      end",
                "   end",
                "end",
                "local id: Types.Id = 1",
                "local counter: Types.Counter = new Types.Counter(value = 0)",
                "local yes: boolean = counter:even(id)",
            },
            "\n"
        )
    )
end

-- Every declaration written together is filled before any record's bodies are
-- checked. An inline method used to be checked where its record stood, so it could
-- not read a field written below it, construct a nested record written after it
-- (NUPP2202, "no field"), or construct a table-qualified record declared after its
-- own (NUPP2006) -- although each is there by the time the method can run.
function M.inlineMethodsSeeDeclarationsWrittenAfterThem()
    assertClean(
        table.concat(
            {
                "local m = {}",
                "record m.A",
                "   function make(self): integer",
                "      local b = new m.B(v = 3)",
                "      local nested = new m.A.Inner(w = 4)",
                "      return b.v + nested.w + self.later + m.B.twice(1)",
                "   end",
                "   record Inner",
                "      w: integer",
                "      function sum(self, a: m.A): integer return self.w + a.later end",
                "   end",
                "   later: integer",
                "end",
                "record m.B",
                "   v: integer",
                "   function twice(x: integer): integer return x * 2 end",
                "end",
                "local total: integer = (new m.A(later = 1)):make()",
                "return m",
            },
            "\n"
        )
    )
end

-- A later `local record` is still not in scope in an earlier record's methods: Lua
-- has not reached that local where the method is written, so the name would read a
-- global. Deferring the bodies does not change what they can see.
function M.aLaterLocalRecordStaysOutOfAnEarlierMethodsScope()
    local got = diagsOf(table.concat({
        "local record A",
        "   function make(self): integer return (new B(v = 3)).v end",
        "end",
        "local record B",
        "   v: integer",
        "   function again(self): B return new B(v = self.v) end",
        "end",
        "print((new A()):make())",
    }, "\n"))
    -- An unknown name: NUPP2105 under the strict floor, and in this gradual file a
    -- construction with no known callable.
    assert(got:find("NUPP2105:2", 1, true) or got:find("NUPP2006:2", 1, true), got)
    assert(not got:find(":6", 1, true), "B names itself in its own method: " .. got)
end

function M.recordsWorkWithPairsAndMetatableTyposAreRejected()
    assertClean(
        table.concat(
            {
                "local record R",
                "   value: number",
                "end",
                "local r: R = new R(value = 0)",
                "for key, value in pairs(r) do print(key, value) end",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local record R end", "local r: R = new R()", "setmetatable(r, {__cal = function() end})",},
                    "\n"
                )
            )
        ),
        "NUPP2118:3"
    )
end

-- The customary-operator fix writes a word, and a word written flush against a
-- name fuses with it: `!ready` has to become `not ready`, not `notready`.
function M.aCustomaryOperatorFixKeepsItsOperandsApart()
    for _, case in ipairs({
        {"local ready = true\nlocal pending = !ready\nreturn pending", "local pending = not ready"},
        {"local a, b = true, false\nlocal c = a&&b\nreturn c", "local c = a and b"},
        {"local a, b = true, false\nlocal c = a||b\nreturn c", "local c = a or b"},
        {"local a, b = true, false\nlocal c = (!a) || b\nreturn c", "local c = (not a) or b"},
    }) do
        local source = case[1]
        for _ = 1, 2 do
            local _, found = diagsOf(source)
            local fix = nil
            for _, diag in ipairs(found) do
                if diag.code == "NUPP2504" and diag.fixes then
                    fix = diag.fixes[1]
                    break
                end
            end
            if not fix then
                break
            end
            source = applyFix(source, fix)
        end
        assert(source:find(case[2], 1, true), "fixed source:\n" .. source)
        assertClean(source)
    end
end

-- A module that returns the declaration itself has no table to attach it to, so
-- the NUPP2119 fix does not offer `record Loose.Loose`.
function M.aDeclarationIsNotAttachedToItself()
    local _, found = diagsOf("record Loose\n    x: number\nend\nreturn Loose")
    assertEq(found[1] and found[1].code, "NUPP2119")
    assert(not found[1].msg:find("Loose.Loose", 1, true), found[1].msg)
    for _, fix in ipairs(found[1].fixes or {}) do
        assert(not fix.title:find("attach", 1, true), fix.title)
        assertClean(applyFix("record Loose\n    x: number\nend\nreturn Loose", fix))
    end
    local module = "local shapes = {}\nrecord Point\n    x: number\nend\nreturn shapes"
    local _, attached = diagsOf(module)
    assertEq(attached[1].fixes[1].title, "attach it to shapes")
    assertClean(applyFix(module, attached[1].fixes[1]))
end

function M.metamethodTyposCarrySafeFixes()
    local literal = table.concat(
        {"local record R end", "local r: R = new R()", "setmetatable(r, {__cal = function() end})",},
        "\n"
    )
    local _, literalDiags = diagsOf(literal)
    local literalFixes = literalDiags[1] and literalDiags[1].fixes
    assertEq(literalFixes and #literalFixes or 0, 1, "one runtime metamethod spelling is uniquely closest")
    assertEq(literalFixes[1].title, "change to `__call`")
    assertClean(applyFix(literal, literalFixes[1]))

    local contract = table.concat(
        {"local record R", "   metamethod __idnex: function(self, key: any): any", "end",},
        "\n"
    )
    local _, contractDiags = diagsOf(contract)
    local contractFixes = contractDiags[1] and contractDiags[1].fixes
    assertEq(contractFixes and #contractFixes or 0, 1, "an adjacent transposition has one contract fix")
    assertEq(contractFixes[1].title, "change to `__index`")
    assertClean(applyFix(contract, contractFixes[1]))

    local missingPrefix = table.concat(
        {"local record R", "   metamethod index: function(self, key: any): any", "end",},
        "\n"
    )
    local _, prefixDiags = diagsOf(missingPrefix)
    local prefixFixes = prefixDiags[1] and prefixDiags[1].fixes
    assertEq(prefixFixes and #prefixFixes or 0, 1, "a known contract missing its prefix has one fix")
    assertClean(applyFix(missingPrefix, prefixFixes[1]))

    local runtimeOnly = table.concat({"local record R", "   metamethod __mode: function(self): string", "end",}, "\n")
    local _, unsupported = diagsOf(runtimeOnly)
    assert(not unsupported[1].fixes, "a valid runtime-only key is unsupported, not misspelled")
end

function M.unsupportedAndDuplicateContractsAreRejected()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local record R", "   metamethod __band: function(self, other: self): self", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2118:2"
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local record R", "   value: number", "   function value(): number return 1 end", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2118:3"
    )
end

function M.mismatchDiagnostics()
    assertEq((diagsOf("local x: number = 'oops'")), "NUPP2001:1")
    assertEq((diagsOf("local x: string\nx = 42")), "NUPP2001:2")
    assertEq((diagsOf("local x: integer = 1.5")), "NUPP2001:1")
    assertEq((diagsOf("local o: number? = 'no'")), "NUPP2001:1")
end

function M.constBindings()
    assertClean("const x: number = 1\nlocal y: number = x")
    assertClean("const t = {}\nt.value = 1")
    assertClean("local x = 1\ndo const x = 2 end")
    assertClean("const function f(n: number): number return n end\nf(1)")

    assertEq((diagsOf("const x = 1\nx = 2")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\nx += 2")), "NUPP2008:2")
    assertEq((diagsOf("const x\nx ??= 2")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\nlocal x = 2")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\ndo local x = 2 end")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\nlocal function f(x) end")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\nfor x = 1, 2 do end")), "NUPP2008:2")
    assertEq((diagsOf("const x = 1\nlocal f = x -> x")), "NUPP2008:2")
    assertEq((diagsOf("const function f() end\nf = nil")), "NUPP2008:2")
end

-- A table literal is contextually checked against the type it initializes, so a
-- literal's field may be written as the wider type. The same latitude must not
-- follow the literal into a name: a stored view of a binding would then write
-- what the binding's own reads do not admit. A literal with a const field is the
-- one that keeps its shape when bound (the others widen to `table`).
function M.aBoundLiteralIsNoLongerFresh()
    local animals = table.concat(
        {
            "local interface Animal",
            "   name: string",
            "end",
            "local record Dog is Animal",
            "   name: string",
            "   bark: string",
            "end",
        },
        "\n"
    )
    assertClean(
        animals .. table.concat(
            {
                "",
                "local pen: {value: Animal} = {const tag = 'k', value = new Dog(name = 'rex', bark = 'woof')}",
                "return pen",
            },
            "\n"
        )
    )
    assertEq(
        diagsOf(
            animals .. table.concat(
                {
                    "",
                    "local kennel = {const tag = 'k', value = new Dog(name = 'rex', bark = 'woof')}",
                    "local pen: {value: Animal} = kennel",
                    "return pen",
                },
                "\n"
            )
        ),
        "NUPP2001:9"
    )
    assertEq(
        diagsOf(
            animals .. table.concat(
                {
                    "",
                    "const kennel = {const tag = 'k', value = new Dog(name = 'rex', bark = 'woof')}",
                    "local pen: {value: Animal} = kennel",
                    "return pen",
                },
                "\n"
            )
        ),
        "NUPP2001:9"
    )
    assertClean(
        animals .. table.concat(
            {
                "",
                "const kennel = {const tag = 'k', value = new Dog(name = 'rex', bark = 'woof')}",
                "local pen: {@readonly value: Animal} = kennel",
                "return pen",
            },
            "\n"
        )
    )
end

-- `const T` reaches the whole value: a table-shaped member read through a const
-- view is itself a const view, and a method may only be called on one when it
-- asked for a read-only receiver.
function M.constReachesTheWholeValue()
    local decls = table.concat(
        {
            "local record Inner",
            "   n: integer",
            "   xs: {integer}",
            "end",
            "local record Outer",
            "   inner: Inner",
            "   m: {[string]: integer}",
            "   function bump(self): nil",
            "      self.inner.n = self.inner.n + 1",
            "   end",
            "   function peek(self: const Outer): integer",
            "      return self.inner.n",
            "   end",
            "end",
        },
        "\n"
    )
    assertEq(
        diagsOf(
            decls .. table.concat(
                {
                    "",
                    "local function f(o: const Outer): nil",
                    "   o.inner.n = 5",
                    "   o.m.k = 1",
                    "   o.inner.xs[1] = 3",
                    "   o:bump()",
                    "   local i: Inner = o.inner",
                    "end",
                    "print(f)",
                },
                "\n"
            )
        ),
        "NUPP2009:16 NUPP2009:17 NUPP2009:18 NUPP2006:19 NUPP2001:20"
    )
    assertClean(
        decls .. table.concat(
            {
                "",
                "local function f(o: const Outer): integer",
                "   local ci: const Inner = o.inner",
                "   local first: integer = o.inner.xs[1]",
                "   local k: integer? = o.m.k",
                "   return o:peek() + o.inner.n + ci.n + first + (k or 0)",
                "end",
                "local o = new Outer(inner = new Inner(n = 1, xs = {}), m = {})",
                "o:bump()",
                "print(f(o), Outer.peek(o))",
            },
            "\n"
        )
    )
    -- a const self is read-only inside the method too
    assertEq(
        diagsOf(
            table.concat(
                {
                    "local record R",
                    "   n: integer",
                    "   function reset(self: const R): nil",
                    "      self.n = 0",
                    "   end",
                    "end",
                    "print(R)",
                },
                "\n"
            )
        ),
        "NUPP2009:4"
    )
end

function M.namedVarargsAreConst()
    assertClean("local function f(...args) return args.n, args[1], ... end")
    assertClean("local f = |...args| -> args.n")
    assertEq((diagsOf("local function f(...args) args = {} end")), "NUPP2008:1")
    assertEq((diagsOf("local f = |...args| -> do\nlocal args = {}\nend")), "NUPP2008:2")
end

function M.operatorDiagnostics()
    assertEq((diagsOf("local x = 'a' + 1")), "NUPP2003:1")
    assertEq((diagsOf("local x = {} .. 'b'")), "NUPP2003:1")
    -- Lua would coerce '1' + 1 at runtime; the checker still flags it
    assertEq((diagsOf("local x = '1' + 1")), "NUPP2003:1")
end

function M.returnChecking()
    assertEq((diagsOf("local function f(): number return 'no' end")), "NUPP2002:1")
    assertEq((diagsOf("local function f(): number return 1, 2 end")), "NUPP2002:1")
    assertClean("local function f(): number, string return 1, 'ok' end")
    -- missing return value against an annotation
    assertEq((diagsOf("local function f(): number return end")), "NUPP2002:1")
end

function M.callChecking()
    local callSource = "local f = function(n: number) end\nf('x')"
    local code, callDiags = diagsOf(callSource)
    assertEq(code, "NUPP2006:2")
    assertEq(#(callDiags[1].related or {}), 1, "bad argument points back to the callable declaration")
    assert(callDiags[1].help:find("parameter list", 1, true), "bad call says what to compare")
    assertEq((diagsOf("local f = function(n: number) end\nf(1, 2)")), "NUPP2007:2")
    assertEq((diagsOf("local n: number = 1\nn(2)")), "NUPP2005:2")
    assertClean("local f = function(...: number): number return 0 end\nf(1, 2, 3)")
end

function M.omittedArgumentMustAcceptNil()
    -- An argument left off a call arrives as nil, so the parameter has to admit
    -- it whether or not the callable has a computed tail.
    local code, diags = diagsOf("local function f(x: string): string return x end\nlocal s: string = f()")
    assertEq(code, "NUPP2006:2")
    assert(diags[1].msg:find("omitted argument 1 supplies nil", 1, true), diags[1].msg)
    assertEq((diagsOf("local function f(x: string, y: integer): string return x end\nf('a')")), "NUPP2006:2")
    assertEq((diagsOf("local m = {}\nfunction m.f(x: string): string return x end\nm.f()")), "NUPP2006:3")
    assertClean("local function f(x: string, y: integer?): string return x end\nf('a')")
    assertClean("local function f(x: string, y: any): string return x end\nf('a')")
    assertClean("local function f(x: string, y: integer | nil) end\nf('a')")
    -- table.sort's comparator is optional, so leaving it off is fine.
    assertClean("local xs = {3, 1}\ntable.sort(xs)")
end

function M.fallingOffTheEndNeedsAnOptionalResult()
    -- Running off the end returns nothing, so a declared result has to admit nil.
    local code, diags = diagsOf(
        table.concat(
            {"local function maybe(flag: boolean): string", "    if flag then return 's' end", "end", "return maybe",},
            "\n"
        )
    )
    assertEq(code, "NUPP2002:3")
    assert(diags[1].msg:find("end of the function without returning", 1, true), diags[1].msg)
    assertEq((diagsOf("local function f(): integer, string\n    return 1\nend")), "NUPP2002:2")
    assertClean("local function maybe(flag: boolean): string?\n    if flag then return 's' end\nend")
    assertClean("local function f(): string, integer?\n    return 's'\nend")
    assertClean("local function f(flag: boolean): string\n    if flag then return 'a' else return 'b' end\nend")
    assertClean(
        "local function f(n: integer): string\n    if n == 1 then return 'a' elseif n == 2 then return 'b' else error('x') end\nend"
    )
    assertClean("local function f(): string\n    do return 'a' end\nend")
    assertClean("local function f(): string\n    while true do\n        return 'a'\n    end\nend")
    assertClean("local function f(): string\n    repeat\n        return 'a'\n    until false\nend")
    assertClean("local function f(): string\n    error('never')\nend")
    assertClean("local function f(): string\n    ::again::\n    do return 'a' end\n    goto again\nend")
    assertEq((diagsOf("local function f(flag: boolean): string\n    while flag do return 'a' end\nend")), "NUPP2002:3")
    assertEq(
        (
            diagsOf(
                "local function f(): string\n    while true do\n        if math.random() > 0.5 then break end\n    end\nend"
            )
        ),
        "NUPP2002:5"
    )
    assertEq((diagsOf("local function f(): string\n    for _ = 1, 3 do return 'a' end\nend")), "NUPP2002:3")
    assertEq(
        (
            diagsOf(
                "local function f(flag: boolean): string\n    if flag then return 'a' elseif not flag then return 'b' end\nend"
            )
        ),
        "NUPP2002:3"
    )
    -- Reaching the end of a body that ends in a label is reaching a target.
    assertEq((diagsOf("local function f(): string\n    do return 'a' end\n    ::done::\nend")), "NUPP2002:4")
    -- A chain over every member of a literal union, leaving through each, is complete.
    assertClean(
        table.concat(
            {
                "local type Color = 'red' | 'green'",
                "local function name(c: Color): string",
                "    if c == 'red' then return 'r' elseif c == 'green' then return 'g' end",
                "end",
            },
            "\n"
        )
    )
    -- A constructor's result is what `new` yields, not what its body returns.
    assertClean(
        table.concat(
            {
                "local record Box",
                "    value: integer",
                "    constructor(self, value: integer): Box",
                "        self.value = value",
                "    end",
                "end",
                "local b = new Box(1)",
                "print(b.value)",
            },
            "\n"
        )
    )
end

function M.fieldChecking()
    assertEq((diagsOf("local p: {x: number} = {x = 1}\nlocal y = p.nope")), "NUPP2004:2")
    assertClean("local p: {x: number} = {x = 1}\nlocal y: number = p.x")
    assertClean("local m: {[string]: number} = {}\nlocal v: number? = m['k']")
    assertEq((diagsOf("local a: {number} = {}\nlocal v = a['k']")), "NUPP2004:2")
end

function M.identifierTyposCarryUnambiguousFixes()
    local fieldSource = table.concat(
        {"local p: {horizontal: number} = {horizontal = 1}", "local value = p.horizonal",},
        "\n"
    )
    local _, fieldDiags = diagsOf(fieldSource)
    local fieldFix = fieldDiags[1] and fieldDiags[1].fixes and fieldDiags[1].fixes[1]
    assert(fieldFix, "field typo has a fix")
    assertEq(fieldFix.title, "change to `horizontal`")
    assertClean(applyFix(fieldSource, fieldFix))
    assertEq(fieldDiags[1].col, 17, "diagnostic points at the member")
    assertEq(fieldDiags[1].length, #"horizonal", "member span")

    local typeSource = "local value: stirng = 'x'"
    local _, typeDiags = diagsOf(typeSource)
    local typeFix = typeDiags[1] and typeDiags[1].fixes and typeDiags[1].fixes[1]
    assert(typeFix, "type typo has a fix")
    assertClean(applyFix(typeSource, typeFix))
end

function M.recordDeclarationsCheck()
    assertClean(
        table.concat(
            {
                "local record Point",
                "   x: number",
                "   y: number",
                "end",
                "local p: Point = new Point(x = 0, y = 0)",
                "local n: number? = p?.x",
            },
            "\n"
        )
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local record Point",
                        "   x: number",
                        "end",
                        "local p: Point = new Point(x = 0)",
                        "local v = p.z",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2004:5"
    )
end

function M.nominalProvenance()
    -- same shape, different declarations: not interchangeable
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local record A",
                        "   v: number",
                        "end",
                        "local record B",
                        "   v: number",
                        "end",
                        "local a: A = new A(v = 0)",
                        "local b: B = a",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2001:8"
    )
    -- but a record erodes to a matching structural shape
    assertClean(
        table.concat(
            {"local record A", "   v: number", "end", "local a: A = new A(v = 0)", "local s: {v: number} = a",},
            "\n"
        )
    )
end

function M.typeAliasAndLiteralUnionCheck()
    assertClean("local type Id = uint32\nlocal i: Id = 7\nlocal n: number = i")
    assertClean("local type Color = 'red' | 'green'\nlocal c: Color\nlocal s: string = c")
end

function M.unknownTypeNames()
    assertEq((diagsOf("local x: Wat = 1")), "NUPP2101:1")
end

function M.shortFunctionsTyped()
    assertClean("local dbl = |x: number| -> x * 2\nlocal n: number = dbl(3)")
    assertEq((diagsOf("local dbl = |x: number| -> x * 2\ndbl('a')")), "NUPP2006:2")
    assertClean("local always = || -> true\nlocal b: boolean = always()")
    assertClean("local blocky = |x: number| -> do return x end\nblocky(1)")
    -- single-parameter sugar; the return type is inferred from the body
    assertClean("local neg = n -> -n\nneg(5)")
end

function M.shortFunctionsInferCallbackParameters()
    local src = table.concat(
        {
            "local type Event = {name: string}",
            "local function observe<E is Event>(eventType: E, observer: function(E))",
            "end",
            "local event: Event = {name = 'ready'}",
            "observe(event, e -> do",
            "    local name: string = e.name",
            "end)",
        },
        "\n"
    )
    assertClean(src)
    assertEq((diagsOf(src:gsub("e.name", "e.missing"))), "NUPP2004:6")
    local longSrc = src:gsub("e %-%> do", "function(e)")
    assertClean(longSrc)
    assertEq((diagsOf(longSrc:gsub("e.name", "e.missing"))), "NUPP2004:6")
end

function M.shortFunctionReturnsCompleteGenericInference()
    local prefix = table.concat(
        {"local function map<T, U>(xs: {T}, f: function(T): U): {U}", "   error('not run')", "end",},
        "\n"
    )
    assertClean(prefix .. "\nlocal values: {number} = map({1, 2}, |x| -> x + 1)")
    assertEq(diagsOf(prefix .. "\nlocal values: {string} = map({1, 2}, |x| -> x + 1)"), "NUPP2001:4")
end

function M.interpolatedStringsTyped()
    assertClean("local n = 3\nlocal s: string = `n is ${n}, twice is ${n * 2}`")
    assertEq((diagsOf("local x: number = `just text ${1}`")), "NUPP2001:1")
    -- errors inside interpolations are still found
    assertEq((diagsOf("local s = `bad: ${'a' + 1}`")), "NUPP2003:1")
end

function M.castsAreTrusted()
    assertClean("local a: any\nlocal n: number = a as number")
    assertClean("local x: number = ('5' as any) as number")
end

-- `table` is gradual toward table structures, so a call takes it as evidence the
-- way it takes `any`: the binders a `table` argument meets read as `any` rather
-- than reporting NUPP2148 for parameters nothing bound.
function M.tableArgumentIsGradualEvidence()
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local env = require("nupp.compiler.project.env").new(here .. "/..")
    local function strictDiags(source)
        local result = parser.parse(source, "walk.nupp")
        assertEq(#result.errors, 0, "syntax errors")
        local out = {}
        for j, d in ipairs(check.check(result, "walk.nupp", env)) do
            out[j] = d.code .. ":" .. d.line .. " " .. d.msg
        end

        return table.concat(out, "\n")
    end
    assertEq(
        strictDiags(
            "local m = {}\n"
                .. "function m.walk(source: table): (string, integer)\n"
                .. "    for key, value in pairs(source) do\n"
                .. "        local s: string, n: integer = key, value\n"
                .. "        return s, n\n"
                .. "    end\n"
                .. "    for _, value in ipairs(source) do\n"
                .. "        local s: string = value\n"
                .. "        return s, 0\n"
                .. "    end\n"
                .. "    return '', 0\n"
                .. "end\n"
                .. "return m"
        ),
        "",
        "pairs and ipairs read a table's entries as any"
    )
    assertEq(
        strictDiags(
            "local m = {}\n"
                .. "local function firstKey<K, V>(t: {[K]: V}): K?\n    return (next(t))\nend\n"
                .. "local function pick<T>(t: {value: T}): T\n    return t.value\nend\n"
                .. "function m.use(source: table): (string?, integer)\n"
                .. "    local s: string? = firstKey(source)\n"
                .. "    local n: integer = pick(source)\n"
                .. "    return s, n\n"
                .. "end\n"
                .. "return m"
        ),
        "",
        "a map or shape parameter binds any from a table"
    )
end

function M.gradualDefaults()
    -- unannotated and unknown things check silently
    assertClean("print(unknown_global.deep.chain(1, 2))")
    assertClean("local x = some_global\nx = 5\nx = 'string'")
    -- inferred table literals stay open (module-table idiom);
    -- annotated shapes are closed
    assertClean("local M = {a = 1}\nM.b = 2\nlocal x = M.b")
    assertEq((diagsOf("local M: {a: number} = {a = 1}\nlocal x = M.b")), "NUPP2004:2")
    -- inferred bindings widen; annotated bindings stay exact
    assertClean("local i = 1\ni = i / 2")
    assertClean("local x = nil\nx = {}\nlocal v = x.field")
    assertEq((diagsOf("local i: integer\ni = 1.5")), "NUPP2001:2")
    -- disabling an inferred local function is legal; an annotated one is not
    assertClean("local function f() end\nf = nil")
    assertEq((diagsOf("local f: function() = function() end\nf = nil")), "NUPP2001:2")
end

-- A callee that borrows its extra arguments keeps none of them, and nothing owned
-- reaches a plain `...: any`, so it fits one. A slot that lends its extra
-- arguments still refuses a callee free to keep them.
function M.aBorrowingVarargTailFitsAPlainOne()
    assertClean(table.concat({
        "local f1: function(...: any) = print",
        "local f2: function(...: any): nil = print",
        "local f3: function(s: string): nil = print",
        "f1('a') f2('b') f3('c')",
    }, "\n"))
    assertEq(
        (diagsOf("local function keep(...: any): nil end\nlocal f: function(borrows ...: any): nil = keep\nf(1)")),
        "NUPP2001:2"
    )
end

-- A call whose callee is a dotted path reports what is wrong with the path once.
function M.aBrokenCalleePathIsReportedOnce()
    local R = "local record R\n    v: integer\nend\nlocal r = new R(v = 1)\n"
    assertEq((diagsOf(R .. "r.nope.goes()")), "NUPP2004:5")
    assertEq((diagsOf(R .. "local y = r.nope.goes(1)\nprint(y)")), "NUPP2004:5")
end

-- A local bound to a namespace path stands for the path: its exported types
-- resolve through it, and a scalar intrinsic read through it keeps the identity
-- the full spelling has, which is what native lowering admits.
function M.aNamespaceAliasKeepsTypesAndIntrinsics()
    local here = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
    local env = require("nupp.compiler.project.env").new(here .. "/..")
    local spanSource = table.concat({
        "local span = nupp.mem.span",
        "local function copy(output: span.WriteSpan<number>, input: span.Span<number>): nil",
        "    for index = 1, #output do output[index] = input[index] end",
        "end",
        "return copy",
    }, "\n")
    assertEq((checkedDiags(spanSource, env)), "", spanSource)
    local source = table.concat({
        "local i32 = nupp.math.i32",
        "local math32 = nupp.math",
        "local function mask(a: int32, b: int32): (int32, int32, int32)",
        "    return i32.andBits(a, b), nupp.math.i32.andBits(a, b), math32.i32.andBits(a, b)",
        "end",
        "return mask",
    }, "\n")
    local result = parser.parse(source, "test.g.nupp")
    local diags = check.check(result, "test.g.nupp", env)
    assertEq(#diags, 0, diags[1] and diags[1].msg or "check")
    local identities = {}
    local function walk(node)
        if type(node) ~= "table" or node.kind == nil then
            return
        end
        if node.kind == "call" then
            identities[#identities + 1] = tostring(node.scalarIntrinsic)
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end
    walk(result.root)
    assertEq(table.concat(identities, " "), "i32.andBits i32.andBits i32.andBits")
end

-- A union of functions is called member-wise: every member has to accept the
-- arguments, and the result is what any of them may answer.
function M.aUnionOfFunctionsIsCallableWhenEveryMemberAccepts()
    local defs = table.concat({
        "local function a(): nil print('a') end",
        "local function b(x: string?): nil print('b', x) end",
        "local function noop(...: any): nil end",
        "local function one(): integer return 1 end",
        "local function name(): string return 'n' end",
        "local function needs(x: string): nil print(x) end",
    }, "\n") .. "\n"
    assertClean(defs .. table.concat({
        "local function run(flag: boolean): nil",
        "   local h = flag ? a : b",
        "   h()",
        "   local log = flag and print or noop",
        "   log('x')",
        "   local pick = flag ? one : name",
        "   local r: integer | string = pick()",
        "   print(r)",
        "end",
        "return run",
    }, "\n"))
    assertEq(
        (diagsOf(defs .. "local function run(flag: boolean): nil\n   local f = flag ? a : needs\n   f()\nend\nreturn run")),
        "NUPP2005:9"
    )
    assertEq(
        (diagsOf(defs .. "local function run(flag: boolean): nil\n   local f = flag ? one : name\n   local n: integer = f()\nend\nreturn run")),
        "NUPP2001:9"
    )
end

-- A `.lua` file is run by LuaJIT unchanged, so the typed layer is refused there
-- exactly where LuaJIT would refuse it: the ternary is its own syntax, while floor
-- division, `??=` and interpolated strings are not.
function M.plainLuaRefusesWhatLuaJITDoesNotRun()
    local function plain(source)
        local tree = parser.parse(source, "plain.lua")
        assertEq(#tree.errors, 0, "syntax: " .. (tree.errors[1] and tree.errors[1].msg or ""))
        local out = {}
        for _, diag in ipairs(check.check(tree, "plain.lua", nil, {})) do
            if diag.code == "NUPP1006" then
                out[#out + 1] = diag.code .. ":" .. diag.line
            end
        end
        return table.concat(out, " ")
    end
    assertEq(plain("local a = true\nlocal x = a ? 1 : 2\nreturn x"), "")
    assertEq(plain("local y = 7 // 2\nreturn y"), "NUPP1006:1")
    assertEq(plain("local z = 7\nz //= 2\nreturn z"), "NUPP1006:2")
    assertEq(plain("local w = nil\nw ??= 1\nreturn w"), "NUPP1006:2")
    assertEq(plain("local n = 1\nlocal s = `n is ${n}`\nreturn s"), "NUPP1006:2")
end

-- `never` has no values, so it adds nothing to a union, and `x or error(...)` is
-- the type of `x`. Keeping it as a member made every field read fail.
function M.neverAddsNothingToAUnion()
    assertEq(T.union({T.never, T.string}), T.string)
    assertEq(T.union({T.never}), T.never)
    assertEq(T.union({}), T.never)
    assertEq(T.optional(T.never), T.nil_)
    local shape = "local record Circle\n    kind: 'circle'\n    radius: number\nend\n"
    assertClean(
        shape .. table.concat(
            {
                "local function a(input: Circle?): number",
                "    local s = input or error('missing')",
                "    return s.radius",
                "end",
                "local function b(input: Circle?): number",
                "    local s = input ?? error('missing')",
                "    return s.radius",
                "end",
                "local function c(input: {radius: number}?): number",
                "    local s = input or error('missing')",
                "    return s.radius",
                "end",
                "return a, b, c",
            },
            "\n"
        )
    )
end

-- A colon call reaches a member the way a field read does, so a receiver that may
-- be nil, a union whose alternatives disagree, `unknown`, an unbounded type
-- parameter, an array and a function all lack a method until narrowed. Each of
-- these used to type the call as `any` and say nothing.
function M.aColonCallNeedsTheMethodOnEveryAlternative()
    local R = "local record R\n    v: integer\n    function get(self): integer\n        return self.v\n    end\nend\n"
    local cases = {
        {"local function f(s: string?): string return s:upper() end", "NUPP2004:1"},
        {"local function f(r: R?): integer return r:get() end", "NUPP2004:7", R},
        {"local function f(u: string | integer): string return u:upper() end", "NUPP2004:1"},
        {"local function f(u: unknown): integer return u:status() end", "NUPP2004:1"},
        {"local function f<T>(x: T): integer return x:size() end", "NUPP2004:1"},
        {"local function f(xs: {integer}): integer return xs:count() end", "NUPP2004:1"},
        {"local function f(g: function(): nil): integer return g:call() end", "NUPP2004:1"},
    }
    for _, case in ipairs(cases) do
        local source = (case[3] or "") .. case[1]
        assertEq((diagsOf(source)), case[2], source)
    end
    -- Narrowed first, or called through the safe form, the method is there.
    assertClean("local function f(s: string?): string? return s?.:upper() end")
    assertClean("local function f(s: string?): string if s then return s:upper() end return '' end")
    assertClean(R .. "local function f(r: R?): integer if r then return r:get() end return 0 end")
    assertClean("local function f(u: 'a' | 'b' | string): string return u:upper() end")
    assertClean("local function f(x: any, t: table): nil x:anything() t:anything() end")
end

-- `unknown` accepts anything, but using one without narrowing or casting
-- first is an ordinary type error -- the same one any other mismatched type
-- would get, since nothing in the checker gives `unknown` a pass the way it
-- does `any`.
function M.unknownNeedsNarrowingOrACast()
    assertClean("local a: unknown = 5")
    assertClean("local b: unknown = 'text'")
    assertEq((diagsOf("local a: unknown = 5\nlocal s: string = a")), "NUPP2001:2")
    assertEq((diagsOf("local a: unknown = 5\nprint(a.field)")), "NUPP2004:2")
    assertEq((diagsOf("local a: unknown = 5\nprint(a + 1)")), "NUPP2003:2")
    assertClean("local a: unknown = 5\nlocal s = a as string\nprint(s)")
    assertClean(
        table.concat(
            {
                "local record P",
                "   x: integer",
                "end",
                "local a: unknown = new P(x = 1)",
                "if a is P then print(a.x) end",
            },
            "\n"
        )
    )
end

-- `never` is what a function that always raises returns; declaring it lets
-- the checker catch a path that returns after all, the same way any other
-- return-type mismatch is caught.
function M.neverAsAReturnType()
    assertClean(table.concat({"local function bail(msg: string): never", "   error(msg)", "end", "print(bail)",}, "\n"))
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local function bail(x: integer): never",
                        "   if x > 0 then return end",
                        "   error('no')",
                        "end",
                        "print(bail)",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2002:2"
    )
    -- a never-returning call leaves the block, narrowing what follows
    assertClean(
        table.concat(
            {
                "local function bail(msg: string): never",
                "   error(msg)",
                "end",
                "local function use(s: string?)",
                "   if not s then bail('missing') end",
                "   print(#s)",
                "end",
                "print(use)",
            },
            "\n"
        )
    )
end

-- The grammar carries `where`, the formatter keeps it and `nupp doc` renders it
-- into a signature, and no checker code reads the expression. A constraint that
-- constrains nothing is worth a diagnostic rather than a footnote.
-- A refinement is the runtime test that decides whether a value is one of
-- these. An interface has no table to stamp, so it is the only identity one can
-- have; a record and a struct already answer `is` exactly, so they may not
-- carry one.
function M.refinementsAreEnforced()
    assertClean(
        table.concat(
            {
                "local interface Circle",
                "   kind: string",
                "   radius: number",
                "   satisfies |self| -> self.kind == 'circle'",
                "end",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {"local interface Tagged", "   tag: string", "   satisfies |self| -> type(self.tag) == 'string'", "end",},
            "\n"
        )
    )
    -- and it composes the way a test does
    assertClean(
        table.concat(
            {
                "local interface Both",
                "   a: integer",
                "   b: boolean",
                "   c: boolean",
                "   satisfies |self| -> self.a == 1 and (self.b or not self.c)",
                "end",
            },
            "\n"
        )
    )
    assertClean("local record Even\n   n: integer\nend")
    -- `matches` stays contextual: a field may still be called one
    assertClean("local record F\n   matches: string\nend")
end

-- A bare field is a truthiness test, as the refinements page says, so it lowers
-- to the access itself: `false` fails it, where `~= nil` would have let it through.
function M.aBareFieldRefinementIsATruthinessTest()
    local predicate = require("nupp.compiler.types.predicate")
    assertEq(predicate.render({op = "truthy", path = {"enabled"}}, "v"), "v.enabled")
    assertEq(predicate.render({op = "truthy", path = {"a", "b"}}, "v"), "v.a?.b")
    assertEq(predicate.render({op = "not", a = {op = "truthy", path = {"off"}}}, "v"), "not (v.off)")
end

-- `#` is the one accessor the refinement subset admits: it reads one value, answers
-- an integer, allocates nothing and calls nothing, so it keeps the properties that
-- let `is` be written anywhere. It reads the same either way round.
function M.aLengthRefinementIsAdmittedAndNormalised()
    local predicate = require("nupp.compiler.types.predicate")
    assertClean(
        table.concat(
            {
                "local interface Short",
                "   name: string",
                "   satisfies |self| -> type(self.name) == 'string' and #self.name <= 4",
                "end",
            },
            "\n"
        )
    )
    local node = {op = "len", path = {"name"}, a = {op = "cmp", cmp = "<=", path = {}, literal = "4", constant = 4}}
    assertEq(predicate.render(node, "v"), '(type(v.name) == "string" and #v.name <= 4)')
    assertEq(predicate.satisfiedByValue(node, {name = "abcd"}), true)
    assertEq(predicate.satisfiedByValue(node, {name = "abcde"}), false)
    assertEq(predicate.satisfiedByValue(node, {name = 7}), nil)
    assertEq(predicate.satisfiedByValue(node, {name = {1}}), nil)
    assertEq(predicate.satisfiedByValue(node, 7), nil)
    -- the subject itself, which is what a constrained scalar constrains
    local bare = {op = "len", path = {}, a = {op = "cmp", cmp = ">=", path = {}, literal = "2", constant = 2}}
    assertEq(predicate.render(bare, "v"), '(type(v) == "string" and #v >= 2)')
    assertEq(predicate.satisfiedByValue(bare, "ab"), true)
    assertEq(predicate.satisfiedByValue(bare, "a"), false)
end

function M.aRefinementRejectsOrderedBooleanAndNilComparisons()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local interface Invalid",
                        "   enabled: boolean",
                        "   satisfies |self| -> self.enabled < true",
                        "end",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2122:3"
    )
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local interface Invalid", "   value: any", "   satisfies |self| -> self.value >= nil", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2122:3"
    )
end

function M.refinementsRecognizeConstantLogicalAnswers()
    local function refuses(test)
        return diagsOf(
            table.concat({"local interface I", "   enabled: boolean", "   satisfies |self| -> " .. test, "end",}, "\n")
        )
    end

    assertEq(refuses("false and self.enabled"), "NUPP2122:3")
    assertEq(refuses("true or self.enabled"), "NUPP2122:3")
end

function M.refinementsAcceptOrdinaryNumericLiteralForms()
    assertClean(
        table.concat(
            {
                "local interface Bounded",
                "   n: number",
                "   satisfies |self| -> self.n >= -1_000 and self.n < 0x10",
                "end",
            },
            "\n"
        )
    )
end

-- Three-valued against a value, the way `satisfiedBy` is against declared fields:
-- proved, refuted, or undecided because the refinement reads what is not there.
function M.satisfiedByValueAnswersThreeWays()
    local predicate = require("nupp.compiler.types.predicate")
    local inRange = {
        op = "and",
        a = {op = "cmp", cmp = ">=", path = {}, literal = "0", constant = 0},
        b = {op = "cmp", cmp = "<=", path = {}, literal = "31", constant = 31},
    }
    assertEq(predicate.satisfiedByValue(inRange, 7), true)
    assertEq(predicate.satisfiedByValue(inRange, 32), false)
    assertEq(predicate.satisfiedByValue(inRange, -1), false)
    -- a string is not ordered against a number, so neither comparison answers
    assertEq(predicate.satisfiedByValue(inRange, "7"), nil)
    assertEq(predicate.satisfiedByValue({op = "typeis", path = {}, luaType = "string"}, "x"), true)
    assertEq(predicate.satisfiedByValue({op = "typeis", path = {}, luaType = "string"}, 1), false)
end

-- A declaration is held to the refinements of the interfaces it declares, where
-- its own fields settle the answer: a field typed `false` fails a truthiness test,
-- and a `string` field fails `type() == "number"`. A `boolean` field settles
-- nothing and stays silent.
function M.aRefinementIsProvedAgainstDeclaredFields()
    local enabled = table.concat(
        {"local interface Enabled", "   enabled: boolean", "   satisfies |self| -> self.enabled", "end",},
        "\n"
    )
    assertEq((diagsOf(enabled .. "\nlocal record Off is Enabled\n   enabled: false\nend")), "NUPP2122:5")
    assertClean(enabled .. "\nlocal record On is Enabled\n   enabled: true\nend")
    assertClean(enabled .. "\nlocal record Either is Enabled\n   enabled: boolean\nend")
    local numbered = table.concat(
        {
            "local interface Numbered",
            "   name: string | integer",
            "   satisfies |self| -> type(self.name) == 'number'",
            "end",
        },
        "\n"
    )
    assertEq((diagsOf(numbered .. "\nlocal record Named is Numbered\n   name: string\nend")), "NUPP2122:5")
    assertClean(numbered .. "\nlocal record Counted is Numbered\n   name: integer\nend")
end

-- A constrained type is its base narrowed: it goes wherever the base goes, a
-- narrower one goes where a wider one is wanted, and nothing enters it that is not
-- already narrowed at least as far. A literal is decided rather than admitted.
function M.constrainedTypesNarrowTheirBase()
    local aliases = table.concat(
        {
            "local type Percent = nupp.types.range(integer, 0, 100)",
            "local type Digit = nupp.types.range(Percent, 0, 9)",
            "local type Short = nupp.types.length(string, 1, 4)",
        },
        "\n"
    )
    assertClean(aliases .. "\nlocal function widen(p: Percent): integer\n   return p\nend\nreturn widen")
    assertClean(aliases .. "\nlocal function fits(d: Digit): Percent\n   return d\nend\nreturn fits")
    assertClean(aliases .. "\nlocal ok: Percent = 50\nreturn ok")
    assertClean(aliases .. "\nlocal ok: Short = 'abcd'\nreturn ok")
    -- the wider one is not established as the narrower
    assertEq((diagsOf(aliases .. "\nlocal function no(p: Percent): Digit\n   return p\nend\nreturn no")), "NUPP2002:5")
    -- nor is the bare base
    assertEq(
        (diagsOf(aliases .. "\nlocal function no(n: integer): Percent\n   return n\nend\nreturn no")),
        "NUPP2002:5"
    )
    -- a literal outside the interval is a violation, not a missing admission
    assertEq((diagsOf(aliases .. "\nlocal no: Percent = 101\nreturn no")), "NUPP2001:4")
    assertEq((diagsOf(aliases .. "\nlocal no: Short = 'abcde'\nreturn no")), "NUPP2001:4")
end

-- An alias is not a brand: one constraint over one base is one type however many
-- names reach it, and however the bounds were written.
function M.constrainedTypesAreStructural()
    assertClean(
        table.concat(
            {
                "local type A = nupp.types.range(integer, 0, 31)",
                "local type B = nupp.types.range(integer, 0, 31)",
                "local function pass(a: A): B",
                "   return a",
                "end",
                "return pass",
            },
            "\n"
        )
    )
end

-- The bounds are checked where they are written, so a declaration that admits
-- nothing is reported rather than compiled into a test no value passes.
function M.constrainedDeclarationsAreValidated()
    assertEq((diagsOf("local type E = nupp.types.range(integer, 10, 0)\nreturn E")), "NUPP2422:1")
    assertEq((diagsOf("local type E = nupp.types.length(integer, 0, 4)\nreturn E")), "NUPP2422:1")
    assertEq((diagsOf("local type E = nupp.types.range(string, 0, 4)\nreturn E")), "NUPP2422:1")
    assertEq((diagsOf("local type E = nupp.types.range(uint32, -1, 4)\nreturn E")), "NUPP2422:1")
    -- an intersection that admits nothing
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local type Small = nupp.types.range(integer, 0, 9)",
                        "local type None = nupp.types.range(Small, 20, 30)",
                        "return None",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2422:2"
    )
end

-- A record's identity is the metatable `new` stamps and a struct's is its
-- ctype. A refinement beside either would be a second answer to a settled
-- question, and which answer `is R` gave would depend on whether a body
-- happened to carry one.
function M.onlyAnInterfaceCarriesARefinement()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {"local record R", "   kind: string", "   satisfies |self| -> self.kind == 'r'", "end",},
                    "\n"
                )
            )
        ),
        "NUPP2122:3"
    )
    assertEq(
        (diagsOf(table.concat({"local struct S", "   n: int32", "   satisfies |self| -> self.n == 1", "end",}, "\n"))),
        "NUPP2122:3"
    )
    -- one per declaration
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local interface J",
                        "   n: integer",
                        "   satisfies |self| -> self.n == 1",
                        "   satisfies |self| -> self.n == 2",
                        "end",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2122:4"
    )
    -- and the clause that used to sit in the head says where it went
    assertEq(
        (diagsOf(table.concat({"local interface I where self.n == 1", "   n: integer", "end",}, "\n"))),
        "NUPP2122:1"
    )
end

-- Each rejection names what was written rather than pointing at a list of what
-- is allowed. The subset exists so the test can run wherever `is` is written,
-- which rules out calls, arithmetic, and anything outside the subject.
-- `record C is Shape` is a claim the checker proves, and Shape's refinement is
-- what `is Shape` runs. When C's own fields make that test fail, the two
-- disagree about the same value and nothing at either site shows it.
function M.aDeclarationIsHeldToTheRefinementsItInherits()
    assertEq(
        (
            diagsOf(
                table.concat(
                    {
                        "local interface Shape",
                        "   kind: string",
                        "   satisfies |self| -> self.kind == 'shape'",
                        "end",
                        "local record Circle is Shape",
                        "   kind: 'circle'",
                        "   radius: number",
                        "end",
                    },
                    "\n"
                )
            )
        ),
        "NUPP2122:5"
    )
    -- a tag that agrees is fine
    assertClean(
        table.concat(
            {
                "local interface Shape",
                "   kind: string",
                "   satisfies |self| -> self.kind == 'circle'",
                "end",
                "local record Circle is Shape",
                "   kind: 'circle'",
                "end",
            },
            "\n"
        )
    )
    -- so is a type test the declared field satisfies
    assertClean(
        table.concat(
            {
                "local interface Shape",
                "   kind: string",
                "   satisfies |self| -> type(self.kind) == 'string'",
                "end",
                "local record Circle is Shape",
                "   kind: 'circle'",
                "end",
            },
            "\n"
        )
    )
    -- and a field no declaration settles decides nothing either way
    assertClean(
        table.concat(
            {
                "local interface Open",
                "   n: integer",
                "   satisfies |self| -> self.n == 1",
                "end",
                "local record Any is Open",
                "   n: integer",
                "end",
            },
            "\n"
        )
    )
end

function M.refinementsRejectWhatCannotBeEnforced()
    local function refuses(test)
        return (
            diagsOf(
                table.concat({"local interface I", "   n: integer", "   satisfies |self| -> " .. test, "end",}, "\n")
            )
        )
    end

    -- arithmetic reaches nothing about the value
    assertEq(refuses("1 + 1 == 3"), "NUPP2122:3")
    -- a constant decides nothing: this one says yes to every value
    assertEq(refuses("true"), "NUPP2122:3")
    -- and this one says no to all of them
    assertEq(refuses("false"), "NUPP2122:3")
    -- a field the declaration does not have compiles to a test never true
    assertEq(refuses("self.nope == 'x'"), "NUPP2122:3")
    -- a call cannot be made where `is` is written
    assertEq(refuses("tostring(self.n) == '1'"), "NUPP2122:3")
    -- nor can anything outside the subject be read
    assertEq(refuses("other == 1"), "NUPP2122:3")
end

-- An untyped function's results are any number of `any`, and print as such: a
-- written `...unknown` is a different tail whose values fit nowhere unnarrowed.
function M.anUndeclaredResultTailRendersAsAny()
    local tail = T.pack({}, {kind = "unknown", type = T.any})
    assertEq(T.tostringPack(tail), "(...any)")
    assertEq(T.tostringPack(T.pack({}, {kind = "homogeneous", type = T.unknown})), "(...unknown)")
    assertEq(
        T.tostring(T.func({}, {T.any}, false, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil)),
        "function(): any"
    )
end

-- Untyped exports of a declared module are the strict floor's second rule, so a
-- `.g.nupp` asking for the typed syntax without the floor reports neither, and
-- the same file held to the floor reports both.
function M.untypedExportsAreTheStrictFloorsRule()
    local source = table.concat({"module models", "", "export function double(n)", "    return n * 2", "end",}, "\n")
    local gradual = parser.parse(source, "models.g.nupp")
    assertEq(#gradual.errors, 0, "syntax errors")
    local codes = {}
    for j, d in ipairs(check.check(gradual, "models.g.nupp")) do
        codes[j] = d.code .. ":" .. d.line
    end
    assertEq(table.concat(codes, " "), "", "a gradual file holds no floor")
    local strict = parser.parse(source, "models.nupp")
    codes = {}
    for j, d in ipairs(check.check(strict, "models.nupp")) do
        codes[j] = d.code .. ":" .. d.line
    end
    assertEq(table.concat(codes, " "), "NUPP2106:3 NUPP2106:3", "a strict file reports both")
end

function M.constructionWidensAnInferredLiteral()
    -- A field is a slot the value can be replaced in, so the type argument
    -- construction infers from a literal is the literal's type: `Box<integer>`,
    -- not `Box<1>`, the way `{1}` is an `{integer}`.
    assertClean(
        table.concat(
            {
                "local record Box<T>",
                "    value: T",
                "end",
                "local b: Box<integer> = new Box(value = 1)",
                "local s: Box<string> = new Box(value = 'a')",
                "b.value = 2",
                "s.value = 'b'",
                "return b, s",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local record Pair<T>",
                "    first: T",
                "    second: T",
                "end",
                "local p: Pair<integer> = new Pair(first = 1, second = 2)",
                "return p",
            },
            "\n"
        )
    )
end

return M
