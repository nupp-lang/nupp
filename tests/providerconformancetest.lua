local parser = require("nupp.compiler.parser")
local check = require("fragment")
local gen = require("nupp.compiler.gen")
local env = require("nupp.compiler.env")
local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local M = {}

local function verify(contract, provider)
    local path = HERE .. "/provider-contracts/" .. contract .. ".nupp"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a");
    file:close()
    local tree = parser.parse(source, path)
    assert(#tree.errors == 0, tree.errors[1] and tree.errors[1].msg)
    local diagnostics = check.check(tree, path, env.new(HERE .. "/.."))
    assert(#diagnostics == 0, diagnostics[1] and diagnostics[1].msg)
    local code, errors = gen.generate(tree, path)
    assert(#errors == 0, errors[1] and errors[1].msg)
    local suite = assert(loadstring(code, "@" .. path))()
    local ok, problem = suite.test(require(provider))
    assert(ok, provider .. ": " .. tostring(problem))
end

function M.scalarBitopsMatchSignedWordVectors()
    verify("bitops", "nupp.runtime.provider.scalarbitops")
end

function M.nativeBitopsMatchSignedWordVectors()
    verify("bitops", "bit")
end

function M.jsonPreservesMarkersAndGenericArrays()
    verify("json", "nupp.runtime.provider.lunajson")
end

function M.portableBuffersPreserveFifoAndBinaryValues()
    verify("textbuffer", "nupp.runtime.provider.tablebuffer")
end

function M.nativeBuffersPreserveFifoAndBinaryValues()
    verify("textbuffer", "nupp.runtime.provider.nativebuffer")
end

function M.tableStructsPreserveValueOperations()
    verify("structvalue", "nupp.runtime.provider.tablestruct")
end

function M.simdExportsTheScalarFunctionsDirectly()
    local simd = require("nupp.simd")
    local scalar = require("nupp.runtime.provider.scalarsimd")
    for _, name in ipairs({"preferredU8", "maskBits64", "tableU8x16", "alignBytes", "paddedStringU8"}) do
        assert(simd[name] == scalar[name], name .. " must retain the implementation function")
    end
    verify("simd", "nupp.runtime.provider.scalarsimd")
end

function M.suspensionPreservesOwnershipAndHandlerIdentity()
    verify("suspension", "nupp.suspension")
end

function M.pathOperationsMatchTheContract()
    verify("path", "nupp.io.path.provider")
end

function M.uriOperationsMatchTheContract()
    verify("uri", "nupp.io.uri.provider")
end

function M.uuidOperationsMatchTheContract()
    verify("uuid", "nupp.runtime.uuid")
end

function M.systemFactsMatchTheContract()
    verify("system", "nupp.system")
end

return M
