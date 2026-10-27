-- Source programs for the Nupp record and physical-field handlers. The native
-- contract tests additionally exercise wide slots and exact error paths.
local test = require("nupp.test")
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")
local serial = 0

local function run(source)
    serial = serial + 1
    local name = "native_records_" .. serial
    local tree = parser.parse(source, name .. ".nupp")
    test.equal(#tree.errors, 0, "syntax errors")
    local diagnostics = check.check(tree, name .. ".nupp", env, {moduleName = name})
    test.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg or "check diagnostics")

    return program.run(tree, name)
end

local M = {}

function M.recordSlotsRetainValuesAcrossCollectionAndMethodCalls()
    local before, after, yes, no = run(
        [[
local record Item
    value: number
    label: string
    function replace(self, value: number): nil
        collectgarbage()
        self.value = value
    end
end
local record Other value: number end
local item = new Item(value = -0.0, label = 'retained')
local alias = item
local before = 1 / item.value
item:replace(17.5)
collectgarbage()
local erased: any = item
return before, alias.value, erased is Item, erased is Other
]]
    )
    test.equal(before, -math.huge)
    test.equal(after, 17.5)
    test.equal(yes, true)
    test.equal(no, false)
end

function M.physicalScalarAndWideFieldsKeepTheirExactValues()
    local small, unsigned, wide, flag, fractional = run(
        [[
local struct Scalars
    small: int8
    unsigned: uint16
    wide: uint64
    flag: boolean
    fractional: float64
end
local value = new Scalars(-127, 65535, 18446744073709551615ULL, true, -0.0)
value.small = -23
value.unsigned = 50000
value.wide = 9223372036854775809ULL
collectgarbage()
return value.small as integer, value.unsigned as integer,
    value.wide == 9223372036854775809ULL, value.flag, 1 / value.fractional
]]
    )
    test.equal(small, -23)
    test.equal(unsigned, 50000)
    test.equal(wide, true)
    test.equal(flag, true)
    test.equal(fractional, -math.huge)
end

function M.physicalFloatWritesReadBackThroughTypedFields()
    local first, second = run(
        [[
local struct Pair x: float32 y: float64 end
local value = new Pair(1.25, -3.5)
local alias = value
value.x = 4.5
value.y = 9.25
collectgarbage()
return alias.x as number, alias.y
]]
    )
    test.equal(first, 4.5)
    test.equal(second, 9.25)
end

return M
