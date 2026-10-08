local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local gen = require("nupp.compiler.lua.gen")
local env = require("nupp.compiler.project.env")
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

-- A seeded differential over random operation sequences. It found the two
-- providers disagreeing on how much a failing multi-count `get` consumed, which
-- the fixed contract above cannot enumerate, so the sequences stay as a check.
function M.portableAndNativeBuffersAgreeOnRandomSequences()
    local bit = require("bit")
    local portable = require("nupp.runtime.provider.tablebuffer")
    local native = require("nupp.runtime.provider.nativebuffer")
    local state = 20260928
    local function draw(low, high)
        state = bit.bxor(state, bit.lshift(state, 13))
        state = bit.bxor(state, bit.rshift(state, 17))
        state = bit.bxor(state, bit.lshift(state, 5))
        return low + (state % 4294967296) % (high - low + 1)
    end
    local function pick(list)
        return list[draw(1, #list)]
    end
    local VALUES = {"", "a", "hello", "\0\255", 0, -1, 1.5, 1e100, 2 ^ 53, true}
    local function run(buffer, op, args)
        local result = {pcall(function()
            return buffer[op](buffer, unpack(args, 1, args.n))
        end)}
        if not result[1] then
            return "raised"
        end
        local out = {}
        for index = 2, #result do
            local value = result[index]
            out[#out + 1] = value == buffer and "self" or type(value) == "string" and ("%q"):format(value) or tostring(value)
        end
        return table.concat(out, ",")
    end
    for _ = 1, 500 do
        local left, right = portable.new(), native.new()
        local log = {}
        for _ = 1, draw(1, 12) do
            local kind = draw(1, 8)
            local op, args
            if kind <= 3 then
                op, args = "put", {n = draw(0, 3)}
                for index = 1, args.n do
                    args[index] = pick(VALUES)
                end
            elseif kind == 4 then
                op, args = "get", {n = draw(0, 2)}
                for index = 1, args.n do
                    args[index] = pick({0, 1, 2, 5, 100, -1})
                end
            elseif kind == 5 then
                op, args = "skip", {pick({0, 1, 3, 100, -1}), n = 1}
            elseif kind == 6 then
                op, args = "set", {pick({"", "xyz", "\0"}), n = 1}
            elseif kind == 7 then
                op, args = "tostring", {n = 0}
            else
                op = pick({"reset", "putf"})
                args = op == "putf" and {"%s-%d", "q", 7, n = 3} or {n = 0}
            end
            log[#log + 1] = op
            local a, b = run(left, op, args), run(right, op, args)
            assert(a == b and #left == #right, table.concat(log, "; ") .. ": portable " .. a .. " len " .. #left
                .. ", native " .. b .. " len " .. #right)
        end
    end
end

function M.tableStructsPreserveValueOperations()
    verify("structvalue", "nupp.runtime.provider.tablestruct")
end

function M.nativeStorageMatchesTheByteContract()
    verify("cstorage", "nupp.runtime.provider.nativestorage")
end

function M.suspensionPreservesOwnershipAndHandlerIdentity()
    verify("suspension", "nupp.runtime.provider.suspension")
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
