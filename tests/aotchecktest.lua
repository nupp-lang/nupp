-- `nupp check` reports what an AOT build of the checked target refuses.
--
-- The checker's own `@aot` rules are structural. Whether a `number` may be a
-- branch condition, a call reaches an admitted intrinsic, or a lane fits the
-- tier is answered by lowering, and a check used to stop short of it: these
-- programs checked clean and then failed `build`. A check of a target whose
-- policy lowers now lowers too, so each refusal below has to come back from
-- `check` with the code and position `nupp aot` gives it, and a target that
-- does not lower, or a file with no `@aot`, has to be left alone.
--
-- Driven through the real binary, since the verdict of a command is the
-- interface.

local test = require("assert")
local json = require("testjson")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local NUPP = HERE .. "/../bin/nupp"

-- Pinned so a feature tier has the same lanes on every machine the suite runs on.
local TRIPLE = "aarch64-apple-darwin"

-- What `check` has to refuse, each as `nupp aot` refuses it. One refusal a file:
-- lowering stops at the first, in a build as here.
local REFUSED = {
    ["truthy.nupp"] = [[
@aot
local function sign(value: number): number
    if value then
        return 1.0
    end
    return 0.0
end

return {sign = sign}
]],
    ["negation.nupp"] = [[
@aot
local function absent(value: number): boolean
    return not value
end

return {absent = absent}
]],
    ["method.nupp"] = [[
@aot
local function rest(source: string, from: integer): string
    return source:sub(from)
end
return {rest = rest}
]],
    ["shift.nupp"] = [[
local u32 = nupp.math.u32

@aot
local function shifted(a: uint32, b: integer): uint32
    return u32.shiftRightLogical(a, b)
end

return {shifted = shifted}
]],
    ["lane.nupp"] = [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function lane(borrows input: span.Span<float>): number
    if species = simd.vectors(array.float) then
        if species.lanes <= #input then
            return species:load(input, 1):extract(5)
        end
    end
    return 0.0
end

return {lane = lane}
]],
    ["kernel.nupp"] = [[
local span = require("nupp.mem.span")

@aot(target = "gpu")
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, enabled: boolean): nil
    assert(#output == #input, "length mismatch")
    for index = 1, #output do
        output[index] = enabled and input[index] or 0.0
    end
end

return {scale = scale}
]],
    ["family.nupp"] = [[
@aot
local function repeated<const N: integer>(value: number, count: N): number
    local answer = value
    for _ = 1, count as integer do
        answer = answer + value
    end
    return answer
end

return repeated(1.0, 1) + repeated(1.0, 2) + repeated(1.0, 3) + repeated(1.0, 4) + repeated(1.0, 5)
    + repeated(1.0, 6) + repeated(1.0, 7) + repeated(1.0, 8) + repeated(1.0, 9)
]],
    -- A read one past what `at + 2 < #source` proves.
    ["cursorpast.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function past(borrows source: span.Span<uint8>): uint32
    local at: uint32 = 0
    local total: uint32 = 0
    while at + 2 < #source do
        total = total + source[at + 4]
        at = at + 3
    end
    return total
end

return {past = past}
]],
    -- A read one past the three elements `#rgb == 3 * #grey` carries from
    -- `at < #grey` into `rgb`.
    ["factorpast.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function past(exclusive grey: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): nil
    assert(#rgb == 3 * #grey)
    local at: uint32 = 0
    while at < #grey do
        grey[at + 1] = rgb[at + 4]
        at = at + 1
    end
end

return {past = past}
]],
    -- A write one past what `out + 3 <= #output` proves.
    ["cursorstorepast.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function storePast(exclusive output: span.WriteSpan<uint8>): uint32
    local out: uint32 = 0
    while out + 3 <= #output do
        output[out + 4] = 7
        out = out + 3
    end
    return out
end

return {storePast = storePast}
]],
}

-- What `check` has to leave alone: an admitted `@aot` function, and a file with none.
local ADMITTED = {
    -- A `float` read passed where `f32` is wanted: the load is already one.
    ["floatread.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function scale(exclusive output: span.WriteSpan<float>, borrows input: span.Span<float>, factor: float): nil
    assert(#output == #input, "length mismatch")
    for index = 1, #output do
        output[index] = nupp.math.f32.mul(input[index], factor)
    end
end

return {scale = scale}
]],
    -- A number literal passed to a `uint32` parameter, which the literal fits.
    ["literalwidth.nupp"] = [[
local valuebuilder = require("nupp.codec.valuebuilder")

@aot
local function pair(nullValue: any): any
    local builder = valuebuilder.new(nullValue)
    valuebuilder.openArray(builder, 2)
    valuebuilder.boolean(builder, true)
    valuebuilder.null(builder)
    valuebuilder.close(builder)
    return valuebuilder.finish(builder)
end

-- Not returned: an `any` result is not an interface a module can export.
local _ = pair
]],
    -- A species witness named through the global `nupp.mem.array` path.
    ["globalwitness.nupp"] = [[
local array = nupp.mem.array
local span = require("nupp.mem.span")
local simd = require("nupp.simd")

@aot
local function countQuotes(borrows source: span.Span<uint8>): uint32
    local cursor: uint32 = 0
    local found: uint32 = 0
    if species = simd.vectors(array.uint8) then
        while cursor + species.lanes <= #source do
            found = found + (species:load(source, cursor + 1) == 34):count()
            cursor = cursor + species.lanes
        end
    end
    if lanes = simd.vectors(nupp.mem.array.uint8) then
        found = found + lanes.lanes - lanes.lanes
    end
    while cursor < #source do
        if source[cursor + 1] == 34 then
            found = found + 1
        end
        cursor = cursor + 1
    end
    return found
end

return {countQuotes = countQuotes}
]],
    ["clamp.nupp"] = [[
@aot
local function clamp(value: number, low: number, high: number): number
    if value < low then return low end
    if value > high then return high end
    return value
end

return {clamp = clamp}
]],
    -- Guards relating counts through a factor and an offset, in each
    -- spelling, feeding a counted loop over the shorter span and the room a
    -- cursor bounded by it has in the longer one.
    ["factorguards.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function box3(exclusive grey: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): nil
    assert(#rgb == 3 * #grey)
    local at: uint32 = 0
    while at < #grey do
        grey[at + 1] = rgb[at + 1] + rgb[at + 2] + rgb[at + 3]
        at = at + 1
    end
end

@aot
local function first(exclusive grey: span.WriteSpan<uint8>, borrows rgb: span.Span<uint8>): uint32
    if #grey * 3 ~= #rgb then
        error("length mismatch", 2)
    end
    local total: uint32 = 0
    for i = 1, #grey do
        grey[i] = rgb[i]
        total = total + 1
    end
    return total
end

@aot
local function padded(exclusive output: span.WriteSpan<uint8>, borrows input: span.Span<uint8>): uint32
    assert(#output >= 4 * #input + 2)
    local i: uint32 = 0
    while i < #input do
        output[i + 1] = input[i + 1]
        output[i + 6] = 0
        i = i + 1
    end
    return i
end

return {box3 = box3, first = first, padded = padded}
]],
    -- Reads and writes displaced past one cursor, each within what its
    -- literal guard proves, in every spelling of the guard.
    ["cursorsteps.nupp"] = [[
local span = require("nupp.mem.span")

@aot
local function triples(exclusive output: span.WriteSpan<uint8>, borrows source: span.Span<uint8>): uint32
    local at: uint32 = 0
    local out: uint32 = 0
    while at + 2 < #source and out + 4 <= #output do
        output[out + 1] = source[at + 1]
        output[out + 2] = source[at + 2]
        output[out + 3] = source[at + 3]
        output[out + 4] = 0
        at = at + 3
        out = out + 4
    end
    local total: uint32 = 0
    if #source > at + 1 then
        total = total + source[at + 2]
    end
    if #source >= at + 2 then
        total = total + source[at + 2]
    end
    if at + 1 >= #source or source[at + 2] == 7 then
        total = total + 1
    end
    if at + 1 < #source and source[at + 2] == 9 then
        total = total + 2
    end
    return out + total
end

return {triples = triples}
]],
    ["plain.nupp"] = [[
local function sign(value: number): number
    if value then
        return 1.0
    end
    return 0.0
end

return {sign = sign}
]],
}

local function write(path, text)
    local parent = path:match("^(.*)/[^/]+$")
    if parent then
        assert(os.execute(("mkdir -p %q"):format(parent)) == 0)
    end
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function run(dir, argv)
    local pipe = assert(io.popen(("cd %q && NO_COLOR= '%s' %s 2>&1; echo \"__exit__:$?\""):format(dir, NUPP, argv)))
    local out = pipe:read("*a")
    pipe:close()
    local code = assert(tonumber(out:match("__exit__:(%d+)%s*$")), "no exit status in:\n" .. out)

    return (out:gsub("__exit__:%d+%s*$", "")), code
end

local function checkJson(dir, argv)
    local out, code = run(dir, "check --json " .. (argv or ""))
    local body = out:match("(%b{})")
    assert(body, ("`check --json %s` in %s answered no JSON: %s"):format(argv or "", dir, out))

    return json.decode(body), code, out
end

local function project(manifest, files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute(("mkdir -p %q"):format(dir)) == 0)
    write(dir .. "/nupp.lua", manifest)
    for name, source in pairs(files) do
        write(dir .. "/" .. name, source)
    end

    return dir
end

-- Every file above, under one lowering target and one that does not lower.
local shared = nil

local function corpus()
    if shared then
        return shared
    end
    local files = {}
    for name, source in pairs(REFUSED) do
        files[name] = source
    end
    for name, source in pairs(ADMITTED) do
        files[name] = source
    end
    shared = project(([[
return {
   include = {"."},
   build = {
      default = "native",
      targets = {
         native = {kind = "modules", aot = "require", aotTarget = %q},
         off = {kind = "modules"},
      },
   },
}
]]):format(TRIPLE), files)

    return shared
end

--- `file -> {"CODE line:col", ...}` for the errors one check reported.
local function refusalsByFile(decoded)
    local found = {}
    for _, diagnostic in ipairs(decoded.diagnostics or {}) do
        if diagnostic.severity == "error" then
            local file = tostring(diagnostic.file):match("([^/\\]+)$")
            found[file] = found[file] or {}
            local start = diagnostic.range and diagnostic.range.start or {}
            found[file][#found[file] + 1] = ("%s %d:%d"):format(diagnostic.code, start.line or 0, start.column or 0)
        end
    end

    return found
end

local M = {}

-- The promise: what `nupp aot` refuses for a target, `nupp check` of that target
-- reports, at the same code and position, and nothing it admits is refused.
function M.checkRefusesExactlyWhatAotRefuses()
    local dir = corpus()
    local decoded, code, raw = checkJson(dir, "")
    test.equal(code, 1, raw)
    assert(decoded.ok == false, raw)
    local checked = refusalsByFile(decoded)
    for name in pairs(REFUSED) do
        local out, aotCode = run(dir, ("aot --triple %s %s"):format(TRIPLE, name))
        test.equal(aotCode, 1, name .. " is refused by aot: " .. out)
        local escaped = name:gsub("%.", "%%.")
        local line, column, refusedCode = out:match(escaped .. ":(%d+):(%d+): aot: (NUPP%d+):")
        assert(refusedCode, name .. ": aot names a coded refusal: " .. out)
        local expected = ("%s %s:%s"):format(refusedCode, line, column)
        local reported = checked[name] or {}
        test.equal(#reported, 1, name .. " is refused once by check: " .. raw)
        test.equal(reported[1], expected, name .. ": check and aot agree")
    end
    for name in pairs(ADMITTED) do
        assert(checked[name] == nil, name .. " is admitted and checks clean: " .. raw)
    end
    for _, name in ipairs({"lane.nupp", "kernel.nupp", "family.nupp"}) do
        assert(checked[name][1]:match("^NUPP290[678] "), name .. " carries its own refusal code: " .. checked[name][1])
    end
end

-- The method-call case `aotclitest` pins for `nupp aot`, through `check`: the
-- code, the range covering the receiver, and help naming the target and tier.
function M.theRefusalIsACodedDiagnosticWithARange()
    local decoded = checkJson(corpus(), "method.nupp")
    local diagnostic = decoded.diagnostics[1]
    assert(diagnostic, "the named file is refused")
    test.equal(diagnostic.code, "NUPP2905")
    test.equal(diagnostic.severity, "error")
    test.equal(diagnostic.range.start.line, 3)
    test.equal(diagnostic.range.start.column, 12)
    test.equal(diagnostic.range["end"].column, 18, "the range covers `source`")
    assert(diagnostic.message:find("method :sub on a string is not admitted", 1, true), diagnostic.message)
    assert(diagnostic.help:find("target native", 1, true) and diagnostic.help:find("neon", 1, true), diagnostic.help)
    test.equal(diagnostic.docs, "docs/learn/performance/ahead-of-time/index.md#annotation-guarantees")
end

-- `off` never lowers and a build under it never refuses, so a check says nothing.
function M.aTargetThatDoesNotLowerIsLeftAlone()
    local decoded, code, raw = checkJson(corpus(), "--target off")
    test.equal(code, 0, raw)
    assert(decoded.ok == true, raw)
end

-- An unchanged project is answered from the last check's records, refusals
-- included: the second check lowers nothing and says the same thing.
function M.aWarmCheckReplaysTheRefusalsWithoutLowering()
    local dir = project(([[
return {include = {"."}, build = {targets = {native = {kind = "modules", aot = "require", aotTarget = %q}}}}
]]):format(TRIPLE), {["method.nupp"] = REFUSED["method.nupp"], ["clamp.nupp"] = ADMITTED["clamp.nupp"]})
    local cold, _, coldRaw = checkJson(dir, "")
    assert(cold.timing.compiledModules > 0, coldRaw)
    local warm, code, warmRaw = checkJson(dir, "")
    test.equal(code, 1, warmRaw)
    test.equal(warm.timing.compiledModules, 0, "nothing is checked or lowered again: " .. warmRaw)
    test.equal(#warm.diagnostics, 1, warmRaw)
    test.equal(warm.diagnostics[1].code, "NUPP2905", warmRaw)
    -- A fix is an edit to that module alone, and the refusal goes with it.
    write(dir .. "/method.nupp", "@aot\nlocal function rest(from: integer): integer\n    return from\nend\n"
        .. "return {rest = rest}\n")
    local fixed, fixedCode, fixedRaw = checkJson(dir, "")
    test.equal(fixedCode, 0, fixedRaw)
    test.equal(fixed.timing.compiledModules, 1, fixedRaw)
end

-- A build lowers what its deliverable reaches. A module no entry requires is
-- not in the library, is not refused by the build, and is not refused here.
function M.onlyWhatTheTargetReachesIsRefused()
    local dir = project(([[
return {
   include = {"src"},
   build = {targets = {native = {kind = "modules", entries = {"main"}, aot = "require", aotTarget = %q}}},
}
]]):format(TRIPLE), {
        ["src/main.nupp"] = 'local used = require("used")\nreturn used\n',
        ["src/used.nupp"] = ADMITTED["clamp.nupp"],
        ["src/stray.nupp"] = REFUSED["truthy.nupp"],
    })
    local decoded, code, raw = checkJson(dir, "")
    test.equal(code, 0, "the unreached module is not the target's to refuse: " .. raw)
    test.equal(#decoded.diagnostics, 0, raw)
    local out, buildCode = run(dir, "build")
    test.equal(buildCode, 0, "and the build agrees: " .. out)
    -- Reached, it is refused, although the module itself did not change.
    write(dir .. "/src/main.nupp", 'local used = require("used")\nlocal stray = require("stray")\n'
        .. "return {used = used, stray = stray}\n")
    local reached, reachedCode, reachedRaw = checkJson(dir, "")
    test.equal(reachedCode, 1, reachedRaw)
    test.equal(reached.diagnostics[1].code, "NUPP2905", reachedRaw)
    assert(tostring(reached.diagnostics[1].file):match("stray%.nupp$"), reachedRaw)
end

-- A const-generic family is specialized for every call the deliverable makes into
-- it. Called only from another module, it used to be lowered by check with its own
-- module's calls alone -- none -- and passed, while the build, collecting the calls
-- across the graph, refused the tenth body. A check now says what the build says,
-- keeps saying it from the records when nothing moved, and stops once the calls do.
function M.aFamilyOnlyAnotherModuleClosesIsRefusedByCheck()
    local family = REFUSED["family.nupp"]:gsub("\nreturn repeated%(.*$", "\nreturn {repeated = repeated}\n")
    local calls = {}
    for count = 1, 9 do
        calls[#calls + 1] = ("repeated(1.0, %d)"):format(count)
    end
    local function caller(n)
        return 'local family = require("family")\nlocal repeated = family.repeated\nreturn '
            .. table.concat(calls, " + ", 1, n) .. "\n"
    end
    local dir = project(([[
return {include = {"src"}, build = {targets = {native = {kind = "modules", entries = {"main"}, aot = "require", aotTarget = %q}}}}
]]):format(TRIPLE), {
        ["src/family.nupp"] = family,
        ["src/main.nupp"] = caller(9),
        ["src/other.nupp"] = "return {answer = 42}\n",
    })
    local out, buildCode = run(dir, "build")
    test.equal(buildCode, 1, "the build refuses the family: " .. out)
    assert(out:find("NUPP2908", 1, true), out)
    local decoded, code, raw = checkJson(dir, "")
    test.equal(code, 1, raw)
    local refused = refusalsByFile(decoded)
    assert(refused["family.nupp"] and refused["family.nupp"][1]:match("^NUPP2908 "), raw)
    test.equal(refused["main.nupp"], nil, raw)
    local warm, warmCode, warmRaw = checkJson(dir, "")
    test.equal(warmCode, 1, warmRaw)
    test.equal(warm.timing.compiledModules, 0, warmRaw)
    test.equal(#warm.diagnostics, 1, warmRaw)
    -- Eight bodies fit, and the verdict follows the caller without the family moving.
    write(dir .. "/src/main.nupp", caller(8))
    local fixed, fixedCode, fixedRaw = checkJson(dir, "")
    test.equal(fixedCode, 0, fixedRaw)
    test.equal(fixed.timing.compiledModules, 1, fixedRaw)
    local _, fixedBuild = run(dir, "build")
    test.equal(fixedBuild, 0, "and the build agrees")
end

return M
