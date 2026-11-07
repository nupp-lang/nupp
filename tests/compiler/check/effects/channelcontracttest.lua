local test = require("assert")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envmod = require("nupp.compiler.project.env")
local root = require("helpers.paths").absoluteTests .. "/.."

local PREFIX = [[
module nupp.tests.channelcontract
local {type Sender, type Receiver} = require("coroutine")
]]

local function diagnostics(source)
    local filename = root .. "/src/nupp/tests/channelcontract.nupp"
    local ast = parser.parse(PREFIX .. source, filename)
    test.eq(#ast.errors, 0, ast.errors[1] and ast.errors[1].msg or "syntax")
    local errors = {}
    for _, diagnostic in ipairs(check.check(ast, filename, envmod.new(root))) do
        if diagnostic.severity ~= "warning" then
            errors[#errors + 1] = diagnostic
        end
    end

    return errors
end

local function clean(source)
    local errors = diagnostics(source)
    test.eq(#errors, 0, errors[1] and errors[1].msg or "contract")
end

local function refuses(source, code)
    local errors = diagnostics(source)
    for _, diagnostic in ipairs(errors) do
        if diagnostic.code == code then
            return
        end
    end
    error("expected " .. code .. ", got " .. (errors[1] and errors[1].code .. ": " .. errors[1].msg or "no diagnostic"))
end

local M = {}

function M.nilIsAMessageAndTheTagNarrowsTheResult()
    clean(
        [[
export function read(borrows receiver: Receiver<integer?>): integer?
    local kind, value = receiver:receive()
    if kind == "value" then return value end
    return nil
end
export function write(borrows sender: Sender<integer?>): nil
    sender:send(nil)
end
]]
    )
end

function M.endpointsEnforcePayloadTypesAndDirection()
    refuses([[
export function wrong(borrows sender: Sender<integer>): nil
    sender:send("text")
end
]], "NUPP2006")
    refuses([[
export function wrong(borrows receiver: Receiver<integer>): nil
    receiver:send(1)
end
]], "NUPP2004")
end

function M.aMovedEndpointCannotBeUsedAgain()
    refuses(
        [[
local function consume(takes sender: Sender<integer>): nil end
export function wrong(takes sender: Sender<integer>): nil
    consume(sender)
    sender:send(1)
end
]],
        "NUPP2603"
    )
end

function M.tryOperationsNeverSuspend()
    clean(
        [[
export function poll(borrows sender: Sender<integer>, borrows receiver: Receiver<integer>): nil
    @nosuspend do
        local sent, unsent = sender:trysend(1)
        local received, value = receiver:tryreceive()
        print(sent, unsent, received, value)
    end
end
]]
    )
    refuses(
        [[
export function wrong(borrows sender: Sender<integer>): nil
    @nosuspend do sender:send(1) end
end
]],
        "NUPP2701"
    )
end

function M.failedTrysendReturnsTheOwnedStorage()
    clean(
        [[
export function offer(
    borrows sender: Sender<affine(table.Array<int32>, table.Array.destroy)>,
    takes values: affine(table.Array<int32>, table.Array.destroy)
): integer
    local kind, returned = sender:trysend(values)
    if kind ~= "sent" then
        local count = returned.count
        own.drop(returned)
        return count
    end
    return 0
end
]]
    )
end

function M.aReturnedEndpointMustRetainItsScopeBorrow()
    local scope = [[
local record Scope is own.Closeable
    function close(takes self): nil end
end
local function issue(borrows owner: Scope): Sender<integer> borrows (owner)
    error("contract fixture", 0)
end
]]
    clean(
        scope
        .. [[
export function forward(borrows owner: Scope): Sender<integer> borrows (owner)
    return issue(owner)
end
]]
    )
    refuses(
        scope .. [[
export function escape(): Sender<integer>
    local owner = Scope()
    return issue(owner)
end
]],
        "NUPP2616"
    )
end

function M.dynamicMessagesCannotEraseAnOwnedPayload()
    refuses(
        [[
export function lose(borrows sender: Sender<any>, takes values: affine(table.Array<int32>, table.Array.destroy)): nil
    sender:trysend(values)
end
]],
        "NUPP2611"
    )
end

function M.endpointPayloadTypesCannotWidenThroughAny()
    for _, endpoint in ipairs({"Sender", "Receiver"}) do
        for _, target in ipairs({"number", "any"}) do
            refuses(
                (
                    [[
export function lose(takes endpoint: %s<integer>): %s<%s>
    return endpoint
end
]]
                ):format(endpoint, endpoint, target),
                "NUPP2002"
            )
        end
    end
end

function M.aWorkerMayTakeAnEndpointFromItsOwnScope()
    clean(
        [[
local owner = coroutine.scope()
local sending, receiving = owner:channel<integer>(1, 64)
local child = owner:work(receiving, function(takes incoming: Receiver<integer>): integer
    local input = incoming
    local kind, value = input:receive()
    return kind == "value" and value or 0
end)
print(child:await())
]]
    )
end

function M.aWorkerCannotOutliveTheScopeThatOwnsItsEndpoint()
    refuses(
        [[
local outer = coroutine.scope()
do
    local inner = coroutine.scope()
    local sending, receiving = inner:channel<integer>(1, 64)
    outer:work(receiving, function(takes incoming: Receiver<integer>): integer
        local input = incoming
        local kind, value = input:receive()
        return kind == "value" and value or 0
    end)
end
]],
        "NUPP2621"
    )
end

function M.aCooperativeChildMayOwnAnEndpointFromItsScope()
    clean(
        [[
local owner = coroutine.scope()
local sending, receiving = owner:channel<integer>(1, 64)
local child = owner:spawn(function(): integer takes(receiving)
    local input = receiving
    local kind, value = input:receive()
    return kind == "value" and value or 0
end)
sending:send(7)
print(child:await())
]]
    )
end

function M.aCooperativeChildCannotKeepAnotherScopesEndpoint()
    refuses(
        [[
local outer = coroutine.scope()
do
    local inner = coroutine.scope()
    local sending, receiving = inner:channel<integer>(1, 64)
    outer:spawn(function(): nil takes(receiving)
        local input = receiving
        input:receive()
    end)
end
]],
        "NUPP2621"
    )
end

function M.endpointsCannotLeaveThroughCooperativeTaskResults()
    refuses(
        [[
local owner = coroutine.scope()
local sending, receiving = owner:channel<integer>(1, 64)
owner:spawn(function(): Receiver<integer> takes(receiving)
    return receiving
end)
]],
        "NUPP2125"
    )
end

function M.endpointsCannotReturnFromAWorkerOrEnterMessages()
    refuses(
        [[
local owner = coroutine.scope()
owner:work(nil as any, function(takes receiver: Receiver<integer>): Receiver<integer>
    return receiver
end)
]],
        "NUPP2006"
    )
    refuses(
        [[
export function wrong(borrows sender: Sender<Receiver<integer>>, takes value: Receiver<integer>): nil
    sender:send(value)
end
]],
        "NUPP2006"
    )
end

function M.pointerMessagesRemainRefused()
    refuses(
        [[
export function wrong(borrows sender: Sender<voidptr>, value: voidptr): nil
    sender:send(value)
end
]],
        "NUPP2006"
    )
end

function M.borrowedSpansCannotBeSent()
    refuses(
        [[
local spans = require("bytes.span")
export function wrong(borrows sender: Sender<spans.Span<int32>>, borrows view: spans.Span<int32>): nil
    sender:send(view)
end
]],
        "NUPP2602"
    )
end

function M.theFactoryRejectsUnsupportedPayloadsBeforeUse()
    refuses([[
local owner = coroutine.scope()
local sender, receiver = owner:channel<voidptr>(1, 64)
]], "NUPP2006")
end

return M
