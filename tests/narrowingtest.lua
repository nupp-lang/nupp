local testAssert = require("nupp.test")
local assertions = require("helpers.assertions")
-- Narrowing through paths, discriminated unions, literal types, and the
-- strict-mode module boundary.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local mutation = require("nupp.compiler.check.mutation")
local analysis = require("nupp.compiler.analysis")
local narrowing = require("nupp.compiler.types.narrowing")
local T = require("nupp.compiler.types")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function diagsOf(src, opts)
    local result = parser.parse(src, "test.g.nupp")
    testAssert.equal(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local out = {}
    for j, d in ipairs(check.check(result, "test.g.nupp", env, opts)) do
        out[j] = d.code .. ":" .. d.line
    end

    return table.concat(out, " ")
end

local assertClean = assertions.check(diagsOf, function(src) return "expected clean:\n" .. src end)

local CFG = table.concat({"local record Cfg", "    port: number?", "    name: string", "end",}, "\n")

local M = {}

-- A type that is not a union survives subtraction whole, as narrowing.md's
-- "Exhausted subtraction" says; only a union that loses every member is `never`.
function M.aWholeSingleTypeSurvivesSubtraction()
    local function shown(t)
        return T.tostring(t)
    end
    testAssert.equal(shown(narrowing.subtract(T.boolean, T.boolean)), "boolean")
    testAssert.equal(shown(narrowing.subtract(T.string, T.string)), "string")
    testAssert.equal(shown(narrowing.subtract(T.nil_, T.nil_)), "nil")
    testAssert.equal(shown(narrowing.subtract(T.boolean, T.literal(true, T.boolean))), "false")
    testAssert.equal(shown(narrowing.subtract(T.union({T.string, T.integer}), T.union({T.string, T.integer}))), "never")
    testAssert.equal(shown(narrowing.subtract(T.any, T.nil_)), "any")
    testAssert.equal(shown(narrowing.subtract(T.unknown, T.nil_)), "unknown")
end

local SHAPES = table.concat(
    {
        "local record Circle",
        "    kind: 'circle'",
        "    radius: number",
        "end",
        "local record Square",
        "    kind: 'square'",
        "    side: number",
        "end",
    },
    "\n"
)

-- The same rule at program level: the else arm after an exhaustive `is` chain
-- holds the last member rather than `never`, so defensive code there checks.
function M.theElseOfAnExhaustiveIsChainKeepsTheLastMember()
    assertClean(
        SHAPES .. "\n" .. table.concat(
            {
                "local function area(v: Circle | Square): number",
                "    if v is Circle then",
                "        return v.radius",
                "    elseif v is Square then",
                "        return v.side",
                "    else",
                "        error('unexpected shape ' .. tostring(v.kind))",
                "    end",
                "end",
                "return area",
            },
            "\n"
        )
    )
end

-- A fact the checker could not see go stale still leaves the declared shape on
-- the arm it rules out, rather than a `never` that would accept anything there.
function M.aStaleFactDoesNotEmptyAType()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local record R",
                    "    v: string?",
                    "end",
                    "local function poke(target: R): nil",
                    "    target.v = 'hi'",
                    "end",
                    "local r = new R(v = nil)",
                    "local holder = {inner = r}",
                    "r.v = nil",
                    "poke(holder.inner)",
                    "if r.v ~= nil then",
                    "    local n: number = r.v + 1",
                    "    print(n)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2003:12"
    )
end

-- `if v = x` on a type parameter: T may be instantiated with an optional, so it
-- is not "never nil". One bounded by a type that is never nil still is.
function M.anIfBindingAcceptsAnOpenTypeParameter()
    assertClean(
        table.concat(
            {
                "local function firstOr<T>(x: T, d: T): T",
                "    if v = x then",
                "        return v",
                "    end",
                "    return d",
                "end",
                "return firstOr",
            },
            "\n"
        )
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function f<T is string>(x: T): T",
                    "    if v = x then",
                    "        return v",
                    "    end",
                    "    return x",
                    "end",
                    "return f",
                },
                "\n"
            )
        ),
        "NUPP2001:2"
    )
end

function M.aNilGuardDoesNotEraseAGradualValue()
    assertClean(
        table.concat(
            {"local function field(v: any): any", "    if v == nil then return nil end", "    return v.member", "end",},
            "\n"
        )
    )
end

-- `type(u) == "table"` classifies an `unknown` for the branch it holds in. The
-- test proves nothing about a declared type, which `is` narrows, and the other
-- branch keeps claiming nothing.
function M.typeNameTestsClassifyAnUnknown()
    assertClean(
        table.concat(
            {
                "local record Point",
                "    x: integer",
                "end",
                "local function classify(u: unknown, w: unknown): string",
                "    if type(u) == \"table\" then",
                "        local t: table = u",
                "        print(t)",
                "    end",
                "    if type(w) ~= \"string\" then",
                "        return \"other\"",
                "    end",
                "    return w",
                "end",
                "return classify",
            },
            "\n"
        )
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function still(u: unknown): string",
                    "    if type(u) == \"table\" then",
                    "        return \"table\"",
                    "    end",
                    "    return u",
                    "end",
                    "local function named(s: string | number): string",
                    "    if type(s) == \"string\" then",
                    "        return s",
                    "    end",
                    "    return \"no\"",
                    "end",
                    "return still, named",
                },
                "\n"
            )
        ),
        "NUPP2002:5 NUPP2002:9"
    )
end

function M.aGotoGuardNarrowsLikeABreak()
    -- Leaving the branch through `goto` is leaving it, the same as `break`.
    assertClean(
        table.concat(
            {
                "local items: {string?} = {'a', nil, 'c'}",
                "for i = 1, 3 do",
                "    local v = items[i]",
                "    if v == nil then",
                "        goto continue",
                "    end",
                "    print(#v)",
                "    ::continue::",
                "end",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "local items: {string?} = {'a', nil, 'c'}",
                "for i = 1, 3 do",
                "    local v = items[i]",
                "    if v == nil then",
                "        break",
                "    end",
                "    print(#v)",
                "end",
            },
            "\n"
        )
    )
end

function M.aForwardGotoCarriesItsFactsToTheLabel()
    -- What the jump knew reaches the label: x is still nil on the jump's path.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function run(flag: boolean): integer",
                    "    local x: string? = nil",
                    "    if flag then",
                    "        goto skip",
                    "    end",
                    "    x = 'a'",
                    "    ::skip::",
                    "    return #x",
                    "end",
                    "return run",
                },
                "\n"
            )
        ),
        "NUPP2003:8"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function run(flag: boolean): integer",
                    "    local x: string? = 'start'",
                    "    do",
                    "        if flag then",
                    "            x = nil",
                    "            goto skip",
                    "        end",
                    "    end",
                    "    x = 'b'",
                    "    ::skip::",
                    "    return #x",
                    "end",
                    "return run",
                },
                "\n"
            )
        ),
        "NUPP2003:11"
    )
    -- Every path agreeing is still a fact.
    assertClean(
        table.concat(
            {
                "local function run(flag: boolean): integer",
                "    local x: string? = nil",
                "    if flag then",
                "        x = 'a'",
                "        goto skip",
                "    end",
                "    x = 'b'",
                "    ::skip::",
                "    return #x",
                "end",
                "return run",
            },
            "\n"
        )
    )
end

function M.anEarlyExitCarriesWhatItLeftUnassigned()
    local strict = {strict = true}
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function run(flag: boolean): integer",
                    "    local p: integer",
                    "    if flag then",
                    "        goto skip",
                    "    end",
                    "    p = 1",
                    "    ::skip::",
                    "    return p + 1",
                    "end",
                    "return run",
                },
                "\n"
            ),
            strict
        ),
        "NUPP2207:8"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function run(flag: boolean): integer",
                    "    local p: integer",
                    "    repeat",
                    "        if flag then",
                    "            break",
                    "        end",
                    "        p = 1",
                    "    until true",
                    "    return p + 1",
                    "end",
                    "return run",
                },
                "\n"
            ),
            strict
        ),
        "NUPP2207:9"
    )
    assertClean(
        table.concat(
            {
                "local function run(flag: boolean): integer",
                "    local p: integer",
                "    repeat",
                "        if flag then",
                "            p = 2",
                "            break",
                "        end",
                "        p = 1",
                "    until true",
                "    return p + 1",
                "end",
                "return run",
            },
            "\n"
        ),
        strict
    )
end

function M.aTypedLocalHoldsNilUntilEveryPathAssignsIt()
    local strict = {strict = true}
    -- Declared without a value, a strict local is read as nil until it is assigned.
    testAssert.equal(diagsOf("local x: string\nprint(x:upper())", strict), "NUPP2207:2")
    testAssert.equal(diagsOf("local x: string\nif #arg > 5 then\n    x = 'set'\nend\nprint(x:upper())", strict), "NUPP2207:5")
    testAssert.equal(diagsOf("local x: string\nwhile #arg > 5 do\n    x = 'set'\nend\nprint(#x)", strict), "NUPP2207:5")
    testAssert.equal(diagsOf("local x: string\nfor _ = 1, #arg do\n    x = 'set'\nend\nprint(#x)", strict), "NUPP2207:5")
    -- Every path assigning it is what makes it hold a value.
    assertClean("local x: string\nif #arg > 5 then\n    x = 'a'\nelse\n    x = 'b'\nend\nprint(#x)", strict)
    assertClean("local x: string\nif #arg > 5 then\n    x = 'a'\nelse\n    return\nend\nprint(#x)", strict)
    assertClean("local x: string\nrepeat\n    x = 'a'\nuntil true\nprint(#x)", strict)
    -- An optional annotation admits the nil the declaration leaves there.
    assertClean("local x: string?\nprint(x)", strict)
    -- A closure may run after the assignment, so its read is not known to come first.
    assertClean("local x: string\nlocal function f(): string\n    return x\nend\nx = 'a'\nprint(f())", strict)
    -- Gradual code keeps `local x: T` as the declaration it always was.
    assertClean("local x: string\nprint(#x)")
end

function M.nilChecksNarrowThroughFieldPaths()
    assertClean(
        CFG .. table.concat(
            {
                "",
                "local c: Cfg = new Cfg(name = 'test')",
                "if c.port ~= nil then",
                "    local p: number = c.port",
                "end",
            },
            "\n"
        )
    )
    -- and outside the guard the field is still optional
    testAssert.equal(diagsOf(CFG .. "\nlocal c: Cfg = new Cfg(name = 'test')\nlocal p: number = c.port"), "NUPP2001:6")
end

function M.narrowingSurvivesTheElseBranch()
    assertClean(
        CFG .. table.concat(
            {
                "",
                "local c: Cfg = new Cfg(name = 'test')",
                "if c.port == nil then",
                "else",
                "    local p: number = c.port",
                "end",
            },
            "\n"
        )
    )
end

function M.assignmentForgetsWhatWasNarrowed()
    -- writing through the path invalidates the refinement
    testAssert.equal(
        diagsOf(
            CFG .. table.concat(
                {
                    "",
                    "local c: Cfg = new Cfg(name = 'test')",
                    "if c.port ~= nil then",
                    "    c.port = nil",
                    "    local p: number = c.port",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:8"
    )
end

local SHAPE = "local s: {tag: 'circle', r: number} | {tag: 'rect', w: number}"

function M.literalTypesAreWritableInAnnotations()
    assertClean("local t: 'circle' = 'circle'")
    testAssert.equal(diagsOf("local t: 'circle' = 'square'"), "NUPP2001:1")
end

function M.discriminantNarrowsAUnionOfShapes()
    assertClean(
        SHAPE .. table.concat(
            {"", "if s.tag == 'circle' then", "    local r: number = s.r", "else", "    local w: number = s.w", "end",},
            "\n"
        )
    )
    -- the member field is not reachable without narrowing
    testAssert.equal(diagsOf(SHAPE .. "\nlocal r: number = s.r"), "NUPP2004:2")
end

function M.discriminantInvertsForInequality()
    assertClean(
        SHAPE .. table.concat(
            {"", "if s.tag ~= 'circle' then", "    local w: number = s.w", "else", "    local r: number = s.r", "end",},
            "\n"
        )
    )
end

function M.fieldsCommonToEveryMemberAreReadable()
    -- the discriminant itself is reachable before any narrowing
    assertClean(SHAPE .. "\nlocal t: string = s.tag")
end

function M.numberLiteralsCarryTheirValue()
    assertClean("local n: number = 1")
    assertClean("local i: integer = 1")
    -- an inferred binding still holds a number, not that one number
    assertClean("local n = 1\nn = 2")
    -- arithmetic is unaffected by literal types
    assertClean("local i: integer = 1 + 2")
    assertClean("local f: number = 1 / 2")
end

function M.strictModeRequiresTypedExports()
    local src = table.concat(
        {
            "local function typed(n: number): number",
            "    return n",
            "end",
            "local function loose(n)",
            "    return n",
            "end",
            "return {typed = typed, loose = loose}",
        },
        "\n"
    )
    assertClean(src)
    testAssert.equal(diagsOf(src, {strict = true}), "NUPP2106:7")
    -- a fully annotated boundary passes
    assertClean(
        table.concat(
            {"local function typed(n: number): number", "    return n", "end", "return {typed = typed}",},
            "\n"
        ),
        {strict = true}
    )
end

-- Each conjunct of an `and` is only reached when the ones before it held, so
-- it is checked knowing that. The condition ending in a bare call is the case
-- that used to get this wrong: inferring the chain narrowed, but analyzing
-- what it proved did not, and the call's arguments were checked as though
-- nothing had been tested.
function M.narrowingReachesLaterConjuncts()
    local decl = table.concat(
        {
            "local record P",
            "    tag: 'p'",
            "end",
            "local record F",
            "    tag: 'f'",
            "    extra: U?",
            "end",
            "local type U = P | F",
            "local function pair(v: U, w: U): boolean",
            "    return v == w",
            "end",
        },
        "\n"
    )
    assertClean(
        decl .. "\n" .. table.concat(
            {
                "local function f(a: U, b: U): boolean",
                "    if a.tag == 'f' and b.tag == 'f' then",
                "        if a.extra and b.extra and not pair(b.extra, a.extra) then",
                "            return false",
                "        end",
                "    end",
                "    return true",
                "end",
            },
            "\n"
        )
    )
    -- the same through plain locals, and through `or` on its falsy side
    assertClean(
        table.concat(
            {
                "local function use(x: number, y: number): number",
                "    return x + y",
                "end",
                "local function f(a: number?, b: number?): number",
                "    if a and b and use(a, b) > 0 then return 1 end",
                "    if not a or not b or use(a, b) > 0 then return 2 end",
                "    return 0",
                "end",
            },
            "\n"
        )
    )
end

-- A helper that always throws leaves the branch it stands in, so a guard
-- clause keeps narrowing when it is spelled as a call rather than inline.
function M.noreturnHelperGuardsLikeError()
    assertClean(
        table.concat(
            {
                "local function fail(msg: string)",
                "    error(msg)",
                "end",
                "local function use(x: string?)",
                "    if not x then fail('no x') end",
                "    print(#x)",
                "end",
                "return {use = use}",
            },
            "\n"
        )
    )
    -- every arm of a complete chain raising counts too
    assertClean(
        table.concat(
            {
                "local function fail(msg: string)",
                "    if msg == '' then",
                "        error('empty')",
                "    else",
                "        error(msg)",
                "    end",
                "end",
                "local function use(x: string?)",
                "    if not x then fail('no x') end",
                "    print(#x)",
                "end",
                "return {use = use}",
            },
            "\n"
        )
    )
end

-- A function that can return is not noreturn, however it ends.
function M.noreturnIsNotInferredWhenAPathReturns()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function maybe(msg: string): integer",
                    "    if msg == '' then return 0 end",
                    "    error(msg)",
                    "end",
                    "local function use(x: string?)",
                    "    if not x then maybe('no x') end",
                    "    print(#x)",
                    "end",
                    "return {use = use}",
                },
                "\n"
            )
        ),
        "NUPP2003:7"
    )
end

-- A declared `never` return says what the checker cannot see, and is refused
-- where it plainly contradicts the body.
function M.declaredNeverReturn()
    assertClean(
        table.concat(
            {
                "local function bail(code: integer): never",
                "    print(code)",
                "    error('bail')",
                "end",
                "local function use(x: string?)",
                "    if x == nil then bail(1) end",
                "    print(#x)",
                "end",
                "return {use = use}",
            },
            "\n"
        )
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function claims(x: integer): never",
                    "    if x > 0 then return x end",
                    "    error('no')",
                    "end",
                    "return {claims = claims}",
                },
                "\n"
            )
        ),
        "NUPP2002:2"
    )
end

-- The prelude declares `error` itself as returning `never`, not through an
-- annotation. `never` fits any declared return, which is what lets `return
-- error(...)` satisfy a typed result in one line -- previously a type error,
-- since a call to the old zero-result signature typed as `nil`.
function M.errorItselfReturnsNever()
    assertClean(
        table.concat(
            {
                "local function pick(s: string?): string",
                "    if s then return s end",
                "    return error('missing')",
                "end",
                "return {pick = pick}",
            },
            "\n"
        )
    )
end

-- `{}` is `table`, which is gradual toward every table structure. Beside one in a
-- union it therefore says nothing that member does not, and a union carrying it is
-- one no field can be read from. Defaulting a declared binding -- the `x = x or {}`
-- every optional parameter is written with -- is what reaches this.
function M.defaultingADeclaredTableKeepsItsStructure()
    local OPTS = "local type Opts = {output: string?, title: string?}\n"
    -- assigned back to the parameter, alone and among several targets
    assertClean(
        OPTS .. table.concat(
            {
                "local function run(opts: Opts?): string?",
                "    opts = opts or {}",
                "    return opts.output",
                "end",
                "return {run = run}",
            },
            "\n"
        )
    )
    assertClean(
        OPTS .. table.concat(
            {
                "local function run(root: string?, opts: Opts?): string?",
                "    root, opts = root or '.', opts or {}",
                "    return opts.output or root",
                "end",
                "return {run = run}",
            },
            "\n"
        )
    )
    -- and written as the branch that defaults it, where the join is what unions
    assertClean(
        OPTS .. table.concat(
            {
                "local function run(opts: Opts?): string?",
                "    if not opts then",
                "        opts = {}",
                "    end",
                "    return opts.output",
                "end",
                "return {run = run}",
            },
            "\n"
        )
    )
    -- an array reached the same way, and an element read off it
    assertClean(
        table.concat(
            {
                "local function first(items: {string}?): string?",
                "    items = items or {}",
                "    return items[1]",
                "end",
                "return {first = first}",
            },
            "\n"
        )
    )
    -- what the collapse must not do: a literal with fields still narrows a
    -- variable declared as a plain table
    assertClean(table.concat({"local t: table = {}", "t = {a = 1}", "local n: integer = t.a",}, "\n"))
end

local BOX = table.concat({"local record Box", "    f: string?", "end",}, "\n")

function M.aLoopBodyWriteIsForgottenAtTheLoopEntry()
    -- The body runs again after its own write, so the narrowing from before the
    -- loop does not reach its first statement. while, numeric for, and repeat.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local n = 0",
                    "if x ~= nil then",
                    "    while n < 2 do",
                    "        local s: string = x",
                    "        x = nil",
                    "        n = n + 1",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "if x ~= nil then",
                    "    for i = 1, 2 do",
                    "        local s: string = x",
                    "        x = nil",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:4"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local n = 0",
                    "if x ~= nil then",
                    "    repeat",
                    "        local s: string = x",
                    "        x = nil",
                    "        n = n + 1",
                    "    until n >= 2",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
    -- A body that writes some other field keeps the fact.
    assertClean(
        BOX .. table.concat(
            {
                "",
                "local record Pair",
                "    a: string?",
                "    b: string?",
                "end",
                "local p: Pair = new Pair(a = 'x')",
                "if p.a ~= nil then",
                "    for i = 1, 2 do",
                "        local s: string = p.a",
                "        p.b = s",
                "    end",
                "end",
            },
            "\n"
        )
    )
end

function M.aBackwardGotoRepeatsTheWritesAfterItsLabel()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local n = 0",
                    "if x ~= nil then",
                    "    ::again::",
                    "    local s: string = x",
                    "    x = nil",
                    "    n = n + 1",
                    "    if n < 2 then",
                    "        goto again",
                    "    end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
end

function M.aClosureDoesNotKeepANarrowingOfALocalAssignedLater()
    -- The literal may run after the assignment, so inside it the local is what
    -- it was declared as.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local function outer()",
                    "    local cbs: {function()} = {}",
                    "    local x: string? = 'hi'",
                    "    if x ~= nil then",
                    "        cbs[#cbs + 1] = function()",
                    "            local s: string = x",
                    "        end",
                    "    end",
                    "    x = nil",
                    "    cbs[1]()",
                    "end",
                    "return outer",
                },
                "\n"
            )
        ),
        "NUPP2001:6"
    )
    -- One nothing assigns keeps its narrowing.
    assertClean(
        table.concat(
            {
                "local function outer()",
                "    local cbs: {function()} = {}",
                "    local x: string? = 'hi'",
                "    if x ~= nil then",
                "        cbs[#cbs + 1] = function()",
                "            local s: string = x",
                "        end",
                "    end",
                "    cbs[1]()",
                "end",
                "return outer",
            },
            "\n"
        )
    )
end

function M.aFunctionHandedToACallIsTakenToRun()
    -- Through a parameter typed as a function, through pcall, and as an
    -- immediately called literal inside the condition itself.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local function run(cb: function())",
                    "    cb()",
                    "end",
                    "if x ~= nil then",
                    "    run(function() x = nil end)",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:7"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "if x ~= nil then",
                    "    pcall(function() x = nil end)",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:4"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "if x ~= nil and (function() x = nil; return true end)() then",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:3"
    )
end

function M.aCalleeWritesReachThroughTheFunctionsItCalls()
    -- Transitive, recursive, and declared after the call site.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local function g()",
                    "    x = nil",
                    "end",
                    "local function f()",
                    "    g()",
                    "end",
                    "if x ~= nil then",
                    "    f()",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:10"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local function f(depth: integer)",
                    "    if depth >= 1 then",
                    "        x = nil",
                    "        return",
                    "    end",
                    "    if x ~= nil then",
                    "        f(depth + 1)",
                    "        local s: string = x",
                    "    end",
                    "end",
                    "f(0)",
                },
                "\n"
            )
        ),
        "NUPP2001:9"
    )
    testAssert.equal(
        diagsOf(
            BOX .. table.concat(
                {
                    "",
                    "local M = {}",
                    "local x: Box = new Box(f = 'hi')",
                    "function M.a(): nil",
                    "    if x.f ~= nil then",
                    "        M.b()",
                    "        local s: string = x.f",
                    "    end",
                    "end",
                    "function M.b(): nil",
                    "    x.f = nil",
                    "end",
                    "return M",
                },
                "\n"
            )
        ),
        "NUPP2001:9"
    )
end

function M.aLongCalleeChainReachesItsFinalWrite()
    local lines = {"local x: string? = 'hi'"}
    local count = 70
    for index = 1, count do
        lines[#lines + 1] = "local function f" .. index .. "()"
        if index == count then
            lines[#lines + 1] = "    x = nil"
        else
            lines[#lines + 1] = "    f" .. (index + 1) .. "()"
        end
        lines[#lines + 1] = "end"
    end
    local result = parser.parse(table.concat(lines, "\n"), "test.g.nupp")
    testAssert.equal(#result.errors, 0, "long call chain parses")
    local summaries = mutation.prescan(result.root)
    testAssert.equal(summaries.byKey.f1.captured.x, true, "the first callee reaches the final write")
end

function M.safeCallsCarryEffectsAndInvalidateShape()
    local result = parser.parse(
        [[
local function mutate(xs: {integer}): nil
    xs[1] = 9
end

local function wrapper(xs: {integer}): nil
    mutate?.(xs)
end

return wrapper
]],
        "test.g.nupp"
    )
    testAssert.equal(#result.errors, 0, "safe-call fixture parses")
    local diags = check.check(result, "test.g.nupp", env, {})
    testAssert.equal(#diags, 0, "safe-call fixture checks")
    local queries = analysis.queries(result.analysis)
    local wrapper = result.root.blocks[1].stats[2].effectInfo
    assert(queries and wrapper, "the wrapper was analyzed")
    testAssert.equal(wrapper.summary.writes["xs[*]"], true, "a known safe call carries its callee's writes")

    local block = wrapper.body.body
    local body = queries.body(block)
    local xs = wrapper.body.params[1].name
    local ok, reason = body.shapeStable(block, body.aliasOf(xs))
    testAssert.equal(ok, false, "a safe call that mutates the array changes its shape")
    testAssert.equal(reason, "a call may change the array's shape", "and says why")
end

function M.aFunctionValueReachedThroughAFieldOrReassignedIsRead()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local ops: {clear: function()} = {clear = function() x = nil end}",
                    "if x ~= nil then",
                    "    ops.clear()",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: string? = 'hi'",
                    "local g: function() = function() end",
                    "g = function() x = nil end",
                    "if x ~= nil then",
                    "    g()",
                    "    local s: string = x",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:6"
    )
end

function M.aMethodThroughAnInterfaceMayWriteTheReceiver()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local interface Clearer",
                    "    clear: function(self)",
                    "end",
                    "local record Box is Clearer",
                    "    f: string?",
                    "end",
                    "function Box:clear()",
                    "    self.f = nil",
                    "end",
                    "local box: Box = new Box(f = 'hi')",
                    "local i: Clearer = box",
                    "if box.f ~= nil then",
                    "    i:clear()",
                    "    local s: string = box.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:14"
    )
end

function M.aNamedArgumentFindsItsParameter()
    testAssert.equal(
        diagsOf(
            BOX .. table.concat(
                {
                    "",
                    "local function clear(b: Box)",
                    "    b.f = nil",
                    "end",
                    "local x: Box = new Box(f = 'hi')",
                    "if x.f ~= nil then",
                    "    clear(b = x)",
                    "    local s: string = x.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:10"
    )
end

function M.aCalleeWriteThroughACopyOfItsParameterReachesTheCaller()
    -- `local me = self` inside the method; a copy of the argument at the call.
    testAssert.equal(
        diagsOf(
            BOX .. table.concat(
                {
                    "",
                    "function Box:clear()",
                    "    local me = self",
                    "    me.f = nil",
                    "end",
                    "local x: Box = new Box(f = 'hi')",
                    "if x.f ~= nil then",
                    "    x:clear()",
                    "    local s: string = x.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:11"
    )
    testAssert.equal(
        diagsOf(
            BOX .. table.concat(
                {
                    "",
                    "local function clear(b: Box)",
                    "    b.f = nil",
                    "end",
                    "local x: Box = new Box(f = 'hi')",
                    "local y = x",
                    "if x.f ~= nil then",
                    "    clear(y)",
                    "    local s: string = x.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:11"
    )
    -- A callee that writes some other field keeps the fact and the copied
    -- discriminant that speaks for the value.
    assertClean(
        table.concat(
            {
                "local record Circle",
                "    kind: 'circle'",
                "    radius: number",
                "    seen: boolean?",
                "end",
                "local record Square",
                "    kind: 'square'",
                "    side: number",
                "    seen: boolean?",
                "end",
                "local function mark(s: Circle | Square)",
                "    s.seen = true",
                "end",
                "local s: Circle | Square = new Circle(kind = 'circle', radius = 1)",
                "local kind = s.kind",
                "mark(s)",
                "if kind == 'circle' then",
                "    local r: number = s.radius",
                "end",
            },
            "\n"
        )
    )
end

function M.copiesAreFollowedThroughAnnotationsAndCopiesOfCopies()
    -- An annotated copy, a copy of a copy, and a fact recorded on the copy while
    -- the write goes through the original.
    testAssert.equal(
        diagsOf(
            BOX .. table.concat(
                {
                    "",
                    "local x: Box = new Box(f = 'hi')",
                    "local y: Box = x",
                    "if x.f ~= nil then",
                    "    y.f = nil",
                    "    local s: string = x.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:8"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: {f: string?} = {f = 'hi'}",
                    "local y = x",
                    "local z = y",
                    "if x.f ~= nil then",
                    "    z.f = nil",
                    "    local s: string = x.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:6"
    )
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: {f: string?} = {f = 'hi'}",
                    "local y = x",
                    "if y.f ~= nil then",
                    "    x.f = nil",
                    "    local s: string = y.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:5"
    )
end

function M.aComputedIndexWriteClearsTheDottedFact()
    -- A literal key names the field; a computed key may be any of them; an
    -- integer key is never a field.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local x: {[string]: string?} = {f = 'hi'}",
                    "if x.f ~= nil then",
                    "    x['f'] = nil",
                    "    local s: string = x.f",
                    "end",
                    "local y: {[string]: string?} = {f = 'hi'}",
                    "local k = 'f'",
                    "if y.f ~= nil then",
                    "    y[k] = nil",
                    "    local s: string = y.f",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:4 NUPP2001:10"
    )
    assertClean(
        table.concat(
            {
                "local record Args",
                "    exprs: {string}?",
                "end",
                "local n: Args = new Args()",
                "n.exprs = {}",
                "for i = 1, 3 do",
                "    n.exprs[#n.exprs + 1] = 'x'",
                "end",
                "local first: {string} = n.exprs",
            },
            "\n"
        )
    )
end

function M.safeNavigationProvesThePathItWalked()
    assertClean(
        table.concat(
            {
                "local record Inner",
                "    f: string?",
                "end",
                "local record Outer",
                "    inner: Inner?",
                "end",
                "local o: Outer? = new Outer(inner = new Inner(f = 'hi'))",
                "if o?.inner?.f ~= nil then",
                "    local s: string = o.inner.f",
                "end",
                "if o?.inner ~= nil then",
                "    local i: Inner = o.inner",
                "end",
            },
            "\n"
        )
    )
    -- A nil result says nothing about which step was nil.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local record Inner",
                    "    f: string?",
                    "end",
                    "local record Outer",
                    "    inner: Inner?",
                    "end",
                    "local o: Outer? = new Outer(inner = new Inner(f = 'hi'))",
                    "if o?.inner == nil then",
                    "    print('none')",
                    "else",
                    "    local i: Inner = o.inner",
                    "end",
                    "if o?.inner == nil then",
                    "    local out: Outer = o",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2001:14"
    )
end

-- `if NAME = EXPR then` binds the value less nil for its arm: `false` stays,
-- a union keeps its other members, and the name is gone in the later arms and
-- after the statement, where it reads whatever it meant outside.
function M.ifBindingsHoldTheNonNilValueForTheirArmOnly()
    assertClean(
        table.concat(
            {
                "local record Cfg",
                "    port: integer?",
                "    flag: boolean | nil",
                "    mixed: string | integer | nil",
                "end",
                "local function read(cfg: Cfg, other: Cfg?): integer",
                "    local port = 'outer'",
                "    if port = cfg.port then",
                "        local p: integer = port",
                "        return p",
                "    elseif flag = cfg.flag then",
                "        local f: boolean = flag",
                "        local text: string = port",
                "        print(f, text)",
                "    elseif seen = other then",
                "        local c: Cfg = seen",
                "        print(c)",
                "    end",
                "    local outer: string = port",
                "    if v = cfg.mixed then",
                "        local m: string | integer = v",
                "        print(m)",
                "    end",
                "    return #outer",
                "end",
                "return read",
            },
            "\n"
        )
    )
    -- The bound expression must admit nil, and the arm binds no fact about
    -- anything else: a plain `cfg.port` is not narrowed by the binding.
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local record Cfg",
                    "    port: integer?",
                    "end",
                    "local function read(cfg: Cfg, count: integer): integer",
                    "    if n = count then",
                    "        return n",
                    "    end",
                    "    if p = cfg.port then",
                    "        local direct: integer = cfg.port",
                    "        return direct + p",
                    "    end",
                    "    return 0",
                    "end",
                    "return read",
                },
                "\n"
            )
        ),
        "NUPP2001:5 NUPP2001:9"
    )
end

-- A method is reached through the value itself, so a union offers the method its
-- alternatives share as one method: whichever alternative the value turns out to be
-- is the one whose body runs, on itself. The receiver is the whole union for that
-- reason, the result is what any of them may return, and every other parameter has to
-- suit whichever one is selected.
function M.aUnionOffersTheMethodItsAlternativesShare()
    assertClean(
        table.concat(
            {
                "local record Present",
                "    value: integer",
                "    function describe(self): string",
                "        return tostring(self.value)",
                "    end",
                "end",
                "local record Absent",
                "    reason: string",
                "    function describe(self): string",
                "        return self.reason",
                "    end",
                "end",
                "local function report(either: Present | Absent): string",
                "    return either:describe()",
                "end",
                "return report",
            },
            "\n"
        )
    )
end

function M.aUnionMethodTakesOnlyWhatEveryAlternativeAccepts()
    testAssert.equal(
        diagsOf(
            table.concat(
                {
                    "local record Counted",
                    "    function at(self, index: integer): integer",
                    "        return index",
                    "    end",
                    "end",
                    "local record Named",
                    "    function at(self, index: string): integer",
                    "        return #index",
                    "    end",
                    "end",
                    "local function read(either: Counted | Named): integer",
                    "    return either:at(1)",
                    "end",
                    "return read",
                },
                "\n"
            )
        ),
        "NUPP2006:12"
    )
end

-- A call through a local alias of a function that clears a captured upvalue ends
-- the narrowing the alias could not name: the call records the entries its callee
-- writes, and those are what invalidate the fact (the `callMutatedEntries` path).
function M.aCallThroughAnAliasEndsTheCalleesCapturedFact()
    local prelude = table.concat({
        "local function get(): string? return 'abc' end",
        "local x: string? = get()",
        "local function f(): nil x = nil end",
    }, "\n")
    testAssert.equal(
        diagsOf(table.concat({prelude, "local g = f", "if x ~= nil then", "    g()", "    print(#x)", "end",}, "\n")),
        "NUPP2003:7"
    )
    testAssert.equal(
        diagsOf(table.concat({
            prelude,
            "if x ~= nil then",
            "    do",
            "        local x = 2",
            "        local h = f",
            "        h()",
            "        print(x)",
            "    end",
            "    print(#x)",
            "end",
        }, "\n")),
        "NUPP2003:11"
    )
    assertClean(table.concat({prelude, "local g = f", "if x ~= nil then", "    print(#x)", "    g()", "end",}, "\n"))
end

return M
