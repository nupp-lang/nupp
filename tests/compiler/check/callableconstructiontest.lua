local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local env = require("nupp.compiler.project.env").new(require("helpers.paths").tests .. "/..")

local function compile(source)
    local parsed = parser.parse(source, "callable.nupp")
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = check.check(parsed, "callable.nupp", env)
    local errors = {}
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.severity ~= "warning" then
            errors[#errors + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
    end

    return parsed, errors
end

-- Each program is its own module, so declarations two programs share a name
-- in stay distinct.
local programs = 0

local function run(source)
    programs = programs + 1
    local name = "callable" .. programs
    local parsed = parser.parse(source, name .. ".nupp")
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = check.check(parsed, name .. ".nupp", env, {moduleName = name})
    for _, diagnostic in ipairs(diagnostics) do
        assert(diagnostic.severity == "warning", diagnostic.code .. ": " .. diagnostic.msg)
    end

    return program.run(parsed, name)
end

local suite = {}

function suite.defaultConstructionAndAliases()
    local Point, direct, alias, chained = run(
        [[
local record Point
    x: number
    y: number = 4
    function total(self): number return self.x + self.y end
end
local Make: Type<Point> = Point
local a = Point(x = 3)
local b = Make(x = 5)
return Point, a:total(), b:total(), Point(x = 7):total()
]]
    )
    assert(direct == 7 and alias == 9 and chained == 11)
    assert(Point(10):total() == 14, "declarations are callable from Lua")
    assert(
        not pcall(setmetatable, Point, {
            __call = function()
                return {}
            end
        }),
        "construction handler is protected"
    )
end

function suite.instanceCallIsSeparateFromConstruction()
    local Handler, result = run(
        [[
local record Handler
    prefix: string
    constructor(self, prefix: string) self.prefix = prefix end
    metamethod __call: function(self, request: string): string
end
Handler.__call = function(self: Handler, request: string): string
    return self.prefix .. request
end
local handler = Handler("hello ")
return Handler, handler("world")
]]
    )
    assert(result == "hello world")
    assert(Handler("Lua ")("caller") == "Lua caller")
end

function suite.overloadsAgreeWithLuaCalls()
    local Value, numberValue, textValue = run(
        [[
local record Value
    text: string
    constructor(self, value: integer) self.text = tostring(value) end
    constructor(self, value: string) self.text = value end
end
local Make = Value
return Value, Value(42).text, Make("ready").text
]]
    )
    assert(numberValue == "42" and textValue == "ready")
    assert(Value(17).text == "17" and Value("lua").text == "lua")
    assert(not pcall(Value, true))
end

function suite.structAliasesUseExplicitConstructors()
    local Vec, result = run(
        [[
local struct Vec
    x: float
    y: float
    constructor(self, value: float) self.x = value self.y = value end
end
local Make: Type<Vec> = Vec
local value = Make(3)
return Vec, value.x + value.y
]]
    )
    assert(result == 6)
    local value = Vec(5)
    assert(value.x == 5 and value.y == 5)
end

function suite.defaultsAreFreshAndDistinguishOmission()
    local Box = run([[
local record Box
    values: {integer} = {}
    label: string? = "default"
end
return Box
]])
    local a, b = Box(), Box()
    a.values[1] = 1
    assert(b.values[1] == nil)
    assert(a.label == "default")
    assert(Box({}, nil).label == nil)
end

function suite.instancesAndGenericBoundsDoNotImplyConstructors()
    for _, source in ipairs({
        "local record R end local value = R() return value()",
        [[local interface Callable metamethod __call: function(self): self end
local function build<T is Callable>(declaration: Type<T>): T return declaration() end]],
    }) do
        local _, errors = compile(source)
        assert(#errors > 0, "calling an instance or unknown construction signature must be rejected")
    end
end

function suite.erasedOverloadDifferencesAreRejected()
    local _, errors = compile(
        [[
local record Box<T> value: T end
local record Pick
    constructor(self, value: Box<string>) end
    constructor(self, value: Box<number>) end
end
]]
    )
    assert(table.concat(errors, " "):find("cannot be distinguished at runtime", 1, true))
end

function suite.declarationsWorkAsTypedReferences()
    local a, b = run(
        [[
local record Point x: integer end
local record Value
    x: integer
    constructor(self, x: integer) self.x = x + 1 end
end
local function point(make: Type<Point>): integer return make(3).x end
local function value(make: Type<Value>): integer return make(3).x end
return point(Point), value(Value)
]]
    )
    assert(a == 3 and b == 4)
end

function suite.computedCalleeRunsBeforeArgumentsOnce()
    local result = run(
        [[
local order: string = ""
local record Point x: integer end
local function choose(): Type<Point> order = order .. "c" return Point end
local function value(): integer order = order .. "v" return 9 end
local point = choose()(value())
return order .. tostring(point.x)
]]
    )
    assert(result == "cv9", result)
end

function suite.runtimeOverloadsUseArityLiteralsNominalsAndOptionalArguments()
    local Value, A, B = run(
        [[
local record A end
local record B end
local record Value
    text: string
    constructor(self) self.text = "empty" end
    constructor(self, which: 'first', value: integer) self.text = "first" end
    constructor(self, which: 'rest', ...: integer) self.text = "rest" end
    constructor(self, value: A) self.text = "A" end
    constructor(self, value: B) self.text = "B" end
end
return Value, A, B
]]
    )
    assert(Value().text == "empty")
    assert(Value("first", 1).text == "first")
    assert(Value("rest", 1, 2).text == "rest")
    assert(Value(A()).text == "A" and Value(B()).text == "B")
    local Optional = run(
        [[
local record Optional
    text: string
    constructor(self, value: string?) self.text = value ?? "missing" end
    constructor(self, value: integer) self.text = tostring(value) end
end
return Optional
]]
    )
    assert(Optional().text == "missing" and Optional(nil).text == "missing")
    assert(Optional("text").text == "text" and Optional(5).text == "5")
end

function suite.checkedDeclarationReplacementIsRejectedThroughAliases()
    local _, errors = compile(
        [[
local record R end
local Alias: Type<R> = R
setmetatable(Alias, {__call = function(): R return R() end})
]]
    )
    assert(table.concat(errors, " "):find("construction handler cannot be replaced", 1, true))
end

function suite.portableStructHookKeepsRawAllocationSeparate()
    local structs = require("nupp.runtime.provider.tablestruct")
    local count = 0
    local S = structs.define({name = "S", fields = {{name = "x", kind = "int32"}}}, {
        __index = {},
        __new = function(ct, x)
            count = count + 1
            local value = ct:zero()
            value.x = x + 1
            return value
        end,
    })
    assert(S(7).x == 8 and count == 1)
    assert(S:zero().x == 0 and count == 1)
end

function suite.generatedConstructorExposesSignatureHelp()
    local parsed, errors = compile("local record Point x: integer y: string end return Point(x = 1, y = 's')")
    assert(#errors == 0, table.concat(errors, "\n"))
    local found

    local function visit(node)
        if node.construction then
            found = require("nupp.compiler.constructors").signatureAt(node)
        end
        for _, child in ipairs(node) do
            if child.kind then
                visit(child)
            end
        end
    end

    visit(parsed.root)
    assert(found and found.tag == "func" and #found.params == 2)
    assert(found.paramNames[1] == "x" and found.paramNames[2] == "y")
end

function suite.callableConstructionRetainsAllocationEffect()
    local _, errors = compile("local record R end @noalloc do local value = R() end")
    assert(table.concat(errors, " "):find("constructs a managed value", 1, true))
    local _, explicitErrors = compile(
        [[
local record R constructor(self) end end
local function make(): R return R() end
@noalloc do local value = make() end
]]
    )
    assert(#explicitErrors > 0, "an explicit constructor allocates even when its body is empty")
end

function suite.interfacesCanOwnFactoryAndDescriptorNamespaces()
    local Factory, value, size = run(
        [[
local interface Factory
    record Options size: integer end
    read: function(self: Factory): integer
    function of(size: integer): Options return Options(size = size) end
end
local record Value is Factory
    function read(self): integer return 4 end
end
local options: Factory.Options = Factory.Options(size = 8)
return Factory, Value():read(), Factory.of(options.size).size
]]
    )
    assert(value == 4 and size == 8)
    assert(Factory.Options(12).size == 12)
    assert(not pcall(Factory), "interfaces have no constructor")
end

function suite.largeGeneratedConstructorsStayWithinLuaLocalLimit()
    local fields = {}
    for index = 1, 220 do
        fields[index] = "f" .. index .. ": integer?"
    end
    local Large = run("local record Large " .. table.concat(fields, " ") .. " end return Large")
    -- A call passes at most 128 values on the VM; the handler still reads every
    -- declared field, and the ones past the arguments stay nil.
    local args = {}
    for index = 1, 128 do
        args[index] = index
    end
    local built = Large(table.unpack(args))
    assert(built.f128 == 128 and built.f220 == nil)
end

function suite.constructorsInitializeReadonlyFieldsOnlyThroughTheirReceiver()
    assert(
        run(
            [[
local record Value
    @readonly x: integer
    constructor(self, x: integer) self.x = x end
end
return Value(7).x
]]
        ) == 7
    )
    for _, source in ipairs({
        [[local record V @readonly x: integer constructor(self) self.x = 1 end end
local v = V() v.x = 2]],
        [[local record V @readonly x: integer
constructor(self, other: V) self.x = 1 other.x = 2 end end]],
        [[local record V @readonly x: integer
constructor(self) self.x = 1 local later = function(): nil self.x = 2 end later() end end]],
        [[local record V @readonly x: integer
constructor(self) self.x = 1 local self = V() self.x = 2 end end]],
    }) do
        local _, errors = compile(source)
        assert(table.concat(errors, " "):find("read-only", 1, true), table.concat(errors, "\n"))
    end
end

function suite.exportedInterfacesExposeTheirStaticNamespace()
    local parsed, errors = compile(
        [[
module callable
export sealed interface Factory
    function of(value: string): string return value end
end
]]
    )
    assert(#errors == 0, table.concat(errors, "\n"))
    local value = assert(parsed.moduleExports.values.Factory)
    assert(value.tag == "metatable", "an exported interface value is its declaration namespace")
    assert(value.of.staticByname.of, "the namespace carries its factory")
    local factory = program.run(parsed, "callable").Factory
    local make = factory.of
    assert(make("held factory") == "held factory")
end

function suite.interfaceCallContractsBelongToInstances()
    local _, errors = compile(
        [[
local interface Callable
    metamethod __call: function(self): string
    function of(): string return "factory" end
end
local held = Callable
local invalid = held()
]]
    )
    assert(#errors > 0, "an interface declaration has no constructor")
    local _, valid = compile(
        [[
local interface Callable metamethod __call: function(self): string end
local function invoke(value: Callable): string return value() end
]]
    )
    assert(#valid == 0, table.concat(valid, "\n"))
end

return suite
