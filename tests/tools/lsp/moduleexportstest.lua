local refactor = require("nupp.tools.moduleexports")
local parser = require("nupp.compiler.syntax.parser")
local test = require("assert")
local check = require("helpers.fragment")
local gen = require("nupp.compiler.lua.gen")
local M = {}

local function convert(source)
    local result = refactor.plan(source)
    assert(result.source, result.reason)
    test.eq(#parser.parse(result.source).errors, 0)
    return result.source
end

function M.moduleNameAndExplicitConstantsConvert()
    local result = convert("module api\nlocal api = {}\nconst api.answer = 42\nexport = api\n")
    test.matches(result, "module api")
    test.matches(result, "export const answer = 42")
end

function M.functionsTypesAndConstantsKeepTheirNamesAndComments()
    local result = convert(
        [=[module sample
local api = {}
--- A point.
record api.Point
    x: number
end
api.answer = 42
--- Return a point.
function api.make(): api.Point
    return api.Point(x = api.answer)
end
export = api
]=]
    )
    test.matches(result, "export record Point")
    test.matches(result, "export const answer = 42")
    test.matches(result, "export function make%(%)%: Point")
    test.matches(result, "Point%(x = answer%)")
    test.matches(result, "%-%-%- A point%.")
    test.eq(result:find("export =", 1, true), nil)
    test.eq(result:find("api.", 1, true), nil)
    test.eq(refactor.plan(result).reason, "no export assignment")
end

function M.stringsCommentsAndOtherObjectsKeepTheirText()
    local result = convert(
        [=[module sample
local api = {}
-- api.get is documented here.
function api.get(value: any): any
    return {text = "api.get", other = value.api}
end
export = api
]=]
    )
    test.matches(result, "%-%- api%.get is documented here%.")
    test.matches(result, '"api%.get"')
    test.matches(result, "value%.api")
end

function M.refusesChangesToIdentityMutationOrBindings()
    local fixtures = {
        'local api = {}\nfunction api.get(): any return api end\nexport = api',
        'local api = {}\nfunction api.get(): nil end\nexport = setmetatable(api, {})',
        'local api = {}\nfunction api.get(): nil end\napi.get = nil\nexport = api',
        'local api = {}\nfunction api.get(get: any): any return api.get(get) end\nexport = api',
        'local api = {}\nfunction api.get(): any return get() end\nexport = api',
        'local api = {}\nfunction api.get(api: any): any return api.get end\nexport = api',
        'local api = {}\nfunction api.get(key: string): any return api[key] end\nexport = api',
        'local api = {}\nfunction api.get(): nil for get = 1, 2 do api.get() end end\nexport = api',
        'local api = {}\nfunction api.get<get>(): nil end\nexport = api',
        'local api = {}\nfunction api.get(x) return x end\nexport = api',
        'local api = {}\nfunction api.get(): nil end\nfunction api.reset(): nil function api.get(): nil end end\nexport = api',
        'local api = require("other")\nexport = api',
        'local api = {answer = 42}\nexport = api',
    }
    for _, fixture in ipairs(fixtures) do
        local result = refactor.plan("module sample\n" .. fixture .. "\n")
        assert(result.reason and not result.edits, fixture)
    end
end

function M.qualifiedTypeMethodsRemainMethods()
    local result = convert(
        [=[module sample
local api = {}
record api.Point
    x: number
end

function api.Point:twice(): number return self.x * 2 end
export = api
]=]
    )
    test.matches(result, "export record Point")
    test.matches(result, "function Point:twice")
end

function M.promotesLocalFunctionsWithoutChangingTheirBindings()
    local source = [=[module sample
local api = {}
--- Count down recursively.
local function countdown(n: number): number
    return n == 0 and 0 or countdown(n - 1) + 1
end
local saved = countdown
local function same(): boolean
    return saved == countdown
end
api.countdown = countdown
api.same = same
function api.run(n: number): number return api.countdown(n) end
export = api
]=]
    local converted = convert(source)
    test.matches(converted, "export function countdown")
    test.matches(converted, "export function same")
    test.matches(converted, "%-%-%- Count down recursively%.")
    test.eq(converted:find("api.countdown = countdown", 1, true), nil)
    test.eq(converted:find("export =", 1, true), nil)
    local saved = package.loaded.sample
    for _, text in ipairs({source, converted}) do
        local parsed = parser.parse(text, "sample.nupp")
        local diagnostics = check.check(parsed, "sample.nupp")
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local lua, errors = gen.generate(parsed, "sample.nupp")
        test.eq(#errors, 0)
        local module = assert(loadstring(lua))()
        test.eq(module.run(5), 5)
        test.eq(module.same(), true)
    end
    package.loaded.sample = saved
end

function M.refusesUnsafeLocalFunctionPublication()
    local fixtures = {
        'local before = get\nlocal function get(): nil end\napi.get = get',
        'local function get(): nil end\nlocal before = api.get\napi.get = get',
        'api.get = get\nlocal function get(): nil end',
        'local function get(): nil end\napi.get = get\nget = function(): nil end',
        'local function get(): nil end\napi.get = get\nfunction get(): nil end',
        'local function get(): nil end\napi.get = get\nlocal function get(): nil end',
        'local function get(): nil end\napi.get = get\nlocal function call(get: any): any return api.get() end',
        'local function get(): nil end\napi.get = get\napi.get = get',
        'local function get() end\napi.get = get',
        'local function get(value): any return value end\napi.get = get',
    }
    for _, fixture in ipairs(fixtures) do
        local result = refactor.plan("module sample\nlocal api = {}\n" .. fixture .. "\nexport = api\n")
        assert(result.reason and not result.edits, fixture)
    end
end

function M.moduleAliasCanAlsoBeAnExportedMemberName()
    local result = convert(
        [=[module sample
local api = {}
function api.api(): integer return 42 end
function api.get(): integer return api.api() end
export = api
]=]
    )
    test.matches(result, "export function api%(%)")
    test.matches(result, "return api%(%)")
end

function M.convertedExportsExecuteWithRecursionAndTypeMethods()
    local source = [=[module sample
local api = {}
local closed: integer = 0
record api.Point
    x: integer
end
function api.Point:twice(): integer return self.x * 2 end
const api.answer = 42
function api.even(n: integer): boolean
    return n == 0 or api.odd(n - 1)
end
function api.odd(n: integer): boolean
    return n ~= 0 and api.even(n - 1)
end
function api.close(takes point: api.Point): nil closed += point.x end
function api.make(): affine(api.Point, api.close)
    return api.Point(x = api.answer)
end
function api.discard(): integer
    do local value = api.make() end
    return closed
end
export = api
]=]
    local saved = package.loaded.sample
    for _, text in ipairs({source, convert(source)}) do
        local parsed = parser.parse(text, "sample.nupp")
        local diagnostics = check.check(parsed, "sample.nupp")
        test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        local lua, errors = gen.generate(parsed, "sample.nupp")
        test.eq(#errors, 0)
        local module = assert(loadstring(lua))()
        test.eq(module.make():twice(), 84)
        test.eq(module.even(10), true)
        test.eq(module.odd(10), false)
        test.eq(module.discard(), 42)
    end
    package.loaded.sample = saved
end

return M
