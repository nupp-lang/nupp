local parser = require('nupp.compiler.syntax.parser')
local checker = require('nupp.compiler.check')
local environment = require('nupp.compiler.project.env')
local program = require('nupp.compiler.vm.programgraph')
local tagged = require('nupp.compiler.vm.taggedprofile')
local executable = require('nupp.compiler.vm.coregraphexecutable')
local contracts = require('nupp.compiler.vm.coregraphcontracts')
local codec = require('nupp.compiler.vm.coregraphcodec')
local M = {}

local function checked(source, moduleName)
    local path, name = '=call_arguments.nupp', moduleName or 'nupp.core.callarguments'
    local parsed = parser.parse(
        source
        or [[
module nupp.core.callarguments
const host = require('nupp.runtime.hostcalls')
local function failure(self: any, value: any): nil
    host.argerror(2, '?', 'invalid format', 2)
end
local box = {read = failure}
local reader = box.read
box:read('x')
reader(box, 'x')
pcall(reader, box, 'x')
export = nil
]],
        path
    )
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local env = environment.new('.', {memoryOnly = true, cache = false, nativeCompilerServices = false})
    local ds = checker.check(parsed, path, env, {
        moduleName = name,
        strict = false,
        lints = {['unused-binding'] = 'off'}
    })
    for _, d in ipairs(ds) do
        assert(d.severity ~= 'error', d.msg)
    end
    local modules = {{name = name, path = path, parsed = parsed, diagnostics = ds}}
    if source and source:find('rawget(_G', 1, true) then
        -- Establish _G through a checked module, as the full guest catalog does.
        -- Metadata tests do not execute this deliberately empty host table.
        local libraryName = 'nupp.runtime.libraryvalues'
        local libraryPath = '=call_arguments_library.nupp'
        local library = parser.parse('module ' .. libraryName .. '\nexport const functions = {_G = {}}\n', libraryPath)
        assert(#library.errors == 0)
        local diagnostics = checker.check(library, libraryPath, env, {moduleName = libraryName, strict = false})
        for _, diagnostic in ipairs(diagnostics) do
            assert(diagnostic.severity ~= 'error', diagnostic.msg)
        end
        table.insert(modules, 1, {name = libraryName, path = libraryPath, parsed = library, diagnostics = diagnostics})
    end
    local p = program.describe(modules, name)

    return program.compile(p, tagged.forVersion(8))
end

local function refuses(f, text)
    local ok, msg = pcall(f);
    assert(not ok, 'accepted forged diagnostic metadata');
    assert(tostring(msg):find(text, 1, true), tostring(msg))
end

function M.checkedSourceKeepsSemanticResultAndSeparateCallDiagnostics()
    local input = checked();
    local semantic, diags = contracts.normalize(input, 8)
    assert(semantic.schema.version == 8 and semantic.diagnostics == nil)
    assert(#diags == 3, #diags)
    assert(diags[1].method == true and diags[1].name == 'read')
    assert(diags[2].method == false and diags[2].name == 'reader')
    assert(diags[3].method == false and diags[3].name == nil)
    local output = executable.fromChecked(input, 8);
    executable.validate(output)
    assert(#output.diagnostics == 3 and output.semantic.diagnostics == nil)
    for _, c in ipairs(output.semantic.contracts) do
        assert(c.method == nil and c.name == nil and c.effect == 1)
    end
end

function M.oldProfileEightWithoutPrimitiveKeepsLegacyEnvelope()
    local output = executable.fromChecked(
        checked(
            [[
module nupp.core.callarguments
local function plain(value: any): nil
    return nil
end
plain(nil)
export = nil
]]
        ),
        8
    )
    executable.validate(output)
    assert(output.diagnostics == nil and output.semantic.schema.version == 8)
    local encoded = codec.encode(output.semantic)
    assert(type(encoded) == 'string' and #encoded > 0)
end

function M.copiedMissingOrMutatedDiagnosticsCannotAuthorizeExecution()
    local output = executable.fromChecked(checked(), 8)
    local saved = output.diagnostics
    output.diagnostics = nil;
    refuses(
        function()
            executable.validate(output)
        end,
        'issued executable metadata changed'
    )
    output.diagnostics = saved
    saved[1].method = false;
    refuses(
        function()
            executable.validate(output)
        end,
        'issued executable metadata changed'
    )
    saved[1].method = true
    saved[2].name = 'pcall';
    refuses(
        function()
            executable.validate(output)
        end,
        'issued executable metadata changed'
    )
    saved[2].name = 'reader';
    executable.validate(output)
    local fake = {};
    for k, v in pairs(output) do
        fake[k] = v
    end
    refuses(
        function()
            executable.validate(fake)
        end,
        'unissued executable catalog'
    )
end

function M.rawV2RejectsDiagnosticFields()
    local semantic, diags = contracts.normalize(checked(), 8)
    semantic.diagnostics = diags
    refuses(
        function()
            codec.encode(semantic)
        end,
        'unknown semantic field'
    )
end

function M.changedIssuedSourceAndMissingCallsiteMapsAreRejected()
    local input = checked()
    local output = executable.fromChecked(input, 8)
    local site
    for _, item in ipairs(input.catalog.calls) do
        if item.node.kind == 'methodCall' then
            site = item;
            break
        end
    end
    assert(site)
    local name = site.node.name.text
    site.node.name.text = 'forgedName'
    refuses(
        function()
            executable.validate(output)
        end,
        'checked call diagnostics changed'
    )
    site.node.name.text = name
    executable.validate(output)
    input.catalog.callByNode[site.node] = nil
    refuses(
        function()
            executable.validate(output)
        end,
        'callsite'
    )
end

function M.diagnosticObjectsCannotBecomeSemanticCallAuthority()
    local input = checked()
    input.diagnostics = {{method = true, name = 'read', target = 0}}
    refuses(
        function()
            executable.fromChecked(input, 8)
        end,
        'unknown semantic field'
    )
    input.diagnostics = nil
    local output = executable.fromChecked(input, 8)
    output.diagnostics[1].target = 0
    refuses(
        function()
            executable.validate(output)
        end,
        'issued executable metadata changed'
    )
end

local function forwardingSource(name, member)
    return (
        [[
module %s
const host = require('nupp.runtime.hostcalls')
local original: any = rawget(_G, 'io')
local luaRead = original.%s
local processInput: any = nil
local function readFile(...: any): ...any
    if processInput ~= nil then
        return processInput:read(...)
    end
    return luaRead(...)
end
local function failure(): nil
    host.argerror(1, 'io.read', 'invalid format', 2)
end
readFile('x')
failure()
export = nil
]]
    ):format(name, member)
end

function M.onlyCheckedStandardWrapperHostBindingsForwardDiagnostics()
    local _, rows = contracts.normalize(
        checked(forwardingSource('nupp.runtime.standardio', 'read'), 'nupp.runtime.standardio'),
        8
    )
    local plain, receiver = 0, 0
    for _, row in ipairs(rows) do
        if row.forward == 1 then
            assert(row.name == 'io.read' and not row.method)
            plain = plain + 1
        elseif row.forward == 2 then
            assert(row.name == 'io.read' and row.method)
            receiver = receiver + 1
        end
    end
    assert(plain == 1 and receiver == 1)
    for _, spec in ipairs({{'nupp.core.callarguments', 'read'}, {'nupp.runtime.standardio', 'write'}}) do
        local _, negative = contracts.normalize(checked(forwardingSource(spec[1], spec[2]), spec[1]), 8)
        for _, row in ipairs(negative) do
            -- A receiver insertion is independent of the different plain binding.
            assert(row.forward == 0 or spec[1] == 'nupp.runtime.standardio' and row.forward == 2)
        end
    end
end

function M.forwardingRowsCannotChangeSemanticAuthorityOrIssuedContext()
    local input = checked(forwardingSource('nupp.runtime.standardio', 'read'), 'nupp.runtime.standardio')
    local output = executable.fromChecked(input, 8)
    local found
    for _, row in ipairs(output.diagnostics) do
        if row.forward == 1 then
            found = row;
            break
        end
    end
    assert(found)
    found.forward = 2
    refuses(
        function()
            executable.validate(output)
        end,
        'issued executable metadata changed'
    )
    found.forward = 1
    executable.validate(output)
    for _, call in ipairs(output.semantic.contracts) do
        assert(call.forward == nil)
    end
    local site
    for _, call in ipairs(input.catalog.calls) do
        if call.node.kind == 'call' and call.node.obj.kind == 'name' and call.node.obj.token.text == 'luaRead' then
            site = call;
            break
        end
    end
    assert(site)
    local definition = site.node.obj.token.definition
    site.node.obj.token.definition = nil
    local ok = pcall(function()
        executable.validate(output)
    end)
    assert(not ok, 'changed checked callee granted forwarding')
    site.node.obj.token.definition = definition
    executable.validate(output)
end

function M.checkedStandardOsBindingForwardsOnlyItsIssuedHostCall()
    local input = checked(
        [[
module nupp.runtime.standardos
const host = require('nupp.runtime.hostcalls')
local original: any = rawget(_G, 'os')
local luaRemove = original.remove
export function remove(value: any): ...any
    return luaRemove(value)
end
local function failure(): nil
    host.argerror(1, 'os.remove', 'invalid argument', 2)
end
remove(false)
failure()
]],
        'nupp.runtime.standardos'
    )
    local output = executable.fromChecked(input, 8)
    executable.validate(output)
    local count = 0
    for _, row in ipairs(output.diagnostics) do
        if row.forward ~= 0 then
            count = count + 1
            assert(row.forward == 1 and row.name == 'os.remove' and not row.method)
        end
    end
    assert(count == 1)
end

return M
