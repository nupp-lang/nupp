-- The `@aot` annotation's source contract.
--
-- `@aot` says a whole function compiles ahead of time rather than being left to
-- LuaJIT. Before any of that can be true there has to be an agreement about what
-- the annotation attaches to and what its body may contain, and that agreement is
-- what these check: the annotation exists, it refuses a body two compilers were
-- promised, it refuses a member that is not a whole function, and it names every
-- construct the AOT IR has no representation for.
--
-- See plans/038-aot-functions.md.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local M = {}

local function codesOf(source)
   local result = parser.parse(source, "test.nupp")
   if #result.errors > 0 then
      error("syntax: " .. result.errors[1].message, 2)
   end
   local out = {}
   for _, diagnostic in ipairs(check.check(result, "test.nupp",
      envMod.new(HERE .. "/.."))) do
      out[#out + 1] = diagnostic.code
   end

   return table.concat(out, " ")
end

local function assertEq(got, want, label)
   if got ~= want then
      error(("%s:\n  want: %s\n  got:  %s"):format(label, want, got), 2)
   end
end

--- Asserts that `source` reports `want` and nothing else.
local function reports(source, want, label)
   assertEq(codesOf(source), want, label)
end

function M.anAdmittedBodyReportsNothing()
   -- The whole point of the subset is that ordinary Nupp is inside it. A body of
   -- arithmetic over admitted scalars is the smallest thing that has to pass, and
   -- if it does not then nothing below is a subset check, it is a syntax error.
   reports([[
@aot
local function scale(value: number, by: number): number
    local scaled = value * by
    if scaled < 0.0 then
        return 0.0
    end

    return scaled
end

return {scale = scale}
]], "", "arithmetic over admitted scalars is admitted")
end

function M.loopsAndBranchesAreAdmitted()
   -- Structured control flow is the reason the annotation exists; a subset that
   -- refused a numeric loop would have nothing left to compile.
   reports([[
@aot
local function accumulate(count: integer): number
    local total = 0.0
    for i = 1, count do
        if i % 2 == 0 then
            total = total + 1.0
        else
            total = total - 1.0
        end
    end

    return total
end

return {accumulate = accumulate}
]], "", "numeric loops and branches are admitted")
end

function M.numericSwitchLocalIsAdmitted()
   reports([[
@aot
local function classify(value: number): number
    local selected = switch value do
        case 0 -> 1.0
        case 1, 2 -> value + 1.0
        else -> 0.0
    end

    return selected
end

return {classify = classify}
]], "", "an integer-valued switch initializer lowers to scalar control flow")

   reports([[
@aot
local function constantClass(): number
    local selected = switch 0 do
        case 0 -> 1.0
    end
    return selected
end

return {constantClass = constantClass}
]], "", "a checker-exhaustive native switch does not require else")
end

function M.laneLoweringIsAttemptedRatherThanRequested()
   -- The shape lane lowering can take is one top-level numeric map loop. It is
   -- recorded rather than required: a body of another shape is an ordinary
   -- `@aot` function that compiles one iteration at a time, and only the
   -- vectorisation check has anything to say about it. `simd = true` used to
   -- make every one of these a build error.
   reports([[
local span = require("nupp.span")

@aot
local function map(
    exclusive output: span.WriteSpan<float>,
    borrows input: span.Span<float>
): nil
    for i = 1, input.count do
        output:set(i, input:get(i))
    end
end
return {map = map}
]], "", "the map-loop shape compiles")

   reports([[
@aot
local function missing(value: number): number
    return value
end

return {missing = missing}
]], "", "a body with no loop is an ordinary AOT function")

   reports([[
@aot
local function two(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end
    for i = 1, count do
        total = total - i
    end

    return total
end

return {two = two}
]], "", "two loops are not a shape lane lowering takes, and not an error")

   reports([[
@aot(lanes = false)
local function scalar(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end

    return total
end

return {scalar = scalar}
]], "", "a deliberately scalar body declines lane lowering")

   -- The setting overrides an estimate in either direction, so both literals
   -- are accepted. Neither is a lane-count knob.
   reports([[
@aot(lanes = true)
local function forced(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end

    return total
end

return {forced = forced}
]], "", "a body may take lane lowering whatever the estimate says")

   reports([[
@aot(lanes = 4)
local function wrong(value: number): number
    return value
end

return {wrong = wrong}
]], "NUPP2115", "lanes is not a lane count")
end

function M.simdAcceptsOnlyTheRequiredSetting()
   reports([[
@aot(simd = false)
local function map(count: integer): number
    local total = 0.0
    for i = 1, count do
        total = total + i
    end
    return total
end

return {map = map}
]], "NUPP2115", "SIMD is a requirement rather than a writable preference")
end

function M.spanMethodCallsAreAdmitted()
   -- The span operations are the memory boundary the whole feature is built on,
   -- and they are written as method calls. Refusing the syntax structurally would
   -- refuse the subset's own vocabulary, so whether a call resolves is left to the
   -- pass that knows the receiver's type.
   reports([[
local span = require("nupp.span")

@aot
local function total(values: span.Span<float>): number
    local sum = 0.0
    for i = 1, values.count do
        sum = sum + values:get(i)
    end

    return sum
end

return {total = total}
]], "", "a span read is admitted")

   reports([[
local span = require("nupp.span")

@aot
local function double(exclusive values: span.WriteSpan<float>): nil
    for i = 1, values.count do
        values:set(i, values:get(i) * 2.0)
    end
end

return {double = double}
]], "", "a span write is admitted")
end

function M.jitAndAotAreMutuallyExclusive()
   -- Two compilers for one body is not a preference to resolve, so it is refused
   -- whichever order the two are written in.
   reports([[
@jit
@aot
local function hot(scale: number): number
    return scale * 2.0
end

return {hot = hot}
]], "NUPP2901", "@jit then @aot")

   reports([[
@aot
@jit
local function hot(scale: number): number
    return scale * 2.0
end

return {hot = hot}
]], "NUPP2901", "@aot then @jit")
end

function M.aotIsRefusedOnARecordMember()
   -- A member's annotations never reach the pragma handler, so this is the case
   -- that regresses silently if the refusal lives in only one place.
   reports([[
local record Point
    x: float
    @aot
    constructor(self, x: float)
        self.x = x
    end
end

return {Point = Point}
]], "NUPP2902", "a constructor is not a whole function")
end

function M.aNestedFunctionIsRefused()
   reports([[
@aot
local function total(scale: number): number
    local function double(x: number): number
        return x * 2.0
    end

    return double(scale)
end

return {total = total}
]], "NUPP2903", "a closure has no AOT IR representation")
end

function M.allocatingConstructsAreRefused()
   reports([[
@aot
local function build(scale: number): number
    local values = {scale}

    return values[1]
end

return {build = build}
]], "NUPP2903", "a table constructor")

   reports([[
@aot
local function label(name: string): string
    return name .. "!"
end

return {label = label}
]], "NUPP2903", "concatenation")
end

function M.arbitraryJumpsAreRefused()
   -- `goto` waits until AOT IR source maps can represent every existing rule, so
   -- both halves of one are named rather than only the jump.
   reports([[
@aot
local function jump(scale: number): number
    goto done
    ::done::

    return scale
end

return {jump = jump}
]], "NUPP2903 NUPP2903", "goto and its label")
end

function M.aRefusedConstructIsReportedOnce()
   -- The walk does not descend into what it refused. A closure holding three
   -- tables is one problem with one fix, and three more diagnostics inside a
   -- function that cannot be there at all would bury it.
   reports([[
@aot
local function total(scale: number): number
    local function build(): number
        local a = {1.0}
        local b = {2.0}

        return a[1] + b[1]
    end

    return build() + scale
end

return {total = total}
]], "NUPP2903", "the closure is named and its contents are not")
end

function M.anUnannotatedFunctionIsUnaffected()
   -- Removing `@aot` from accepted source preserves its ordinary Nupp answer, so
   -- the same body without the annotation reports nothing at all.
   reports([[
local function total(scale: number): number
    local function double(x: number): number
        return x * 2.0
    end

    return double(scale)
end

return {total = total}
]], "", "the subset applies only where it was asked for")
end

return M
