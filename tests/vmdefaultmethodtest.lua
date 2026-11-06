local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local checker = require("helpers.fragment")
local environment = require("nupp.compiler.project.env")
local lower = require("nupp.compiler.vm.lower")
local ROOT = require("helpers.paths").root
local METHODS = 96
local M = {}

local function execute(kind)
    local name = "vmdefaultmethodtest." .. kind
    local path = ROOT .. "/tests/" .. name .. ".nupp"
    local source = {
        "local label: string = 'before'",
        "local integral: integer = 1",
        "local fractional: number = 0.5",
        "local " .. kind .. " Defaults",
    }
    for index = 1, METHODS do
        source[#source + 1] = ("function value%d(self): (string, integer, number, any)"):format(index)
        source[#source + 1] = ("return label, integral + %d, fractional + %d, _G['marker']"):format(index, index)
        source[#source + 1] = "end"
    end
    source[#source + 1] = "end"
    if kind == "interface" then
        source[#source + 1] = "local record Instance is Defaults end"
    end
    source[#source + 1] = "label = 'after'; integral = 11; fractional = 2.5"
    source[#source + 1] = kind == "interface" and "return Instance()" or "return Defaults()"
    local result = parser.parse(table.concat(source, "\n"), path)
    test.eq(#result.errors, 0, result.errors[1] and result.errors[1].msg)
    local diagnostics = checker.check(result, path, environment.new(ROOT), {moduleName = name, strict = false})
    test.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    result.root.vmModuleExports = result.moduleExports
    local image = lower.emit(
        name,
        {},
        function(candidate)
            return candidate == name and path or nil
        end,
        function()
            return result.root
        end,
        true
    )
    local globals = setmetatable({marker = kind .. " environment"}, {__index = _G})
    globals._G = globals
    local value = assert(__nupp_load_image(image))({value = globals})
    for index = 1, METHODS do
        local label, integral, fractional, marker = value["value" .. index](value)
        test.eq(label, "after")
        test.eq(integral, 11 + index)
        test.eq(fractional, 2.5 + index)
        test.eq(marker, kind .. " environment")
    end
end

function M.environmentAwareInterfaceDefaultsReclaimClosureTemporaries()
    execute("interface")
end

function M.environmentAwareRecordMethodsReclaimClosureTemporaries()
    execute("record")
end

return M
