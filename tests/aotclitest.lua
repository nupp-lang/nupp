-- `nupp aot`: what an `@aot` function compiles to, and whether it vectorised.
--
-- Driven through the real binary rather than the module, because the artifacts and
-- the exit status are the whole interface. `--check` is an exit status, so a test that
-- could not read one would not be testing it.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
   local p = assert(io.popen("pwd"))
   HERE = p:read("*l") .. "/" .. HERE
   p:close()
end
local NUPP = HERE .. "/../bin/nupp"

local M = {}

local function project(files)
   local dir = os.tmpname()
   os.remove(dir)
   assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
   local manifest = assert(io.open(dir .. "/nupp.lua", "wb"))
   manifest:write('return {include = {"."}}\n')
   manifest:close()
   for name, source in pairs(files) do
      local handle = assert(io.open(dir .. "/" .. name, "wb"))
      handle:write(source)
      handle:close()
   end
   return dir
end

-- LuaJIT's `popen` close answers only whether the pipe shut, never the exit status, so
-- the status is carried back through the pipe itself.
local function run(dir, argv)
   local pipe = assert(io.popen(
      ("cd %q && NO_COLOR= '%s' aot %s 2>&1; echo \"__exit__:$?\""):format(dir, NUPP, argv)))
   local out = pipe:read("*a")
   pipe:close()
   local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

   return (out:gsub("__exit__:%d+%s*$", "")), code
end

-- A register-resident loop: sixteen bytes read once, then arithmetic over locals that
-- touches no memory. Above the intensity threshold, so lanes are expected to pay.
local COMPUTE = [[
local span = require("nupp.span")

local struct Point
    re: float
    im: float
end

local struct Escape
    iterations: int32
    escaped: uint32
end

@aot
local function escapes(
    exclusive out: span.WriteSpan<Escape>,
    borrows points: span.Span<Point>,
    first: integer,
    last: integer,
    limit: int32
): nil
    if out.count ~= points.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > out.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local cell = out:getMut(i)
        local point = points:get(i)
        local cx = point.re
        local cy = point.im
        local zx = 0.0
        local zy = 0.0
        local zxSquared = 0.0
        local zySquared = 0.0
        local iteration = 0
        local escaped = 0
        while iteration < limit do
            if zxSquared + zySquared > 4.0 then
                escaped = 1
                break
            end
            zy = 2.0 * zx * zy + cy
            zx = zxSquared - zySquared + cx
            zxSquared = zx * zx
            zySquared = zy * zy
            iteration = iteration + 1
        end
        cell.iterations = iteration
        cell.escaped = escaped
    end
end

return {escapes = escapes, Point = Point, Escape = Escape,}
]]

-- The same shape with almost no arithmetic: two fields in, two fields out, one multiply
-- and add each. Below the threshold, so lane lowering is declined rather than refused.
local STREAMING = [[
local span = require("nupp.span")

local struct Position
    x: float
    y: float
end

local struct Velocity
    vx: float
    vy: float
end

@aot
local function advance(
    exclusive positions: span.WriteSpan<Position>,
    borrows velocities: span.Span<Velocity>,
    first: integer,
    last: integer,
    dt: float
): nil
    if positions.count ~= velocities.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > positions.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local position = positions:getMut(i)
        local velocity = velocities:get(i)
        position.x = position.x + velocity.vx * dt
        position.y = position.y + velocity.vy * dt
    end
end

return {advance = advance, Position = Position, Velocity = Velocity,}
]]

-- Lanes asked for, and a construct the rewrite has no lane form for. This is the one
-- outcome `--check` fails on: the loop wanted to run several iterations at once and did
-- not, which is what an ordinary edit can take away without any test noticing.
local REFUSED = STREAMING
   :gsub("@aot\n", "@aot(lanes = true)\n")
   :gsub("        local position = positions:getMut%(i%)",
      "        local scale = dt\n"
      .. "        for step = 1, 2 do\n"
      .. "            scale = scale\n"
      .. "        end\n"
      .. "        local position = positions:getMut(i)")

--- A target every host can compile for, at a tier that holds the wide gangs.
---
--- Pinned because these assert which gang a body takes, and that depends on what
--- the target can hold: the same source takes four lanes at avx2 and two at the
--- x86-64 baseline. Left to the host, they would assert the runner's CPU.
local PINNED = "--target x86_64-unknown-linux-gnu --features avx2 "

local BYTE_CLASSIFIER = [[
local span = require("nupp.span")

@aot(lanes = true)
local function classify(
    exclusive flags: span.WriteSpan<uint8>,
    borrows bytes: span.Span<uint8>
): nil
    if flags.count ~= bytes.count then error("length mismatch", 2) end
    for i = 1, flags.count do
        local byte = bytes:get(i)
        local flag: uint32 = 0
        if byte == 34 then
            flag = 1
        elseif byte == 92 then
            flag = 2
        end
        flags:set(i, flag)
    end
end

return {classify = classify}
]]

function M.aRegisterResidentLoopReportsItsGangAndWidth()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, PINNED .. "compute.nupp")
   test.equal(code, 0, out)
   assert(out:find("mixed4", 1, true), "the gang is named: " .. out)
   assert(out:find("4 lanes", 1, true), "the width is named: " .. out)
   assert(out:find("operations per byte", 1, true), "the estimate behind the decision is shown: " .. out)
end

function M.aStreamingLoopDeclinesRatherThanFailing()
   local dir = project{["stream.nupp"] = STREAMING}
   local out, code = run(dir, "--check stream.nupp")
   test.equal(code, 0, "declining is not a failure\n" .. out)
   assert(out:find("too little arithmetic per byte", 1, true),
      "the reason it declined is the estimate: " .. out)
end

function M.aLoopThatWantedLanesAndDidNotGetThemFails()
   local dir = project{["refused.nupp"] = REFUSED}
   local out, code = run(dir, "--check refused.nupp")
   test.equal(code, 1, "wanting lanes and not getting them is the failure\n" .. out)
   assert(out:find("ran one iteration at a time", 1, true), "the outcome is named: " .. out)
   assert(out:find("nested numeric loop", 1, true),
      "the construct that stopped it is named, not only that it stopped: " .. out)
end

function M.checkAloneDoesNotFailAWorkingLoop()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, "--check compute.nupp")
   test.equal(code, 0, out)
end

function M.emitPrintsTheGeneratedC()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, PINNED .. "--emit c compute.nupp")
   test.equal(code, 0, out)
   assert(out:find("void ks_escapes(", 1, true), "the exported symbol is defined: " .. out)
   assert(out:find("ks_escapes_forced_scalar", 1, true),
      "the oracle the lane body is diffed against comes out too: " .. out)
   assert(out:find("*restrict", 1, true),
      "the writable span carries the disjointness ownership proved: " .. out)
   assert(out:find("ks_sel_f64x4", 1, true),
      "the conditional became a select rather than a branch: " .. out)
end

function M.emitPrintsTheIrAndTheBinding()
   local dir = project{["compute.nupp"] = COMPUTE}
   local ir, irCode = run(dir, PINNED .. "--emit ir compute.nupp")
   test.equal(irCode, 0, ir)
   assert(ir:find("simd lanes(4)", 1, true), "the lane body is in the IR beside the scalar one: " .. ir)
   assert(ir:find("disjoint r0 r1", 1, true), "the alias matrix is in the IR: " .. ir)

   local binding, bindingCode = run(dir, "--emit binding compute.nupp")
   test.equal(bindingCode, 0, binding)
   assert(binding:find("layoutof(Escape)", 1, true),
      "the wrapper checks the struct layout rather than trusting it: " .. binding)
   assert(binding:find("unsafe do", 1, true), "the foreign call is the only unsafe part: " .. binding)
end

function M.narrowScalarSpansKeepTheirStorageAndUseLanes()
   local dir = project{["bytes.nupp"] = BYTE_CLASSIFIER}

   local ir, irCode = run(dir, PINNED .. "--check --emit ir bytes.nupp")
   test.equal(irCode, 0, ir)
   assert(ir:find("flags:u32 source(uint8)", 1, true),
      "the IR distinguishes storage from its established value: " .. ir)
   assert(ir:find("vspan:i32x8 bytes[i..i+7]", 1, true),
      "a byte load is widened into the gang: " .. ir)
   assert(ir:find("vset flags[i..i+7]", 1, true),
      "a scalar span store is scattered from the gang: " .. ir)

   local c, cCode = run(dir, PINNED .. "--emit c bytes.nupp")
   test.equal(cCode, 0, c)
   assert(c:find("uint8_t *restrict p_flags", 1, true),
      "the output pointer retains byte storage: " .. c)
   assert(c:find("const uint8_t *p_bytes", 1, true),
      "the input pointer retains const byte storage: " .. c)
   assert(c:find("p_flags[i + 7] = (uint8_t)lanes[7]", 1, true),
      "lane values narrow only when stored: " .. c)

   local binding, bindingCode = run(dir, "--emit binding bytes.nupp")
   test.equal(bindingCode, 0, binding)
   assert(binding:find("exclusive flags: uint8*", 1, true), binding)
   assert(binding:find("borrows bytes: const uint8*", 1, true), binding)
   assert(binding:find("span.WriteSpan<uint8>", 1, true), binding)
end

function M.fixedWidthSwitchesEmitNativeCDispatch()
   local source = [[
local span = require("nupp.span")

local struct Signed
    value: int32
end

local struct Unsigned
    value: uint32
end

@aot
local function signed(
    exclusive output: span.WriteSpan<Signed>,
    borrows input: span.Span<Signed>
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end
    for i = 1, output.count do
        local value = input:get(i).value
        local result: int32 = switch value do
            case -2147483648 -> 1
            case 1, 2 -> 2
            else -> 0
        end
        output:getMut(i).value = result
    end
end

@aot
local function unsigned(
    exclusive output: span.WriteSpan<Unsigned>,
    borrows input: span.Span<Unsigned>
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end
    for i = 1, output.count do
        local value = input:get(i).value
        local result: uint32 = switch value do
            case 0 -> 1
            case 4294967295 -> 2
            else -> 0
        end
        output:getMut(i).value = result
    end
end

return {signed = signed, unsigned = unsigned, Signed = Signed, Unsigned = Unsigned}
]]
   local dir = project{["switch.nupp"] = source}
   local out, code = run(dir, "--emit c switch.nupp")
   test.equal(code, 0, out)
   local first = assert(out:find("switch (", 1, true), out)
   assert(out:find("switch (", first + 1, true),
      "both exact-width selectors use native switch: " .. out)
   assert(out:find("case (-INT32_C(2147483647) - INT32_C(1)):", 1, true),
      "int32 minimum has an exact C spelling: " .. out)
   assert(out:find("case INT32_C(1):", 1, true) and
      out:find("case INT32_C(2):", 1, true),
      "grouped labels remain separate C labels: " .. out)
   assert(out:find("case INT32_C(2):\n        {", 1, true),
      "native switch arms scope conversion temporaries: " .. out)
   assert(out:find("case UINT32_C(4294967295):", 1, true),
      "uint32 maximum has an exact C spelling: " .. out)
end

function M.binary64SwitchesKeepComparisonBranches()
   local dir = project{["switch.nupp"] = [[
local span = require("nupp.span")

local struct Value
    value: int32
end

@aot
local function classify(
    exclusive output: span.WriteSpan<Value>,
    borrows input: span.Span<Value>,
    selector: number
): nil
    if output.count ~= input.count then
        error("length mismatch", 2)
    end
    for i = 1, output.count do
        local ignored = input:get(i).value
        local result: int32 = switch selector do
            case 1 -> 1.0
            case 2 -> 2.0
            else -> 0.0
        end
        output:getMut(i).value = result + ignored
    end
end
return {classify = classify, Value = Value}
]]}
   local out, code = run(dir, "--emit c switch.nupp")
   test.equal(code, 0, out)
   test.equal(out:find("switch (", 1, true), nil,
      "binary64 is not converted for native switch")
   assert(out:find("if (", 1, true), out)
end

function M.jsonCarriesTheOutcomeAndTheEstimate()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, PINNED .. "--json compute.nupp")
   test.equal(code, 0, out)
   local decoded = require("cjson").decode(out)
   test.equal(decoded.file, "compute.nupp")
   -- One entry per `@aot` function in the file, in source order.
   test.equal(#decoded.functions, 1)

   local only = decoded.functions[1]
   test.equal(only.name, "escapes")
   test.equal(only.symbol, "ks_escapes")
   test.equal(only.outcome, "lowered")
   test.equal(only.lanes.shape, "mixed4")
   test.equal(only.lanes.lanes, 4)
   assert(only.intensity.perByte > 1.0, "the estimate is above the threshold it was judged by")
   test.equal(#only.refusals, 0, "a lowered loop has nothing to explain")
   assert(decoded.ir and decoded.c and decoded.binding, "all three artifacts are carried")
end

function M.jsonNamesWhatRefusedTheLoop()
   local dir = project{["refused.nupp"] = REFUSED}
   local out, code = run(dir, "--json --check refused.nupp")
   test.equal(code, 1, out)
   local decoded = require("cjson").decode(out:match("^(%b{})"))
   local only = decoded.functions[1]
   test.equal(only.outcome, "refused")
   test.equal(only.lanes, nil, "there is no gang to report")
   assert(#only.refusals >= 1, "the refusal is data, not only a message")
   assert(only.refusals[1].message:find("nested numeric loop", 1, true),
      "and it names the construct: " .. only.refusals[1].message)
   assert(only.refusals[1].line > 0, "at a position")
end

-- Two functions over one struct, landing on different gangs: `scale` is
-- ordinary binary64 and takes four lanes, `brighten` is written through
-- `nupp.math.f32` and takes eight. One file used to hold exactly one function,
-- and two gangs in one file is where the shared prelude has to not collide.
local TWO = [[
local span = require("nupp.span")

local struct Sample
    value: float
    weight: float
end

@aot(lanes = true)
local function scale(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    factor: number
): nil
    if samples.count ~= source.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > samples.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples:getMut(i)
        local input = source:get(i)
        sample.value = input.value * factor + input.weight
        sample.weight = input.weight * factor
    end
end

@aot(lanes = true)
local function brighten(
    exclusive samples: span.WriteSpan<Sample>,
    borrows source: span.Span<Sample>,
    first: integer,
    last: integer,
    lift: float
): nil
    if samples.count ~= source.count then
        error("length mismatch", 2)
    end
    if first < 1 or last > samples.count or first > last + 1 then
        error("range out of bounds", 2)
    end

    for i = first, last do
        local sample = samples:getMut(i)
        local input = source:get(i)
        local value = nupp.math.f32.narrow(input.value)
        local weight = nupp.math.f32.narrow(input.weight)
        sample.value = nupp.math.f32.add(value, lift)
        sample.weight = nupp.math.f32.mul(weight, lift)
    end
end

return {scale = scale, brighten = brighten, Sample = Sample,}
]]

function M.everyAotFunctionInAFileIsCompiled()
   local dir = project{["two.nupp"] = TWO}
   local out, code = run(dir, PINNED .. "--json two.nupp")
   test.equal(code, 0, out)
   local decoded = require("cjson").decode(out)
   test.equal(#decoded.functions, 2, "both functions are reported")
   test.equal(decoded.functions[1].name, "scale", "in source order")
   test.equal(decoded.functions[2].name, "brighten")
   test.equal(decoded.functions[1].lanes.shape, "mixed4", "ordinary arithmetic takes four lanes")
   test.equal(decoded.functions[2].lanes.shape, "f32x8", "explicit binary32 takes eight")

   -- One struct declared once, both gangs present, and each function bringing
   -- its own pair of bodies.
   local _, ccode = run(dir, PINNED .. "--emit c two.nupp")
   test.equal(ccode, 0)
   local c = select(1, run(dir, PINNED .. "--emit c two.nupp"))
   test.equal(select(2, c:gsub("} KsSample;", "")), 1, "the shared struct is declared once")
   assert(c:find("ks_any_m64x4", 1, true) and c:find("ks_any_m32x8", 1, true),
      "each gang brings its own mask helpers, named so they cannot collide")
   test.equal(select(2, c:gsub("float nupp_f32_nan", "")), 1,
      "the helpers no gang owns appear once however many gangs the file uses")
   for _, symbol in ipairs({"ks_scale", "ks_scale_forced_scalar", "ks_brighten", "ks_brighten_forced_scalar"}) do
      assert(c:find("void " .. symbol .. "(", 1, true), symbol .. " is defined")
   end

   local binding = select(1, run(dir, PINNED .. "--emit binding two.nupp"))
   assert(binding:find("scale = scale", 1, true) and binding:find("brighten = brighten", 1, true),
      "the generated module exports both wrappers: " .. binding:sub(-200))
end

-- A gang is 16 or 32 bytes. The tier decides which fit: 32 is one AVX register
-- and two NEON registers, 16 is the SSE2 register every x86-64 has. The tier is
-- selected rather than measured, because a build that probed the machine in
-- front of it would produce an artifact that only runs there.
function M.theBaselineX86TierGetsTheNarrowGang()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu compute.nupp")
   test.equal(code, 0, "plain x86-64 vectorises rather than refusing\n" .. out)
   local decoded = require("cjson").decode(out)
   test.equal(decoded.target.tier, "baseline", "and did not quietly promise instructions nobody asked for")
   test.equal(decoded.functions[1].lanes.shape, "mixed2")
   test.equal(decoded.functions[1].lanes.lanes, 2,
      "half the lanes of AVX, which is the point: a smaller win, not no win")

   local checkOut, checkCode = run(dir, "--check --target x86_64-unknown-linux-gnu compute.nupp")
   test.equal(checkCode, 0, "and --check agrees it lowered\n" .. checkOut)
end

function M.aWiderTierGetsTheWiderGang()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp")
   test.equal(code, 0, out)
   local decoded = require("cjson").decode(out)
   test.equal(decoded.target.triple, "x86_64-unknown-linux-gnu")
   test.equal(decoded.target.tier, "avx2", "the tier is reported, because it changed the answer")
   test.equal(decoded.functions[1].lanes.shape, "mixed4")
   test.equal(decoded.functions[1].lanes.lanes, 4)
end

function M.theWidestGangThatFitsWins()
   -- Both widths are available at avx2, so the choice has to be the wider one.
   -- Preference used to come from the order the shapes were listed in, which
   -- would have picked four narrow lanes over four wide ones here.
   local dir = project{["compute.nupp"] = COMPUTE}
   local out = select(1, run(dir, "--json --target x86_64-unknown-linux-gnu --features avx2 compute.nupp"))
   local decoded = require("cjson").decode(out)
   test.equal(decoded.functions[1].lanes.shape, "mixed4",
      "not mixed2, which also fits and holds half as much")
end

function M.armHasOneTierAndNeedsNoSelection()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, "--json --target aarch64-apple-darwin compute.nupp")
   test.equal(code, 0, out)
   local decoded = require("cjson").decode(out)
   test.equal(decoded.target.tier, "neon", "its 16-byte registers are mandatory, so there is nothing to opt into")
   test.equal(decoded.functions[1].lanes.shape, "mixed4")
end

function M.anUnknownTargetOrTierIsRejected()
   local dir = project{["compute.nupp"] = COMPUTE}
   local out, code = run(dir, "--target sparc-sun-solaris compute.nupp")
   test.equal(code, 1, out)
   assert(out:find("unknown target", 1, true), out)

   local tierOut, tierCode = run(dir, "--target aarch64-apple-darwin --features sse9 compute.nupp")
   test.equal(tierCode, 1, tierOut)
   assert(tierOut:find("has no feature tier sse9", 1, true),
      "and names the tiers it does have: " .. tierOut)
end

function M.aFileWithNoAotFunctionIsAnError()
   local dir = project{["plain.nupp"] = "local m = {}\n\nreturn m\n"}
   local out, code = run(dir, "plain.nupp")
   test.equal(code, 1, out)
   assert(out:find("no @aot function", 1, true), "which says so: " .. out)
end

return M
