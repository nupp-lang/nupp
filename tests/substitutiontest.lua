-- Substitution has two jobs. Rebinding `self` over a member must preserve every
-- other binder; specializing a call must materialize the ones inference never
-- reached, as `any`. One operation did both, and the preserving callers silently
-- got the materializing behaviour: a generic method's own binder became `any`,
-- so the result fit wherever it was put and nothing reported.
--
-- These characterize both directions at every path that substitutes a partial map.
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

local function diagnostics(source)
    env.loaded = {}
    local parsed = parser.parse(source, "test.g.nupp")
    assertEq(#parsed.errors, 0, "syntax: " .. (parsed.errors[1] and parsed.errors[1].msg or ""))
    return check.check(parsed, "test.g.nupp", env)
end

local function codes(source)
    local out = {}
    for j, d in ipairs(diagnostics(source)) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local function clean(source)
    assertEq(codes(source), "", "expected clean check for:\n" .. source)
end

local function reports(source, want)
    assertEq(codes(source), want, "for:\n" .. source)
end

local M = {}

-- 1. Direct specialization: the method is declared where it is called from.
function M.aGenericMethodPreservesItsOwnBinder()
    local body = table.concat(
        {
            "local record Box",
            "   function idOf<C>(self, value: C): C",
            "      return value",
            "   end",
            "end",
            "local box = new Box()",
        },
        "\n"
    ) .. "\n"
    reports(body .. "local wrong: string = box:idOf(42)\nreturn wrong\n", "NUPP2001")
    clean(body .. "local kept: integer = box:idOf(42)\nreturn kept\n")
end

-- 2. Inherited default: declaration inheritance substitutes a self-only map too,
-- so it has the same erasure to answer for.
function M.aGenericDefaultMethodPreservesItsOwnBinder()
    local body = table.concat(
        {
            "local interface Source",
            "   function idOf<C>(self, value: C): C",
            "      return value",
            "   end",
            "end",
            "local record Box is Source",
            "end",
            "local box = new Box()",
        },
        "\n"
    ) .. "\n"
    reports(body .. "local wrong: string = box:idOf(42)\nreturn wrong\n", "NUPP2001")
    clean(body .. "local kept: integer = box:idOf(42)\nreturn kept\n")
end

-- 3. Both at once: an instantiated generic record whose method mentions the
-- declaration's parameter and its own.
function M.anInstantiatedRecordKeepsBothBinders()
    local body = table.concat(
        {
            "local record Cell<T>",
            "   held: T",
            "   function get(self): T",
            "      return self.held",
            "   end",
            "   function swap<U>(self, other: U): U",
            "      return other",
            "   end",
            "end",
            "local cell: Cell<string> = nil as any",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local held: string = cell:get()\nreturn held\n")
    reports(body .. "local wrong: integer = cell:get()\nreturn wrong\n", "NUPP2001")
    clean(body .. "local swapped: integer = cell:swap(1)\nreturn swapped\n")
    reports(body .. "local wrong: string = cell:swap(1)\nreturn wrong\n", "NUPP2001")
end

-- 4. The job the self-only map exists for: `self` follows the receiver.
function M.anInheritedSelfFollowsTheReceiver()
    local body = table.concat(
        {
            "local interface Chainable",
            "   function chain(self): self",
            "      return self",
            "   end",
            "end",
            "local record Node is Chainable",
            "   value: integer",
            "end",
            "local node = new Node(value = 1)",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local same: Node = node:chain()\nreturn same\n")
    reports(body .. "local wrong: string = node:chain()\nreturn wrong\n", "NUPP2001")
end

-- 5. The other direction, which the split must not break: a destination answers a
-- result-only binder without leaking that binder or materializing it as `any`.
function M.aDestinationAnswersAResultOnlyBinder()
    local body = table.concat({"local function pick<T>(): T?", "   return nil", "end",}, "\n") .. "\n"
    clean(body .. "local anything: string? = pick()\nreturn anything\n")
    clean(body .. "local other: integer? = pick()\nreturn other\n")
end

-- A binder inference never reached takes the default its declaration wrote at a
-- construction and at a call alike. A default naming an earlier binder follows what
-- that one became.
function M.anUninferredBinderMaterializesAsItsDefault()
    local body = table.concat(
        {
            "local record Opt<T = string>",
            "   value: T?",
            "end",
            "local record Pair<K, V = K>",
            "   key: K",
            "   value: V?",
            "end",
            "local function pick<T = string>(): T?",
            "   return nil",
            "end",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local o = new Opt()\nlocal s: string? = o.value\nreturn s\n")
    reports(body .. "local o = new Opt()\nlocal n: integer? = o.value\nreturn n\n", "NUPP2001")
    clean(body .. "local p = new Pair(key = 1)\nlocal n: integer? = p.value\nreturn n\n")
    reports(body .. "local p = new Pair(key = 1)\nlocal s: string? = p.value\nreturn s\n", "NUPP2001")
    clean(body .. "local s: string? = pick()\nreturn s\n")
    reports(body .. "local n: integer? = pick()\nreturn n\n", "NUPP2001")
    -- The default is what an empty construction builds; another instantiation is
    -- written as one.
    reports(body .. "local o: Opt<integer> = new Opt()\nreturn o\n", "NUPP2001")
    clean(body .. "local o = new Opt() as Opt<integer>\nlocal n: integer? = o.value\nreturn n\n")
end

-- A type-level operation over an instantiated nominal -- `Box<T>.["value"]`, `keyof
-- Box<T>` -- carries no binder mark in its id, because the nominal's id carries none.
-- Substitution has to walk it to find `T`, or the call site keeps the blocked term.
function M.anOperationOverAnInstantiatedNominalIsSubstitutedAtTheCall()
    clean(
        table.concat(
            {
                "local m = {}",
                "record m.Box<T>",
                "   value: T",
                "end",
                'function m.get<T>(b: m.Box<T>): m.Box<T>.["value"]',
                "   return b.value as any",
                "end",
                "function m.key<T>(b: m.Box<T>): keyof m.Box<T>",
                '   return "value" as any',
                "end",
                "local one: integer = 1",
                "local b = new m.Box(value = one)",
                "local n: integer = m.get(b)",
                'local k: "value" = m.key(b)',
                "print(n, k)",
            },
            "\n"
        )
    )
end

-- A bound says what a T can do, not what may stand in for one. Answering a
-- `T is Named` result with some record that is Named hands whoever passed a
-- different record the wrong type, so only the binder itself fits a result of T,
-- an argument of T, or a field of T, however the bound is satisfied.
function M.aBoundedBinderAcceptsOnlyItself()
    local body = table.concat(
        {
            "local interface Named",
            "   name: string",
            "end",
            "local record P is Named",
            "   name: string",
            "end",
            "local record Cell<T is Named>",
            "   item: T",
            "end",
        },
        "\n"
    ) .. "\n"
    reports(
        body .. table.concat(
            {"local function same<T is Named>(x: T): T", '   return new P(name = "p")', "end", "return same",},
            "\n"
        ),
        "NUPP2002"
    )
    reports(
        body .. table.concat(
            {
                "local function store<T is Named>(cell: Cell<T>): nil",
                '   cell.item = new P(name = "p")',
                "end",
                "return store",
            },
            "\n"
        ),
        "NUPP2001"
    )
    reports(
        body .. table.concat(
            {
                "local function keep<T is Named>(x: T): nil",
                "   local held: T = x",
                '   held = new P(name = "p")',
                "end",
                "return keep",
            },
            "\n"
        ),
        "NUPP2001"
    )
    reports(
        body .. table.concat(
            {
                "local function fill<T is Named>(cell: Cell<T>, x: P): nil",
                "   local function put(item: T) cell.item = item end",
                "   put(x)",
                "end",
                "return fill",
            },
            "\n"
        ),
        "NUPP2006"
    )
    clean(
        body .. table.concat(
            {
                "local function same<T is Named>(x: T): T",
                "   local held: T = x",
                "   return held",
                "end",
                "local function other<T is Named, U is T>(x: T, y: U): T",
                "   local function put(item: T) print(item.name) end",
                "   put(y)",
                "   return y",
                "end",
                "local function stop<T is Named>(x: T): T",
                '   error("never")',
                "end",
                "return same, other, stop",
            },
            "\n"
        )
    )
end

-- Passing a T where a concrete parameter is wanted is the same mistake in the
-- other direction: a bound satisfies the parameter, an absent bound does not.
function M.aBinderReachesOnlyWhatItsBoundAllows()
    reports(
        table.concat(
            {
                "local function label(x: string): string return x end",
                "local function show<T>(x: T): string",
                "   return label(x)",
                "end",
                "return show",
            },
            "\n"
        ),
        "NUPP2006"
    )
    clean(
        table.concat(
            {
                "local function label(x: string): string return x end",
                "local function show<T is string>(x: T): string",
                "   return label(x)",
                "end",
                "local function optional<T>(x: T): T",
                "   if x ~= nil then print(x) end",
                "   return x",
                "end",
                "return show, optional",
            },
            "\n"
        )
    )
end

-- A literal written where a callable is expected has its results inferred from
-- what it returns. A result the slot left open -- a generic's result-only binder
-- -- is bound by the body rather than materialized as `any`, and a result the slot
-- fixed is checked against what the body produces.
function M.anExpectedLiteralInfersItsResults()
    local body = table.concat(
        {
            "local function map<A, B>(xs: {A}, f: function(A): B): {B}",
            "   local out: {B} = {}",
            "   for i, x in ipairs(xs) do out[i] = f(x) end",
            "   return out",
            "end",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local strings: {string} = map({1, 2}, function(x) return tostring(x) end)\nreturn strings\n")
    reports(
        body .. "local wrong: {integer} = map({1, 2}, function(x) return tostring(x) end)\nreturn wrong\n",
        "NUPP2001"
    )
    reports(
        body .. "local wrong: {integer} = map({1, 2}, function(x): string return tostring(x) end)\nreturn wrong\n",
        "NUPP2001"
    )
    -- Both branches count, and a position one return leaves out is nil there.
    clean(
        body .. table.concat(
            {
                "local mixed: {integer | string | nil} = map({1, 2}, function(x)",
                "   if x > 1 then return x end",
                '   if x < 0 then return end',
                '   return "small"',
                "end)",
                "return mixed",
            },
            "\n"
        )
    )
    -- Nothing written where a callable is expected keeps its documented `any`.
    clean(
        table.concat(
            {
                "local plain = function(x: integer) return tostring(x) end",
                "local loose: {integer} = map({1, 2}, plain)",
                "return loose",
            },
            "\n"
        )
    )
    -- A literal whose results the slot fixed is held to them.
    reports(
        table.concat(
            {
                "local interface Named",
                "   name: string",
                "end",
                "local record P is Named",
                "   name: string",
                "end",
                "local record Q is Named",
                "   name: string",
                "   extra: integer",
                "end",
                'local build: function(): Q = function() return new P(name = "p") end',
                "return build",
            },
            "\n"
        ),
        "NUPP2001"
    )
end

function M.anUninferredResultParameterIsAnError()
    local body = table.concat(
        {
            "local function make<T>(): T",
            "   error('not reached')",
            "end",
        },
        "\n"
    ) .. "\n"
    local found = diagnostics(body .. "local value = make()\nreturn value\n")
    assertEq(#found, 1, "one uninferred parameter")
    assertEq(found[1].code, "NUPP2148")
    assert(found[1].msg:find("T", 1, true), "diagnostic names the parameter")
    assert(found[1].msg:find("make", 1, true), "diagnostic names the callee")
    assert(found[1].help and found[1].help:find("make<T>(...)", 1, true), "help shows the explicit form")
    clean(body .. "local value = make<string>()\nreturn value\n")
    clean(body .. "local value: string = make()\nreturn value\n")
end

function M.explicitTypeArgumentsStayFixedAgainstArguments()
    reports(
        table.concat(
            {
                "local function identity<T>(value: T): T return value end",
                "return identity<string>(1)",
            },
            "\n"
        ),
        "NUPP2006"
    )
end

function M.onlyResultBindersNeedInferenceEvidence()
    clean(
        table.concat(
            {
                "local function phantom<T>(): integer return 1 end",
                "local function defaulted<T = string>(): T return 'ok' as T end",
                "local one = phantom()",
                "local two: string = defaulted()",
                "return one, two",
            },
            "\n"
        )
    )
end

function M.gradualArgumentsAreInferenceEvidence()
    local body = table.concat(
        {
            "local record Box<T>",
            "   value: T",
            "end",
            "local function identity<T>(value: T): T return value end",
            "local function unwrap<T>(value: Box<T>): T return value.value end",
            "local value: any = nil",
            "local direct = identity(value)",
            "local nested = unwrap(value)",
            "return direct, nested",
        },
        "\n"
    )
    clean(body)
    reports(
        body:gsub(
            "return direct, nested",
            "local function extra<T, U>(value: Box<T>): U error('not reached') end\nlocal missing = extra(value)\nreturn missing"
        ),
        "NUPP2148"
    )
end

function M.typePackResultsNeedInferenceEvidence()
    reports(
        table.concat(
            {
                "local function makePack<A...>(): A...",
                "   error('not reached')",
                "end",
                "local left, right = makePack()",
                "return left, right",
            },
            "\n"
        ),
        "NUPP2148"
    )
end

function M.genericConstructionsNeedInferenceEvidence()
    local body = table.concat({"local record Empty<T>", "   tag: string", "end",}, "\n") .. "\n"
    reports(body .. "local value = new Empty(tag = 'x')\nreturn value\n", "NUPP2148")
    clean(body .. "local value = new Empty<integer>(tag = 'x')\nreturn value\n")
    local declared = table.concat(
        {
            "local record Made<T>",
            "   tag: string",
            "   constructor(self, tag: string) self.tag = tag end",
            "end",
        },
        "\n"
    ) .. "\n"
    reports(declared .. "local value = new Made('x')\nreturn value\n", "NUPP2148")
    clean(declared .. "local value = new Made<integer>('x')\nreturn value\n")
end

function M.genericMethodsNeedInferenceEvidence()
    local body = table.concat(
        {
            "local record Holder",
            "   function pick<T>(self): T? return nil end",
            "end",
            "local holder = new Holder()",
        },
        "\n"
    ) .. "\n"
    reports(body .. "local value = holder:pick()\nreturn value\n", "NUPP2148")
    clean(body .. "local value: integer? = holder:pick<integer>()\nreturn value\n")
end

function M.onlyTheWinningOverloadReportsUninferredResults()
    local body = table.concat(
        {
            "local type Pick = function<T>(tag: 'generic'): T",
            "   & function(tag: 'fixed'): integer",
            "local pick: Pick = nil as any",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local value: integer = pick('fixed')\nreturn value\n")
    reports(body .. "local value = pick('generic')\nreturn value\n", "NUPP2148")
end

-- A callback returning some other type that satisfies the bound widens the binder
-- to the union, the way any binder met twice does, so the caller sees both.
function M.aCallbackResultJoinsTheBinderItReturns()
    local body = table.concat(
        {
            "local interface Named",
            "   name: string",
            "end",
            "local record P is Named",
            "   name: string",
            "end",
            "local record Q is Named",
            "   name: string",
            "   extra: integer",
            "end",
            "local function make<T is Named>(proto: T, f: function(): T): T",
            "   return f()",
            "end",
            'local q = make(new Q(name = "q", extra = 1), function() return new P(name = "p") end)',
        },
        "\n"
    ) .. "\n"
    reports(body .. "local e: integer = q.extra\nreturn e\n", "NUPP2004")
    clean(body .. "local n: string = q.name\nreturn n\n")
end

-- A literal argument binds a type argument to its base type, as construction from
-- a literal already did: a `Cell<0>` could never hold another value. A binder whose
-- bound the base type fails keeps the literal it was passed.
function M.aLiteralArgumentBindsItsBaseType()
    local body = table.concat(
        {
            "local record Cell<T>",
            "   value: T",
            "end",
            "local function cell<T>(v: T): Cell<T>",
            "   return new Cell(value = v)",
            "end",
            'local function pick<T is "a" | "b">(v: T): T',
            "   return v",
            "end",
            "local function map<A, B>(xs: {A}, f: function(A): B): {B}",
            "   local out: {B} = {}",
            "   for i, x in ipairs(xs) do out[i] = f(x) end",
            "   return out",
            "end",
        },
        "\n"
    ) .. "\n"
    clean(body .. "local c = cell(0)\nc.value = 5\nlocal d: Cell<integer> = c\nreturn d\n")
    clean(body .. 'local a: "a" = pick("a")\nreturn a\n')
    reports(body .. 'local b: "b" = pick("a")\nreturn b\n', "NUPP2001")
    clean(body .. "local zeros: {integer} = map({1, 2}, function(x) return 0 end)\nreturn zeros\n")
end

function M.removingABoundRestoresLiteralWideningAcrossChecks()
    local prefix = [[local record Cell<T>
   value: T
end
local function cell<T is 0>(value: T): Cell<T>
   return new Cell(value = value)
end
]]
    local revisions = {
        prefix .. "return cell(0)\n",
        prefix:gsub("T is 0", "T") .. "local c = cell(0)\nc.value = 5\nlocal d: Cell<integer> = c\nreturn d\n",
    }
    local retained = {}
    local revisionEnv = envMod.new(HERE .. "/..")
    for index, source in ipairs(revisions) do
        local parsed = parser.parse(source, "generic-bound-edit.g.nupp")
        retained[index] = parsed
        assertEq(#parsed.errors, 0, "revision syntax")
        local diagnostics = check.check(parsed, "generic-bound-edit.g.nupp", revisionEnv)
        assertEq(#diagnostics, 0, "revision " .. index .. ": " .. (diagnostics[1] and diagnostics[1].msg or ""))
    end
    assertEq(#retained, 2, "both checked revisions remain live")
end

-- A table written with positional entries where a tuple result is declared is that
-- tuple, the way an annotated local reads its initializer, so a generic body can
-- return a pair of its binders.
function M.aPositionalLiteralReturnsAsTheDeclaredTuple()
    clean(
        table.concat(
            {
                "local function pair<A, B>(a: A, b: B): {A, B}",
                "   return {a, b}",
                "end",
                'local p = pair(1, "x")',
                "local n: integer = p[1]",
                "local s: string = p[2]",
                "return n, s",
            },
            "\n"
        )
    )
    reports(
        table.concat(
            {"local function swapped<A, B>(a: A, b: B): {A, B}", "   return {b, a}", "end", "return swapped",},
            "\n"
        ),
        "NUPP2002"
    )
end

-- A binder met in a mutable container's element position is fixed there: the
-- array already holds that type, and a value argument cannot widen the binding
-- and then ride array covariance into it. A `const` view reads only, so it
-- still unions.
function M.aContainerElementFixesTheBinder()
    local body = table.concat(
        {
            "local function push<T>(xs: {T}, v: T): nil",
            "   xs[#xs + 1] = v",
            "end",
            "local function unshift<T>(v: T, xs: {T}): nil",
            "   table.insert(xs, 1, v)",
            "end",
            "local function put<K, V>(m: {[K]: V}, k: K, v: V): nil",
            "   m[k] = v",
            "end",
            "local function first<T>(xs: const {T}, fallback: T): T",
            "   return xs[1] or fallback",
            "end",
            "local ints: {integer} = {1}",
            "local names: {[string]: string} = {}",
        },
        "\n"
    ) .. "\n"
    reports(body .. 'push(ints, "s")\nreturn ints\n', "NUPP2006")
    reports(body .. 'unshift("s", ints)\nreturn ints\n', "NUPP2006")
    reports(body .. 'put(names, "k", 5)\nreturn names\n', "NUPP2006")
    clean(body .. "push(ints, 2)\nunshift(0, ints)\nput(names, 'k', 'v')\nreturn ints\n")
    clean(body .. 'local either: integer | string = first(ints, "none")\nreturn either\n')
end

-- An application writes as many arguments as the declaration binds parameters. Left
-- unchecked, a short one produced a type whose remaining parameters nothing had bound,
-- which fits no value the program can build and surfaced only as a mismatch between
-- two types that print the same.
function M.anApplicationWritesAsManyArgumentsAsTheDeclarationBinds()
    local pair = table.concat({"local record Pair<A, B>", "   a: A", "   b: B", "end",}, "\n") .. "\n"
    reports(pair .. "local short: Pair<integer> = nil as any\nreturn short\n", "NUPP2146")
    reports(pair .. "local long: Pair<integer, string, boolean> = nil as any\nreturn long\n", "NUPP2146")
    reports(pair .. "local bare: Pair = nil as any\nreturn bare\n", "NUPP2146")
    clean(pair .. "local exact: Pair<integer, string> = nil as any\nreturn exact\n")
end

-- A trailing parameter the declaration defaulted may be left out, and the two
-- spellings that name a declaration rather than one of its values take none at all.
function M.anApplicationMayLeaveOutADefaultedParameter()
    clean(
        table.concat(
            {
                "local record Tagged<A, B = string>",
                "   a: A",
                "   b: B",
                "end",
                "local one: Tagged<integer> = nil as any",
                "local both: Tagged<integer, boolean> = nil as any",
                "return one, both",
            },
            "\n"
        ) .. "\n"
    )
    clean(
        table.concat(
            {
                "local record Box<T>",
                "   value: T",
                "end",
                "local function witness(w: Type<Box>): nil end",
                "local shape: metatable<Box> = nil as any",
                "return witness, shape",
            },
            "\n"
        ) .. "\n"
    )
end

-- Inside its own body a generic declaration means itself applied to its own
-- parameters, so the recursive field its reference documents carries the argument the
-- construction inferred rather than losing it.
function M.aGenericDeclarationStandsForItsOwnInstantiationInItsBody()
    local node = table.concat({
        "local record Node<T>",
        "   value: T",
        "   next: Node?",
        "end",
    }, "\n") .. "\n"
    clean(
        node
        .. "local tail: Node<integer> = new Node(value = 2)\n"
        .. "local head: Node<integer> = new Node(value = 1, next = tail)\n"
        .. "return head\n"
    )
    reports(
        node
        .. "local function link(head: Node<integer>, tail: Node<string>): nil\n"
        .. "   head.next = tail\n"
        .. "end\n"
        .. "return link\n",
        "NUPP2001"
    )
    reports(
        node
        .. "local function valueOf(head: Node<integer>): string\n"
        .. "   local rest = head.next\n"
        .. "   if rest ~= nil then return rest.value end\n"
        .. "   return 'none'\n"
        .. "end\n"
        .. "return valueOf\n",
        "NUPP2002"
    )
end

return M
