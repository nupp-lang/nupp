local ROOT = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]")) .. "/.."
local lower = require("nupp.compiler.clif.lower")
local M = {}

local function quote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function capture(command)
    local p = assert(io.popen(command .. " 2>&1; echo __exit__:$?"))
    local text = p:read("*a")
    p:close()
    local status = assert(tonumber(text:match("__exit__:(%d+)%s*$")))

    return status, (text:gsub("__exit__:%d+%s*$", ""))
end

local function write(path, text)
    local f = assert(io.open(path, "wb"))
    f:write(text)
    f:close()
end

local glue, layouts

local function setup()
    if glue then
        return
    end
    local status, text = capture("cd " .. quote(ROOT) .. " && python3 scripts/vm-cli glue")
    assert(status == 0, text)
    glue = assert(text:match("([^\r\n]+)%s*$"))
    layouts = os.tmpname()
    status, text = capture(quote(glue) .. " native layouts " .. quote(layouts))
    assert(status == 0, text)
end

local function compile(source)
    setup()
    local path = os.tmpname() .. ".nupp"
    write(path, "module native.scalarhelper\nconst native = require(\"nupp.runtime.vm.intrinsics\")\n" .. source)
    local ok, result = pcall(lower.compile, ROOT, {path}, {handlers = true, layouts = layouts, include = {"src"}})
    os.remove(path)
    if not ok then
        error(result, 0)
    end

    return result
end

local function execute(source, args)
    local clif = compile(source)
    assert(not clif:find("call fn", 1, true), "scalar helpers must be inlined")
    local path = os.tmpname() .. ".clif"
    write(path, clif)
    local words = {"0", "0"}
    for i, value in ipairs(args) do
        words[i + 2] = quote(value)
    end
    -- The private final argument is the support function's dispatch table.
    words[#words + 1] = "0"
    local status, text = capture(
        quote(glue) .. " native jit " .. quote(path) .. " ProbeSlow " .. table.concat(words, " ")
    )
    os.remove(path)
    assert(status == 0, text)

    return assert(tonumber(text:match("^%s*(%-?%d+)%s*$")), text)
end

function M.repeatedNestedAndLoopCallsHaveSeparateCheckedBindings()
    local source = [[
local function choose(x: int64): int64
    local total: int64 = 0
    for i = 1LL, 3LL do
        if x < 0 then return x end
        total = total + x + i
    end
    return total
end
export function ProbeSlow(pc: voidptr, context: voidptr, x: int64, y: int64): uint64
    local first = choose(choose(x))
    local second = choose(y)
    local total: int64 = first + second
    local n: int64 = 0
    while n < 3 do
        total = total + choose(n)
        n = n + 1
    end
    return native.word(total)
end
]]
    for _, pair in ipairs({{2, 3}, {-2, 3}, {3, -5}, {-4, -7}}) do
        local function choose(x)
            return x < 0 and x or 3 * x + 6
        end

        local want = choose(choose(pair[1])) + choose(pair[2]) + choose(0) + choose(1) + choose(2)
        assert(execute(source, pair) == want)
    end
end

function M.statementHelperReturnsAndSideEffectsStayInsideItsActivation()
    local source = [[
local function store(ptr: voidptr, x: int64): nil
    if x < 0 then return end
    native.storeIndex(ptr, 0, x)
end
local function read(ptr: voidptr, x: int64): int64
    store(ptr, x)
    return native.loadIndex(ptr, 0) + 1
end
export function ProbeSlow(pc: voidptr, context: voidptr, x: int64, y: int64): uint64
    local scratch = native.stackBytes(16)
    native.storeIndex(scratch, 0, 7)
    local a = read(scratch, x)
    local b = read(scratch, y)
    return native.word(a * 100 + b)
end
]]
    assert(execute(source, {11, -3}) == 1212)
    assert(execute(source, {-1, 17}) == 818)
end

function M.recursionAndMismatchedResultsAreRefused()
    local source = [[
local function recurse(x: int64): int64
    if x == 0 then return 0LL end
    return recurse(x - 1)
end
export function ProbeSlow(pc: voidptr, context: voidptr, x: int64): uint64
    return native.word(recurse(x))
end
]]
    local ok, problem = pcall(compile, source)
    assert(not ok and tostring(problem):find("recursive helper", 1, true), tostring(problem))
    ok = pcall(compile, source:gsub("return recurse%(x %- 1%)", 'return "wrong"'))
    assert(not ok)
end

function M.stackScratchRequiresBoundedLiteralIntegersAndSupportFunctions()
    for _, expression in ipairs({"0", "-1", "1.5", "4097", "x"}) do
        local ok = pcall(
            compile,
            "export function ProbeSlow(pc: voidptr, context: voidptr, x: int64): uint64\nlocal p = native.stackBytes("
            .. expression
            .. ")\nreturn native.address(p)\nend\n"
        )
        assert(not ok, expression)
    end
    local ok, problem = pcall(
        compile,
        [[
export function Move(pc: voidptr, regs: voidptr, ints: voidptr, floats: voidptr, context: voidptr, frame: voidptr): uint64
    local p = native.stackBytes(16)
    return native.fail()
end
]]
    )
    assert(not ok and tostring(problem):find("stack scratch belongs", 1, true), tostring(problem))
end

return M
