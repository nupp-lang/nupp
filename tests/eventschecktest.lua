-- The checker rules NEP 33 introduced for typed events: closure literals adopting
-- the modes of the slot they are passed to, pack binders forwarding the contracts
-- of the arguments that bound them, a declaration's construction contract as a
-- named pack. The derive that asks for an initializer, and its refusals, are
-- exercised with `nupp.events` once that module lands.

local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local run = 0
local function diagnostics(source)
    run = run + 1
    env.loaded = {}
    local filename = ("eventscheck-%d.g.nupp"):format(run)
    local parsed = parser.parse(source, filename)
    assertEq(#parsed.errors, 0, "syntax: " .. (parsed.errors[1] and parsed.errors[1].msg or ""))

    return check.check(parsed, filename, env)
end

local function codes(source)
    local out = {}
    for j, diagnostic in ipairs(diagnostics(source)) do
        out[j] = diagnostic.code
    end

    return table.concat(out, " ")
end

local function clean(source)
    local found = diagnostics(source)
    assertEq(#found, 0, "expected a clean check, got " .. (found[1] and (found[1].code .. ": " .. found[1].msg) or ""))
end

local function contains(text, needle)
    assert(text:find(needle, 1, true), ("expected %q in:\n%s"):format(needle, text))
end

local OBSERVED = [[
local record Damage
    amount: number
end

local record World
    frame: integer
end

local type Observer = function(borrows event: Damage, exclusive world: World): nil

local record Bus
    handlers: {Observer}

    function observe(self, callback: Observer): nil
        self.handlers[#self.handlers + 1] = callback
    end
end

local bus = new Bus(handlers = {})
]]

local M = {}

---------------------------------------------------------------------------
-- Mode adoption
---------------------------------------------------------------------------

function M.shortFunctionsAdoptTheSlotsModes()
    clean(OBSERVED .. [[
bus:observe(|event, world| -> do
    event.amount = event.amount * 2
    world.frame = world.frame + 1
end)
]])
end

function M.functionLiteralsAdoptTheSlotsModes()
    clean(OBSERVED .. [[
bus:observe(function(event, world)
    world.frame = world.frame + 1
    print(event.amount)
end)
]])
end

function M.aOneArgumentObserverFits()
    clean(OBSERVED .. [[
bus:observe(|event| -> print(event.amount))
]])
end

function M.anAdoptedBorrowCannotBeStored()
    assertEq(codes(OBSERVED .. [[
local kept: {Damage} = {}
bus:observe(|event| -> do
    kept[#kept + 1] = event
end)
]]), "NUPP2603", "storing an adopted borrow")
end

function M.anAdoptedBorrowCannotBeReturnedFromANestedFunction()
    assertEq(codes(OBSERVED .. [[
bus:observe(function(event, world): nil
    local function grab(): Damage
        return event
    end
    world.frame = #tostring(grab())
end)
]]), "NUPP2608", "returning an adopted borrow")
end

function M.aWrittenModeIsKept()
    -- A type annotation alone is still bare of a mode and adopts; a mode the
    -- literal writes is kept, and a written `borrows` where the slot asks for
    -- `exclusive` is the mismatch it always was.
    clean(OBSERVED .. [[
bus:observe(function(borrows event: Damage, world: World): nil
    world.frame = 1
end)
]])
    assertEq(codes(OBSERVED .. [[
bus:observe(function(borrows event: Damage, borrows world: World): nil
    print(world.frame)
end)
]]), "NUPP2006", "a written borrows does not become exclusive")
end

function M.takesIsNeverAdopted()
    assertEq(codes([[
local record Token
    closed: boolean
    function drop(takes self): nil
        self.closed = true
    end
end

local function consume(callback: function(takes token: Token): nil): nil
    callback(new Token(closed = false))
end

consume(|token| -> print(token.closed))
]]), "NUPP2006", "a literal does not adopt takes")
end

function M.anAnnotatedLocalHandsItsCallableTypeToALiteral()
    clean(OBSERVED .. [[
local f: Observer = |event| -> print(event.amount)
local g: Observer = function(event, world)
    world.frame = world.frame + 1
    event.amount = 2
end
bus:observe(f)
bus:observe(g)
]])
    assertEq(codes(OBSERVED .. [[
local kept: {Damage} = {}
local h: Observer = |event| -> do
    kept[1] = event
end
bus:observe(h)
]]), "NUPP2603", "an adopted borrow stored from an annotated local")
end

function M.aCallbackBodyKeepsOnlyItsSecondPassDiagnostics()
    -- A generic call infers a callback once with `any` parameters to bind its
    -- generics. A named argument on a method of such a parameter is refused in
    -- that pass and accepted in the real one; only the real one is reported.
    clean([[
local record Damage
    amount: number
    source: integer
    kind: string = "physical"
end

local record Bus
    frame: number

    function send(exclusive self, amount: number, source: integer, kind: string?): nil
        self.frame = self.frame + amount + source + #(kind or "")
    end
end

local function each<E>(event: Type<E>, bus: Bus, callback: function(borrows event: E, exclusive bus: Bus): nil): nil
    callback(new Damage(amount = 1, source = 1) as any as E, bus)
end

each(Damage, new Bus(frame = 0), |event, bus| -> do
    bus:send(amount = event.amount, source = event.source)
end)
]])
end

function M.aParameterBorrowSuspendsThroughAHandledCallOnly()
    -- A handled suspension leaves a handler responsible for the continuation,
    -- so an observer holding the borrowed event may park. A raw yield leaves
    -- nobody responsible, and the caller's owner would be stranded through
    -- this frame, which is why a parameter borrow counts as an obligation.
    clean([[
local time = require("nupp.time")

local record Damage
    amount: number
end

local function observe(borrows event: Damage): nil
    time.sleep(1)
    event.amount = event.amount + 1
end

print(observe)
]])
    assertEq(codes([[
local record Damage
    amount: number
end

local function observe(borrows event: Damage): nil
    coroutine.yield()
    event.amount = event.amount + 1
end

print(observe)
]]), "NUPP2603", "a raw yield with a parameter borrow live")
end

---------------------------------------------------------------------------
-- Pack binders forward contracts
---------------------------------------------------------------------------

local FORWARDED = [[
local record World
    frame: integer
end

local function apply<A..., R...>(scoped f: function(A...): R..., ...: A...): R...
    return f(...)
end
]]

function M.aProtectedCallForwardsAnExclusiveView()
    clean(FORWARDED .. [[
local function step(exclusive world: World, delta: integer): nil
    world.frame = world.frame + delta
end

local function protectedStep(exclusive world: World): nil
    local ok, failure = pcall(step, world, 1)
    if not ok then
        error(failure, 0)
    end
    apply(step, world, 2)
end
]])
end

function M.aForwardedViewHoldsTheCalleeToItsMode()
    assertEq(codes(FORWARDED .. [[
local function step(world: World, delta: integer): nil
    world.frame = world.frame + delta
end

local function protectedStep(exclusive world: World): nil
    local ok = pcall(step, world, 1)
    print(ok)
end
]]), "NUPP2603", "a plain callee cannot receive a forwarded exclusive view")
end

function M.aProtectedCallForwardsABorrow()
    clean(FORWARDED .. [[
local function read(borrows world: World): integer
    return world.frame
end

local function protectedRead(borrows world: World): integer
    local ok, frame = pcall(read, world)
    return ok and frame or 0
end
]])
end

---------------------------------------------------------------------------
-- The construction contract
---------------------------------------------------------------------------

local CONSTRUCTED = [[
local record Damage
    amount: number
    source: integer
    kind: string = "physical"
end

local record Diagonal
    x: integer
    y: integer
    constructor(self, at: integer)
        self.x = at
        self.y = at
    end
end

local comptime function Construction(E: type): typepack
    return nupp.types.construction(E)
end

local function count<E>(event: Type<E>, ...: unpackof Construction(E)): integer
    return select("#", ...)
end
]]

function M.aComputedTailBindsNamedArguments()
    clean(CONSTRUCTED .. [[
print(count(Damage, amount = 1, source = 2))
print(count(Damage, 1, 2, "fire"))
print(count(Damage, amount = 1, source = 2, kind = "fire"))
print(count(Diagonal, at = 4))
print(count(Diagonal, 4))
]])
end

function M.aComputedTailRefusesAnUnknownName()
    assertEq(codes(CONSTRUCTED .. [[
print(count(Damage, amount = 1, sauce = 2))
]]), "NUPP2125", "an unknown named argument")
end

function M.aComputedTailRefusesAMissingRequiredSlot()
    assertEq(codes(CONSTRUCTED .. [[
print(count(Damage, amount = 1))
]]), "NUPP2125", "an omitted required slot")
end

function M.severalConstructorsHaveNoContract()
    local found = diagnostics([[
local record Overloaded
    x: integer
    constructor(self, x: integer)
        self.x = x
    end
    constructor(self, x: integer, y: integer)
        self.x = x + y
    end
end

local comptime function Construction(E: type): typepack
    return nupp.types.construction(E)
end

local function count<E>(event: Type<E>, ...: unpackof Construction(E)): integer
    return select("#", ...)
end

print(count(Overloaded, 1))
]])
    assert(#found > 0, "several constructors were accepted as one contract")
    contains(found[1].msg, "several")
end

return M
