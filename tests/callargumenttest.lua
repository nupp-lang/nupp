local parser = require('nupp.compiler.syntax.parser')
local checker = require('nupp.compiler.check')
local environment = require('nupp.compiler.project.env')
local program = require('nupp.compiler.vm.programgraph')
local tagged = require('nupp.compiler.vm.taggedprofile')
local executable = require('nupp.compiler.vm.coregraphexecutable')
local contracts = require('nupp.compiler.vm.coregraphcontracts')
local codec = require('nupp.compiler.vm.coregraphcodec')
local M = {}

local function checked(source)
    local path, name = '=call_arguments.nupp', 'nupp.core.callarguments'
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
    local p = program.describe({{name = name, path = path, parsed = parsed, diagnostics = ds}}, name)

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

return M
