local parser = require("nupp.compiler.syntax.parser")
local checker = require("nupp.compiler.check")
local environment = require("nupp.compiler.project.env")
local program = require("nupp.compiler.vm.programgraph")
local tagged = require("nupp.compiler.vm.taggedprofile")
local executable = require("nupp.compiler.vm.coregraphexecutable")
local contracts = require("nupp.compiler.vm.coregraphcontracts")
local M = {}

local function refuses(f, text)
    local ok, message = pcall(f)
    assert(not ok, "accepted forged diagnostic metadata")
    assert(tostring(message):find(text, 1, true), tostring(message))
end

local function processForwarding(moduleName, recordName, swapped)
    moduleName = moduleName or 'io.internal.process'
    recordName = recordName or 'Process'
    local env = environment.new('.', {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local fileName, filePath = 'io.internal.fileformat', '=argument_fileformat.nupp'
    local file = parser.parse(
        [[
module io.internal.fileformat
const host = require('nupp.runtime.hostcalls')
export function seek(self: any, direction: any, offset: any): (any, any)
    host.argerror(2, '?', 'invalid option', 2)
    return nil, nil
end
export function setvbuf(self: any, mode: any, size: any): (any, any)
    return nil, nil
end
]],
        filePath
    )
    assert(#file.errors == 0)
    local ds, _, exports = checker.check(file, filePath, env, {moduleName = fileName, strict = false})
    for _, d in ipairs(ds) do
        assert(d.severity ~= 'error', d.msg)
    end
    local resolve = env.resolveModuleExports
    env.resolveModuleExports = function(self, name)
        return name == fileName and exports or resolve(self, name)
    end
    local path = '=argument_process.nupp'
    local source = (
        'module %s\nlocal file = require("io.internal.fileformat")\nlocal record %s\n'
        .. 'function seek(self, direction: any, offset: any): (any, any)\n'
        .. 'local value, problem = file.seek(self, %s)\nreturn value, problem\nend\nend\nexport = %s\n'
    ):format(moduleName, recordName, swapped and 'offset, direction' or 'direction, offset', recordName)
    local parsed = parser.parse(source, path)
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = checker.check(parsed, path, env, {moduleName = moduleName, strict = false})
    for _, d in ipairs(diagnostics) do
        assert(d.severity ~= 'error', d.msg)
    end
    local p = program.describe(
        {
            {name = fileName, path = filePath, parsed = file, diagnostics = ds},
            {name = moduleName, path = path, parsed = parsed, diagnostics = diagnostics}
        },
        moduleName
    )

    return program.compile(p, tagged.forVersion(8))
end

function M.onlyIssuedProcessRecordAndExactFileImportForwardErrors()
    local input = processForwarding()
    local _, rows = contracts.normalize(input, 8)
    local count = 0
    for _, row in ipairs(rows) do
        if row.forward ~= 0 then
            count = count + 1
            assert(row.forward == 1 and row.name == '?' and not row.method)
        end
    end
    assert(count == 1, count)
    for _, spec in ipairs({
        {'nupp.core.callarguments', 'Process', false},
        {'io.internal.process', 'Other', false},
        {'io.internal.process', 'Process', true}
    }) do
        local _, negative = contracts.normalize(processForwarding(unpack(spec)), 8)
        for _, row in ipairs(negative) do
            assert(row.forward == 0)
        end
    end
end

function M.processForwardingRejectsChangedCalleeAndMissingImportSite()
    local input = processForwarding()
    local output = executable.fromChecked(input, 8)
    local call
    for _, site in ipairs(input.catalog.calls) do
        if site.node.kind == 'call' and site.node.obj.kind == 'dotIndex' then
            call = site.node;
            break
        end
    end
    assert(call)
    local member = call.obj.name.text
    call.obj.name.text = 'setvbuf'
    refuses(
        function()
            executable.validate(output)
        end,
        'checked call diagnostics changed'
    )
    call.obj.name.text = member
    executable.validate(output)
    local requirement
    for _, site in ipairs(input.catalog.requires) do
        if site.module == 'io.internal.fileformat' then
            requirement = site;
            break
        end
    end
    assert(requirement)
    input.catalog.requireByNode[requirement.node] = nil
    local ok = pcall(executable.validate, output)
    assert(not ok, 'missing checked require authorized diagnostic forwarding')
    input.catalog.requireByNode[requirement.node] = requirement
    executable.validate(output)
    local original = call.obj.obj.token.definition
    call.obj.obj.token.definition = nil
    ok = pcall(executable.validate, output)
    assert(not ok, 'changed import binding authorized diagnostic forwarding')
    call.obj.obj.token.definition = original
    executable.validate(output)
end

return M
