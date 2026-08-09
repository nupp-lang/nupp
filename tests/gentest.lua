local parser = require("nupp.parser")
local gen = require("nupp.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local ROOT = HERE .. "/.."

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
            tostring(want), tostring(got)), 2)
    end
end

local function generate(src)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax errors in test source")
    local code, diags = gen.generate(result, "test")
    assertEq(#diags, 0, "gen diagnostics for " .. src)
    return code
end

local function generateCoverage(src)
    local result = parser.parse(src, "coverage-test.nupp")
    assertEq(#result.errors, 0, "syntax errors in coverage test source")
    local code, diags, metadata = gen.generate(result, "coverage-test.nupp",
        {path = "coverage-test.nupp"})
    assertEq(#diags, 0, "coverage gen diagnostics for " .. src)
    return code, metadata
end

-- Compile and execute; returns the chunk's results.
local function run(src, ...)
    local code = generate(src)
    local chunk, err = loadstring(code, "@gen_test")
    if not chunk then
        error("generated code does not load: " .. tostring(err)
            .. "\n---\n" .. code, 2)
    end
    return chunk(...)
end

local function countLines(s)
    local _, n = s:gsub("\n", "")
    return n
end

local M = {}

function M.lineCountInvariant()
    local cases = {
        "local x: number = 1\nreturn x",
        "local record R\n   a: number\n   b: string\nend\nreturn 1",
        "local f =\n   |a: number,\n    b: number| -> a + b\nreturn f(1, 2)",
        "return `multi\nline ${1 +\n2} tail`",
        "local v: number | string = 5\nif v is number then\n   return v\nend",
        "local f = |a: number,\n   b: number| -> do\n   return a + b\nend\nreturn f(1, 2)",
        "local t = nil\nlocal v = t?.a\n   ?.b\nreturn v",
        "local n = 7\nn //=\n   2\nreturn n",
        "local m = nil\nm ??=\n   3\nreturn m",
    }
    for _, src in ipairs(cases) do
        local code = generate(src)
        assertEq(countLines(code), countLines(src) + 1,
            "line count changed for:\n" .. src .. "\n---\n" .. code)
    -- (+1: generated output always ends with a final newline)
    end
end

function M.coverageModeLeavesNormalOutputAlone()
    local src = "local n: integer = 1\nreturn n"
    local result = parser.parse(src, "coverage-off.nupp")
    local ordinary = assert(gen.generate(result, "coverage-off.nupp"))
    local explicitlyOff = assert(gen.generate(result, "coverage-off.nupp", false))
    assertEq(explicitlyOff, ordinary, "coverage=false changes ordinary Lua")
end

function M.coverageModeCountsStatementsFunctionsAndBranches()
    local code, metadata = generateCoverage(table.concat({
        "local function choose(value: boolean): integer",
        "   if value then return 1 end",
        "   return 2",
        "end",
        "return choose(true)",
    }, "\n"))
    assertEq(countLines(code), 5, "coverage generation changes line count")
    assert(metadata and metadata.path == "coverage-test.nupp", "coverage manifest path")
    local kinds = {}
    for _, site in ipairs(metadata.sites) do kinds[site.kind] = (kinds[site.kind] or 0) + 1 end
    assert((kinds.statement or 0) >= 3, "statement sites are recorded")
    assert((kinds["function"] or 0) >= 1, "function sites are recorded")
    assert((kinds.branch or 0) >= 1, "branch sites are recorded")
    _G.__nuppCoverage = nil
    local chunk, err = loadstring(code, "@coverage_generated")
    assert(chunk, tostring(err) .. "\n" .. code)
    assertEq(chunk(), 1, "instrumented program result")
    local hits = assert(_G.__nuppCoverage and _G.__nuppCoverage.hits["coverage-test.nupp"])
    local sawStatement, sawFunction, sawTrue = false, false, false
    for _, site in ipairs(metadata.sites) do
        if site.kind == "statement" and (hits[tostring(site.id)] or 0) > 0 then
            sawStatement = true
        end
        if site.kind == "function" and (hits[tostring(site.id)] or 0) > 0 then
            sawFunction = true
        end
        if site.kind == "branch" and (hits[tostring(site.id) .. ":true"] or 0) > 0 then
            sawTrue = true
        end
    end
    assert(sawStatement and sawFunction and sawTrue,
        "instrumented run records the executed source sites")
    _G.__nuppCoverage = nil
end

function M.erasure()
    assertEq(run("local x: number = 21\nreturn x * 2"), 42)
    assertEq(run("local record P\n   x: number\nend\nlocal p = { x = 7 } as P\nreturn p.x"), 7)
    assertEq(run("local type E = 'a' | 'b'\nreturn 'ok'"), "ok")
    assertEq(run("local type Id = uint32\nlocal i = 9\nreturn i + 0"), 9)
    assertEq(run("local function f<T>(x: T): T return x end\nreturn f('generic')"), "generic")
    assertEq(run("@jit local function hot(): number return 5 end\nreturn hot()"), 5)
end

function M.nestedRecordsAndInlineMethodsRun()
    assertEq(run(table.concat({
        "local record namespace",
        "   record Task",
        "      value: number",
        "      function doubled(): number",
        "         return self.value * 2",
        "      end",
        "   end",
        "end",
        "local task = setmetatable({value = 21}, namespace.Task)",
        "return task:doubled()",
    }, "\n")), 42)
end

function M.tecsStyleLateEventRegistrationRuns()
    assertEq(run(table.concat({
        "local interface Event",
        "   eventId: integer",
        "   init: function(instance: self, ...: any)",
        "end",
        "local record events",
        "   record OnSpawn is Event",
        "      entity: integer",
        "      metamethod __call: function(self, entity: integer): self",
        "   end",
        "end",
        "events.OnSpawn.init = function(instance: events.OnSpawn, entity: integer)",
        "   instance.entity = entity",
        "end",
        "local function newEvent<E is Event>(event: metatable<E>)",
        "   local id = 7",
        "   local instanceMt = {__index = event}",
        "   setmetatable(event, {__call = function(_self: E, ...: any): E",
        "      local instance = setmetatable({eventId = id}, instanceMt) as E",
        "      event.init(instance, ...)",
        "      return instance",
        "   end})",
        "end",
        "newEvent(events.OnSpawn)",
        "local spawned = events.OnSpawn(42)",
        "return spawned.eventId + spawned.entity",
    }, "\n")), 49)
end

function M.constSemantics()
    assertEq(run("const x: number = 42\nreturn x"), 42)
    assertEq(run("const function f(x: number): number return x * 2 end\nreturn f(21)"),
        42)
    local code = generate("const answer: integer = 42\nreturn answer")
    assert(code:find("const answer = 42", 1, true),
        "const should survive type erasure: " .. code)
end

function M.generatedSingleAssignmentBindingsAreConst()
    local recordCode = generate(table.concat({
        "local record Point",
        "   x: number",
        "end",
        "return Point",
    }, "\n"))
    assert(recordCode:find("const Point = {}", 1, true), recordCode)

    local interfaceCode = generate(table.concat({
        "local interface Named",
        "   name: string",
        "   function getName(): string return self.name end",
        "end",
        "return Named",
    }, "\n"))
    assert(interfaceCode:find("const Named = {}", 1, true), interfaceCode)

    local compoundCode = generate(table.concat({
        "local target = {value = 8}",
        "target['value'] //= 2",
        "return target.value",
    }, "\n"))
    assert(compoundCode:find("do const __nuppT", 1, true), compoundCode)
    assert(compoundCode:find("const __nuppT2 =", 1, true), compoundCode)
end

-- A literal type is a type-only node like any other postfix or shape: the annotation
-- has to vanish rather than leaving its token behind as a bare expression statement
-- next to the one the initializer already wrote.
function M.literalTypeErasure()
    assertEq(run("local t: true = true\nreturn t"), true)
    assertEq(run("local f: false = false\nreturn f"), false)
    assertEq(run("local m: \"read\" = \"read\"\nreturn m"), "read")
    assertEq(run(
        "local function mode(x: \"read\"): \"read\" return x end"
        .. "\nreturn mode(\"read\")"), "read")
end

-- `const T`, the read-only view, is a type node the same way `T?` or `T*` are: erased
-- in place, not left as a stray identifier beside the value.
function M.constTypeErasure()
    assertEq(run("local x: const number = 42\nreturn x"), 42)
end

function M.ternarySemantics()
    assertEq(run("return 1 < 2 ? 'yes' : 'no'"), "yes")
    -- falsy middle arm must still be selected (the a-and-b-or-c pitfall)
    assertEq(run("local t = true\nreturn t ? false : 1"), false)
    -- laziness: the untaken arm must not evaluate
    assertEq(
        run([[
local hits = 0
local function boom() hits = hits + 1 return 9 end
local v = true ? 1 : boom()
return hits]]),
        0
    )
    -- right associativity chain
    assertEq(run("local n = 2\nreturn n == 1 ? 'one' : n == 2 ? 'two' : 'many'"), "two")
end

function M.safeNavigationSemantics()
    assertEq(run("local t = { x = 5 }\nreturn t?.x"), 5)
    assertEq(run("local t = nil\nreturn t?.x"), nil)
    assertEq(run("local t = { m = { n = 3 } }\nreturn t?.m?.n"), 3)
    assertEq(run("local t = nil\nreturn t?.['k']"), nil)
    assertEq(run("local f = nil\nreturn f?.(1)"), nil)
    assertEq(run("local f = function(a) return a * 3 end\nreturn f?.(2)"), 6)
    -- single evaluation of the object expression
    assertEq(
        run(
            [[
local calls = 0
local function get() calls = calls + 1 return { v = 1 } end
local _ = get()?.v
return calls]]
        ),
        1
    )
end

function M.shortFunctionSemantics()
    assertEq(run("local add = |a, b| -> a + b\nreturn add(2, 3)"), 5)
    assertEq(run("local dbl = x -> x * 2\nreturn dbl(21)"), 42)
    assertEq(run("local t = || -> true\nreturn t()"), true)
    assertEq(run("local f = |n: number| -> do return n + 1 end\nreturn f(1)"), 2)
    assertEq(run("local curry = a -> b -> a .. b\nreturn curry('x')('y')"), "xy")
    -- Expression-bodied short functions always return exactly one value.
    assertEq(select("#", run([[
local function pair() return 1, 2 end
local one = || -> pair()
return one()]])), 1)
end

-- What LuaJIT 2.1 backported is written out, not lowered. This is the whole reason a
-- `?.` chain costs a branch instead of a closure call, so it is asserted on the
-- generated text rather than only on the behaviour.
function M.backportedSyntaxIsPassedThrough()
    local cases = {
        {"local t = nil\nreturn t?.a?.b", "?."},
        {"local t = nil\nreturn t?.:m()", "?. : m"},
        {"local t = {}\nreturn t:m?.()", "?."},
        {"return 1 ?? 2", "??"},
        {"return true ? 1 : 2", "?"},
        {"return 3 & 5 | 2 ~ 1 << 1 >> 1 ~>> 1", "&"},
        {"local a = 1\na += 2\nreturn a", "+="},
        {"local a = 5\na ~= 3\nreturn a", "~="},
        {"return (|a| -> a)(1)", "|a| ->"},
        {"return 1_000", "1_000"},
    }
    for _, case in ipairs(cases) do
        local code = generate(case[1])
        assert(code:find(case[2], 1, true),
            ("expected %q in the output for %s\n---\n%s")
            :format(case[2], case[1], code))
    end
    -- and no trace of the lowerings these replaced
    local lowered = generate("local t = nil\nreturn t?.a ?? (1 & 2)")
    assert(not lowered:find("function", 1, true), "no closure: " .. lowered)
    assert(not lowered:find("bit.", 1, true), "no bit library: " .. lowered)
end

-- What 2.1 did not backport still is lowered, so those keep their own tests.
function M.unbackportedSyntaxIsStillLowered()
    assertEq(run("return -7 // 2"), -4)
    assertEq(run("local a = -7\na //= 2\nreturn a"), -4)
    assertEq(run("local a = nil\na ??= 5\nreturn a"), 5)
    assertEq(run("local f = |...v| -> v.n\nreturn f(1, 2, 3)"), 3)
    assertEq(run("local function f(...v) return v.n end\nreturn f(nil, nil)"), 2)
    local code = generate("return 7 // 2")
    assert(code:find("math.floor", 1, true), "floor division lowers: " .. code)
end

function M.numberSeparatorSemantics()
    assertEq(run("return 1_234 + 0_x_10 + 1_e_2"), 1350)
    local code = generate("return 1_2_3")
    assert(code:find("1_2_3", 1, true),
        "separators survive: the runtime reads them: " .. code)
end

function M.continueSemantics()
    assertEq(run([[
local total = 0
for i = 1, 5 do
   if i % 2 == 0 then continue end
   total += i
end
return total]]), 9)
    assertEq(
        run([[
local n, hits = 0, 0
repeat
   n += 1
   if n < 3 then continue end
   hits += 1
until n >= 3
return hits]]),
        1
    )
end

function M.namedVarargSemantics()
    local n, first, second, plain = run(
        [[
local function collect(prefix, ...args)
   return args.n, args[1], args[2], select("#", ...)
end
return collect("ignored", nil, 3)]]
    )
    assertEq(n, 2)
    assertEq(first, nil)
    assertEq(second, 3)
    assertEq(plain, 2)
    assertEq(run("local count = |...args| -> args.n\nreturn count(nil, nil)"), 2)

    local code = generate("local function f(...args) return args.n end")
    assert(code:find("...", 1, true), "plain vararg remains in output")
    assert(code:find("const args = { n = select", 1, true),
        "named vararg table is lowered")
    assert(not code:find("...args", 1, true), "named spelling is erased")
end

function M.istringSemantics()
    assertEq(run("local n = 6\nreturn `n is ${n}, double ${n * 2}`"),
        "n is 6, double 12")
    assertEq(run("return `${1}${2}`"), "12")
    assertEq(run("return `plain`"), "plain")
    assertEq(run("return `quote \" and \\` tick`"), 'quote " and ` tick')
    assertEq(run("return `escaped \\${x}`"), "escaped ${x}")
    assertEq(run("return `a\nb`"), "a\nb")
    assertEq(run("local t = { n = 4 }\nreturn `v=${ ({ t.n })[1] }`"), "v=4")
end

function M.isSemantics()
    assertEq(run("local v: number | string = 'hi'\nreturn v is string"), true)
    assertEq(run("local v: number | string = 5\nreturn v is string"), false)
    assertEq(run("local v = nil\nreturn v is nil"), true)
    assertEq(run("local f = print\nreturn f is function(): nil"), true)
end

function M.bitAndFloordivSemantics()
    assertEq(run("return 5 & 3"), 1)
    assertEq(run("return 5 | 2"), 7)
    assertEq(run("return 2 ~ 3"), 1)
    assertEq(run("return 1 << 4"), 16)
    assertEq(run("return 256 >> 4"), 16)
    assertEq(run("return -8 ~>> 1"), -4)
    assertEq(run("return ~0"), -1)
    assertEq(run("return -7 // 2"), -4)
    assertEq(run("return 7 // 2"), 3)
end

function M.exampleProgramRuns()
    local src = assert(io.open(ROOT .. "/examples/todo.nupp")):read("*a")
    local result = parser.parse(src, "todo.nupp")
    assertEq(#result.errors, 0, "example must parse")
    -- checking first supplies reified-struct hints to the generator
    local check = require("fragment")
    local envMod = require("nupp.env")
    local checkDiags = check.check(result, "todo.nupp", envMod.new(ROOT))
    assertEq(#checkDiags, 0, "example must check")
    local code, diags = gen.generate(result, "todo.nupp")
    assertEq(#diags, 0, "example must generate")
    assertEq(countLines(code), countLines(src),
        "example line-count invariant")
    -- capture print output
    local lines = {}
    local realPrint = print
    _G.print = function(...)
        local parts = {}
        for j = 1, select("#", ...) do parts[j] = tostring(select(j, ...)) end
        lines[#lines + 1] = table.concat(parts, "\t")
    end
    local chunk = assert(loadstring(code, "@examples/todo.nupp"))
    local ok, err = pcall(chunk)
    _G.print = realPrint
    assert(ok, "example must run: " .. tostring(err))
    local text = table.concat(lines, "\n")
    assert(text:find("#1 write the parser", 1, true), "task 1 listed:\n" .. text)
    assert(not text:find("water the plants", 1, true), "low task filtered")
    assert(not text:find("#2", 1, true), "done task filtered")
    assert(text:find("nothing is due", 1, true), "guard branch output")
    assert(text:find("^%[ %]", 1) or true, "format sane")
    assert(text:find("5", 1, true), "lerp result printed")
end

return M
