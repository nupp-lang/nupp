local testAssert = require("assert")
local assertions = require("helpers.assertions")
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local program = require("program")
local envMod = require("nupp.compiler.project.env")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function checked(source, opts)
    local result = parser.parse(source, "ownership-test.nupp")
    testAssert.eq(#result.errors, 0, "syntax: " .. (result.errors[1] and result.errors[1].msg or ""))
    local diags = check.check(result, "ownership-test.nupp", env, opts)
    return result, diags
end

local function codes(source)
    local _, diags = checked(source)
    local out = {}
    for _, diag in ipairs(diags) do
        out[#out + 1] = diag.code
    end

    return table.concat(out, " ")
end

local function diagnosticsOf(source)
    local _, diags = checked(source)
    return diags
end

local assertClean = assertions.check(diagnosticsOf)

local function runGenerated(source, label)
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")

    return program.run(result, label)
end

local RESOURCE = table.concat(
    {
        "cdef struct resource",
        "   value: int32",
        "end",
        "cdef function resource_create(): resource*",
        "cdef function resource_free(takes value: resource*)",
        "local function resource_new(): affine(resource*, resource_free)",
        "   return resource_create()",
        "end",
    },
    "\n"
)

local M = {}

function M.aCloseableBoundDestroysFactoryResultsOnEveryExit()
    runGenerated(
        [[
local closed = 0
local record Resource is own.Closeable
    function close(takes self): nil closed += 1 end
end
local interface Factory<S is own.Closeable>
    begin: function(self): S
end
local record Resources is Factory<Resource>
    function begin(self): Resource return new Resource() end
end
local function use<S is own.Closeable>(factory: Factory<S>, fail: boolean): nil
    local value = factory:begin()
    if fail then error("abort") end
end
local factory = new Resources()
use(factory, false)
assert(closed == 1)
local function fail(): nil use(factory, true) end
assert(not pcall(fail))
assert(closed == 2)
local interface Consumer
    apply: function<S is own.Closeable>(self, factory: Factory<S>): nil
end
local record Consume is Consumer
    function apply<S is own.Closeable>(self, factory: Factory<S>): nil
        local value = factory:begin()
    end
end
local consumer: Consumer = new Consume()
consumer:apply(factory)
assert(closed == 3)
]],
        "closeable-factory-bound"
    )
end

function M.aCallableBoundRetainsTheActualOwningResult()
    runGenerated(
        [[
local closed = 0
local record Resource is own.Closeable
    function close(takes self): nil
        closed += 1
    end
end
local function create(): Resource
    return new Resource()
end
local function retain<F is function(...: any): any>(factory: F): F
    return factory
end
do
    local factory = retain(create)
    local resource = factory()
    resource:close()
end
assert(closed == 1)
]],
        "owning-callable-bound"
    )
end

function M.copyableBoundsRejectOwnedInitializersBeforeErasure()
    assertClean(
        [[
local function cache<V is own.Copyable>(build: function(): V): V
    return build()
end
local value: string? = cache(function(): string? return nil end)
local record Node
    next: Node?
    value: string
end
local node = cache(function(): Node return new Node(value = "ok") end)
print(value, node.value)
]]
    )
    for _, result in ipairs({"Resource", "managed(Resource)"}) do
        local construct = result == "Resource" and "new Resource()" or "own.manage(new Resource())"
        local problem = codes(
            [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local function cache<V is own.Copyable>(build: function(): V): V
    return build()
end
local value = cache(function(): ]]
            .. result
            .. [[
    return ]]
            .. construct
            .. [[
end)
]]
        )
        assert(problem:find("NUPP2116", 1, true), problem)
    end
end

function M.callableResultsCannotForgetAnOwnershipObligation()
    local problem = codes(
        [[
local function release(takes value: integer): nil end
local function acquire(): affine(integer, release) return 7 end
local factory: function(): integer = acquire
return factory
]]
    )
    assert(problem:find("NUPP2001", 1, true), problem)
end

function M.copyabilityCannotBeHiddenByAnInheritedBoundOrBorrow()
    local source = [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local interface Cached is own.Copyable
    label: string
end
local function retain<V is own.Copyable>(value: V): nil end
local function inherited<V is Cached>(value: V): nil end
local function inspect(borrows value: Resource): nil
    retain(value)
end
local owner = new Resource()
retain(owner)
inherited(owner)
]]
    local count = 0
    for _, diagnostic in ipairs(diagnosticsOf(source)) do
        if diagnostic.code == "NUPP2116" then
            count = count + 1
        end
    end
    testAssert.eq(count, 3)
end

function M.genericCallableResultsKeepTheirOwnership()
    runGenerated(
        [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local function invoke<V>(build: function(): V): V
    return build()
end
local value = invoke(function(): Resource return new Resource() end)
value:close()
]],
        "generic-callable-owning-result"
    )
end

function M.optionalCallableResultsKeepTheirOwnership()
    runGenerated(
        [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local function invoke<V>(build: function(): V?): V?
    return build()
end
local value = invoke(function(): Resource? return new Resource() end)
if value ~= nil then value:close() end
]],
        "generic-optional-owning-result"
    )
end

function M.genericFactoriesRetainAnExplicitResultOwner()
    runGenerated(
        [[
local record Host
    closes: integer
end

local record Owner<H is table> is own.Closeable
    host: H
    function close(takes self): nil
    end
end
local function create<H is table>(host: H): Owner<H>
    return new Owner<H>(host = host)
end
local owner = create(new Host(closes = 0))
owner:close()
]],
        "generic-owning-result"
    )
    testAssert.eq(
        codes(
            [[
local record Owner<H is table> is own.Closeable
    host: H
    function close(takes self): nil end
end
local function create<H is table>(host: H): Owner<H>
    return new Owner<H>(host = host)
end
local owner = create({})
owner:close()
owner:close()
]]
        ),
        "NUPP2601"
    )
end

function M.genericBorrowingCallbacksCanReborrowAnOwningTypeArgument()
    assertClean(
        [[
local record Resource is own.Closeable
    function close(takes self): nil end
end
local interface Consumer<T>
    apply: function(self, exclusive value: T): nil
end
local record Use is Consumer<Resource>
    function apply(self, exclusive value: Resource): nil end
end
local function invoke<T>(consumer: Consumer<T>, exclusive value: T): nil
    consumer:apply(value)
end
local function forward(exclusive value: Resource): nil
    invoke(new Use(), value)
end
local value = new Resource()
forward(value)
value:close()
]]
    )
end

-- The arms of a branch are alternatives, so an owner discharged on one is not
-- discharged on its sibling. A narrowed binding shares its declaration's ownership
-- state, which used to make the first arm's move visible in the second and report
-- the second as a use after move.
function M.everyArmOfABranchDischargesIndependently()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function twoArms(flag: boolean): nil",
                "   local value = resource_new()",
                "   if flag then",
                "      own.drop(value)",
                "   else",
                "      own.drop(value)",
                "   end",
                "end",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function chain(n: integer): nil",
                "   local value = resource_new()",
                "   if n == 1 then",
                "      own.drop(value)",
                "   elseif n == 2 then",
                "      own.drop(value)",
                "   else",
                "      own.drop(value)",
                "   end",
                "end",
            },
            "\n"
        )
    )
end

-- The independence is per arm, not a licence to discharge twice: a second move on
-- the same path, and a use after the statement, both still report.
function M.branchIndependenceStillCatchesADoubleMove()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function twice(flag: boolean): nil",
                    "   local value = resource_new()",
                    "   if flag then",
                    "      own.drop(value)",
                    "      own.drop(value)",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2601",
        "a second move on one path still reports"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function afterwards(flag: boolean): nil",
                    "   local value = resource_new()",
                    "   if flag then",
                    "      own.drop(value)",
                    "   else",
                    "      own.drop(value)",
                    "   end",
                    "   own.drop(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2601",
        "a move after every arm moved still reports"
    )
end

function M.scalarGenericPreservationTransfersAnOwner()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function id<T>(takes value: T): T preserves value",
                "   return value",
                "end",
                "local value = resource_new()",
                "local forwarded = id(value)",
                "own.drop(forwarded)",
            },
            "\n"
        )
    )
end

function M.scalarGenericPreservationMovesItsInputExactlyOnce()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function id<T>(takes value: T): T preserves value",
                    "   return value",
                    "end",
                    "local value = resource_new()",
                    "local forwarded = id(value)",
                    "print(value)",
                    "own.drop(forwarded)",
                },
                "\n"
            )
        ),
        "NUPP2601"
    )
end

function M.genericPreservationAgreesAcrossBranchSpecificReturns()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function id<T>(takes value: T): T preserves value return value end",
                "local function choose<T>(takes value: T, flag: boolean): T preserves value",
                "   if flag then",
                "      return value",
                "   else",
                "      return id(value)",
                "   end",
                "end",
                "local forwarded = choose(resource_new(), true)",
                "own.drop(forwarded)",
            },
            "\n"
        )
    )
end

function M.fixedPackPreservationCarriesTheExactResultSlot()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function label<T>(takes value: T): (string, T preserves value)",
                "   return 'resource', value",
                "end",
                "local name, forwarded = label(resource_new())",
                "print(name)",
                "own.drop(forwarded)",
            },
            "\n"
        )
    )
end

function M.genericPreservationMovesCapabilitiesIntoAggregateResults()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local record Box<T>",
                "   value: T",
                "end",
                "local function box<T>(takes value: T): Box<T> preserves value",
                "   return new Box(value = value)",
                "end",
                "local boxed = box(resource_new())",
                "own.drop(boxed)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Pair<T>",
                    "   left: T",
                    "   right: T",
                    "end",
                    "local function ambiguous<T>(takes value: T): Pair<T> preserves value",
                    "   return new Pair(left = value, right = value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2606 NUPP2602",
        "a relation cannot guess between repeated components or duplicate a move"
    )
end

function M.genericPreservationReducesIdentityMappedResults()
    assertClean(
        table.concat(
            {
                "local type View<T> = {@readonly [K in keyof T]: T.[K]}",
                "local record Box<T>",
                "   value: T",
                "end",
                "local function box<T>(takes value: T): View<Box<T>> preserves value",
                "   return new Box(value = value)",
                "end",
                RESOURCE,
                "local boxed = box(resource_new())",
                "own.drop(boxed)",
            },
            "\n"
        )
    )
end

function M.callableAssignmentCannotEraseAPreservationRelation()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local function preserving<T>(takes value: T): T preserves value",
                    "   return value",
                    "end",
                    "local plain: function<T>(takes value: T): T = preserving",
                    "print(plain)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
    -- A literal that spells the relation has promised it, wherever it is written.
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local plain: function<T>(takes value: T): T = function<T>(takes value: T): T preserves value",
                    "   return value",
                    "end",
                    "print(plain)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
end

-- An inferred relation is what a body happens to allow rather than a promise, so a
-- literal written into a slot takes its relations from the slot, as it does its
-- parameter types. Inferred apart, an identity literal fitted no slot that did not
-- spell `preserves`.
function M.aLiteralTakesItsInferredRelationsFromItsSlot()
    assertClean(
        table.concat(
            {
                "local plain: function<T>(value: T): T = function<T>(value: T): T",
                "   return value",
                "end",
                "local preserving: function<T>(value: T): T preserves value = function<T>(value: T): T",
                "   return value",
                "end",
                "print(plain(1), preserving(2))",
            },
            "\n"
        )
    )
end

function M.assertPreservesAndNarrowsAnOptionalOwner()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local function cleanup(takes value: resource*): nil end",
                "cdef function maybe_resource_c(): resource*?",
                "local function maybe_resource(): affine(resource*?, cleanup)",
                "   return maybe_resource_c()",
                "end",
                "local value = assert(maybe_resource())",
                "own.drop(value)",
            },
            "\n"
        )
    )
end

function M.assertForwardsOwnersInItsCompleteResultPack()
    local declaration = table.concat({RESOURCE, "local function through<A...>(...: A...): A... return ... end",}, "\n")
    assertClean(
        table.concat(
            {
                declaration,
                "local first = resource_new()",
                "local last = resource_new()",
                "local present, gap, tail = assert(first, nil, last)",
                "local empty: nil = gap",
                "own.drop(present)",
                "own.drop(tail)",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                declaration,
                "local first = resource_new()",
                "local last = resource_new()",
                "local present, gap, tail = assert(through(first, nil, last))",
                "local empty: nil = gap",
                "own.drop(present)",
                "own.drop(tail)",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                declaration,
                "local requireTruthy = assert",
                "local first = resource_new()",
                "local last = resource_new()",
                "local present, gap, tail = requireTruthy(first, nil, last)",
                "local empty: nil = gap",
                "own.drop(present)",
                "own.drop(tail)",
            },
            "\n"
        )
    )
    testAssert.matches(
        codes(
            declaration
            .. "\nlocal value = resource_new()\nlocal result = assert(value)\nprint(value)\nown.drop(result)"
        ),
        "NUPP2601",
        "forwarding moves the owner exactly once"
    )
end

function M.optionalAliasesKeepExplicitCleanupOwnership()
    assertClean(
        table.concat(
            {
                "local record Resource",
                "   closed: boolean",
                "end",
                "local function closeResource(takes value: Resource): nil",
                "   value.closed = true",
                "end",
                "local type MaybeResource = affine(Resource, closeResource)?",
                "local function open(): affine(Resource, closeResource)",
                "   return new Resource(closed = false)",
                "end",
                "local value: MaybeResource = open()",
                "if value then own.drop(value) end",
            },
            "\n"
        )
    )
end

function M.expressionSelectionCannotDuplicateAnOwner()
    assertClean(
        RESOURCE .. table.concat(
            {"", "local value = resource_new()", "local moved = (value)", "own.drop(moved)",},
            "\n"
        )
    )

    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {"", "local value = resource_new()", "local moved = true and value", "own.drop(moved)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.ownersCannotBeStoredInPlainConstructorFields()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local record Box",
                    "   value: resource*",
                    "end",
                    "local value = resource_new()",
                    "local box = new Box(value = value)",
                    "print(box.value)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.localFunctionDeclarationsBorrowCapturedOwners()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function run(): nil",
                    "   local value = resource_new()",
                    "   local function read(): nil print(value.value) end",
                    "   own.drop(value)",
                    "   read()",
                    "end",
                    "return run",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.backwardGotosAreOwnershipLoopEdges()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {"", "local value = resource_new()", "::again::", "own.drop(value)", "goto again",},
                "\n"
            )
        ),
        "NUPP2609"
    )
end

-- A move on a path that leaves early is still a move where that path lands: after
-- the loop for `break`, at the header for `continue`, at the label for a forward
-- `goto`. Each of these used to drop the move with the `if` arm that made it, which
-- accepted a double free.
local function exitEdge(lines)
    return codes(RESOURCE .. "\n" .. table.concat(lines, "\n"))
end

function M.aMoveBeforeAnExitEdgeReachesWhereTheEdgeLands()
    local function run(body)
        local lines = {"local function run(flag: boolean): nil", "   local value = resource_new()"}
        for _, line in ipairs(body) do
            lines[#lines + 1] = "   " .. line
        end
        lines[#lines + 1] = "end"
        lines[#lines + 1] = "return run"

        return exitEdge(lines)
    end

    -- break out of while, repeat, numeric for, and generic for
    testAssert.eq(
        run({
            "while true do",
            "   if flag then own.drop(value) break end",
            "   break",
            "end",
            "own.drop(value)"
        }),
        "NUPP2601"
    )
    testAssert.eq(
        run({
            "repeat",
            "   if flag then own.drop(value) break end",
            "until true",
            "own.drop(value)"
        }),
        "NUPP2601"
    )
    testAssert.eq(
        run({
            "for i = 1, 2 do",
            "   if flag then own.drop(value) break end",
            "end",
            "own.drop(value)"
        }),
        "NUPP2601"
    )
    testAssert.eq(
        run({
            "for _ in ipairs({1, 2}) do",
            "   if flag then own.drop(value) break end",
            "end",
            "own.drop(value)"
        }),
        "NUPP2601"
    )
    -- the exit suffix is the same edge
    testAssert.eq(
        run({
            "for i = 1, 2 do",
            "   if flag then own.drop(value) end",
            "   local n = tonumber(flag and 'x' or '1') or break",
            "   print(n)",
            "   break",
            "end",
            "own.drop(value)",
        }),
        "NUPP2601"
    )
    -- continue runs the header again
    testAssert.eq(
        run({
            "for i = 1, 2 do",
            "   if i == 1 then own.drop(value) continue end",
            "end",
            "own.drop(value)"
        }),
        "NUPP2609"
    )
    -- a forward goto lands at its label
    testAssert.eq(
        run({
            "do",
            "   if flag then own.drop(value) goto done end",
            "end",
            "::done::",
            "own.drop(value)"
        }),
        "NUPP2601"
    )
    -- controls: every edge discharging it, or none of them, stays clean
    testAssert.eq(
        run({
            "while true do",
            "   if flag then own.drop(value) break end",
            "   own.drop(value)",
            "   break",
            "end"
        }),
        ""
    )
    testAssert.eq(run({"for i = 1, 2 do", "   if flag then break end", "end", "own.drop(value)"}), "")
    testAssert.eq(run({"if flag then goto done end", "print(value.value)", "::done::", "own.drop(value)"}), "")
    testAssert.eq(run({"for i = 1, 2 do", "   if flag then continue end", "   print(i)", "end", "own.drop(value)"}), "")
    -- a loop whose body always returns leaves by its own test with the owner intact
    testAssert.eq(run({"for i = 1, 2 do", "   own.drop(value)", "   return", "end", "own.drop(value)"}), "")
end

function M.aConsumingParameterMustBeDischargedOnEveryExitEdge()
    testAssert.eq(
        exitEdge({
            "local function run(takes value: affine(resource*, resource_free), n: integer): nil",
            "   for i = 1, n do",
            "      if i == 2 then own.drop(value) break end",
            "   end",
            "end",
            "return run",
        }),
        "NUPP2603"
    )
    testAssert.eq(
        exitEdge({
            "local function run(takes value: affine(resource*, resource_free), flag: boolean): nil",
            "   while true do",
            "      if flag then own.drop(value) break end",
            "   end",
            "end",
            "return run",
        }),
        ""
    )
end

function M.sharedAndExclusiveArgumentsCannotAlias()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function inspect(borrows left: resource*, exclusive right: resource*): nil end",
                    "local value = resource_new()",
                    "inspect(value, value)",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        "NUPP2607"
    )
end

function M.untypedVarargsCannotEraseOwners()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function keep(...: any): nil end",
                    "local value = resource_new()",
                    "keep(value)",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        "NUPP2611"
    )
end

function M.earlyExitMovesDoNotPoisonFallthrough()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function run(stop: boolean): nil",
                "   local value = resource_new()",
                "   if stop then",
                "      own.drop(value)",
                "      return",
                "   end",
                "   print(value.value)",
                "   own.drop(value)",
                "end",
                "return run",
            },
            "\n"
        )
    )

    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function run(stop: boolean): nil",
                "   local value = resource_new()",
                "   if stop then",
                "      own.drop(value)",
                "      error('stop')",
                "   end",
                "   print(value.value)",
                "   own.drop(value)",
                "end",
                "return run",
            },
            "\n"
        )
    )

    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function run(stop: boolean): nil",
                "   local value = resource_new()",
                "   while true do",
                "      if stop then",
                "         own.drop(value)",
                "         break",
                "      end",
                "      print(value.value)",
                "      own.drop(value)",
                "      break",
                "   end",
                "end",
                "return run",
            },
            "\n"
        )
    )

    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function run(stop: boolean): nil",
                "   local value = resource_new()",
                "   local selected = switch stop do",
                "      case true -> do",
                "         own.drop(value)",
                "         return",
                "      end",
                "      case false -> 1",
                "   end",
                "   print(selected, value.value)",
                "   own.drop(value)",
                "end",
                "return run",
            },
            "\n"
        )
    )
end

function M.assertingANamedOptionalOwnerKeepsItInPlace()
    local declaration = table.concat(
        {
            RESOURCE,
            "local function cleanup(takes value: resource*): nil end",
            "cdef function maybe_resource_c(): resource*?",
            "local function maybe_resource(): affine(resource*?, cleanup)",
            "   return maybe_resource_c()",
            "end",
        },
        "\n"
    )
    assertClean(
        table.concat(
            {
                declaration,
                "local value = maybe_resource()",
                "local present = assert(value, 'resource is required')",
                "own.drop(present)",
            },
            "\n"
        )
    )
    testAssert.eq(codes(declaration .. "\nassert(maybe_resource())"), "NUPP2605")
end

function M.aPreservesBodyMustReturnTheNamedParameter()
    testAssert.eq(
        codes(
            table.concat(
                {"local function wrong<T>(takes value: T, other: T): T preserves value", "   return other", "end",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.stringPointerProvenanceRejectsAnUnanchoredExpression()
    testAssert.eq(codes(table.concat({"local pointer = ffi.cast<cstring>('a' .. 'b')",}, "\n")), "NUPP2501")
end

function M.stringPointerProvenanceFollowsBindingsAndPreservation()
    assertClean(
        table.concat(
            {
                "local function id<T>(takes value: T): T preserves value",
                "   return value",
                "end",
                "local text = 'a' .. 'b'",
                "local direct = ffi.cast<cstring>(text)",
                "local forwarded = ffi.cast<cstring>(id(text))",
                "print(direct ~= nil, forwarded ~= nil)",
            },
            "\n"
        )
    )
end

function M.preservingACopyableValueDoesNotBorrowTheLocalBinding()
    assertClean(
        [[
local record Box<T>
    value: T
end
local function box<T>(value: T): Box<T>
    return new Box<T>(value = value)
end
local function make(): Box<{string}>
    local values = {"one", "two"}
    return box(values)
end
print(#make().value)
]]
    )
end

function M.pairsBorrowsItsMapAndKeepsTheIteratorScoped()
    assertClean(
        [[
local function count(borrows values: {[string]: integer}): integer
    local result: integer = 0
    for _, value in pairs(values) do
        result += value
    end
    return result
end
print(count({one = 1, two = 2}))
]]
    )
    testAssert.eq(
        codes(
            [[
local function escape(borrows values: {[string]: integer}): function(): ((string, integer) | (nil))
    return pairs(values)
end
]]
        ),
        "NUPP2608"
    )
end

function M.ffiGcCannotAttachASecondCleanupToAnOwner()
    testAssert.eq(
        codes(
            table.concat(
                {RESOURCE, "local value = resource_new()", "ffi.gc(value, resource_free)", "own.drop(value)",},
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.anAliasedCFunctionKeepsItsForeignBoundary()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "cdef function inspect(value: voidptr)",
                    "local indirect = inspect",
                    "local raw = ffi.cast<voidptr>(8)",
                    "indirect(raw)",
                },
                "\n"
            )
        ),
        "NUPP2604"
    )
end

function M.nominalRecordsCanRetainDeclaredBorrowedFields()
    assertClean(
        table.concat(
            {
                "local record Buffer",
                "   value: string",
                "end",
                "local function closeBuffer(takes value: Buffer): nil end",
                "local function openBuffer(): affine(Buffer, closeBuffer)",
                "   return new Buffer(value = 'bytes')",
                "end",
                "local function view(borrows source: Buffer): Buffer borrows (source)",
                "   return source",
                "end",
                "local record Cursor",
                "   source: Buffer",
                "   bytes: Buffer borrows (source)",
                "end",
                "local source = openBuffer()",
                "do",
                "   local cursor = new Cursor(source = source, bytes = view(source))",
                "   print(cursor.bytes.value)",
                "end",
                "own.drop(source)",
            },
            "\n"
        )
    )
end

function M.aBorrowedFieldMustMatchItsDeclaredSiblingRoot()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Buffer",
                    "   value: string",
                    "end",
                    "local function view(borrows source: Buffer): Buffer borrows (source)",
                    "   return source",
                    "end",
                    "local record Cursor",
                    "   source: Buffer",
                    "   bytes: Buffer borrows (source)",
                    "end",
                    "local left = new Buffer(value = 'left')",
                    "local right = new Buffer(value = 'right')",
                    "local cursor = new Cursor(source = left, bytes = view(right))",
                },
                "\n"
            )
        ),
        "NUPP2619"
    )
end

function M.aRecordCanOwnTheRootOfItsBorrowedField()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local record Parsed",
                "   source: affine(resource*, resource_free)",
                "   view: resource* borrows (source)",
                "end",
                "local source = resource_new()",
                "local parsed = new Parsed(source = source, view = borrow(source))",
                "print(parsed.view.value)",
                "own.drop(parsed)",
            },
            "\n"
        )
    )
end

function M.anInternallyBorrowedRootFieldCannotMoveAlone()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local record Parsed",
                    "   source: affine(resource*, resource_free)",
                    "   view: resource* borrows (source)",
                    "end",
                    "local source = resource_new()",
                    "local parsed = new Parsed(source = source, view = borrow(source))",
                    "local detached = parsed.source",
                    "own.drop(detached)",
                    "own.drop(parsed)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.scopedCallbacksMayCaptureABorrow()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local value = resource_new()",
                "do",
                "   local view = borrow(value)",
                "   pcall(function() borrows (view) print(view.value) end)",
                "end",
                "own.drop(value)",
            },
            "\n"
        )
    )
end

function M.callbackCapturesBorrowOwnersByDefault()
    assertClean(
        table.concat(
            {RESOURCE, "local value = resource_new()", "pcall(function() print(value.value) end)", "own.drop(value)",},
            "\n"
        )
    )
end

function M.coroutineChildrenCannotCaptureAParentBorrow()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local suspension = require(\"coroutine.sus\")",
                    "local value = resource_new()",
                    "do",
                    "   local view = borrow(value)",
                    "   local child = suspension.create(function() print(view.value) end)",
                    "   coroutine.resume(child)",
                    "end",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

-- A terminal may suspend: discharging it is a settlement point. Only a region that
-- forbids suspending refuses one, and it says so where the owner is discharged.
function M.settlingTerminalsAreAcceptedOutsideRegions()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Resource value: integer end",
                    "local park: function(): nil = nil as any",
                    "local function close(takes value: Resource): nil",
                    "   park()",
                    "end",
                    "local function open(): affine(Resource, close)",
                    "   return new Resource(value = 1)",
                    "end",
                    "local value = open()",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.settlingTerminalsAreRefusedInsideANosuspendRegion()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Resource value: integer end",
                    "local park: function(): nil = nil as any",
                    "local function close(takes value: Resource): nil",
                    "   park()",
                    "end",
                    "local function open(): affine(Resource, close)",
                    "   return new Resource(value = 1)",
                    "end",
                    "@nosuspend do",
                    "   local value = open()",
                    "   own.drop(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2701"
    )
end

-- Parameter modes were read at the position the parameter takes in the function type,
-- which an inline method spelling `self` shifts by one. Every mode came from the
-- neighbour on its left: `takes` landed on the receiver and the argument arrived
-- borrowing, so a method that consumed an owner was checked as one that did not.
function M.anInlineMethodOwnsTheParameterItTakes()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local record Holder",
                    "   count: integer",
                    "   function keep(self, takes value: resource*): nil",
                    "      self.count = self.count + 1",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

-- The same body, discharging what it took. The receiver stays a borrow throughout:
-- shifting the modes the other way would consume `self` instead.
function M.anInlineMethodDischargesWhatItTakes()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local record Holder",
                "   count: integer",
                "   function keep(self, takes value: resource*): nil",
                "      self.count = self.count + 1",
                "      resource_free(value)",
                "   end",
                "end",
            },
            "\n"
        )
    )
end

-- A qualified method reads its modes from the same source positions, and always did.
function M.aQualifiedMethodOwnsTheParameterItTakes()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local record Holder",
                "   count: integer",
                "end",
                "function Holder.keep(self, takes value: resource*): nil",
                "   self.count = self.count + 1",
                "end",
            },
            "\n"
        )
    )
end

-- `@unsafe own.release` lowers to its argument, so using it for the assertion rather
-- than the value left an expression where Lua wants a statement. The check and the
-- build both passed and the output would not load.
function M.aDiscardedOwnershipIntrinsicEmitsLoadableLua()
    local source = table.concat(
        {
            RESOURCE,
            "local function spend(takes value: resource*): nil",
            "   @unsafe do",
            "      local _raw = @unsafe own.release(value)",
            "   end",
            "end",
            "return spend",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-discarded-intrinsic")
    assert(chunk, tostring(loadErr))
end

function M.manageRejectsTransferOnlyOwners()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Request",
                    "   value: integer",
                    "end",
                    "local function beginRequest(): affine(Request) return new Request(value = 1) end",
                    "local cell = own.manage(beginRequest())",
                },
                "\n"
            )
        ),
        "NUPP2612"
    )
end

function M.managedCellsCarryExactCleanupPoliciesBehindAliases()
    local source = table.concat(
        {
            RESOURCE,
            "do",
            "   local owner = own.manage(resource_new())",
            "   local handle = owner:alias()",
            "   local returned, problem = handle:take()",
            "   assert(problem == nil)",
            "   own.drop(assert(returned))",
            "end",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    program.image(result, "ownership-test")
end

function M.managedCellsEnforceCustodyAtRuntime()
    local source = table.concat(
        {
            "local cleaned = 0",
            "local record FileState value: integer end",
            "local function closeFile(takes file: FileState): nil",
            "   cleaned = cleaned + file.value",
            "end",
            "local function openFile(value: integer): affine(FileState, closeFile)",
            "   return new FileState(value = value)",
            "end",
            "local owner = own.manage(openFile(1))",
            "local handle = owner:alias()",
            "local stale = handle",
            "local erased: any = handle",
            "local recoveredAlias, recoveryProblem = own.recoveralias(erased)",
            "assert(recoveryProblem == nil)",
            "if not recoveredAlias then error('recovery failed') end",
            "local recovered, policyProblem = recoveredAlias:downcast<affine(FileState, closeFile)>()",
            "assert(policyProblem == nil)",
            "if not recovered then error('downcast failed') end",
            "local file, takeProblem = recovered:take()",
            "assert(takeProblem == nil)",
            "if not file then error('take failed') end",
            "own.drop(file)",
            "local _, staleProblem = stale:with(function(borrows value) return value.value end)",
            "assert(staleProblem ~= nil)",
            "do local another = own.manage(openFile(2)) end",
            "return cleaned, staleProblem and staleProblem.code",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-dynamic-runtime")
    assert(chunk, tostring(loadErr))
    local cleaned, staleCode = chunk()
    testAssert.eq(cleaned, 3, "take and managed destruction each clean exactly once")
    testAssert.eq(staleCode, "NUPP2614", "taking a cell tombstones every copied alias")
end

function M.managedCellsRejectCapabilitiesTheyCannotDischarge()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Request value: integer end",
                    "local function begin(): affine(Request) return new Request(value = 1) end",
                    "local owner = own.manage(begin())",
                },
                "\n"
            )
        ),
        "NUPP2612"
    )
end

function M.dynamicErasureAndBorrowEscapesHaveDedicatedDiagnostics()
    testAssert.eq(codes(table.concat({RESOURCE, "local value: any = resource_new()",}, "\n")), "NUPP2611")

    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function leak(borrows value: resource*): resource*",
                    "   return value",
                    "end",
                    "return leak",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

function M.loopBackEdgesCannotConsumeAnOuterCapabilityConditionally()
    local _, diags = checked(
        table.concat(
            {
                RESOURCE,
                "local function run(flag: boolean): nil",
                "   local value = resource_new()",
                "   while flag do",
                "      own.drop(value)",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(diags[1] and diags[1].code, "NUPP2609")
    testAssert.eq(#(diags[1].related or {}), 1, "loop diagnostic names its back edge")
end

function M.generalRegionsDistinguishSiblingFieldsAndExactIndexes()
    local prelude = table.concat(
        {
            "local record Pair",
            "   left: table",
            "   right: table",
            "end",
            "local function together(exclusive left: table, exclusive right: table): nil end",
            "local pair = new Pair(left = {}, right = {})",
        },
        "\n"
    )
    assertClean(prelude .. "\ntogether(pair.left, pair.right)")
    testAssert.eq(codes(prelude .. "\ntogether(pair.left, pair.left)"), "NUPP2607")

    local indexed = table.concat(
        {
            "local function together(exclusive left: table, exclusive right: table): nil end",
            "local values: {table} = {{}, {}}",
        },
        "\n"
    )
    assertClean(indexed .. "\ntogether(values[1], values[2])")
    testAssert.eq(codes(indexed .. "\nlocal i: integer = 1\ntogether(values[i], values[i])"), "NUPP2607")
    testAssert.eq(codes(indexed .. "\nlocal i: integer = 1\ntogether(values[i], values[1])"), "NUPP2607")
    testAssert.eq(codes(indexed .. "\nlocal value = {}\ntogether(value, value)"), "NUPP2607")
end

function M.checkedRegionIntervalsProveOnlyActualDisjointness()
    local prelude = table.concat(
        {
            "local function together(exclusive left: int32[?], exclusive right: int32[?]): nil end",
            "local values = ffi.new<int32[4]>()",
            "@unsafe do",
        },
        "\n"
    )
    assertClean(
        prelude .. table.concat(
            {
                "",
                "   local left = own.region(values, values, 1, 2)",
                "   local right = own.region(values, values, 3, 4)",
                "   together(left, right)",
                "end",
            },
            "\n"
        )
    )
    local result, diags = checked(
        prelude .. table.concat(
            {
                "",
                "   local left = own.region(values, values, 1, 3)",
                "   local right = own.region(values, values, 3, 4)",
                "   together(left, right)",
                "end",
            },
            "\n"
        )
    )
    assert(result)
    testAssert.eq(diags[1] and diags[1].code, "NUPP2607")
    testAssert.eq(#(diags[1].related or {}), 1, "overlap names the earlier checked region")
end

function M.publicContractsAreExplicitOnlyForCapabilityBearingParameters()
    assertClean(
        table.concat({"local m = {}", "function m.length(value: string): integer return #value end", "return m",}, "\n")
    )
    testAssert.eq(
        codes(table.concat({"local m = {}", "function m.forward<T>(value: T): T return value end", "return m",}, "\n")),
        "NUPP2610"
    )
    testAssert.eq(
        codes(
            table.concat(
                {"local m = {}", "function m.forward<T>(takes value: T): T return value end", "return m",},
                "\n"
            )
        ),
        "NUPP2610 NUPP2603"
    )
    assertClean(
        table.concat(
            {"local m = {}", "function m.forward<T>(takes value: T): T preserves value return value end", "return m",},
            "\n"
        )
    )
end

function M.aliasRecoveryChecksTheStoredCapabilityPolicy()
    local source = table.concat(
        {
            "local record File is own.Closeable",
            "   function flush(exclusive self): nil end",
            "   function close(takes self): nil end",
            "end",
            "local record Socket is own.Closeable",
            "   function flush(exclusive self): nil end",
            "   function close(takes self): nil end",
            "end",
            "local owner = own.manage(new File())",
            "local erased: any = owner:alias()",
            "local recovered, problem = own.recoveralias(erased)",
            "assert(recovered ~= nil and problem == nil)",
            "local file, fileProblem = recovered:downcast<File>()",
            "assert(file ~= nil and fileProblem == nil)",
            "local mismatch, mismatchProblem = recovered:downcast<Socket>()",
            "return mismatch, mismatchProblem and mismatchProblem.code",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-alias-recovery")
    assert(chunk, tostring(loadErr))
    local mismatch, mismatchCode = chunk()
    testAssert.eq(mismatch, nil)
    testAssert.eq(mismatchCode, "NUPP2613")
end

function M.managedCallbackBorrowsReleaseOnErrorsAndRejectConflicts()
    local source = table.concat(
        {
            "local record Client is own.Closeable",
            "   value: integer",
            "   function flush(exclusive self): nil end",
            "   function close(takes self): nil end",
            "end",
            "local owner = own.manage(new Client(value = 1))",
            "local handle = owner:alias()",
            "local conflict: string? = nil",
            "local _, outerProblem = handle:with(function(borrows value)",
            "   local _, problem = handle:withexclusive(function(exclusive item) return item.value end)",
            "   conflict = problem and problem.code",
            "   return value.value",
            "end)",
            "assert(outerProblem == nil)",
            "local raised = pcall(function(): nil",
            "   handle:with(function(borrows value): nil error('callback failed') end)",
            "end)",
            "local answer, finalProblem = handle:withexclusive(function(exclusive value)",
            "   value.value = value.value + 1",
            "   return value.value",
            "end)",
            "return conflict, raised, answer, finalProblem",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-managed-borrows")
    assert(chunk, tostring(loadErr))
    local conflict, raised, answer, finalProblem = chunk()
    testAssert.eq(conflict, "NUPP2620")
    testAssert.eq(raised, false)
    testAssert.eq(answer, 2)
    testAssert.eq(finalProblem, nil)
end

function M.spansCarryBoundsRootsAndAnAffineWriteExtent()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local text = 'bytes'",
                "local whole = spans.fromstring(text)",
                "local part = whole:slice(2, 4)",
                "local byte: uint32 = part[1]",
                "print(byte)",
                "local storage: uint8[?] = ffi.new('uint8_t[4]') as any",
                "do",
                "   local writable = spans.writecarray(storage, 4)",
                "   writable[1] = 65",
                "   own.drop(writable)",
                "end",
            },
            "\n"
        )
    )
end

function M.spansPreserveTheCArrayElementType()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[4]>()",
                "do",
                "   local view = spans.fromcarray(storage, 4)",
                "   local value: int32 = view[1]",
                "end",
                "local writable = spans.writecarray(storage, 4)",
                "writable[2] = 42 as int32",
                "own.drop(writable)",
            },
            "\n"
        )
    )
end

function M.spansExportANameableGenericWithoutTheirRepresentation()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local function first(borrows view: spans.Span<int32>): int32",
                "   return view[1]",
                "end",
                "local storage = ffi.new<int32[4]>()",
                "local view = spans.fromcarray(storage, 4)",
                "local value: int32 = first(view)",
                "print(value)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local view = spans.fromcarray(storage, 4)",
                    "print(view.pointer)",
                },
                "\n"
            )
        ),
        "NUPP2004",
        "the span interface does not expose its representation"
    )

    testAssert.eq(
        codes(
            table.concat(
                {"local spans = require(\"binary.span\")", "local made = new spans.Span()", "print(made)",},
                "\n"
            )
        ),
        "NUPP2004",
        "the interface has no public representation to construct"
    )
end

function M.fixedSpansRefineDynamicSpansWithoutLengthChecks()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local function exact(borrows view: spans.FixedSpan<int32, 4>): integer",
                "   return #view as integer",
                "end",
                "local function dynamic(borrows view: spans.Span<int32>): integer",
                "   return #view",
                "end",
                "local storage = ffi.new<int32[4]>()",
                "do",
                "   local view = spans.fromfixedcarray(storage, 4)",
                "   print(exact(view), dynamic(view), view[1])",
                "end",
                "local writable = spans.writefixedcarray(storage, 4)",
                "do",
                "   local shared = writable:shared()",
                "   print(exact(shared))",
                "end",
                "writable[1] = 42 as int32",
                "own.drop(writable)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local view = spans.fromfixedcarray(storage, 3)",
                    "print(#view)",
                },
                "\n"
            )
        ),
        "NUPP2006",
        "the literal count must match the fixed C array"
    )

    testAssert.eq(
        codes(
            table.concat(
                {"local spans = require(\"binary.span\")", "local record Forged is spans.Span<int32>", "end",},
                "\n"
            )
        ),
        "NUPP2136",
        "callers cannot implement the sealed span contract"
    )
end

function M.spanRefsExposeOnlyTheCapabilityTheirViewOwns()
    local cdecls = table.concat(
        {
            "cdef function read_values(borrows values: const int32*, count: integer)",
            "cdef function write_values(borrows values: int32*, count: integer)",
        },
        "\n"
    )
    assertClean(
        table.concat(
            {
                cdecls,
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[4]>()",
                "do",
                "   local view = spans.fromcarray(storage, 4):slice(2, 3)",
                "   local pointer, count = view:ref()",
                "   read_values(pointer, count)",
                "end",
                "do",
                "   local writable = spans.writecarray(storage, 4)",
                "   do",
                "      local pointer, count = writable:ref()",
                "      write_values(pointer, count)",
                "   end",
                "   writable[1] = 7 as int32",
                "   own.drop(writable)",
                "end",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    cdecls,
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local view = spans.fromcarray(storage, 4)",
                    "local pointer, count = view:ref()",
                    "write_values(pointer, count)",
                },
                "\n"
            )
        ),
        "NUPP2006",
        "a shared span cannot supply a mutable C parameter"
    )
end

function M.writeSpanDowngradesAndRefsHoldItsExclusiveBarrier()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local writable = spans.writecarray(storage, 4)",
                    "local pointer, count = writable:ref()",
                    "own.drop(writable)",
                    "print(pointer ~= nil, count)",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a live mutable ref blocks consuming its writer"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local writable = spans.writecarray(storage, 4)",
                    "local shared = writable:shared()",
                    "writable[1] = 1 as int32",
                    "print(shared[1])",
                    "own.drop(writable)",
                },
                "\n"
            )
        ),
        "NUPP2607 NUPP2602",
        "a shared downgrade blocks mutation and drop"
    )
end

function M.writableSlicesAreAffineChildrenOfTheirWriter()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[6]>()",
                "local writable = spans.writecarray(storage, 6)",
                "do",
                "   local middle = writable:slice(2, 4)",
                "   middle[1] = 11 as int32",
                "   do",
                "      local nested = middle:slice(2, 2)",
                "      nested[1] = 12 as int32",
                "   end",
                "   middle[3] = 13 as int32",
                "end",
                "do",
                "   local empty = writable:slice(4, 3)",
                "   own.drop(empty)",
                "end",
                "writable[6] = 14 as int32",
                "own.drop(writable)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local writable = spans.writecarray(storage, 4)",
                    "local child = writable:slice(2, 3)",
                    "writable[1] = 1 as int32",
                    "print(#child)",
                },
                "\n"
            )
        ),
        "NUPP2607",
        "a live child blocks exclusive parent use"
    )

    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[4]>()",
                "local writable = spans.writefixedcarray(storage, 4)",
                "local child: spans.Writable<int32> = writable:slice(2, 3)",
                "child[1] = 7 as int32",
                "own.drop(child)",
                "own.drop(writable)",
            },
            "\n"
        )
    )
end

function M.commonSpanRangesBorrowEveryInputWithoutBoxingOrConsumption()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local indexed = require(\"binary.span\")",
                "local inputStorage = ffi.new<int32[4]>()",
                "local outputStorage = ffi.new<int32[4]>()",
                "const input = spans.fromfixedcarray(inputStorage, 4)",
                "const output = spans.writefixedcarray(outputStorage, 4)",
                "local indices = indexed.range(1, 4, input, output)",
                "for index = indices.first, indices.last do",
                "   output[index] = input[index]",
                "end",
                "own.drop(output)",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local indexed = require(\"binary.span\")",
                "local storage = ffi.new<int32[1]>()",
                "const view = spans.fromcarray(storage, 1)",
                "local empty = indexed.range(1, 0, view)",
                "print(empty.first, empty.last)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local indexed = require(\"binary.span\")",
                    "const fake = {count = 4}",
                    "local indices = indexed.range(1, 4, fake)",
                    "print(indices.first)",
                },
                "\n"
            )
        ),
        "NUPP2403",
        "an arbitrary count-shaped table cannot forge the sealed contract"
    )
end

function M.heapArraysAreOwnedAndBecomeCheckedSpans()
    assertClean(
        table.concat(
            {
                "local heap = require('nupp.heap')",
                "local values = heap.alloc(ffi.typeof<int32>(), 1000000)",
                "print(values.count)",
                "do",
                "   local writable = values:write()",
                "   writable[1] = 42 as int32",
                "   print(#writable)",
                "   own.drop(writable)",
                "end",
                "local readable = values:read()",
                "local value: int32 = readable[1]",
                "print(value, #readable)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local heap = require('nupp.heap')",
                    "local values = heap.alloc(ffi.typeof<int32>(), 4)",
                    "local readable = values:read()",
                    "local writable = values:write()",
                    "print(#readable, #writable)",
                },
                "\n"
            )
        ),
        "NUPP2607",
        "a live array read blocks a writer"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local heap = require('nupp.heap')",
                    "local values = heap.alloc(ffi.typeof<int32>(), 4)",
                    "local writable = values:write()",
                    "local readable = values:read()",
                    "print(#readable, #writable)",
                },
                "\n"
            )
        ),
        "NUPP2607",
        "a live array writer blocks a reader"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local heap = require('nupp.heap')",
                    "local values = heap.alloc(ffi.typeof<int32>(), 4)",
                    "print(values.pointer)",
                },
                "\n"
            )
        ),
        "NUPP2209",
        "an array's allocation pointer is private"
    )
end

function M.heapArraysPreserveCountsAndCleanUpAtRuntime()
    local source = table.concat(
        {
            "local heap = require('nupp.heap')",
            "local function exercise(count: integer): (integer, int32)",
            "   local values = heap.alloc(ffi.typeof<int32>(), count)",
            "   if count > 0 then",
            "      local writable = values:write()",
            "      writable[count] = 73 as int32",
            "      own.drop(writable)",
            "   end",
            "   local readable = values:read()",
            "   local value: int32 = 0",
            "   if count > 0 then value = readable[count] end",
            "   return #readable, value",
            "end",
            "local zero = exercise(0)",
            "local one, value = exercise(1)",
            "local negative = pcall(function()",
            "   local values = heap.alloc(ffi.typeof<int32>(), -1)",
            "   values:close()",
            "end)",
            "local overflow = pcall(function()",
            "   local values = heap.alloc(ffi.typeof<int32>(), 9007199254740991 as integer)",
            "   values:close()",
            "end)",
            "local fractional = pcall(function()",
            "   local values = heap.alloc(ffi.typeof<int32>(), 1.5 as any)",
            "   values:close()",
            "end)",
            "local unwound = pcall(function()",
            "   local values = heap.alloc(ffi.typeof<int32>(), 2)",
            "   local writable = values:write()",
            "   writable[1] = 1 as int32",
            "   error('unwind')",
            "end)",
            "return zero, one, value, negative, overflow, fractional, unwound",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-heap-array")
    assert(chunk, tostring(loadErr))
    local zero, one, value, negative, overflow, fractional, unwound = chunk()
    testAssert.eq(zero, 0, "zero-length allocation retains count")
    testAssert.eq(one, 1, "one-element allocation retains count")
    testAssert.eq(tonumber(value), 73, "write and read views address the allocation")
    testAssert.eq(negative, false, "negative allocation is rejected")
    testAssert.eq(overflow, false, "overflowing allocation is rejected")
    testAssert.eq(fractional, false, "fractional allocation is rejected")
    testAssert.eq(unwound, false, "error unwinding discharges writer before array")
end

function M.writeSpansProveSiblingPartitionsAndRejectOverlap()
    local prelude = table.concat(
        {
            "local spans = require(\"binary.span\")",
            "local function pair(exclusive a: spans.WriteSpan<int32>, exclusive b: spans.WriteSpan<int32>): nil",
            "   if #a > 0 then a[1] = 1 as int32 end",
            "   if #b > 0 then b[1] = 2 as int32 end",
            "end",
            "local storage = ffi.new<int32[8]>()",
            "local writable = spans.writecarray(storage, 8)",
            "local split = writable:splitat(4)",
        },
        "\n"
    )

    assertClean(prelude .. "\npair(split.left, split.right)")
    testAssert.eq(codes(prelude .. "\npair(split.left, split.left)"), "NUPP2607", "one child is not two regions")
    testAssert.eq(codes(prelude .. "\nwritable[1] = 1 as int32"), "NUPP2607", "a split blocks its parent")
    testAssert.eq(
        codes(
            prelude .. table.concat(
                {"", "local nested = split.left:splitat(2)", "pair(split.left, nested.right)",},
                "\n"
            )
        ),
        "NUPP2607 NUPP2607",
        "an ancestor overlaps its descendant"
    )

    assertClean(
        table.concat(
            {
                prelude,
                "do",
                "   local nested = split.right:splitat(2)",
                "   pair(nested.left, nested.right)",
                "end",
                "pair(split.left, split.right)",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[2]>()",
                "local writable = spans.writecarray(storage, 2)",
                "do",
                "   local split = writable:splitat(1)",
                "   split.left[1] = 1 as int32",
                "end",
                "writable[2] = 2 as int32",
                "own.drop(writable)",
            },
            "\n"
        )
    )
end

function M.exclusiveParametersCanBeForwardedWithoutAStoredBorrow()
    local prelude = table.concat(
        {
            "local spans = require(\"binary.span\")",
            "local function inner(exclusive values: spans.WriteSpan<int32>): nil end",
            "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
            "   inner(values)",
            "end",
        },
        "\n"
    )
    assertClean(prelude)

    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local function inner(exclusive values: spans.WriteSpan<int32>): nil end",
                "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
                "   local element = values[1]",
                "   inner(values)",
                "   print(element)",
                "end",
            },
            "\n"
        )
    )

    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local function inspect(borrows values: spans.WriteSpan<int32>): nil end",
                "local function outer(exclusive values: spans.WriteSpan<int32>): nil",
                "   local element = values[1]",
                "   inspect(values)",
                "   print(element)",
                "end",
            },
            "\n"
        )
    )
end

function M.writeSpanPartitionsKeepCountsOffsetsAndBoundsAtRuntime()
    local source = table.concat(
        {
            "local heap = require('nupp.heap')",
            "local function exercise(mid: integer): (integer, integer, int32, int32)",
            "   local values = heap.alloc(ffi.typeof<int32>(), 4)",
            "   local leftCount: integer = -1 as integer",
            "   local rightCount: integer = -1 as integer",
            -- heap.alloc does not promise zeroed memory, and the assertions below
            -- read an element no split ever writes, so without this they see whatever
            -- was there.
            "   do",
            "      local zeroing = values:write()",
            "      for i = 1, #zeroing do zeroing[i] = 0 as int32 end",
            "      own.drop(zeroing)",
            "   end",
            "   do",
            "      local writable = values:write()",
            "      do",
            "         local split = writable:splitat(mid)",
            "         leftCount, rightCount = #split.left, #split.right",
            "         if #split.left > 0 then split.left[#split.left] = 11 as int32 end",
            "         if #split.right > 0 then split.right[1] = 22 as int32 end",
            "         if #split.right > 1 then",
            "            local nested = split.right:splitat(1)",
            "            nested.right[1] = 33 as int32",
            "         end",
            "      end",
            "      own.drop(writable)",
            "   end",
            "   local readable = values:read()",
            "   return leftCount, rightCount, readable[1], readable[4]",
            "end",
            "local l0, r0 = exercise(0)",
            "local l1, r1 = exercise(1)",
            "local l3, r3 = exercise(3)",
            "local l4, r4, first4, last4 = exercise(4)",
            "local low = pcall(function() exercise(-1) end)",
            "local high = pcall(function() exercise(5) end)",
            "return l0, r0, l1, r1, l3, r3, l4, r4, first4, last4, low, high",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-partitions")
    assert(chunk, tostring(loadErr))
    local l0, r0, l1, r1, l3, r3, l4, r4, first4, last4, low, high = chunk()
    testAssert.eq(table.concat({l0, r0, l1, r1, l3, r3, l4, r4}, ","), "0,4,1,3,3,1,4,0")
    testAssert.eq(tonumber(first4), 0, "an empty right half writes nothing")
    testAssert.eq(tonumber(last4), 11, "the left boundary write reaches the original last element")
    testAssert.eq(low, false, "negative split points raise")
    testAssert.eq(high, false, "split points beyond count raise")
end

function M.tecsShapedColumnsPartitionIntoCheckedNativeKernelInputs()
    assertClean(
        table.concat(
            {
                "local heap = require('nupp.heap')",
                "cdef struct Transform2D",
                "   x: float",
                "   y: float",
                "   rotation: float",
                "   scaleX: float",
                "   scaleY: float",
                "   originX: float",
                "   originY: float",
                "end",
                "cdef function update_transforms(",
                "   borrows values: Transform2D* countedBy(count), count: uint64",
                ")",
                "local column = heap.alloc(ffi.typeof<Transform2D>(), 1024)",
                "do",
                "   local writable = column:write()",
                "   do",
                "      local halves = writable:splitat(512)",
                "      update_transforms(halves.left)",
                "      update_transforms(halves.right)",
                "   end",
                "   own.drop(writable)",
                "end",
                "local readable = column:read()",
                "print(#readable)",
            },
            "\n"
        )
    )
end

function M.borrowedCArrayIndexingStillNeedsABound()
    testAssert.eq(
        codes(
            table.concat(
                {"local text = 'bytes'", "local pointer = ffi.cast<const uint8[?]>(text)", "local byte = pointer[0]",},
                "\n"
            )
        ),
        "NUPP2604"
    )
end

function M.aFixedCArrayAdmitsOnlyAStaticallyInBoundsIndex()
    assertClean(table.concat({"local bytes = ffi.new<uint8[4]>()", "bytes[3] = 1",}, "\n"))
    testAssert.eq(codes(table.concat({"local bytes = ffi.new<uint8[4]>()", "bytes[4] = 1",}, "\n")), "NUPP2604")
end

-- A result declared `borrows p` is tied to the argument passed for p: that
-- argument cannot be released while the result is live, and the result cannot
-- outlive it. `borrows self` says the same about a method's receiver, which is
-- what lets a container hand out an element without giving up ownership.

local POOL = table.concat(
    {
        "local record Res",
        "   name: string",
        "end",
        "local record Pool",
        "   items: {Res}",
        "end",
        "local function close_pool(takes p: Pool): nil end",
        "local function open_pool(): affine(Pool, close_pool)",
        "   return new Pool(items = {})",
        "end",
        "function Pool:get(index: integer): Res borrows (self)",
        "   return self.items[index]",
        "end",
        "local function peek(borrows p: Pool): Pool borrows (p)",
        "   return p",
        "end",
    },
    "\n"
)

local ITERATOR_BORROWS = table.concat(
    {
        "local record Iterated",
        "   value: integer",
        "end",
        "@comptime local function IterationResult(T: type, mode: string): typepack",
        "   return types.pack({T}, nil, {mode})",
        "end",
        "local record Cursor",
        "   next: function(): unpackof IterationResult(Iterated, 'borrowed')",
        "   nextExclusive: function(): unpackof IterationResult(Iterated, 'exclusive')",
        "end",
        "local function closeCursor(takes cursor: Cursor): nil end",
        "local function openCursor(): affine(Cursor, closeCursor)",
        "   return new Cursor(next = nil as any, nextExclusive = nil as any)",
        "end",
        "local function inspectCursor(borrows cursor: Cursor): nil end",
    },
    "\n"
)

function M.genericForBorrowsItsIteratorForEachBody()
    testAssert.eq(
        codes(
            ITERATOR_BORROWS .. table.concat(
                {
                    "",
                    "local cursor = openCursor()",
                    "for value in cursor.next do",
                    "   own.drop(cursor)",
                    "   print(value.value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.genericForReleasesIterationBorrowsOnEveryExit()
    assertClean(
        ITERATOR_BORROWS .. table.concat(
            {
                "",
                "local cursor = openCursor()",
                "for value in cursor.next do",
                "   if value.value == 1 then",
                "      continue",
                "   end",
                "   break",
                "end",
                "own.drop(cursor)",
            },
            "\n"
        )
    )
end

function M.exclusiveIteratorResultsBlockSharedUseOfTheirRoot()
    testAssert.eq(
        codes(
            ITERATOR_BORROWS .. table.concat(
                {
                    "",
                    "local cursor = openCursor()",
                    "for value in cursor.nextExclusive do",
                    "   inspectCursor(cursor)",
                    "   print(value.value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2607"
    )
end

function M.aBorrowedResultBlocksReleasingItsSource()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {"", "local pool = open_pool()", "local held = peek(pool)", "own.drop(pool)", "print(held.items)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.aMethodResultCanBorrowTheReceiver()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {"", "local pool = open_pool()", "local item = pool:get(1)", "own.drop(pool)", "print(item.name)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.aBorrowedResultIsReleasedWithItsScope()
    assertClean(
        POOL .. table.concat(
            {
                "",
                "local pool = open_pool()",
                "do",
                "   local item = pool:get(1)",
                "   print(item.name)",
                "end",
                "own.drop(pool)",
            },
            "\n"
        )
    )
end

function M.anElementCanBeBorrowedThroughAnAutomaticOwner()
    assertClean(
        POOL .. table.concat(
            {
                "",
                "local function use(): string",
                "   do",
                "      local pool = open_pool()",
                "      local item = pool:get(1)",
                "      return item.name",
                "   end",
                "end",
            },
            "\n"
        )
    )
end

function M.aBorrowedResultCannotOutliveItsSource()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local function leak(): Pool",
                    "   do",
                    "      local pool = open_pool()",
                    "      return peek(pool)",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

function M.borrowingAConsumedParameterIsRejected()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {"", "local function eat(takes p: Pool): Pool borrows (p)", "   return p", "end",},
                "\n"
            )
        ),
        "NUPP2618 NUPP2603"
    )
end

function M.borrowingSomethingThatIsNotAParameterIsRejected()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {"", "local function odd(borrows p: Pool): Pool borrows (q)", "   return p", "end",},
                "\n"
            )
        ),
        "NUPP2109"
    )
end

function M.returningABorrowStillNeedsTheAnnotation()
    testAssert.eq(
        codes(POOL .. table.concat({"", "local function sneak(borrows p: Pool): Pool", "   return p", "end",}, "\n")),
        "NUPP2608"
    )
end

-- A borrow relation is linear flow information the way a preservation relation
-- is: a callable that forgets one lets its caller lose the root and read what the
-- source freed. Callable assignment therefore keeps the relation exactly.
function M.aCallableSlotCannotForgetABorrowRelation()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local f: function(borrows p: Pool): Pool = peek",
                    "local pool = open_pool()",
                    "local v = f(pool)",
                    "own.drop(pool)",
                    "print(v ~= nil)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local f: function(borrows p: Pool): Pool borrows (p) = peek",
                    "local pool = open_pool()",
                    "local v = f(pool)",
                    "own.drop(pool)",
                    "print(v ~= nil)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
    assertClean(
        POOL .. table.concat(
            {
                "",
                "local f: function(borrows p: Pool): Pool borrows (p) = peek",
                "local pool = open_pool()",
                "do",
                "   local v = f(pool)",
                "   print(v ~= nil)",
                "end",
                "own.drop(pool)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local function plain(borrows p: Pool): Pool return p end",
                    "local f: function(borrows p: Pool): Pool borrows (p) = plain",
                },
                "\n"
            )
        ),
        "NUPP2608 NUPP2001"
    )
end

-- Borrowing a borrow needs no separate machinery: a borrow can only be bound
-- in the scope that creates it — it cannot be assigned outward, stored, or
-- returned without a declaration — so a derived borrow can never outlive the
-- one it came from, and the intermediate keeps the root borrowed meanwhile.

-- On a method there is only one thing a source-less borrow could mean, so
-- A borrowed method result elides to `borrows self`, the way Rust elides an output
-- lifetime to `&self`. The result is still explicitly a borrow, so nothing
-- returning a plain value is affected.

-- An owning result may also retain a borrow of its input, which is what a
-- layered resource is: the session owns itself and holds the socket, so the
-- socket cannot be released until the session is.

local LAYERED = table.concat(
    {
        "local record Socket",
        "   fd: integer",
        "end",
        "local record TLS",
        "   s: Socket",
        "end",
        "local function close_socket(takes s: Socket): nil end",
        "local function close_tls(takes t: TLS): nil end",
        "local function open_socket(): affine(Socket, close_socket)",
        "   return new Socket(fd = 1)",
        "end",
        "local function open_tls(borrows s: Socket): affine(TLS, close_tls) borrows (s)",
        "   return new TLS(s = s)",
        "end",
    },
    "\n"
)

function M.anOwningResultCanRetainAnInputBorrow()
    assertClean(
        LAYERED .. table.concat(
            {"", "local sock = open_socket()", "local tls = open_tls(sock)", "own.drop(tls)", "own.drop(sock)",},
            "\n"
        )
    )
end

function M.theHeldSourceCannotBeReleasedFirst()
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {"", "local sock = open_socket()", "local tls = open_tls(sock)", "own.drop(sock)", "own.drop(tls)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- Reverse automatic cleanup releases the session before the socket, which is exactly
-- the order the borrow requires.
function M.layeredResourcesHoldTogetherInAScope()
    assertClean(
        LAYERED .. table.concat(
            {
                "",
                "local function use()",
                "   do",
                "      local sock = open_socket()",
                "      local tls = open_tls(sock)",
                "      print(tls.s.fd)",
                "   end",
                "end",
            },
            "\n"
        )
    )
end

function M.anOwningResultThatBorrowsIsStillOwned()
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {"", "local sock = open_socket()", "local tls = open_tls(sock)", "own.drop(sock)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.aMethodBorrowedReturnElidesToTheReceiver()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "function Pool:first(): Res borrows (self)",
                    "   return self.items[1]",
                    "end",
                    "local pool = open_pool()",
                    "local item = pool:first()",
                    "own.drop(pool)",
                    "print(item.name)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- A generic for is handed an iterator, a state and a control variable, so a function
-- that gives a loop something it only borrows puts that borrow in the second result.
-- The relation used to be readable on the first result alone: a clause anywhere else
-- was parsed and dropped, and the return then reported NUPP2608 with help naming the
-- clause that was already written.
function M.aBorrowedResultMayBeAnyResult()
    assertClean(
        POOL .. table.concat(
            {
                "",
                "local function walk(borrows p: Pool): (function(Pool, integer): (integer, Res), Pool borrows (p), integer)",
                "   return function(source: Pool, index: integer): (integer, Res)",
                "      return index + 1, source.items[index]",
                "   end, p, 0",
                "end",
                "local pool = open_pool()",
                "for index, item in walk(pool) do",
                "   print(index, item.name)",
                "end",
                "own.drop(pool)",
            },
            "\n"
        )
    )
end

-- The relation states one position, so it holds that position and no other.
function M.aBorrowedResultHoldsOnlyItsOwnSlot()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local function both(borrows p: Pool): (Pool, Pool borrows (p))",
                    "   return p, p",
                    "end",
                    "print(both)",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

-- One callable records one borrow relation, so two of them are refused rather than
-- silently keeping the first. The second clause having been refused, returning that
-- result's borrow is an unbacked one, which is the NUPP2608 beside it.
function M.onlyOneResultMayDeclareABorrow()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local function pair(borrows left: Pool, borrows right: Pool): (Pool borrows (left), Pool borrows (right))",
                    "   return left, right",
                    "end",
                    "print(pair)",
                },
                "\n"
            )
        ),
        "NUPP2621 NUPP2608"
    )
end

-- A borrow in a later slot is still tied to its owner at the call site, so binding it
-- and dropping the owner underneath it is caught where a first-slot borrow would be.
function M.aLaterBorrowedResultStillOutlivesNothing()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local function view(borrows p: Pool): (integer, Pool borrows (p))",
                    "   return 0, p",
                    "end",
                    "local pool = open_pool()",
                    "local count, held = view(pool)",
                    "own.drop(pool)",
                    "print(count, held.items)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- The member type callers read was derived from the annotations before the body was
-- checked, and that pass never worked out what a `borrows` result borrows from. The
-- result kept its qualifier and lost its source, so a call had nothing to tie the value
-- to and handed back the raw one, which reported at the first dereference instead of at
-- the method.
function M.anInlineMethodsBorrowedResultKeepsItsSource()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local record Holder",
                    "   items: {Res}",
                    "   function first(self): Res borrows (self)",
                    "      return self.items[1]",
                    "   end",
                    "end",
                    "local function close_holder(takes h: Holder): nil end",
                    "local function open_holder(): affine(Holder, close_holder) return new Holder(items = {}) end",
                    "local h = open_holder()",
                    "local item = h:first()",
                    "own.drop(h)",
                    "print(item.name)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- The same method declared and defined apart, which always carried its source. Both
-- spellings have to agree, since the difference is where the body is written.
function M.aDeclaredMethodsBorrowedResultKeepsItsSource()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local record Holder",
                    "   items: {Res}",
                    "   first: function(self: Holder): Res borrows (self)",
                    "end",
                    "function Holder.first(self): Res borrows (self)",
                    "   return self.items[1]",
                    "end",
                    "local function close_holder(takes h: Holder): nil end",
                    "local function open_holder(): affine(Holder, close_holder) return new Holder(items = {}) end",
                    "local h = open_holder()",
                    "local item = h:first()",
                    "own.drop(h)",
                    "print(item.name)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.aMethodReturningAPlainValueDoesNotBorrow()
    assertClean(
        POOL .. table.concat(
            {
                "",
                "function Pool:count(): integer",
                "   return #self.items",
                "end",
                "local pool = open_pool()",
                "local n = pool:count()",
                "own.drop(pool)",
                "print(n)",
            },
            "\n"
        )
    )
end

function M.anExplicitSourceStillWinsOverElision()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {"", "function Pool:other(borrows p: Pool): Res borrows (p)", "   return p.items[1]", "end",},
                "\n"
            )
        ),
        ""
    )
end

function M.aChainOfBorrowsStillHoldsTheRoot()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local pool = open_pool()",
                    "local first = peek(pool)",
                    "local second = peek(first)",
                    "own.drop(pool)",
                    "print(second.items)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.aDerivedBorrowCannotOutliveItsIntermediate()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local pool = open_pool()",
                    "local held = peek(pool)",
                    "do",
                    "   local inner = peek(pool)",
                    "   held = peek(inner)",
                    "end",
                    "own.drop(pool)",
                },
                "\n"
            )
        ),
        -- `held` still borrows the pool when the pool is dropped: the rebinding
        -- inside the block does not end the loan the declaration holds.
        "NUPP2608 NUPP2602"
    )
end

function M.aDerivedBorrowCannotBeStored()
    testAssert.eq(
        codes(
            POOL .. table.concat(
                {
                    "",
                    "local pool = open_pool()",
                    "local sink: {Pool} = {}",
                    "local first = peek(pool)",
                    "sink[1] = peek(first)",
                    "own.drop(pool)",
                },
                "\n"
            )
        ),
        "NUPP2603 NUPP2602"
    )
end

-- The declaration is the contract: a result declared `borrows p` may be
-- derived through any number of intermediates, and the checker takes the
-- annotation's word for what it roots at, exactly as it does for an owning result.
function M.aBorrowMayBeDerivedThroughAnIntermediate()
    assertClean(
        POOL .. table.concat(
            {
                "",
                "local function deep(borrows p: Pool): Pool borrows (p)",
                "   local mid = peek(p)",
                "   return peek(mid)",
                "end",
            },
            "\n"
        )
    )
end

function M.liveDroppableOwnersAreDestroyedAutomatically()
    testAssert.eq(codes(RESOURCE .. "\nlocal value = resource_new()"), "")
    testAssert.eq(codes(RESOURCE .. "\nresource_new()"), "NUPP2605")
end

function M.opaqueOwnersAreTransferOnly()
    local opaque = table.concat(
        {
            "cdef function resource_new_c(): voidptr",
            "local function resource_new(): affine(voidptr)",
            "   return resource_new_c()",
            "end",
            "cdef function resource_take(takes value: voidptr)",
        },
        "\n"
    )
    assertClean(opaque .. "\nlocal value = resource_new()\nresource_take(value)")
    testAssert.eq(codes(opaque .. "\nlocal value = resource_new()\nown.drop(value)"), "NUPP2602")
end

function M.affineUsesItsExactCleanupFunction()
    local source = table.concat(
        {
            "local calls = ''",
            "local record File",
            "   closed: boolean",
            "   function drop(takes self): nil",
            "      calls = calls .. 'close'",
            "      self.closed = true",
            "   end",
            "end",
            "local function closeFile(takes file: File): nil",
            "   calls = calls .. 'close'",
            "   file.closed = true",
            "   @unsafe do local _raw = @unsafe own.release(file) end",
            "end",
            "local function openFile(): affine(File, closeFile)",
            "   return new File(closed = false)",
            "end",
            "local file = openFile()",
            "own.drop(file)",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-default-drop")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "close", "default drop operation runs")
end

function M.anExplicitDropAfterACallIsASeparateStatement()
    local source = table.concat(
        {
            "local calls = ''",
            "local record File",
            "   function drop(takes self): nil calls = calls .. 'stop' end",
            "end",
            "local function closeFile(takes file: File): nil @unsafe do local _raw = @unsafe own.release(file) end end",
            "local function openFile(): affine(File, closeFile) return new File() end",
            "local file = openFile()",
            "print('before')",
            "file:drop()",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-explicit-drop")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "stop", "the terminal call runs once after another call statement")
end

function M.aCleanupFunctionCanBeConstrainedByAnInterface()
    assertClean(
        table.concat(
            {
                "local interface Closeable",
                "   drop: @nosuspend function(takes value: self): nil",
                "end",
                "local record File is Closeable",
                "   closed: boolean",
                "end",
                "function File.drop(takes self): nil self.closed = true end",
                "local function close<T is Closeable>(takes value: T): nil value:drop() end",
                "local function openFile(): affine(File, close)",
                "   return new File(closed = false)",
                "end",
                "do local file = openFile(); print(file.closed) end",
            },
            "\n"
        )
    )
end

function M.ownedFieldsApplyToEveryOverload()
    assertClean(
        table.concat(
            {
                "local record File",
                "   function drop(takes self): nil end",
                "end",
                "local function closeFile(takes file: File): nil @unsafe do local _raw = @unsafe own.release(file) end end",
                "local record Library",
                "   open: function(name: string): affine(File, closeFile) & function(id: integer): affine(File, closeFile)",
                "end",
                "local library = nil as any as Library",
                "do local named = library.open('name') end",
                "do local numbered = library.open(1) end",
            },
            "\n"
        )
    )
end

-- Field access reads an owner through its qualifier, and method calls did not, so
-- a misspelled method on an owned structural handle reported nothing at all. The
-- terminal is still reached through the qualifier rather than found on the shape,
-- which is why the cleanup's own name stays exempt.
function M.aMisspelledMethodOnAnOwnedShapeIsReported()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local type Handle = {run: function(held: any, value: integer): integer}",
                    "local function shut(takes self: Handle): nil end",
                    "local function make(): affine(Handle, shut) return nil as any end",
                    "local held = make()",
                    "print(held:missing())",
                },
                "\n"
            )
        ),
        "NUPP2004"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local type Handle = {run: function(held: any, value: integer): integer}",
                    "local function shut(takes self: Handle): nil end",
                    "local function make(): affine(Handle, shut) return nil as any end",
                    "local held = make()",
                    "print(held:run(1))",
                },
                "\n"
            )
        ),
        "",
        "a declared method still resolves through the qualifier"
    )
end

-- A borrowed nominal took the owned-nominal exemption, so any method name on a
-- `borrows` parameter checked clean and answered `any`. A borrow owns nothing and
-- has no terminal to reach, so it answers only the record's own methods.
function M.aMisspelledMethodOnABorrowedRecordIsReported()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record R",
                    "    x: integer",
                    "    function bump(self: R): integer return self.x + 1 end",
                    "end",
                    "local function use(borrows r: R): nil print(r:missing(1)) end",
                    "return use",
                },
                "\n"
            )
        ),
        "NUPP2004"
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record R",
                    "    x: integer",
                    "    function bump(self: R): integer return self.x + 1 end",
                    "end",
                    "local function use(borrows r: R): nil print(r:bump()) end",
                    "return use",
                },
                "\n"
            )
        ),
        "",
        "a declared method still resolves through a borrow"
    )
end

function M.affineRejectsMissingAndInexactCleanupFunctions()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record File",
                    "   closed: boolean",
                    "end",
                    "local function openFile(): affine(File, missingCleanup) return new File(closed = false) end",
                },
                "\n"
            )
        ),
        "NUPP2131"
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record File",
                    "   closed: boolean",
                    "end",
                    "local function closeFile(file: File): nil end",
                    "local function openFile(): affine(File, closeFile) return new File(closed = false) end",
                },
                "\n"
            )
        ),
        "NUPP2615"
    )
end

function M.anAffineCleanupBindingMayNotBeReassigned()
    -- The terminal is part of the type's identity, so the name has to be that
    -- function wherever an owner is discharged. Reassigning it anywhere in the file
    -- would hijack every later cleanup, however the name read where the type was
    -- written.
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record File end",
                    "local function closeFile(takes file: File): nil end",
                    "local function openFile(): affine(File, closeFile) return new File() end",
                    "closeFile = function(takes file: File): nil end",
                },
                "\n"
            )
        ),
        "NUPP2131"
    )
    assertClean(
        table.concat(
            {
                "local record File end",
                "local function closeFile(takes file: File): nil end",
                "local function openFile(): affine(File, closeFile) return new File() end",
                "local other = closeFile",
            },
            "\n"
        )
    )
end

function M.aCallbackOnlyInvokedIsInferredScoped()
    -- A visible body that only ever calls its callback promises what `scoped` spells,
    -- and the promise reaches the call: a closure borrowing an owner may be handed
    -- to it, because the callback cannot outlive the call.
    local resource = table.concat(
        {
            "local record Res name: string end",
            "local function close(takes r: Res): nil end",
            "local function open(name: string): affine(Res, close) return new Res(name = name) end",
        },
        "\n"
    )
    assertClean(
        resource .. table.concat(
            {
                "",
                "local function run(cb: function(): nil): nil",
                "   cb()",
                "end",
                "local function body(): nil",
                "   local r = open('a')",
                "   run(function(): nil borrows (r) print(r.name) end)",
                "   own.drop(r)",
                "end",
            },
            "\n"
        )
    )
    -- One that lets the callback out keeps the plain reading, and the borrow is
    -- refused as it always was.
    testAssert.eq(
        codes(
            resource .. table.concat(
                {
                    "",
                    "local kept: (function(): nil)? = nil",
                    "local function keep(cb: function(): nil): nil",
                    "   kept = cb",
                    "   cb()",
                    "end",
                    "local function body(): nil",
                    "   local r = open('a')",
                    "   keep(function(): nil borrows (r) print(r.name) end)",
                    "   own.drop(r)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

-- A declared scoped callback was counted as invoked directly when the invocation
-- sat inside a nested closure, which may be stored and run after the call has
-- returned, so the borrow the callback carried outlived its owner.
function M.aDeclaredScopedCallbackCannotEscapeThroughANestedClosure()
    local resource = table.concat(
        {
            "local record Res name: string end",
            "local function close(takes r: Res): nil end",
            "local function open(name: string): affine(Res, close) return new Res(name = name) end",
            "local stash: function(): nil = function(): nil end",
        },
        "\n"
    )
    testAssert.eq(
        codes(
            resource .. table.concat(
                {
                    "",
                    "local function run(scoped cb: function(): nil): nil",
                    "   stash = function(): nil",
                    "      cb()",
                    "   end",
                    "   cb()",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a nested closure"
    )
    testAssert.eq(
        codes(
            resource .. table.concat(
                {
                    "",
                    "local function run(scoped cb: function(): nil): nil",
                    "   local function step(): nil",
                    "      cb()",
                    "   end",
                    "   step()",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a nested local function"
    )
    assertClean(
        resource .. table.concat(
            {
                "",
                "local function run(scoped cb: function(): nil): nil",
                "   stash = function(): nil print('later') end",
                "   cb()",
                "end",
                "local function body(): nil",
                "   local r = open('a')",
                "   run(function(): nil borrows (r) print(r.name) end)",
                "   own.drop(r)",
                "end",
            },
            "\n"
        )
    )
end

function M.affineTerminalsMustTakeTheirResource()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record File end",
                    "local function closeFile(borrows file: File): nil end",
                    "local type FileOwner = affine(File, closeFile)",
                },
                "\n"
            )
        ),
        "NUPP2615"
    )
end

function M.ownershipQualifiersAndParameterModesAreTyped()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function inspect(borrows value: resource*): int32",
                "   return value.value",
                "end",
                "local value: affine(resource*, resource_free) = resource_new()",
                "inspect(value)",
                "resource_free(value)",
            },
            "\n"
        )
    )
end

function M.readOnlyHelpersInferBorrowContracts()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function inspect(value: resource*): int32",
                "   return value.value",
                "end",
                "local value = resource_new()",
                "do",
                "   local view = borrow(value)",
                "   inspect(view)",
                "end",
                "resource_free(value)",
            },
            "\n"
        )
    )
end

function M.escapingHelpersCannotLaunderBorrows()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local saved: resource*?",
                    "local function stash(value: resource*)",
                    "   saved = value",
                    "end",
                    "local value = resource_new()",
                    "do",
                    "   local view = borrow(value)",
                    "   stash(view)",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.explicitBorrowContractsPinEscapeErrorsToTheBody()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local saved: resource*?",
                    "local function stash(borrows value: resource*)",
                    "   saved = value",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

function M.sharedBorrowsPermitStableMutation()
    assertClean(
        RESOURCE .. table.concat(
            {"", "local function rename(borrows value: resource*)", "   value.value = 1", "end",},
            "\n"
        )
    )
end

function M.exclusiveRequiresCallDurationExclusivity()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function reset(exclusive value: resource*)",
                    "   value.value = 0",
                    "end",
                    "local value = resource_new()",
                    "do",
                    "   local view = borrow(value)",
                    "   reset(value)",
                    "   print(view.value)",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2607"
    )

    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function reset(exclusive value: resource*)",
                "   value.value = 0",
                "end",
                "local value = resource_new()",
                "do",
                "   local view = borrow(value)",
                "   reset(view)",
                "end",
                "resource_free(value)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function reset(exclusive value: resource*)",
                    "   value.value = 0",
                    "end",
                    "local value = resource_new()",
                    "do",
                    "   local first = borrow(value)",
                    "   local second = borrow(value)",
                    "   reset(first)",
                    "   print(second.value)",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2607"
    )
end

function M.consumeMovesAndRejectsLaterUse()
    local source = RESOURCE .. table.concat(
        {"", "local value = resource_new()", "resource_free(value)", "print(value)",},
        "\n"
    )
    testAssert.eq(codes(source), "NUPP2601")
    local _, diags = checked(source)
    testAssert.eq(#(diags[1].related or {}), 1, "move origin is attached")
    testAssert.eq(diags[1].related[1].message, "owner was moved here")
    assert(diags[1].help and diags[1].help:find("borrow", 1, true), "move diagnostic explains the alternative")
end

function M.doubleConsumeIsRejected()
    local got = codes(
        RESOURCE .. table.concat(
            {"", "local value = resource_new()", "resource_free(value)", "resource_free(value)",},
            "\n"
        )
    )
    assert(got:find("NUPP2601", 1, true), "double consume reports a move: " .. got)
end

function M.movesInsideNarrowedBranchesReachTheOuterOwner()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local value = resource_new()",
                    "if value then",
                    "   resource_free(value)",
                    "end",
                    "print(value)",
                },
                "\n"
            )
        ),
        "NUPP2601"
    )
end

function M.nullableOwnersNarrowWithoutLosingOwnership()
    assertClean(
        table.concat(
            {
                "cdef struct maybe_resource",
                "   value: int32",
                "end",
                "cdef function free(takes value: maybe_resource*)",
                "cdef function maybe_new_c(): maybe_resource*?",
                "local function maybe_new(): affine(maybe_resource*?, free)",
                "   return maybe_new_c()",
                "end",
                "local value = maybe_new()",
                "if value then",
                "   print(value.value)",
                "   own.drop(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.assignmentMovesAndProtectsLiveOwners()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {"", "local first = resource_new()", "local second = first", "print(first)", "resource_free(second)",},
                "\n"
            )
        ),
        "NUPP2601"
    )
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local first = resource_new()",
                    "local second = resource_new()",
                    "second = first",
                    "resource_free(second)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.ownershipCannotDisappearIntoRawAnnotations()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {"", "local ownedValue = resource_new()", "local rawValue: resource* = ownedValue",},
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.ownershipQualifiersSupportManagedValuesButPinsRequirePointers()
    testAssert.eq(
        codes(
            table.concat(
                {"local function closeText(takes value: string): nil end", "local value: affine(number, closeText)",},
                "\n"
            )
        ),
        "NUPP2615"
    )
    testAssert.eq(codes("local value: affine(number)"), "")
    testAssert.eq(codes("local value: Borrowed<string>"), "NUPP2101")
    testAssert.eq(codes("local value: pinned(boolean)"), "NUPP2602")
end

function M.liveBorrowPreventsMoveUntilScopeEnds()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local value = resource_new()",
                    "do",
                    "   local view = borrow(value)",
                    "   resource_free(value)",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local value = resource_new()",
                "do",
                "   local view = borrow(value)",
                "   print(view.value)",
                "end",
                "resource_free(value)",
            },
            "\n"
        )
    )
end

function M.borrowedValuesCannotEscape()
    local returned = RESOURCE .. table.concat(
        {"", "local function bad(borrows value: resource*): resource*", "   return value", "end",},
        "\n"
    )
    testAssert.eq(codes(returned), "NUPP2608")

    local stored = RESOURCE .. table.concat(
        {
            "",
            "local value = resource_new()",
            "do",
            "   local view = borrow(value)",
            "   local box = { value = view }",
            "end",
            "resource_free(value)",
        },
        "\n"
    )
    testAssert.eq(codes(stored), "NUPP2603")
end

function M.aBorrowingClosureCannotEraseProvenanceOnReturn()
    local got = codes(
        RESOURCE .. table.concat(
            {
                "",
                "local function callback(borrows value: resource*): function(): int32",
                "   return function(): int32",
                "      return value.value",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(got, "NUPP2608")
end

function M.rawReconstructionRequiresUnsafe()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local raw = resource_create()",
                "local value = @unsafe own.adopt<affine(resource*, resource_free)>(raw)",
                "resource_free(value)",
            },
            "\n"
        )
    )

    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local raw = resource_create()",
                "@unsafe do",
                "   local value = @unsafe own.adopt<affine(resource*, resource_free)>(raw)",
                "   own.drop(value)",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local raw: voidptr = nil as any",
                    "local function wrong(takes value: string): nil end",
                    "@unsafe do",
                    "   local value = @unsafe own.adopt<affine(voidptr, wrong)>(raw)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2615"
    )
end

function M.ownershipCallsReplaceAdoptReleaseAndDropSyntax()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local raw = resource_create()",
                "local value = @unsafe own.adopt<affine(resource*, resource_free)>(raw)",
                "local restored = @unsafe own.release(value)",
                "local again = @unsafe own.adopt<affine(resource*, resource_free)>(restored)",
                "own.drop(again)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            RESOURCE
            .. "\nlocal raw = resource_create()\nlocal value = own.adopt<affine(resource*, resource_free)>(raw)"
        ),
        "NUPP2604"
    )
end

function M.rawAbandonmentRequiresUnsafe()
    assertClean(
        RESOURCE .. table.concat(
            {"", "local value = resource_new()", "local raw = @unsafe own.release(value)", "print(raw)",},
            "\n"
        )
    )
end

function M.unsafeDoesNotSuppressOwnershipObligations()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local value = resource_new()",
                    "@unsafe do",
                    "   local box = {value = value}",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )

    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local value = resource_new()",
                    "@unsafe do",
                    "   ffi.cast<voidptr>(value)",
                    "end",
                    "resource_free(value)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.bodyfulBorrowContractsNeedProvenanceProof()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function fake(borrows source: resource*, raw: resource*): resource* borrows (source)",
                    "   return raw",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2619"
    )
end

function M.borrowFromRestoresOpaqueProvenanceExplicitly()
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function recover(borrows source: resource*, raw: resource*): resource* borrows (source)",
                "   @unsafe do",
                "      return borrowFrom(raw, source)",
                "   end",
                "end",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function recover(borrows source: resource*, raw: resource*): resource* borrows (source)",
                    "   return borrowFrom(raw, source)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2604"
    )
end

function M.borrowedResultsCanNameMultipleSources()
    local source = RESOURCE .. table.concat(
        {
            "",
            "local record Pair",
            "   left: resource*",
            "   right: resource*",
            "end",
            "local function closePair(takes pair: Pair): nil end",
            "local function pair(borrows left: resource*, borrows right: resource*)",
            "   : affine(Pair, closePair) borrows(left, right)",
            "   return new Pair(left = left, right = right)",
            "end",
        },
        "\n"
    )
    assertClean(
        source .. table.concat(
            {
                "",
                "local left = resource_new()",
                "local right = resource_new()",
                "local joined = pair(left, right)",
                "own.drop(joined)",
                "resource_free(right)",
                "resource_free(left)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            source .. table.concat(
                {
                    "",
                    "local left = resource_new()",
                    "local right = resource_new()",
                    "local joined = pair(left, right)",
                    "resource_free(left)",
                    "own.drop(joined)",
                    "resource_free(right)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.affineRecordsDropOwnedFieldsInReverseOrder()
    local source = table.concat(
        {
            "local calls = ''",
            "local record Res",
            "   name: string",
            "end",
            "local function closeRes(takes value: Res): nil",
            "   calls = calls .. value.name",
            "end",
            "local function openRes(name: string): affine(Res, closeRes)",
            "   return new Res(name = name)",
            "end",
            "local record Bundle",
            "   first: affine(Res, closeRes)",
            "   second: affine(Res, closeRes)",
            "end",
            "local bundle = new Bundle(first = openRes('a'), second = openRes('b'))",
            "own.drop(bundle)",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-affine-record")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "ba", "fields close in reverse declaration order")
end

function M.affineRecordsTrackPartialFieldMoves()
    assertClean(
        table.concat(
            {
                "local record Res end",
                "local function closeRes(takes value: Res): nil end",
                "local function openRes(): affine(Res, closeRes) return new Res() end",
                "local record Bundle",
                "   value: affine(Res, closeRes)",
                "end",
                "local bundle = new Bundle(value = openRes())",
                "local value = bundle.value",
                "own.drop(value)",
                "own.drop(bundle)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Res end",
                    "local function closeRes(takes value: Res): nil end",
                    "local function openRes(): affine(Res, closeRes) return new Res() end",
                    "local record Bundle",
                    "   value: affine(Res, closeRes)",
                    "end",
                    "local bundle = new Bundle(value = openRes())",
                    "local value = bundle.value",
                    "print(bundle.value)",
                    "own.drop(value)",
                    "own.drop(bundle)",
                },
                "\n"
            )
        ),
        "NUPP2601"
    )
end

function M.customDropOperationsMustDischargeEveryOwnedField()
    local prefix = table.concat(
        {
            "local record Res end",
            "local function closeRes(takes value: Res): nil end",
            "local function openRes(): affine(Res, closeRes) return new Res() end",
        },
        "\n"
    )
    assertClean(
        prefix .. "\n" .. table.concat(
            {
                "local record Bundle",
                "   first: affine(Res, closeRes)",
                "   second: affine(Res, closeRes)",
                "   function drop(takes self): nil",
                "      closeRes(self.second)",
                "      closeRes(self.first)",
                "   end",
                "end",
                "local bundle = new Bundle(first = openRes(), second = openRes())",
                "own.drop(bundle)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            prefix .. "\n" .. table.concat(
                {
                    "local record Bundle",
                    "   first: affine(Res, closeRes)",
                    "   second: affine(Res, closeRes)",
                    "   function drop(takes self): nil",
                    "      closeRes(self.second)",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.contextualCleanupUsesExplicitOwnerFields()
    local source = table.concat(
        {
            "local released = ''",
            "local record Arena",
            "   name: string",
            "end",
            "local record Allocation",
            "   arena: Arena",
            "   value: string",
            "   function drop(takes self): nil",
            "      released = self.arena.name .. ':' .. self.value",
            "   end",
            "end",
            "local function releaseAllocation(takes allocation: Allocation): nil",
            "   released = allocation.arena.name .. ':' .. allocation.value",
            "   @unsafe do local _raw = @unsafe own.release(allocation) end",
            "end",
            "local function allocate(arena: Arena, value: string): affine(Allocation, releaseAllocation)",
            "   return new Allocation(arena = arena, value = value)",
            "end",
            "local arena = new Arena(name = 'frame')",
            "local allocation = allocate(arena, 'buffer')",
            "own.drop(allocation)",
            "return released",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-context")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "frame:buffer", "the drop operation reads its explicit context")
end

function M.rawCoroutinesCannotSuspendTemporalObligations()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   coroutine.yield()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function pause(borrows value: resource*)",
                    "   coroutine.yield()",
                    "   print(value.value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    assertClean(table.concat({"local function pause()", "   coroutine.yield()", "end",}, "\n"))
end

function M.aRawYieldThroughAnAliasIsRefused()
    -- `local co = coroutine` is common enough that leaving it unrecognized would be a
    -- hole anyone falls into by accident.
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local co = coroutine",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   co.yield()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.aRawYieldThroughAChainOfAliasesIsRefused()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local co = coroutine",
                    "local also = co",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   also.yield()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.aRawYieldThroughAHelperIsRefused()
    -- The helper is where the yield is written; the obligation is live at its
    -- caller. Nobody is responsible for the abandoned continuation either way, so
    -- the helper's summary answers for the call, one hop or several away.
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local function pause()",
                    "   coroutine.yield()",
                    "end",
                    "local function rest()",
                    "   pause()",
                    "end",
                    "local function body()",
                    "   local value = resource_new()",
                    "   rest()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    -- With nothing live at the call, the helper is free to yield.
    assertClean(
        table.concat(
            {"local function pause()", "   coroutine.yield()", "end", "local function body()", "   pause()", "end",},
            "\n"
        )
    )
end

function M.aHandledSuspensionThroughAHelperIsAllowed()
    -- A handler took the resume and the cancellation, so a helper that parks the
    -- handled way is not a raw yield however far away it is.
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                'local suspension = require("coroutine.sus")',
                "local function pause()",
                "   coroutine.suspend('test', function(resume: function(any), _: any): (function()?)",
                "      resume(true)",
                "      return nil",
                "   end)",
                "end",
                "local function body()",
                "   local value = resource_new()",
                "   pause()",
                "   resource_free(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.aYieldWrittenUnderUnsafeIsTheAuthorsToAnswerFor()
    -- `@unsafe do` is where the author takes over a guarantee the checker cannot
    -- see: a driver that forwards a nested thread's park to whoever resumes it
    -- yields raw because that is what forwarding is, and its callers keep their
    -- borrows across it.
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local function forward()",
                "   @unsafe do",
                "      coroutine.yield()",
                "   end",
                "end",
                "local function pause()",
                "   local value = resource_new()",
                "   forward()",
                "   @unsafe do",
                "      coroutine.yield()",
                "   end",
                "   resource_free(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.aRawYieldThroughABoundFunctionIsRefused()
    -- `local y = coroutine.yield` binds the function rather than the table, and a
    -- call through that name, or a name bound to it in turn, is the same raw yield.
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local y = coroutine.yield",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   y()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local co = coroutine",
                    "local y = co.yield",
                    "local also = y",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   also()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    -- A binding read from somebody else's table is left alone.
    assertClean(
        RESOURCE .. table.concat(
            {
                "",
                "local coroutine = {yield = function() end}",
                "local y = coroutine.yield",
                "local function pause()",
                "   local value = resource_new()",
                "   y()",
                "   resource_free(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.rebindingTheNameToItselfIsStillTheLibrary()
    -- `local coroutine = coroutine` reads the outer binding and rebinds the name, so
    -- resolving that name afterwards can answer with the binding being made. The
    -- initializer's own token still points at what it read, which is what tells them
    -- apart.
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local coroutine = coroutine",
                    "local function pause()",
                    "   local value = resource_new()",
                    "   coroutine.yield()",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

-- A C function states ownership in the type: `affine(T, cleanup)` on the slot an
-- `out` parameter writes, and `Success<T, N>` on the return saying which status
-- means those slots hold values. The ABI is unchanged -- the wrapper says who
-- discharges the value, not how it is passed.
function M.cdefOwnedOutputsBecomeLuaReturns()
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function posix_memalign(out result: affine(voidptr, free)*,"
            .. " alignment: uint64, size: uint64): Success<int32, 0>",
            "local status, pointer = posix_memalign(16, 64)",
            "if pointer then own.drop(pointer) end",
            "return status == 0",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    if package.config:sub(1, 1) == "\\" then
        return
    end
    local chunk, loadErr = program.load(result, "ownership-cdef-out")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), true, "owned out pointer is returned and dropped")
end

function M.failedOwnedOutputsAreNil()
    if package.config:sub(1, 1) == "\\" then
        return
    end
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function posix_memalign(out result: affine(voidptr, free)*,"
            .. " alignment: uint64, size: uint64): Success<int32, 0>",
            "local status, pointer = posix_memalign(3, 64)",
            "local failed = pointer == nil",
            "if pointer then own.drop(pointer) end",
            "return status ~= 0 and failed",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-cdef-out-failure")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), true, "failed output is nil")
end

function M.ignoredOwnedOutputsAreRejected()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "cdef function free(takes value: voidptr)",
                    "cdef function posix_memalign(out result: affine(voidptr, free)*,"
                    .. " alignment: uint64, size: uint64): Success<int32, 0>",
                    "posix_memalign(16, 64)",
                },
                "\n"
            )
        ),
        "NUPP2605"
    )
end

-- `Failure<T, N>` is the other direction: every status but N means the outputs
-- hold values. One statement on the return covers both of them, where two
-- contracts could disagree about the same call.
function M.multipleOwnedOutputsPreserveCAndLuaOrder()
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function make_pair(out first: affine(voidptr, free)*, seed: int32,"
            .. " out second: affine(voidptr, free)*): Success<int32, 7>",
            "local status, first, second = make_pair(1)",
            "if second then own.drop(second) end",
            "if first then own.drop(first) end",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    program.image(result, "ownership-test")
end

-- An owning C return is the same statement in the same place: the wrapper is on
-- the result type, so a caller's obligation begins where the pointer arrives.
function M.cdefReturnsMayOwnTheirResult()
    assertClean(
        table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "cdef function malloc(size: uint64): affine(voidptr, free)",
                "local value = malloc(8)",
                "own.drop(value)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "cdef function free(takes value: voidptr)",
                    "cdef function malloc(size: uint64): affine(voidptr, free)",
                    "malloc(8)",
                },
                "\n"
            )
        ),
        "NUPP2605"
    )
end

-- A status wrapper is about a C call's outputs, so it says nothing anywhere else.
function M.statusWrappersBelongOnACdefReturn()
    testAssert.eq(
        codes(table.concat({"local function make(): Success<integer, 0>", "   return 0", "end", "return make",}, "\n")),
        "NUPP2602"
    )
end

-- An ordered list of operations, as one terminal. `drop` stops where a cleanup
-- raises, which is right for one and wrong for a list: the steps after the
-- failure are obligations of their own. This is the contract automatic
-- destruction and resource sets already keep, reached from a terminal.
function M.attemptAllRunsEveryStepAfterAFailure()
    local invocations = {"   own.attemptall(value, stop, release)"}
    if program.onVm() then
        -- VM lowering also publishes callbacks when the intrinsic is an expression.
        invocations[#invocations + 1] = "   local completed: nil = own.attemptall(value, stop, release)"
        invocations[#invocations + 1] = "   return own.attemptall(value, stop, release)"
    end
    for index, invocation in ipairs(invocations) do
        local source = table.concat(
            {
                "local record Resource id: integer end",
                "local calls = ''",
                "local function stop(value: Resource): nil",
                "   calls = calls .. 'stop'",
                "   error('stop failed')",
                "end",
                "local function release(value: Resource): nil",
                "   calls = calls .. ',release'",
                "end",
                "local function finish(takes value: Resource): nil",
                invocation,
                "end",
                "local function open(): affine(Resource, finish)",
                "   return new Resource(id = 1)",
                "end",
                "local ok = pcall(function()",
                "   local value = open()",
                "   own.drop(value)",
                "end)",
                "return calls, ok",
            },
            "\n"
        )
        local result, diags = checked(source)
        testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
        local chunk, loadErr = program.load(result, "ownership-attempt-all" .. index)
        assert(chunk, tostring(loadErr))
        local calls, ok = chunk()
        testAssert.eq(calls, "stop,release", "every step is attempted")
        testAssert.eq(ok, false, "and the failure still propagates")
    end
end

-- A step that consumes the value leaves every later one running on something
-- already released, so only the last may take it.
function M.onlyTheFinalAttemptAllOperationMayTakeTheValue()
    local declaration = table.concat(
        {
            "local record Resource id: integer end",
            "local function first(takes value: Resource): nil end",
            "local function second(value: Resource): nil end",
            "local function finish(takes value: Resource): nil",
        },
        "\n"
    )
    -- `first` consuming its own parameter is NUPP2603 in its empty body; the
    -- ordering rule is the second diagnostic.
    testAssert.eq(
        codes(declaration .. table.concat({"", "   own.attemptall(value, first, second)", "end",}, "\n")),
        "NUPP2615"
    )
    assertClean(
        table.concat(
            {
                "local record Resource id: integer end",
                "local function first(value: Resource): nil end",
                "local function second(takes value: Resource): nil",
                "   @unsafe do local _raw = @unsafe own.release(value) end",
                "end",
                "local function finish(takes value: Resource): nil",
                "   own.attemptall(value, first, second)",
                "end",
                "return finish",
            },
            "\n"
        )
    )
end

function M.cdefBorrowedOutputsTrackTheirInputOwner()
    local declarations = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function make_owner_c(): voidptr",
            "local function make_owner(): affine(voidptr, free)",
            "   return make_owner_c()",
            "end",
            "cdef function get_view(borrows owner: voidptr,",
            "   out view: voidptr* borrows (owner)): Success<int32, 0>",
        },
        "\n"
    )
    testAssert.eq(
        codes(
            declarations .. "\n" .. table.concat(
                {"local owner = make_owner()", "local status, view = get_view(owner)", "own.drop(owner)",},
                "\n"
            )
        ),
        "NUPP2602"
    )
    assertClean(
        declarations .. "\n" .. table.concat(
            {"local owner = make_owner()", "do", "   local status, view = get_view(owner)", "end", "own.drop(owner)",},
            "\n"
        )
    )
end

function M.cdefBorrowedOutputSourcesMustBeSharedInputs()
    testAssert.eq(
        codes(
            table.concat(
                {"cdef function get_view(owner: voidptr,", "   out view: voidptr* borrows (owner)): int32",},
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.cdefBorrowRelationsBelongOnOutputs()
    testAssert.eq(
        codes(table.concat({"cdef function get_view(borrows owner: voidptr borrows (owner)): int32",}, "\n")),
        "NUPP2602"
    )
end

function M.cdefBorrowedOutputsMayNameSeveralSharedInputs()
    local declarations = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function make_owner_c(): voidptr",
            "local function make_owner(): affine(voidptr, free)",
            "   return make_owner_c()",
            "end",
            "cdef function combine(borrows left: voidptr, borrows right: voidptr,",
            "   out view: voidptr* borrows (left, right)): int32",
        },
        "\n"
    )
    testAssert.eq(
        codes(
            declarations .. "\n" .. table.concat(
                {
                    "local left = make_owner()",
                    "local right = make_owner()",
                    "local _, view = combine(left, right)",
                    "own.drop(left)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
    testAssert.eq(
        codes(
            declarations .. "\n" .. table.concat(
                {
                    "local left = make_owner()",
                    "local right = make_owner()",
                    "local _, view = combine(left, right)",
                    "own.drop(right)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.borrowedIsNotACompilerAnnotation()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "@borrowed(out = view, from = owner)",
                    "cdef function get_view(borrows owner: voidptr,",
                    "   out view: voidptr* borrows (owner)): int32",
                },
                "\n"
            )
        ),
        "NUPP2111"
    )
end

function M.stringDerivedPointersCannotEscape()
    testAssert.eq(
        codes(
            table.concat({"local text = 'hello'", "local pointer = ffi.cast<cstring>(text)", "return pointer",}, "\n")
        ),
        "NUPP2608"
    )
    assertClean(
        table.concat({"cdef function strlen(value: cstring): uint64", "local text = 'hello'", "strlen(text)",}, "\n")
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local text = 'hello'",
                    "local pointer = ffi.cast<cstring>(text)",
                    "text = 'other'",
                    "print(pointer ~= nil)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.callbackPointersRequireUnsafe()
    testAssert.eq(codes("local cb = ffi.cast<voidptr>(function() end)"), "NUPP2604")
    -- Inside `unsafe` the cast is permitted.
    local permitted = table.concat(
        {
            "@unsafe do",
            "   local callback = function() end",
            "   local cb = ffi.cast<voidptr>(callback)",
            "   local handle = own.pin(cb, callback)",
            "end",
        },
        "\n"
    )
    assertClean(permitted)
end

function M.rawPointerAccessRequiresUnsafe()
    local declarations = table.concat(
        {"cdef struct RawBox", "   value: int32", "end", "local pointer = ffi.cast<RawBox*>(1)",},
        "\n"
    )
    testAssert.eq(codes(declarations .. "\nprint(pointer.value)"), "NUPP2604")
    assertClean(declarations .. table.concat({"", "@unsafe do", "   print(pointer.value)", "end",}, "\n"))
end

function M.rawPointerCallsRequireUnsafeOrAContract()
    local source = table.concat(
        {"cdef function opaque_use(value: voidptr)", "local pointer = ffi.cast<voidptr>(1)",},
        "\n"
    )
    testAssert.eq(codes(source .. "\nopaque_use(pointer)"), "NUPP2604")
    assertClean(source .. table.concat({"", "@unsafe do", "   opaque_use(pointer)", "end",}, "\n"))
    assertClean(
        table.concat(
            {
                "cdef function checked_use(borrows value: voidptr)",
                "local function inspect(borrows value: voidptr)",
                "   checked_use(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.inferredBorrowsPermitSharedMutation()
    assertClean(
        table.concat(
            {
                "cdef struct MutableBox",
                "   value: int32",
                "end",
                "local function increment(box: MutableBox*)",
                "   box.value = box.value + 1",
                "end",
            },
            "\n"
        )
    )
end

function M.pinsProveAndAnchorManagedPointers()
    assertClean(
        table.concat(
            {
                "cdef function remember(retains value: cstring)",
                "cdef function forget(releases value: cstring)",
                "local text = 'hello'",
                "local pointer = ffi.cast<cstring>(text)",
                "local handle: pinned(cstring) = own.pin(pointer, text)",
                "remember(handle)",
                "forget(handle)",
            },
            "\n"
        )
    )

    testAssert.eq(
        codes(
            table.concat(
                {
                    "local first = 'first'",
                    "local second = 'second'",
                    "local pointer = ffi.cast<cstring>(first)",
                    "local handle = own.pin(pointer, second)",
                },
                "\n"
            )
        ),
        "NUPP2604"
    )
end

function M.retainedPinsMustFollowReleaseContracts()
    local prelude = table.concat(
        {
            "cdef function remember(retains value: cstring)",
            "cdef function forget(releases value: cstring)",
            "local text = 'hello'",
            "local pointer = ffi.cast<cstring>(text)",
            "local handle = own.pin(pointer, text)",
        },
        "\n"
    )
    testAssert.eq(codes(prelude .. "\nremember(handle)"), "NUPP2603")
    testAssert.eq(codes(prelude .. "\nforget(handle)"), "NUPP2602")

    local got = codes(prelude .. table.concat({"", "remember(handle)", "remember(handle)", "forget(handle)",}, "\n"))
    testAssert.eq(got, "NUPP2602")

    testAssert.eq(
        codes(
            table.concat(
                {
                    "cdef function remember(retains value: cstring)",
                    "local text = 'hello'",
                    "local pointer = ffi.cast<cstring>(text)",
                    "remember(pointer)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.pinnedArgumentsLowerToTheirCPointers()
    local source = table.concat(
        {
            "cdef function remember(retains value: cstring)",
            "cdef function forget(releases value: cstring)",
            "local text = 'hello'",
            "local pointer = ffi.cast<cstring>(text)",
            "local handle = own.pin(pointer, text)",
            "remember(handle)",
            "forget(handle)",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    program.image(result, "ownership-test")
end

function M.rawTransferAndDropAreStaticAndDeterministic()
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function malloc(size: uint64): voidptr",
            "local function ownedMalloc(size: integer): affine(voidptr, free)",
            "   return malloc(size)",
            "end",
            "local value = ownedMalloc(8)",
            "local raw",
            "@unsafe do",
            "   raw = @unsafe own.release(value)",
            "   local restored = @unsafe own.adopt<affine(voidptr, free)>(raw)",
            "   own.drop(restored)",
            "end",
            "return true",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-runtime")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), true, "raw transfer runs without a double free")
end

function M.sameSpelledCleanupBindingsKeepDistinctReferences()
    local source = table.concat(
        {
            "local calls = ''",
            "local record Resource end",
            "do",
            "   local function close(takes value: Resource): nil calls = calls .. 'a' end",
            "   local function open(): affine(Resource, close) return new Resource() end",
            "   local value = open()",
            "   own.drop(value)",
            "end",
            "do",
            "   local function close(takes value: Resource): nil calls = calls .. 'b' end",
            "   local function open(): affine(Resource, close) return new Resource() end",
            "   local value = open()",
            "   own.drop(value)",
            "end",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-cleanup-identity")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "ab", "each contract kept its resolved binding")
end

function M.consumingCFunctionsNeedNoRuntimeDetachment()
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function malloc(size: uint64): voidptr",
            "local function ownedMalloc(size: integer): affine(voidptr, free)",
            "   return malloc(size)",
            "end",
            "local value = ownedMalloc(8)",
            "free(value)",
            "return true",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-takes")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), true, "C consumption runs without a double free")
end

function M.ownershipLoweringEmitsLoadableTransparentValues()
    local source = table.concat(
        {
            "cdef function free(takes value: voidptr)",
            "cdef function malloc(size: uint64): voidptr",
            "local function ownedMalloc(size: integer): affine(voidptr, free)",
            "   return malloc(size)",
            "end",
            "local value = ownedMalloc(8)",
            "local raw",
            "@unsafe do",
            "   raw = @unsafe own.release(value)",
            "   local restored = @unsafe own.adopt<affine(voidptr, free)>(raw)",
            "   own.drop(restored)",
            "end",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0)
    local chunk, loadErr = program.load(result, "ownership-transparent-lowering")
    assert(chunk, tostring(loadErr))
end

-- `function m.f()` has to put f on the table the way `m.f = ...` does, which
-- means recording the path a later reference reads back. It did not, so `m.f`
-- resolved through an open table as `any`, and every annotation on it was
-- accepted and then meant nothing. An owning result is how that was noticed: the
-- obligation simply never existed.
function M.aQualifiedFunctionCarriesAnAutomaticallyDischargedOwnedContract()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local m = {}",
                    "local function closeFile(takes file: io.File): nil",
                    "   file:close()",
                    "end",
                    "function m.open(path: string): affine(io.File, closeFile)",
                    "   local file = io.stdin",
                    "   return file",
                    "end",
                    "local handle = m.open('x')",
                },
                "\n"
            )
        ),
        "",
        "the owner from m.open is tracked for automatic discharge"
    )
end

function M.aFunctionValuedFieldCanDeclareAnOwningProducer()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local record Api",
                "   open: function(): affine(resource*, resource_free)",
                "end",
                "local api: Api = nil as any",
                "local value = api.open()",
                "own.drop(value)",
            },
            "\n"
        )
    )
end

local MIGRATABLE_SESSION = table.concat(
    {
        "local record Session",
        "   id: integer",
        "   function drop(takes self): nil",
        "      print(self.id)",
        "   end",
        "end",
        "local function closeSession(takes session: Session): nil @unsafe do local _raw = @unsafe own.release(session) end end",
    },
    "\n"
)
function M.ownedBorrowingCallableFieldKeepsItsDischargeObligation()
    assertClean(
        table.concat(
            {
                MIGRATABLE_SESSION,
                "local record Pool",
                "   open: function(exclusive self: Pool): affine(Session, closeSession) borrows(self)",
                "end",
                "local pool: Pool = nil as any",
                "local session = pool:open()",
                "own.drop(session)",
            },
            "\n"
        )
    )
end

-- The same fix without the ownership: a qualified function is a typed function,
-- so its argument and its result are checked at the call.
function M.aQualifiedFunctionIsTypedAtItsCallSite()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local m = {}",
                    "function m.width(text: string): integer",
                    "   return #text",
                    "end",
                    "local n: string = m.width(1)",
                },
                "\n"
            )
        ),
        "NUPP2001 NUPP2006",
        "both the result and the argument are checked"
    )
end

function M.aQualifiedFunctionAcquiresIntoAnAutomaticLocal()
    assertClean(
        table.concat(
            {
                "local m = {}",
                "local function closeFile(takes file: io.File): nil",
                "   file:close()",
                "end",
                "function m.open(path: string): affine(io.File, closeFile)",
                "   local file = io.stdin",
                "   return file",
                "end",
                "function m.slurp(path: string): string",
                "   do",
                "      local file = m.open(path)",
                "      return file:read('*a')",
                "   end",
                "end",
            },
            "\n"
        )
    )
end

-- Every intrinsic is spelled bare or qualified with `nupp.`, and the two mean
-- the same thing: same diagnostics, same lowering.

function M.remainingOwnershipHelpersAnswerToTheirQualifiedSpelling()
    assertClean(
        table.concat(
            {
                RESOURCE,
                "local value = resource_new()",
                "do",
                "   local view = own.borrow(value)",
                "end",
                "own.drop(value)",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "cdef function free(takes value: voidptr)",
                "cdef function malloc(size: uint64): voidptr",
                "local function ownedMalloc(size: integer): affine(voidptr, free)",
                "   return malloc(size)",
                "end",
                "local value = ownedMalloc(8)",
                "@unsafe do",
                "   local raw = @unsafe own.release(value)",
                "   local owner = @unsafe own.adopt<affine(voidptr, free)>(raw)",
                "   do",
                "      local view = own.borrowfrom(raw, owner)",
                "   end",
                "   own.drop(owner)",
                "end",
            },
            "\n"
        )
    )
    assertClean(
        table.concat(
            {
                "cdef function remember(retains value: cstring)",
                "cdef function forget(releases value: cstring)",
                "local text = 'hello'",
                "local pointer = ffi.cast<cstring>(text)",
                "local handle: pinned(cstring) = own.pin(pointer, text)",
                "remember(handle)",
                "forget(handle)",
            },
            "\n"
        )
    )
end

function M.disposeIsNotAnAnnotationAliasForDrop()
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "@dispose",
                    "local function close(takes value: resource*)",
                    "   resource_free(value)",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2111"
    )
end

function M.qualifiedDisposeIsNotAnIntrinsicAliasForDrop()
    testAssert.eq(
        codes(table.concat({RESOURCE, "local value = resource_new()", "nupp.dispose(value)",}, "\n")),
        "NUPP2004 NUPP2611"
    )
end

function M.bothSpellingsOfDropLowerTheSameWay()
    local function lowered(call)
        local source = table.concat(
            {
                "local calls = ''",
                "local record File",
                "   closed: boolean",
                "   function drop(takes self): nil",
                "      calls = calls .. 'close'",
                "   end",
                "end",
                "local function closeFile(takes file: File): nil",
                "   calls = calls .. 'close'",
                "   @unsafe do local _raw = @unsafe own.release(file) end",
                "end",
                "local function openFile(): affine(File, closeFile)",
                "   return new File(closed = false)",
                "end",
                "local file = openFile()",
                call,
                "return calls",
            },
            "\n"
        )
        local result, diags = checked(source)
        testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
        local chunk, loadErr = program.load(result, "ownership-qualified-drop")
        assert(chunk, tostring(loadErr))
        testAssert.eq(chunk(), "close", "the drop operation runs")
    end

    lowered("own.drop(file)")
    lowered("own.drop(file)")
end

function M.aBindingNamedOwnShadowsTheQualifiedSpelling()
    -- The intrinsic is reached through the compiler's `own` root, so a local of
    -- that name means what the program says it means, as any other name would.
    assertClean(
        table.concat(
            {
                "local own = {",
                "   drop = function(value: integer): integer return value end",
                "}",
                "local answer = own.drop(3)",
            },
            "\n"
        )
    )
    -- and a local named after a bare intrinsic shadows it the same way
    assertClean(
        table.concat({"local function drop(value: integer): integer return value end", "local answer = drop(3)",}, "\n")
    )
end

function M.aQualifiedIntrinsicGivesItsParameterTheSameMode()
    -- Parameter modes are read out of a body before the names in it resolve, so
    -- both spellings have to be recognized by their spelling alone. Without that
    -- the helper below infers a plain parameter and the double release goes
    -- unreported.
    testAssert.eq(
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function release(value: resource*)",
                    "   own.drop(value)",
                    "end",
                    "local value = resource_new()",
                    "release(value)",
                    "release(value)",
                },
                "\n"
            )
        ),
        codes(
            table.concat(
                {
                    RESOURCE,
                    "local function release(value: resource*)",
                    "   own.drop(value)",
                    "end",
                    "local value = resource_new()",
                    "release(value)",
                    "release(value)",
                },
                "\n"
            )
        )
    )
end

local CLOSURE_RESOURCE = table.concat(
    {
        "local calls = 0",
        "local record ClosureResource",
        "   value: integer",
        "end",
        "local function closeClosureResource(takes value: ClosureResource): nil",
        "   calls = calls + 1",
        "end",
        "local function openClosureResource(value: integer): affine(ClosureResource, closeClosureResource)",
        "   return new ClosureResource(value = value)",
        "end",
    },
    "\n"
)

function M.aTakingClosureMovesItsCaptureAndIsSingleShot()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local resource = openClosureResource(7)",
                    "local callback = function(): integer takes (resource)",
                    "   return resource.value",
                    "end",
                    "print(resource.value)",
                    "print(callback())",
                    "print(callback())",
                },
                "\n"
            )
        ),
        "NUPP2601 NUPP2601",
        "construction moves the capture and invocation moves the closure"
    )
end

function M.aCalledTakingClosureCleansItsCapture()
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local resource = openClosureResource(7)",
            "local callback = function(): integer takes (resource)",
            "   return resource.value",
            "end",
            "local answer = callback()",
            "return answer, calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-call")
    assert(chunk, tostring(loadErr))
    local answer, calls = chunk()
    testAssert.eq(answer, 7)
    testAssert.eq(calls, 1, "a called closure releases its capture once")
end

function M.aTakingClosureOverAnOwnedParameterGenerates()
    -- The parameter's move is recorded before the body's cleanup planning replaces
    -- the local, so the capture's move can name an owner no region tracks. That
    -- lookup once fell back to the region itself and wrote the table into the code.
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local function use(takes resource: affine(ClosureResource, closeClosureResource)): integer",
            "   local callback = function(): integer takes (resource)",
            "      return resource.value",
            "   end",
            "   return callback()",
            "end",
            "return use(openClosureResource(7)), calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-parameter")
    assert(chunk, tostring(loadErr))
    local answer, calls = chunk()
    testAssert.eq(answer, 7)
    testAssert.eq(calls, 1, "the closure releases the parameter it took once")
end

function M.anUncalledTakingClosureCleansItsCapture()
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "do",
            "   local resource = openClosureResource(7)",
            "   local callback = function(): integer takes (resource)",
            "      return resource.value",
            "   end",
            "end",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-drop")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), 1, "an uncalled closure releases its capture once")
end

function M.aBorrowingClosureKeepsItsSourceLive()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local resource = openClosureResource(7)",
                    "local callback = function() borrows (resource)",
                    "   print(resource.value)",
                    "end",
                    "own.drop(resource)",
                    "callback()",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "the source cannot be released while its closure remains live"
    )
end

function M.aBorrowingClosureEndsItsBorrowWithItsScope()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local resource = openClosureResource(7)",
                "do",
                "   local callback = function() borrows (resource)",
                "      print(resource.value)",
                "   end",
                "   callback()",
                "end",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

function M.borrowedClosureTypesNameTheirSiblingSource()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local record ClosureHolder",
                "   source: affine(ClosureResource, closeClosureResource)",
                "   callback: function(): integer borrows (source)",
                "end",
            },
            "\n"
        )
    )
end

function M.aResultAnnotatedClosureInfersItsBorrowCapture()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local resource = openClosureResource(7)",
                "do",
                "   local callback = function(): integer",
                "      return resource.value",
                "   end",
                "   print(callback())",
                "end",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

function M.resultAnnotatedClosuresComposeTakingAndBorrowedCaptures()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local taken = openClosureResource(7)",
                "local borrowed = openClosureResource(5)",
                "local callback = function(): integer takes (taken) borrows (borrowed)",
                "   return taken.value + borrowed.value",
                "end",
                "print(callback())",
                "own.drop(borrowed)",
            },
            "\n"
        )
    )
end

function M.aTakingClosureReturnNeedsANameableAffineAnnotation()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local function make()",
                    "   local resource = openClosureResource(7)",
                    "   return function(): integer takes (resource)",
                    "      return resource.value",
                    "   end",
                    "end",
                    "local callback = make()",
                    "print(callback())",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.aTakesCallbackCannotEraseBorrowedClosureProvenance()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local function retain(takes callback: function(): any): affine(function(): any)",
                    "   return callback",
                    "end",
                    "local resource = openClosureResource(7)",
                    "local retained = retain(function(): any borrows (resource)",
                    "   print(resource.value)",
                    "end)",
                    "own.drop(resource)",
                    "retained()",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "only a scoped overload may accept a borrowed callback"
    )
end

function M.pcallConsumesATakingClosure()
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local resource = openClosureResource(7)",
            "local ok, answer = pcall(function(): integer takes (resource)",
            "   return resource.value",
            "end)",
            "return ok, answer, calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-pcall")
    assert(chunk, tostring(loadErr))
    local ok, answer, calls = chunk()
    testAssert.eq(ok, true)
    testAssert.eq(answer, 7)
    testAssert.eq(calls, 1, "pcall's invoked closure releases its capture")
end

function M.aRepeatableParameterCannotReceiveATakingClosure()
    local declarations = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local function twice(scoped callback: function(): nil): nil",
            "   callback()",
            "   callback()",
            "end",
            "local function viaBorrow(borrows callback: function(): nil): nil",
            "   callback()",
            "end",
        },
        "\n"
    )
    local taking = {
        "local resource = openClosureResource(7)",
        "local callback = function(): nil takes (resource)",
        "   own.drop(resource)",
        "end",
    }
    testAssert.eq(
        codes(declarations .. "\n" .. table.concat(taking, "\n") .. "\ntwice(callback)"),
        "NUPP2602",
        "a named closure passed to scoped"
    )
    testAssert.eq(
        codes(
            declarations .. table.concat(
                {
                    "",
                    "local resource = openClosureResource(7)",
                    "twice(function(): nil takes (resource)",
                    "   own.drop(resource)",
                    "end)",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a literal closure passed to scoped"
    )
    testAssert.eq(
        codes(declarations .. "\n" .. table.concat(taking, "\n") .. "\nviaBorrow(callback)\nviaBorrow(callback)"),
        "NUPP2602 NUPP2602",
        "a named closure passed to borrows"
    )
    testAssert.eq(
        codes(
            declarations .. table.concat(
                {
                    "",
                    "local resource = openClosureResource(7)",
                    "viaBorrow(function(): nil takes (resource)",
                    "   own.drop(resource)",
                    "end)",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a literal closure passed to borrows"
    )
end

-- A closure captured from an enclosing function is seen through a borrow, and the
-- call path let a borrowed function through, so a nested closure invoked a taking
-- closure as often as it was itself invoked while the owner still held it.
function M.aCapturedTakingClosureCannotBeInvokedThroughABorrow()
    local taking = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local function body(): nil",
            "   local resource = openClosureResource(7)",
            "   local finish = function(): nil takes (resource)",
            "      own.drop(resource)",
            "   end",
        },
        "\n"
    )
    testAssert.eq(
        codes(
            taking .. table.concat(
                {
                    "",
                    "   local wrapper = function(): nil",
                    "      finish()",
                    "   end",
                    "   wrapper()",
                    "   wrapper()",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "an inferred capture"
    )
    testAssert.eq(
        codes(
            taking .. table.concat(
                {
                    "",
                    "   local wrapper = function(): nil borrows (finish)",
                    "      finish()",
                    "   end",
                    "   wrapper()",
                    "   finish()",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602 NUPP2602",
        "a declared borrow capture"
    )
    testAssert.eq(
        codes(
            taking .. table.concat(
                {"", "   local function wrapper(): nil", "      finish()", "   end", "   wrapper()", "end",},
                "\n"
            )
        ),
        "NUPP2602",
        "a local function"
    )
    assertClean(
        taking .. table.concat(
            {
                "",
                "   local wrapper = function(): nil takes (finish)",
                "      finish()",
                "   end",
                "   wrapper()",
                "end",
            },
            "\n"
        )
    )
end

function M.raceDropsATakingLoserThatWasNeverEntered()
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local tasks = require(\"coroutine\")",
            "local entered = 0",
            "local first = openClosureResource(1)",
            "local second = openClosureResource(2)",
            "local answer, winner = tasks.race({",
            "   function(): integer takes (first)",
            "      return first.value",
            "   end,",
            "   function(): integer takes (second)",
            "      entered = entered + 1",
            "      return second.value",
            "   end,",
            "})",
            "return answer, winner, entered, calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-race")
    assert(chunk, tostring(loadErr))
    local answer, winner, entered, calls = chunk()
    testAssert.eq(answer, 1)
    testAssert.eq(winner, 1)
    testAssert.eq(entered, 0, "race did not enter the losing closure")
    testAssert.eq(calls, 2, "race cleaned both the winner and unentered loser")
end

function M.raceAcceptsBorrowedClosuresWithoutRetainingThem()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local tasks = require(\"coroutine\")",
                "local resource = openClosureResource(7)",
                "local answer = tasks.race({",
                "   function(): integer borrows (resource)",
                "      return resource.value",
                "   end,",
                "})",
                "print(answer)",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

-- A task scope is a Closeable: its block closes it on the way out, and `own.drop`
-- closes one held in an ordinary local early, settling its children there rather
-- than where the block ends.
function M.aTaskScopeClosesThroughItsScopeAndThroughDrop()
    local order = runGenerated(
        table.concat(
            {
                "local tasks = require(\"coroutine\")",
                "local order: {string} = {}",
                "do local scope = tasks.scope() ;",
                "   scope:spawn(function(): nil order[#order + 1] = 'child' end)",
                "end",
                "order[#order + 1] = 'after block'",
                "do",
                "   local scope = tasks.scope()",
                "   scope:spawn(function(): nil order[#order + 1] = 'early child' end)",
                "   own.drop(scope)",
                "   order[#order + 1] = 'after drop'",
                "end",
                "return table.concat(order, ',')",
            },
            "\n"
        ),
        "task-scope-close"
    )
    testAssert.eq(order, "child,after block,early child,after drop", "each scope settled where it was closed")
end

-- A scope's bound is a duration, named with its unit like every other one in the
-- runtime; `tasks.deadline()` is the absolute instant it becomes.
function M.aTaskScopeTakesItsTimeoutInMilliseconds()
    assertClean(
        "local tasks = require(\"coroutine\")\ndo local scope = tasks.scope(limit = 2, timeoutms = 5) ;\n   print(scope)\nend"
    )
    local refused = codes(
        "local tasks = require(\"coroutine\")\nlocal scope = tasks.scope(deadline = 5)\nnupp.drop(scope)"
    )
    assert(refused:find("NUPP2125", 1, true) == 1, "the old name is not an argument: " .. refused)
end

-- `gather` takes the same two contracts `race` does: a borrowed family runs and is
-- left with its owner, and an owned family is called or dropped exactly once.
function M.gatherCallsEveryTakingBranchOnce()
    local source = CLOSURE_RESOURCE .. table.concat(
        {
            "",
            "local tasks = require(\"coroutine\")",
            "local first = openClosureResource(1)",
            "local second = openClosureResource(2)",
            "local values = tasks.gather({",
            "   function(): integer takes (first)",
            "      return first.value",
            "   end,",
            "   function(): integer takes (second)",
            "      return second.value",
            "   end,",
            "})",
            "return values[1], values[2], calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "taking-closure-gather")
    assert(chunk, tostring(loadErr))
    local one, two, calls = chunk()
    testAssert.eq(one, 1)
    testAssert.eq(two, 2)
    testAssert.eq(calls, 2, "gather cleaned both taking branches")
end

function M.gatherAcceptsBorrowedClosuresWithoutRetainingThem()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local tasks = require(\"coroutine\")",
                "local resource = openClosureResource(7)",
                "local values = tasks.gather({",
                "   function(): integer borrows (resource)",
                "      return resource.value",
                "   end,",
                "})",
                "print(values[1])",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

-- A named cleanup identity can delegate to an ordinary method without giving the
-- method or its spelling compiler privilege.
local DROPPING_RECORD = table.concat(
    {
        "local record Session",
        "   id: integer",
        "",
        "   drop: @nosuspend function(takes self: Session): nil",
        "end",
        "function Session.drop(takes self): nil",
        "   @unsafe do",
        "      local _raw = @unsafe own.release(self)",
        "   end",
        "end",
        "local function closeSession(takes session: Session): nil @unsafe do local _raw = @unsafe own.release(session) end end",
    },
    "\n"
)

function M.anOwnedResultUsesTheTypesStructuralDropOperation()
    assertClean(
        DROPPING_RECORD .. table.concat(
            {
                "",
                "local function open(id: integer): affine(Session, closeSession)",
                "   return new Session(id = id)",
                "end",
                "do",
                "   local session = open(7)",
                "   print(session.id)",
                "end",
            },
            "\n"
        )
    )
end

function M.anOwnedResultUsesALaterQualifiedStructuralDropOperation()
    local source = table.concat(
        {
            "local m = {}",
            "record m.Session",
            "   id: integer",
            "   drop: @nosuspend function(takes self: m.Session): nil",
            "end",
            "record m.Factory",
            "end",
            "function m.Session.drop(takes self): nil",
            "   local _raw = @unsafe own.release(self)",
            "end",
            "function m.closeSession(takes session: m.Session): nil session:drop() end",
            "record m.Pool",
            "   open: function(): affine(m.Session, m.closeSession)",
            "end",
            "function m.Factory:open(): affine(m.Session, m.closeSession)",
            "   return new m.Session(id = 1)",
            "end",
            "do",
            "   local factory = new m.Factory()",
            "   local session = factory:open()",
            "   print(session.id)",
            "end",
            "return m",
        },
        "\n"
    )
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local path = dir .. "/src/main.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(source)
    file:close()
    local project = envMod.new(dir, {config = {include = {"src"}}})
    local result = parser.parse(source, path)
    local diags = check.check(result, path, project)
    os.execute("rm -rf '" .. dir .. "'")
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-qualified-order")
    assert(chunk, tostring(loadErr))
    assert(chunk())
end

function M.anOwnedResultCanNameAQualifiedFreeTerminal()
    local source = table.concat(
        {
            "local m = {}",
            "m.closed = 0",
            "record m.Session",
            "   id: integer",
            "end",
            "function m.closeSession(takes session: m.Session): nil",
            "   m.closed = m.closed + 1",
            "   @unsafe do",
            "      local _raw = @unsafe own.release(session)",
            "   end",
            "end",
            "record m.Pool",
            "   open: function(): affine(m.Session, m.closeSession)",
            "end",
            "local pool = new m.Pool(",
            "   open = function(): affine(m.Session, m.closeSession)",
            "      return new m.Session(id = 1)",
            "   end",
            ")",
            "own.drop(pool.open())",
            "return m",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-qualified-free-drop")
    assert(chunk, tostring(loadErr))
    local module = chunk()
    testAssert.eq(module.closed, 1, "the qualified terminal is registered and runs")
end

function M.aTransferFieldDoesNotInvokeItsValuesStructuralDropOperation()
    assertClean(
        table.concat(
            {
                "local record Session",
                "   function drop(takes self): nil",
                "      local _raw = @unsafe own.release(self)",
                "   end",
                "end",
                "local record Box",
                "   value: affine(Session)",
                "end",
                "local function open(): affine(Session)",
                "   return new Session()",
                "end",
                "local function box(takes value: Session): nil",
                "   local stored = new Box(value = value)",
                "   @unsafe do",
                "      local _raw = @unsafe own.release(stored)",
                "   end",
                "end",
                "box(open())",
            },
            "\n"
        )
    )
end

function M.anAffineResultNeedsOneCleanupOrExplicitTransferOnlyPolicy()
    testAssert.eq(
        codes(
            table.concat(
                {"local function allocate(): affine(voidptr, missingCleanup)", "   return nil as any", "end",},
                "\n"
            )
        ),
        "NUPP2131",
        "a missing cleanup function is reported once"
    )

    assertClean(
        table.concat(
            {
                "local function allocate(): affine(voidptr)",
                "   return nil as any",
                "end",
                "local value = allocate()",
                "@unsafe do",
                "   local _raw = @unsafe own.release(value)",
                "end",
            },
            "\n"
        )
    )
end

function M.anOwnedResultCannotSilentlyDiscardExtraTerminals()
    local _, diagnostics = checked(
        table.concat(
            {
                "cdef function stop(takes value: voidptr)",
                "cdef function release(takes value: voidptr)",
                "local allocate: function(): affine(voidptr, stop, release)",
            },
            "\n"
        )
    )
    testAssert.eq(#diagnostics, 1, diagnostics[2] and diagnostics[2].msg or "one diagnostic")
    testAssert.eq(diagnostics[1].code, "NUPP2421")
end

-- Every result position is resolved, so a function may own its second result and
-- not only its first.
function M.aNonFirstResultMayBeOwned()
    assertClean(
        DROPPING_RECORD .. table.concat(
            {
                "",
                "local function openLogged(id: integer): (integer, affine(Session, closeSession))",
                "   return id * 2, new Session(id = id)",
                "end",
                "do",
                "   local code, session = openLogged(7)",
                "   print(code + session.id)",
                "end",
            },
            "\n"
        )
    )
end

function M.anOwnedNonFirstResultIsDestroyedAtItsScope()
    local source = DROPPING_RECORD .. table.concat(
        {
            "",
            "local closed = 0",
            "local function closeCounted(takes session: Session): nil",
            "   closed += 1",
            "   closeSession(session)",
            "end",
            "local function openLogged(id: integer): (integer, affine(Session, closeCounted))",
            "   return id * 2, new Session(id = id)",
            "end",
            "local function use(): integer",
            "   local code, session = openLogged(7)",
            "   return code",
            "end",
            "return use(), closed",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local answer, closed = program.run(result, "ownership-test")
    testAssert.eq(answer, 14)
    testAssert.eq(closed, 1, "the second result is discharged at scope exit")
end

function M.anOwnedResultDeclaresAnOwningResult()
    assertClean(
        DROPPING_RECORD .. table.concat(
            {
                "",
                "local function open(id: integer): affine(Session, closeSession)",
                "   return new Session(id = id)",
                "end",
                "do",
                "   local session = open(7)",
                "   print(session.id)",
                "end",
            },
            "\n"
        )
    )
end

-- A cleanup key names the function a declaration registers and reaches the
-- interned identity of every owned type discharged by it. Deriving it from a byte
-- offset moved it whenever unrelated text above the declaration moved, so a type
-- built after an edit stopped matching the same type read from the cache.
function M.aCleanupKeyDoesNotMoveWithTextAboveIt()
    local body = table.concat(
        {
            "local function use(): integer",
            "   do",
            "      local value = resource_new()",
            "      return value.value",
            "   end",
            "end",
            "return use",
        },
        "\n"
    )

    local function keysOf(source)
        local result, diags = checked(source)
        testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
        local found, seen = {}, {}

        local function walk(node)
            if type(node) ~= "table" or seen[node] then
                return
            end
            seen[node] = true
            for _, registration in ipairs(rawget(node, "cleanupRegistrations") or {}) do
                found[#found + 1] = registration.cleanup.key
            end
            for _, child in ipairs(node) do
                walk(child)
            end
        end

        walk(result.root)
        table.sort(found)
        assert(#found > 0, "no cleanup key was registered")

        return table.concat(found, ",")
    end

    local plain = keysOf(RESOURCE .. "\n" .. body)
    local shifted = keysOf(
        "-- a comment that shifts every offset below it\n" .. "-- and a second line of it\n" .. RESOURCE .. "\n" .. body
    )
    testAssert.eq(shifted, plain, "the cleanup key moved with text above the declaration")
end

-- A terminal named only in a type still has to publish the function before a
-- top-level owner can leave the module scope and ask the lazy resolver for it.
function M.cleanupForwardsArgumentsWithProtectedCalls()
    local result, diagnostics = checked(
        [[
local record Resource
    id: integer
    function destroy(takes self): nil
        assert(self.id == 7)
        @unsafe do
            local _self = @unsafe own.release(self)
        end
    end
end
local function create(): affine(Resource, Resource.destroy)
    return new Resource(id = 7)
end
local function run(): integer
    local value = create()
    return value.id
end
return run()
]]
    )
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    testAssert.eq(program.run(result, "portablecleanup"), 7)
end

function M.inlineTerminalsRegisterTheirRuntimeOwner()
    local result, diagnostics = checked(
        [[
local closed = 0
local record Resource
    function destroy(takes self): nil
        closed = closed + 1
        @unsafe do
            local _self = @unsafe own.release(self)
        end
    end
end
local function create(): affine(Resource, Resource.destroy)
    return new Resource()
end
own.drop(create())
return closed
]]
    )
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    testAssert.eq(program.run(result, "inlinecleanup"), 1)
end

function M.importedTerminalsRegisterTheirDeclaringModulesLocalName()
    local environment = envMod.new(os.tmpname(), {cache = false})
    local declarationPath = "cleanupcontract.nupp"
    local declaration = parser.parse(
        [[
module cleanupcontract
local resource = {closed = 0}
record resource.Value
    id: integer
end
function resource.release(takes value: resource.Value): nil
    resource.closed = resource.closed + 1
    @unsafe do
        local _value = @unsafe own.release(value)
    end
end
export = resource
]],
        declarationPath
    )
    local diagnostics, moduleType, exports = check.check(declaration, declarationPath, environment)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    environment.loaded.cleanupcontract = {type = moduleType, exports = exports, path = declarationPath}
    local consumer = parser.parse(
        [[
local imported = require("cleanupcontract")
local function create(): affine(imported.Value, imported.release)
    return {id = 1} as any
end
own.drop(create())
return true
]],
        "cleanupconsumer.nupp"
    )
    diagnostics = check.check(consumer, "cleanupconsumer.nupp", environment)
    testAssert.eq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
    local loaded = package.loaded.cleanupcontract
    local ok, problem = pcall(function()
        local provider = program.run(declaration, "cleanupcontract")
        package.loaded.cleanupcontract = provider
        assert(program.run(consumer, "cleanupconsumer"))
        testAssert.eq(provider.closed, 1)
    end)
    package.loaded.cleanupcontract = loaded
    assert(ok, problem)
end

function M.aTerminalNamedInATypeIsRegisteredAtItsDeclaration()
    local source = table.concat(
        {
            "cdef function malloc(size: uint64): voidptr",
            "cdef function free(takes value: voidptr)",
            "local function allocate(): affine(voidptr, free)",
            "   return malloc(8)",
            "end",
            "local value = allocate()",
            "return true",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local ok, answer = pcall(program.run, result, "ownership-test")
    assert(ok, tostring(answer))
    testAssert.eq(answer, true, "the top-level owner was not discharged")
end

function M.closeableTypesCarryAnInherentCloseObligation()
    assertClean(
        table.concat(
            {
                "local record Client is own.Closeable",
                "   function flush(exclusive self): nil end",
                "   function close(takes self): nil end",
                "end",
                "local client = new Client()",
                "client:flush()",
            },
            "\n"
        )
    )
end

function M.affineOfAnAffineInterfaceSelectsItsInherentTerminal()
    assertClean(
        table.concat(
            {
                "local interface Sink is own.Closeable",
                "   close: @nosuspend function(takes self: Sink): nil",
                "end",
                "local record BufferSink is Sink",
                "   anchor: any",
                "   function close(takes self): nil end",
                "end",
                "local function open(borrows anchor: any): affine(Sink) borrows (anchor)",
                "   return new BufferSink(anchor = anchor)",
                "end",
                "local anchor = {}",
                "local sink = open(anchor)",
                "sink:close()",
            },
            "\n"
        )
    )
end

function M.constructorsMayInitializeCloseableFields()
    assertClean(
        table.concat(
            {
                "local record Resource is own.Closeable",
                "   function close(takes self): nil end",
                "end",
                "local record Pair",
                "   first: Resource?",
                "   second: Resource?",
                "   constructor(self, first: boolean, second: boolean)",
                "      if first then self.first = new Resource() end",
                "      if second then self.second = new Resource() end",
                "   end",
                "end",
                "local pair = new Pair(true, true)",
            },
            "\n"
        )
    )
end

function M.consumingAggregatesMayForwardTheWholeOwner()
    assertClean(
        table.concat(
            {
                "local record Resource is own.Closeable",
                "   function close(takes self): nil end",
                "end",
                "local record Box",
                "   value: Resource",
                "   function finish(takes self): nil",
                "      self.value:close()",
                "   end",
                "   function close(takes self): nil",
                "      self:finish()",
                "   end",
                "end",
                "local box = new Box(value = new Resource())",
                "box:close()",
            },
            "\n"
        )
    )
end

function M.aggregatesOwnTheAffineMemberActuallyStoredInAUnionField()
    local source = table.concat(
        {
            "local calls = ''",
            "local record Resource is own.Closeable",
            "   name: string",
            "   function close(takes self): nil calls = calls .. self.name end",
            "end",
            "local type Item = Resource | string",
            "local record Box",
            "   item: Item",
            "end",
            "do",
            "   local box = new Box(item = new Resource(name = 'r'))",
            "   print(box.item)",
            "end",
            "do",
            "   local box = new Box(item = 'plain')",
            "   print(box.item)",
            "end",
            "return calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-affine-union-field")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), "r", "only the affine union member is closed")
end

function M.affineInterfacesRequireOneValidTerminal()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local interface Broken is own.Affine<self.close>",
                    "   close: function(self: Broken): boolean",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2615"
    )

    local conflicts = codes(
        table.concat(
            {
                "local interface First is own.Affine<self.close>",
                "   close: @nosuspend function(takes self: First): nil",
                "end",
                "local interface Second is own.Affine<self.destroy>",
                "   destroy: @nosuspend function(takes self: Second): nil",
                "end",
                "interface Both is First, Second end",
            },
            "\n"
        )
    )
    assert(conflicts:find("NUPP2615", 1, true), conflicts)
end

function M.taskHandlesRemainRootedInTheirScope()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local escaped: any = nil",
                    "do local scope = coroutine.scope() ;",
                    "   escaped = scope:spawn(function(): integer return 1 end)",
                    "end",
                    "print(escaped)",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

function M.taskHandleAggregatesCarryTheirScopeProvenance()
    assertClean(
        table.concat(
            {
                "do local scope = coroutine.scope() ;",
                "   local handles = {scope:spawn(function(): integer return 1 end)}",
                "   handles[2] = scope:spawn(function(): integer return 2 end)",
                "   for _, handle in ipairs(handles) do print(handle:await()) end",
                "end",
            },
            "\n"
        )
    )

    local got = codes(
        table.concat(
            {
                "local kept: any = nil",
                "do local scope = coroutine.scope() ;",
                "   kept = {scope:spawn(function(): integer return 1 end)}",
                "end",
                "return kept",
            },
            "\n"
        )
    )
    assert(got:find("NUPP2608", 1, true), got)
end

function M.returningTaskSpawnsRefuseBorrowedAffineCaptures()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Resource is own.Closeable",
                    "   function close(takes self): nil end",
                    "end",
                    "local resource = new Resource()",
                    "do local scope = coroutine.scope() ;",
                    "   local callback = function(): nil borrows (resource)",
                    "      print(resource ~= nil)",
                    "   end",
                    "   scope:spawn(callback)",
                    "end",
                    "resource:close()",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- A scope joins every child before it settles, so a child body may borrow the scope it
-- is started on: the borrow cannot outlive what it borrows (D-16). It may borrow
-- nothing else, and a scope another scope settles first is something else.
function M.aChildBodyMayBorrowTheScopeThatStartsIt()
    assertClean(
        table.concat(
            {
                "local seen = 0",
                "do local scope = coroutine.scope(limit = 4) ;",
                "   for index = 1, 3 do",
                "      scope:spawn(function(): nil",
                "         scope:spawn(function(): nil seen = seen + index end)",
                "      end)",
                "   end",
                "   local function body(): nil",
                "      scope:cancel('done')",
                "   end",
                "   scope:spawn(body)",
                "   scope:spawn('canceller', function(): nil scope:cancel('named') end)",
                "end",
                "return seen",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "do local outer = coroutine.scope() ;",
                    "   do local inner = coroutine.scope() ;",
                    "      outer:spawn(function(): nil",
                    "         inner:spawn(function(): nil end)",
                    "      end)",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "a child of the outer scope may not borrow the inner one, which settles first"
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Resource is own.Closeable",
                    "   function close(takes self): nil end",
                    "end",
                    "do local resource = new Resource() ;",
                    "   do local scope = coroutine.scope() ;",
                    "      scope:spawn(function(): nil",
                    "         scope:cancel(tostring(resource ~= nil))",
                    "      end)",
                    "   end",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602",
        "borrowing the scope does not admit borrowing anything beside it"
    )
end

-- An owner moved into a record field is the record's to close: the region that held
-- it no longer runs its cleanup, wherever the construction stands -- a binding, an
-- argument, a statement or a return. Before, every one of these closed it twice.
function M.anOwnerMovedIntoAFieldIsClosedOnce()
    local source = table.concat(
        {
            "local closed: integer = 0",
            "local record Inner is own.Closeable",
            "   function close(takes self): nil closed = closed + 1 end",
            "end",
            "local record Outer is own.Closeable",
            "   _inner: Inner",
            "   function close(takes self): nil self._inner:close() end",
            "end",
            "local function viaLocal(): nil",
            "   local inner = new Inner()",
            "   local outer = new Outer(_inner = inner)",
            "   outer:close()",
            "end",
            "local function consume(takes o: Outer): nil o:close() end",
            "local function viaArgument(): nil",
            "   local inner = new Inner()",
            "   consume(new Outer(_inner = inner))",
            "end",
            "local function viaDrop(): nil",
            "   local inner = new Inner()",
            "   own.drop(new Outer(_inner = inner))",
            "end",
            "local function make(): Outer",
            "   local inner = new Inner()",
            "   return new Outer(_inner = inner)",
            "end",
            "local counts: {integer} = {}",
            "viaLocal() counts[1] = closed closed = 0",
            "viaArgument() counts[2] = closed closed = 0",
            "viaDrop() counts[3] = closed closed = 0",
            "local outer = make()",
            "counts[4] = closed",
            "own.drop(outer)",
            "counts[5] = closed",
            "return counts",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-field-move")
    assert(chunk, tostring(loadErr))
    testAssert.eq(table.concat(chunk(), ","), "1,1,1,0,1", "each moved owner is closed once, by the record")
end

-- A one-argument affine(T) reads T's terminal as it resolves. Named above T's own
-- declaration -- a field or method of an earlier record -- it used to resolve before
-- T's `is` claim was read, and settled on a transfer-only owner with no terminal, so
-- ordinary local ownership refused it (NUPP2615). The claim may come straight from the
-- prelude, through an interface declared further down, or onto a generic declaration.
function M.aClaimDeclaredBelowItsFirstUseStillGivesATerminal()
    local source = table.concat(
        {
            "local closed: integer = 0",
            "local record Spec",
            "   compile: function(borrows self: Spec): affine(Kernel)",
            "   box: function(borrows self: Spec): affine(Box<integer>)",
            "   function viaMethod(borrows self): affine(Kernel) return self:compile() end",
            "end",
            "local record Kernel is Resource",
            "   function close(takes self): nil closed = closed + 1 end",
            "end",
            "local record Box<T> is own.Closeable",
            "   v: T",
            "   function close(takes self): nil closed = closed + 10 end",
            "end",
            "local interface Resource is own.Closeable end",
            "local spec = new Spec(",
            "   compile = function(borrows self: Spec): affine(Kernel) return new Kernel() end,",
            "   box = function(borrows self: Spec): affine(Box<integer>)",
            "      return new Box<integer>(v = 2)",
            "   end",
            ")",
            "do local k = spec:compile() ; end",
            "do local b = spec:box() ; end",
            "do local m = spec:viaMethod() ; end",
            "return closed",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-forward-claim")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), 12, "each acquisition is closed once at the end of its with")
end

-- The same inside one record's body: a nested declaration named above the nested
-- one that claims Closeable. Its claim is read with its siblings' names in scope, so
-- an outer interface of the same name as a nested one lends it nothing.
function M.aNestedClaimDeclaredBelowItsFirstUseStillGivesATerminal()
    local source = table.concat(
        {
            "local closed: integer = 0",
            "local interface Resource end",
            "local record Outer",
            "   record Spec",
            "      compile: function(borrows self: Outer.Spec): affine(Outer.Kernel)",
            "      plain: function(borrows self: Outer.Spec): affine(Outer.Plain)",
            "   end",
            "   record Kernel is Resource",
            "      function close(takes self): nil closed = closed + 1 end",
            "   end",
            "   record Plain is own.Closeable",
            "      function close(takes self): nil closed = closed + 10 end",
            "   end",
            "   interface Resource is own.Closeable end",
            "end",
            "local spec = new Outer.Spec(",
            "   compile = function(borrows self: Outer.Spec): affine(Outer.Kernel)",
            "      return new Outer.Kernel()",
            "   end,",
            "   plain = function(borrows self: Outer.Spec): affine(Outer.Plain) return new Outer.Plain() end",
            ")",
            "do local k = spec:compile() ; end",
            "do local p = spec:plain() ; end",
            "return closed",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-nested-forward-claim")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), 11, "each acquisition is closed once at the end of its with")
end

-- Reading claims ahead of the bodies must not instantiate a generic declaration
-- before it is filled: the instantiation would keep the half-built members and
-- supertypes it was made from.
function M.readingClaimsEarlyLeavesALaterGenericContractIntact()
    local source = table.concat(
        {
            "local interface Source<T>",
            "   read: function(self): T",
            "end",
            "local interface NumberSource is Source<number>",
            "   reset: function(self): nil",
            "end",
            "local record Counter is NumberSource",
            "   n: number",
            "   function read(self): number return self.n end",
            "   function reset(self): nil self.n = 0 end",
            "end",
            "local c: NumberSource = new Counter(n = 3)",
            "return c:read()",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
end

-- An optional owner narrowed by `if p == nil then error() end` is as present as one
-- `assert` unwrapped, so its affine field moves the same way. The move used to be
-- refused, because the field was looked for on the declared `P?` rather than on the
-- record behind the nil.
function M.aFieldMovesOutOfAnOptionalOwnerOnceItIsNarrowed()
    local source = table.concat(
        {
            "local record W is own.Closeable function close(takes self): nil end end",
            "local record P is own.Closeable",
            "   w: W?",
            "   function close(takes self): nil if self.w ~= nil then self.w:close() end end",
            "end",
            "local function make(): (affine(P)?, string?) return new P(w = new W()), nil end",
            "local function consume(takes w: W?): nil if w ~= nil then w:close() end end",
            "local function viaAssert(): nil",
            "   local p = assert(make())",
            "   consume(p.w)",
            "end",
            "local function viaError(): nil",
            "   local p, err = make()",
            "   if p == nil then error(err) end",
            "   consume(p.w)",
            "end",
            "local function viaBranch(): nil",
            "   local p = make()",
            "   if p ~= nil then consume(p.w) end",
            "end",
        },
        "\n"
    )
    local _, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
end

-- A record whose own `close` closes its fields runs it on whatever it still holds.
-- Moving an optional field out used to leave the field in place, so the record's
-- close closed it a second time; the move is now a take that leaves nil behind,
-- however the field leaves -- a takes argument, a consuming method, a binding, a
-- return, or another record's construction.
function M.anOptionalFieldTakenFromASelfClosingRecordIsClosedOnce()
    local source = table.concat(
        {
            "local closed: integer = 0",
            "local record W is own.Closeable",
            "   function close(takes self): nil closed = closed + 1 end",
            "end",
            "local record P is own.Closeable",
            "   w: W?",
            "   function close(takes self): nil",
            "      if self.w ~= nil then self.w:close() end",
            "      closed = closed + 100",
            "   end",
            "end",
            "local record Box is own.Closeable",
            "   held: W?",
            "   function close(takes self): nil if self.held ~= nil then self.held:close() end end",
            "end",
            "local function consume(takes w: W?): nil if w ~= nil then w:close() end end",
            "local function viaArgument(): nil local p = new P(w = new W()) consume(p.w) end",
            "local function viaMethod(): nil",
            "   local p = new P(w = new W())",
            "   if p.w ~= nil then p.w:close() end",
            "end",
            "local function viaBinding(): nil",
            "   local p = new P(w = new W())",
            "   local w = p.w",
            "   if w ~= nil then w:close() end",
            "end",
            "local function viaConstruction(): nil",
            "   local p = new P(w = new W())",
            "   local b = new Box(held = p.w)",
            "end",
            "local function viaRefill(): nil",
            "   local p = new P(w = new W())",
            "   consume(p.w)",
            "   p.w = nil",
            "   p:close()",
            "end",
            "local function viaReturn(): W? local p = new P(w = new W()) return p.w end",
            "local counts: {integer} = {}",
            "for _, run in ipairs({viaArgument, viaMethod, viaBinding, viaConstruction, viaRefill}) do",
            "   closed = 0",
            "   run()",
            "   counts[#counts + 1] = closed",
            "end",
            "closed = 0",
            "local w = viaReturn()",
            "counts[#counts + 1] = closed",
            "consume(w)",
            "counts[#counts + 1] = closed",
            "return counts",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-field-take")
    assert(chunk, tostring(loadErr))
    testAssert.eq(table.concat(chunk(), ","), "101,101,101,101,101,100,101", "the taken field is closed once")
end

-- A field that cannot hold nil has nothing to leave behind, so it cannot move out
-- of a record whose own cleanup would close it again, and the help says how to let
-- it. A record closed field by field keeps its per-field moves.
function M.aRequiredFieldCannotLeaveASelfClosingRecord()
    local source = table.concat(
        {
            "local record W is own.Closeable function close(takes self): nil end end",
            "local record P is own.Closeable",
            "   w: W",
            "   function close(takes self): nil self.w:close() end",
            "end",
            "local record Pair",
            "   w: W",
            "   o: W",
            "end",
            "local function consume(takes w: W): nil w:close() end",
            "local function refused(): nil local p = new P(w = new W()) consume(p.w) end",
            "local function admitted(): nil local pair = new Pair(w = new W(), o = new W()) consume(pair.w) end",
            "return {refused = refused, admitted = admitted}",
        },
        "\n"
    )
    local _, diags = checked(source)
    testAssert.eq(#diags, 1, diags[2] and diags[2].msg or "one refusal")
    testAssert.eq(diags[1].code, "NUPP2602")
    assert(diags[1].msg:find("cannot move out of a record its own cleanup closes", 1, true), diags[1].msg)
    assert(diags[1].help and diags[1].help:find("`w: W?`", 1, true), tostring(diags[1].help))
end

-- An optional aggregate owner is closed field by field, as the same record is when
-- it cannot be nil. The optional's cleanups used to be rebuilt from the obligation
-- tree, which keeps the field only as a component, so each became `close` on the
-- record itself: the scope's end raised "attempt to call method 'close'".
function M.anOptionalAggregateOwnerClosesItsFields()
    local source = table.concat(
        {
            "local closed: integer = 0",
            "local record W is own.Closeable",
            "   function close(takes self): nil closed = closed + 1 end",
            "end",
            "local record P",
            "   w: W?",
            "   o: W?",
            "end",
            "local function make(ok: boolean): (P?, string?)",
            "   if ok then return new P(w = new W(), o = new W()), nil end",
            "   return nil, 'no'",
            "end",
            "local function consume(takes w: W?): nil if w ~= nil then w:close() end end",
            "local function held(): nil local p = make(true) end",
            "local function viaError(): integer",
            "   local p, err = make(true)",
            "   if p == nil then error(err) end",
            "   consume(p.w)",
            "   return closed",
            "end",
            "local function absent(): nil local p = make(false) end",
            "held()",
            "local whole = closed",
            "closed = 0",
            "local during = viaError()",
            "local after = closed",
            "closed = 0",
            "absent()",
            "return {whole, during, after, closed}",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-optional-aggregate")
    assert(chunk, tostring(loadErr))
    local ok, counts = pcall(chunk)
    assert(ok, tostring(counts))
    testAssert.eq(table.concat(counts, ","), "2,1,2,0", "each field is closed once")
end

-- Reaching through the nil is only for an owner the checker already knows is there:
-- indexing the optional owner itself is still refused.
function M.aFieldCannotMoveOutOfAnOwnerThatMayBeNil()
    local source = table.concat(
        {
            "local record W is own.Closeable function close(takes self): nil end end",
            "local record P is own.Closeable",
            "   w: W?",
            "   function close(takes self): nil if self.w ~= nil then self.w:close() end end",
            "end",
            "local function make(): affine(P)? return new P(w = new W()) end",
            "local function consume(takes w: W?): nil if w ~= nil then w:close() end end",
            "local p = make()",
            "consume(p.w)",
        },
        "\n"
    )
    local _, diags = checked(source)
    testAssert.eq(#diags, 1, "only the index is refused")
    testAssert.eq(diags[1].code, "NUPP2004")
end

function M.cancellingAQueuedTaskDropsItsTransferredCaptures()
    local source = table.concat(
        {
            "local drops = 0",
            "local record Resource is own.Closeable",
            "   function close(takes self): nil drops = drops + 1 end",
            "end",
            "do local scope = coroutine.scope() ;",
            "   local resource = new Resource()",
            "   local child = scope:spawn(function(): nil takes (resource)",
            "      resource:close()",
            "   end)",
            "   child:cancel()",
            "end",
            "return drops",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "ownership-task-capture")
    assert(chunk, tostring(loadErr))
    testAssert.eq(chunk(), 1, "the cancelled child's uncalled capture was not dropped")
end

-- A consuming parameter whose type names a terminal is an owner the body has to
-- discharge. The first `takes` parameter used to be marked consumed at the end of
-- every body, the exemption a terminal's own definition needs applied to every
-- function, so a body that returned early or fell through leaked it silently.
local CONSUMABLE = table.concat(
    {
        "local record Res is own.Closeable",
        "   id: integer",
        "   function flush(exclusive self): nil end",
        "   function close(takes self): nil end",
        "end",
        "local function open(id: integer): Res return new Res(id = id) end",
    },
    "\n"
)

function M.takesParameterLeftLiveAtAReturnIsReported()
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local function sink(takes r: Res, flag: boolean): nil",
                    "   if flag then return end",
                    "   own.drop(r)",
                    "end",
                    "sink(open(1), true)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.takesParameterLeftLiveAtTheBodyEndIsReported()
    testAssert.eq(
        codes(CONSUMABLE .. "\nlocal function sink(takes r: Res): nil print(r.id) end\nsink(open(1))"),
        "NUPP2603"
    )
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local function sink(takes r: Res, takes s: Res): nil",
                    "   own.drop(s)",
                    "end",
                    "sink(open(1), open(2))",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local record Sink",
                    "   function keep(self, takes r: Res): nil print(r.id) end",
                    "end",
                    "local sink = new Sink()",
                    "sink:keep(open(1))",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.takesParameterDischargedOnOnlySomePathsIsReported()
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local function sink(takes r: Res, flag: boolean): nil",
                    "   if flag then own.drop(r) end",
                    "end",
                    "sink(open(1), true)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local function sink(takes r: Res, flag: boolean): integer",
                    "   return switch flag do",
                    "      case true -> 1",
                    "      else -> do own.drop(r) yield 2 end",
                    "   end",
                    "end",
                    "sink(open(1), true)",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.takesParameterDischargedOnEveryPathIsAccepted()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local function pass(takes r: Res): Res return r end",
                "local function sink(takes r: Res, flag: boolean): nil",
                "   if flag then",
                "      own.drop(r)",
                "      return",
                "   end",
                "   local kept = pass(r)",
                "   own.drop(kept)",
                "end",
                "local function either(takes r: Res, flag: boolean): nil",
                "   if flag then own.drop(r) else r:close() end",
                "end",
                "local function released(takes r: Res): integer",
                "   local raw = @unsafe own.release(r)",
                "   return raw.id",
                "end",
                "sink(open(1), true)",
                "either(open(2), false)",
                "print(released(open(3)))",
            },
            "\n"
        )
    )
end

function M.terminalDefinitionsAreTheEndpointOfTheirParameter()
    -- A cleanup function's payload names no terminal, and a record's own terminal
    -- method is what the obligation runs: neither body has anything left to
    -- discharge.
    assertClean(
        table.concat(
            {
                "local record File",
                "   closed: boolean",
                "end",
                "local function closeFile(takes file: File): nil file.closed = true end",
                "local function openFile(): affine(File, closeFile) return new File(closed = false) end",
                "local record Sock is own.Closeable",
                "   closed: boolean",
                "   function flush(exclusive self): nil end",
                "   function close(takes self): nil self.closed = true end",
                "end",
                "local file = openFile()",
                "own.drop(file)",
                "local sock = new Sock(closed = false)",
                "own.drop(sock)",
            },
            "\n"
        )
    )
end

-- A non-retaining parameter keeps an owned temporary alive for the full statement,
-- after which the generator can run its terminal. Other uses still have no sound
-- place to discharge the temporary and remain diagnostics.
function M.anOwnedTemporaryLoanedForOneStatementIsAccepted()
    local header = CONSUMABLE .. "\n" .. table.concat(
        {
            "local function use(borrows r: Res): nil print(r.id) end",
            "local function edit(exclusive r: Res): nil r.id = r.id end",
            "local function pass(takes r: Res): Res return r end",
        },
        "\n"
    ) .. "\n"
    assertClean(header .. "use(open(1))")
    assertClean(header .. "edit(open(2))")
    assertClean(header .. "open(3):flush()")
    assertClean(header .. "use(new Res(id = 4))")
    assertClean(header .. "use(pass(open(5)))")
    assertClean(header .. "local flag = true\nuse(switch flag do case true -> open(6) else -> open(7) end)")
end

function M.statementOwnedTemporariesRunTheirTerminalsAtCompletion()
    local source = table.concat(
        {
            "local calls = ''",
            "local record Res is own.Closeable",
            "   name: string",
            "   function flush(exclusive self): nil end",
            "   function close(takes self): nil calls = calls .. self.name end",
            "end",
            "local function open(name: string): Res return new Res(name = name) end",
            "local function openPair(name: string): (Res, string) return new Res(name = name), 'p' end",
            "local function inspect(borrows first: Res, exclusive second: Res): nil",
            "   calls = calls .. 'u' .. first.name .. second.name",
            "end",
            "local function inspectPair(borrows value: Res, label: string): nil calls = calls .. label end",
            "local function view(borrows value: Res): string",
            "   calls = calls .. 'v'",
            "   return value.name",
            "end",
            "local function inspectLabel(borrows value: Res, label: string): nil",
            "   calls = calls .. value.name .. label",
            "end",
            "local function returning(): string return view(open('r')) end",
            "local function raising(): nil inspectLabel(open('e'), error('boom')) end",
            "inspect(open('a'), open('b'))",
            "inspectPair(openPair('q'))",
            "open('m'):flush()",
            "local answer = returning()",
            "local ok = pcall(raising)",
            "return answer, ok, calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "statement-owned-temporaries")
    assert(chunk, tostring(loadErr))
    local answer, ok, calls = chunk()
    testAssert.eq(answer, "r")
    testAssert.eq(ok, false)
    testAssert.eq(calls, "uabbapqmvre")
end

-- A local declared by a statement that owns a temporary is bound after it: the
-- statement runs inside the cleanup region's function, and the name used to be
-- declared there and lost with it. Each activation keeps its own binding, so a
-- region reused by a loop or a recursive call never writes another one's.
function M.aLocalInitializedThroughAStatementOwnedTemporaryIsBound()
    local source = table.concat(
        {
            "local calls = ''",
            "local record Res is own.Closeable",
            "   name: string",
            "   function close(takes self): nil calls = calls .. self.name end",
            "end",
            "local function open(name: string): Res return new Res(name = name) end",
            "local function view(borrows value: Res): string",
            "   calls = calls .. 'v'",
            "   return value.name",
            "end",
            "local function both(borrows value: Res): (string, integer) return value.name, #value.name end",
            "local top = view(open('t'))",
            "local name, size = both(open('pq'))",
            "local kept: {function(): string} = {}",
            "for i = 1, 3 do",
            "   local each = view(open(tostring(i)))",
            "   kept[#kept + 1] = function(): string return each end",
            "end",
            "local function nest(level: integer): string",
            "   local here = view(open(tostring(level)))",
            "   if level < 3 then",
            "      local deeper = nest(level + 1)",
            "      return here .. deeper",
            "   end",
            "   return here",
            "end",
            "local nested = nest(1)",
            "return top, name, size, kept[1]() .. kept[2]() .. kept[3](), nested, calls",
        },
        "\n"
    )
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, loadErr = program.load(result, "statement-owned-locals")
    assert(chunk, tostring(loadErr))
    local top, name, size, loop, nested, calls = chunk()
    testAssert.eq(top, "t")
    testAssert.eq(name, "pq")
    testAssert.eq(size, 2)
    testAssert.eq(loop, "123")
    testAssert.eq(nested, "123")
    testAssert.eq(calls, "vtpqv1v2v3v1v2v3")
end

function M.anOwnedTemporaryWithoutANonRetainingLoanIsReported()
    local header = CONSUMABLE .. "\nlocal function use(borrows r: Res): nil print(r.id) end\n"
    testAssert.eq(codes(header .. "print(open(2).id)"), "NUPP2603")
    testAssert.eq(codes(header .. "if open(3) then print('made') end"), "NUPP2603")
end

function M.aBorrowFromAStatementOwnedTemporaryCannotEscapeTheStatement()
    testAssert.eq(
        codes(
            CONSUMABLE
            .. "\nlocal function view(borrows value: Res): Res borrows(value) return value end"
            .. "\nlocal dangling = view(open(1))\nprint(dangling.id)"
        ),
        "NUPP2619"
    )
end

function M.anOwnedTemporaryThatIsBoundMovedOrReturnedIsAccepted()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local record Holder",
                "   kept: Res",
                "end",
                "local function sink(takes r: Res): nil own.drop(r) end",
                "local function pass(takes r: Res): Res return r end",
                "local function make(id: integer): Res return new Res(id = id) end",
                "local function pick(flag: boolean): Res",
                "   return switch flag do",
                "      case true -> open(1)",
                "      else -> do yield open(2) end",
                "   end",
                "end",
                "local a = open(3)",
                "local b = (open(4))",
                "local c = pass(open(5))",
                "local d = open(6)",
                "local h = new Holder(kept = open(7))",
                "sink(open(8))",
                "own.drop(open(9))",
                "sink(make(10))",
                "sink(pick(true))",
                "local raw = @unsafe own.release(open(11))",
                "print(raw.id)",
                "do local w = open(12) ; print(w.id) end",
                "own.drop(a)",
                "own.drop(b)",
                "own.drop(c)",
                "own.drop(d)",
                "own.drop(h)",
            },
            "\n"
        )
    )
end

-- A field moved out of an owning record is state that flows like the whole
-- owner's: a loop that moves it again on its next iteration, and a branch that
-- moves it on some arms only, used to pass because the moved-field set was
-- recorded once and never compared at a back edge or a join.
local PAIR = table.concat(
    {
        CONSUMABLE,
        "local record Pair",
        "   left: Res",
        "   right: Res",
        "end",
        "local function consume(takes r: Res): nil own.drop(r) end",
        "local function pair(): Pair return new Pair(left = open(1), right = open(2)) end",
    },
    "\n"
)

function M.aFieldMovedInsideALoopIsReportedAtTheBackEdge()
    testAssert.eq(codes(PAIR .. "\nlocal p = pair()\nfor i = 1, 2 do consume(p.left) end"), "NUPP2609")
    testAssert.eq(
        codes(PAIR .. "\nlocal p = pair()\nlocal n = 0\nwhile n < 2 do n = n + 1 consume(p.left) end"),
        "NUPP2609"
    )
    assertClean(PAIR .. "\nlocal p = pair()\nfor i = 1, 2 do consume(p.left) break end")
end

function M.aFieldMovedOnSomePathsOfAnAutomaticOwnerIsDroppedConditionally()
    assertClean(
        PAIR .. "\n" .. table.concat(
            {
                "local function run(flag: boolean): nil",
                "   local p = pair()",
                "   if flag then consume(p.left) end",
                "   own.drop(p)",
                "end",
                "local function lexical(flag: boolean): nil",
                "   local p = pair()",
                "   if flag then consume(p.left) end",
                "end",
                "run(true)",
                "lexical(false)",
            },
            "\n"
        )
    )
    -- The field may still be live on the other path, so it cannot be refilled; the
    -- refused store is then judged as any other store of an owner is.
    testAssert.eq(
        codes(
            PAIR .. "\n" .. table.concat(
                {"local p = pair()", "if p.right.id == 2 then consume(p.left) end", "p.left = open(3)", "own.drop(p)",},
                "\n"
            )
        ),
        "NUPP2602 NUPP2603"
    )
end

function M.aFieldMovedOnSomePathsOfAConsumingParameterIsReported()
    -- A parameter has no run-time record of which fields it still holds, so the
    -- arms have to agree.
    testAssert.eq(
        codes(
            PAIR .. "\n" .. table.concat(
                {
                    "local function sink(takes p: Pair, flag: boolean): nil",
                    "   if flag then consume(p.left) end",
                    "   own.drop(p.left)",
                    "   own.drop(p.right)",
                    "end",
                    "sink(pair(), true)",
                },
                "\n"
            )
        ),
        "NUPP2603 NUPP2601 NUPP2602"
    )
    assertClean(
        PAIR .. "\n" .. table.concat(
            {
                "local function sink(takes p: Pair, flag: boolean): nil",
                "   if flag then consume(p.left) else own.drop(p.left) end",
                "   own.drop(p.right)",
                "end",
                "sink(pair(), true)",
            },
            "\n"
        )
    )
end

function M.anOwnedFieldLeftLiveAtAReturnFromATerminalIsReported()
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local record Guarded",
                    "   resource: Res",
                    "   closed: boolean",
                    "   function close(takes self): nil",
                    "      if self.closed then return end",
                    "      self.closed = true",
                    "      self.resource:close()",
                    "   end",
                    "end",
                    "local guarded = new Guarded(resource = open(1), closed = false)",
                    "guarded:close()",
                },
                "\n"
            )
        ),
        "NUPP2603"
    )
end

function M.aFieldDischargedBeforeAReturnFromAConsumingParameterIsAccepted()
    assertClean(
        PAIR .. "\n" .. table.concat(
            {
                "local function sink(takes p: Pair): nil",
                "   own.drop(p.left)",
                "   own.drop(p.right)",
                "   return",
                "end",
                "local function pass(takes p: Pair): Pair",
                "   return p",
                "end",
                "sink(pair())",
                "own.drop(pass(pair()))",
            },
            "\n"
        )
    )
end

function M.anOwnedFieldNarrowedToNilAtAReturnNeedsNoDischarge()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local record MaybePair",
                "   left: Res?",
                "   right: Res",
                "end",
                "local function sink(takes p: MaybePair): nil",
                "   own.drop(p.right)",
                "   if p.left == nil then return end",
                "   own.drop(p.left)",
                "end",
                "sink(new MaybePair(left = open(1), right = open(2)))",
            },
            "\n"
        )
    )
end

-- An optional consuming parameter that an arm narrows to nil holds nothing on
-- that arm, so discharging it on the other arm only is not a partial discharge.
function M.anOptionalConsumingParameterNarrowedToNilIsDischarged()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local function sink(takes r: Res?): nil",
                "   if r ~= nil then own.drop(r) end",
                "end",
                "local function other(takes r: Res?): nil",
                "   if r == nil then return end",
                "   own.drop(r)",
                "end",
                "sink(open(1))",
                "sink(nil)",
                "other(open(2))",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            CONSUMABLE
            .. "\nlocal function sink(takes r: Res?, flag: boolean): nil\n   if flag then own.drop(r) end\nend\nsink(open(1), true)"
        ),
        "NUPP2603"
    )
end

-- An owner handed out by an iterator is dropped at the end of each iteration
-- like a local; it used to be reported as leaking at the loop variable.
function M.aForInVariableHoldingAnOwnerIsDroppedEachIteration()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local function use(borrows r: Res): nil print(r.id) end",
                "local function iter(state: integer, control: integer): (integer?, Res?)",
                "   if control >= 2 then return nil, nil end",
                "   return control + 1, open(control + 1)",
                "end",
                "for i, r in iter, 0, 0 do",
                "   if r then use(r) end",
                "   if i == 2 then break end",
                "end",
            },
            "\n"
        )
    )
end

-- A `Res?` local keeps its optionality: nil fills the slot back once the owner
-- is discharged, and a slot that starts nil takes its first owner without
-- overwriting anything. A live owner is still never overwritten.
function M.anOptionalOwnerSlotIsFilledOnceAndClearedAfterDischarge()
    assertClean(CONSUMABLE .. "\nlocal a: Res? = open(1)\nown.drop(a)\na = nil")
    testAssert.eq(codes(CONSUMABLE .. "\nlocal a: Res? = open(1)\na = nil"), "NUPP2602")
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local function use(borrows r: Res): nil print(r.id) end",
                "local function late(flag: boolean): nil",
                "   local b: Res? = nil",
                "   if flag then b = open(1) end",
                "   if b ~= nil then use(b) end",
                "end",
                "late(true)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            CONSUMABLE
            .. "\nlocal function twice(flag: boolean): nil\n   local c: Res? = nil\n   if flag then c = open(2) end\n   c = open(3)\nend\ntwice(true)"
        ),
        "NUPP2602"
    )
end

-- A switch arm that names an owner moves it into the switch's value, so the name
-- is spent afterwards and the binding that takes the value closes it once.
function M.aSwitchArmNamingAnOwnerMovesIt()
    assertClean(
        CONSUMABLE .. "\n" .. table.concat(
            {
                "local function pick(flag: boolean): nil",
                "   local a = open(1)",
                "   local b = switch flag do",
                "      case true -> a",
                "      else -> do yield open(2) end",
                "   end",
                "   own.drop(b)",
                "end",
                "pick(true)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            CONSUMABLE .. "\n" .. table.concat(
                {
                    "local function use(borrows r: Res): nil print(r.id) end",
                    "local function pick(flag: boolean): nil",
                    "   local a = open(1)",
                    "   local b = switch flag do",
                    "      case true -> a",
                    "      else -> open(2)",
                    "   end",
                    "   use(a)",
                    "   own.drop(b)",
                    "end",
                    "pick(true)",
                },
                "\n"
            )
        ),
        "NUPP2601"
    )
end

-- An implicit global has no declaration, so a leak through it used to be
-- reported at 0:0; the assignment that made the global is where it belongs.
function M.aLeakThroughAnImplicitGlobalIsReportedAtTheAssignment()
    local _, diags = checked(
        CONSUMABLE .. "\nlocal function stash(): nil\n   local a = open(1)\n   kept = a\nend\nstash()"
    )
    testAssert.eq(#diags, 1, diags[1] and diags[1].msg or "one leak")
    testAssert.eq(diags[1].code, "NUPP2603")
    testAssert.eq(diags[1].line, 9, "reported at the assignment")
end

-- A local function that reads a captured owner borrows it, as a function
-- expression doing the same would, so it cannot leave the scope that owns the
-- capture: not through a return, a table, or an assignment to an outer binding.
-- It used to bind its type unwrapped, so every escape check keyed on the borrowed
-- tag let it through and the caller ran it over a closed resource.
function M.aLocalFunctionCapturingAnOwnerCannotEscapeItsScope()
    local function escaping(resultType, escape)
        return CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local function make(): " .. resultType,
                "   local resource = openClosureResource(7)",
                "   local function peek(): integer",
                "      return resource.value",
                "   end",
                "   return " .. escape,
                "end",
                "print(make())",
            },
            "\n"
        )
    end

    testAssert.eq(codes(escaping("function(): integer", "peek")), "NUPP2608", "returned")
    testAssert.eq(codes(escaping("{function(): integer}", "{peek}")), "NUPP2603", "stored in a table")
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local kept: function(): integer",
                    "do",
                    "   local resource = openClosureResource(7)",
                    "   local function peek(): integer",
                    "      return resource.value",
                    "   end",
                    "   kept = peek",
                    "end",
                    "print(kept())",
                },
                "\n"
            )
        ),
        "NUPP2608",
        "assigned outward"
    )
end

-- The borrow a local function holds is still checked at each call rather than held
-- as a lexical loan, so dropping the owner first and calling afterwards is what is
-- refused, and a call before the drop is fine.
function M.aLocalFunctionStillBorrowsItsCaptureAtEachCall()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local resource = openClosureResource(7)",
                "local function peek(): integer",
                "   return resource.value",
                "end",
                "print(peek())",
                "own.drop(resource)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local resource = openClosureResource(7)",
                    "local function peek(): integer",
                    "   return resource.value",
                    "end",
                    "own.drop(resource)",
                    "print(peek())",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- A record built from a borrow is a view of what the borrow came from, so it
-- leaves the scope on the borrow's terms: returned only under a declared
-- `borrows (source)`. The argument path only asked about owners, so a closure over
-- an owner and a local function reading one landed in a field, and the record was
-- returned and used after its root was closed.
function M.aRecordBuiltFromABorrowIsAViewOfItsRoot()
    local function constructed(field, value)
        return CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local record Holder",
                "   " .. field,
                "end",
                "local function make(): Holder",
                "   local resource = openClosureResource(7)",
                "   local function peek(): integer",
                "      return resource.value",
                "   end",
                "   return new Holder(" .. value .. ")",
                "end",
                "print(make())",
            },
            "\n"
        )
    end

    testAssert.eq(
        codes(constructed("peek: function(): integer", "peek = function(): integer return resource.value end")),
        "NUPP2608",
        "a closure over an owner"
    )
    testAssert.eq(codes(constructed("peek: function(): integer", "peek = peek")), "NUPP2608", "a local function")
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local record Holder",
                "   peek: function(): integer",
                "end",
                "local function wrap(borrows resource: ClosureResource): Holder borrows (resource)",
                "   return new Holder(peek = function(): integer return resource.value end)",
                "end",
                "local resource = openClosureResource(7)",
                "do",
                "   local holder = wrap(resource)",
                "   print(holder.peek())",
                "end",
                "own.drop(resource)",
            },
            "\n"
        )
    )
end

-- An owning field is discharged by the record's cleanup, so a borrow put there
-- would be closed by something that never owned it: a double close once the root
-- is dropped too. No declared relation makes that sound, so it is refused outright.
function M.aBorrowCannotFillAnOwningRecordField()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local record Holder",
                    "   kept: affine(ClosureResource, closeClosureResource)",
                    "end",
                    "local function wrap(borrows resource: ClosureResource): Holder",
                    "   return new Holder(kept = resource)",
                    "end",
                    "local resource = openClosureResource(7)",
                    "local holder = wrap(resource)",
                    "own.drop(resource)",
                    "own.drop(holder)",
                },
                "\n"
            )
        ),
        "NUPP2603",
        "a borrows parameter into an owning field"
    )
end

-- A borrow crosses an untyped boundary on the same terms as an owner: what the
-- callee does with it cannot be seen, and one that keeps it reads a closed
-- resource. Only owners were asked about, so a borrows parameter, an any vararg,
-- and a closure handed to coroutine.create all crossed.
function M.aBorrowCannotCrossAnAnyParameter()
    local function crossing(declaration, call)
        return CLOSURE_RESOURCE .. table.concat(
            {
                "",
                declaration,
                "local function via(borrows resource: ClosureResource): nil",
                "   " .. call,
                "end",
                "local resource = openClosureResource(7)",
                "via(resource)",
                "own.drop(resource)",
            },
            "\n"
        )
    end

    testAssert.eq(
        codes(crossing("local function keep(value: any): nil print(value) end", "keep(resource)")),
        "NUPP2611",
        "an any parameter"
    )
    testAssert.eq(
        codes(crossing("local function pack(...: any): {any} return {...} end", "print(pack(resource))")),
        "NUPP2611",
        "an any vararg"
    )
    testAssert.eq(
        codes(crossing("", "coroutine.create(function(): nil print(resource.value) end)")),
        "NUPP2611",
        "a coroutine body"
    )
    testAssert.eq(codes(crossing("local sink: any", "sink(resource)")), "NUPP2611", "a callable held in an any local")
end

-- The way out of the refusal above is a declaration, not an escape hatch. A
-- local holding a callable may spell the same parameter modes a function
-- declaration spells, and once it does the call is no longer untyped: the
-- contract on the slot is what the callee is held to. This is how an
-- ahead-of-time wrapper hands its own borrowed parameter to the compiled body
-- of the same function, which `binding.builderLoader` emits, and it is only
-- sound because the slot says `borrows` -- an any-typed slot stays refused.
function M.aBorrowCrossesACallableSlotThatDeclaresBorrows()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local native: function(borrows value: ClosureResource): integer",
                "local function via(borrows resource: ClosureResource): integer",
                "   return native(resource)",
                "end",
                "local resource = openClosureResource(7)",
                "print(via(resource))",
                "own.drop(resource)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local native: function(value: ClosureResource): integer",
                    "local function via(borrows resource: ClosureResource): integer",
                    "   return native(resource)",
                    "end",
                    "local resource = openClosureResource(7)",
                    "print(via(resource))",
                    "own.drop(resource)",
                },
                "\n"
            )
        ),
        "NUPP2603",
        "a callable slot that declares no contract"
    )
end

-- Every other route into any reports NUPP2611. A record field typed any was
-- exempted from the field check, so an owner constructed into one was held by a
-- record that would never close it.
function M.anOwnerCannotBeConstructedIntoAnAnyField()
    testAssert.eq(
        codes(
            CLOSURE_RESOURCE .. table.concat(
                {
                    "",
                    "local record Box",
                    "   item: any",
                    "end",
                    "local box = new Box(item = openClosureResource(7))",
                    "print(box.item)",
                },
                "\n"
            )
        ),
        "NUPP2611 NUPP2603"
    )
end

-- A callee that borrows a parameter promises to keep nothing, and a plain slot is
-- never handed an owner, so the promise fits the slot the way `scoped` does. The
-- other way round stays refused: a plain body may keep what a borrowing caller
-- handed it.
function M.aBorrowingFunctionFitsAPlainCallableSlot()
    assertClean(
        table.concat(
            {
                "local record Counter",
                "   value: integer",
                "   label: function(self: Counter): string",
                "end",
                "local function describe(borrows self: Counter): string",
                "   return tostring(self.value)",
                "end",
                "local c = new Counter(value = 1, label = describe)",
                "local d = new Counter(value = 2, label = tostring)",
                "print(c.value + d.value)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local record Counter",
                    "   value: integer",
                    "end",
                    "local function plain(self: Counter): string",
                    "   return tostring(self.value)",
                    "end",
                    "local slot: function(borrows self: Counter): string = plain",
                    "print(slot)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )
end

-- The prelude's identity and rendering helpers read their argument and keep
-- nothing, so a borrow may reach them. They were declared over plain `any`, and
-- holding a borrow at the any boundary then refused `tostring(view)` and
-- `rawequal(view, other)` alongside the stores that actually retain.
function M.aBorrowMayReachThePreludesNonRetainingHelpers()
    assertClean(
        CLOSURE_RESOURCE .. table.concat(
            {
                "",
                "local function probe(borrows r: ClosureResource): string",
                "   local same = rawequal(r, r)",
                "   local n = rawlen({})",
                "   print(r)",
                "   return type(r) .. tostring(r) .. tostring(same) .. tostring(n)",
                "end",
                "local r = openClosureResource(1)",
                "print(r)",
                "print(probe(r))",
                "own.drop(r)",
            },
            "\n"
        )
    )
end

-- A shared call may read through the live exclusive view that supplies its value.
-- The exclusive loan blocks a competing read through the owner, not a reborrow of
-- that same view while evaluating a non-retaining argument.
function M.aSharedArgumentMayReadThroughItsExclusiveView()
    assertClean(
        table.concat(
            {
                "local spans = require(\"binary.span\")",
                "local storage = ffi.new<int32[4]>()",
                "local writable = spans.writecarray(storage, 4)",
                "do",
                "   local pointer, count = writable:ref()",
                "   print(pointer ~= nil, count)",
                "end",
                "own.drop(writable)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local writable = spans.writecarray(storage, 4)",
                    "local pointer = writable:ref()",
                    "print(writable ~= nil)",
                    "print(pointer ~= nil)",
                },
                "\n"
            )
        ),
        "NUPP2607",
        "the exclusive view does not authorize a competing read through its owner"
    )
end

function M.anExclusiveReceiverCanReborrowItselfForACallback()
    assertClean(
        [[
local interface Output is own.Closeable
    write: function(exclusive self: Output, value: string): nil
end
local interface Emit<T>
    emit: function(self, borrows value: T, exclusive output: Output): nil
end
local record Sink is Output
    function write(exclusive self, value: string): nil end
    function emit<T>(exclusive self, borrows value: T, callback: Emit<T>): nil
        callback:emit(value, self)
    end
    function close(takes self): nil end
end
]]
    )
    local rejected = codes(
        [[
local record Sink is own.Closeable
    function close(takes self): nil end
    function view(borrows self): Sink borrows(self)
        return self
    end
    function write(exclusive self): nil end
    function invalid(exclusive self): nil
        local retained = self:view()
        self:write()
        print(retained)
    end
end
]]
    )
    testAssert.eq(rejected, "NUPP2607")
end

-- An owner is introduced by a typed producer or an audited adoption. Annotating a
-- binding minted one on whatever the initializer was -- a plain table from any --
-- and the scope exit then ran cleanup on something that was never a resource.
function M.anAnnotationCannotMintAnOwnerFromAny()
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {"", "local raw: any = {}", "local value: affine(resource*, resource_free) = raw", "own.drop(value)",},
                "\n"
            )
        ),
        "NUPP2611"
    )
    testAssert.eq(
        codes(
            RESOURCE .. table.concat(
                {
                    "",
                    "local raw: resource* = resource_create()",
                    "local value: affine(resource*, resource_free) = raw",
                    "own.drop(value)",
                },
                "\n"
            )
        ),
        "NUPP2001",
        "a plain value is not the affine type"
    )
    assertClean(
        RESOURCE .. table.concat(
            {"", "local value: affine(resource*, resource_free)? = nil", "print(value == nil)",},
            "\n"
        )
    )
end

-- An owner rooted in another owner is a view of it as much as a borrow is. The
-- assignment path moved the value and forgot the roots, so a rooted owner assigned
-- to a binding in an outer scope, or returned, outlived a root that lexical
-- destruction then closed underneath it.
function M.aRootedOwnerCannotOutliveItsRoot()
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {
                    "",
                    "local tls: affine(TLS, close_tls)",
                    "do",
                    "   local sock = open_socket()",
                    "   tls = open_tls(sock)",
                    "end",
                    "own.drop(tls)",
                },
                "\n"
            )
        ),
        "NUPP2608",
        "assigned to an outer binding"
    )
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {
                    "",
                    "local function leak(): affine(TLS, close_tls)",
                    "   local sock = open_socket()",
                    "   return open_tls(sock)",
                    "end",
                    "own.drop(leak())",
                },
                "\n"
            )
        ),
        "NUPP2608",
        "returned over a local root"
    )
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {
                    "",
                    "local function forget(borrows sock: Socket): affine(TLS, close_tls)",
                    "   return open_tls(sock)",
                    "end",
                    "local sock = open_socket()",
                    "own.drop(forget(sock))",
                    "own.drop(sock)",
                },
                "\n"
            )
        ),
        "NUPP2608",
        "returned without declaring the parameter it is rooted in"
    )
end

-- Assigned to a binding declared after its root, a rooted owner is held on the
-- same terms a `local` would hold it: the root cannot be dropped first.
function M.anAssignedRootedOwnerHoldsItsRoot()
    assertClean(
        LAYERED .. table.concat(
            {
                "",
                "local sock = open_socket()",
                "local tls: affine(TLS, close_tls)",
                "tls = open_tls(sock)",
                "own.drop(tls)",
                "own.drop(sock)",
            },
            "\n"
        )
    )
    testAssert.eq(
        codes(
            LAYERED .. table.concat(
                {
                    "",
                    "local sock = open_socket()",
                    "local tls: affine(TLS, close_tls)",
                    "tls = open_tls(sock)",
                    "own.drop(sock)",
                    "own.drop(tls)",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

-- A child span is rooted in the writer it was sliced from, so it cannot be handed
-- to a binding that outlives that writer either.
function M.aChildSpanCannotOutliveItsWriter()
    testAssert.eq(
        codes(
            table.concat(
                {
                    "local spans = require(\"binary.span\")",
                    "local storage = ffi.new<int32[4]>()",
                    "local child: spans.Writable<int32>",
                    "do",
                    "   local writable = spans.writecarray(storage, 4)",
                    "   child = writable:slice(2, 3)",
                    "end",
                    "child[1] = 1 as int32",
                    "own.drop(child)",
                },
                "\n"
            )
        ),
        "NUPP2608"
    )
end

-- A callee borrowing the whole record sees every field, including the one that is
-- gone. A whole move of a partially moved record is refused; the borrow argument
-- path never asked, so the callee read a closed resource through the borrow.
function M.aPartiallyMovedRecordCannotBeBorrowedWhole()
    local PAIR = RESOURCE .. table.concat(
        {
            "",
            "local record Pair",
            "   left: affine(resource*, resource_free)",
            "   right: affine(resource*, resource_free)",
            "   function peek(self): nil",
            "      print(self.left.value)",
            "   end",
            "end",
            "local function consume(takes value: affine(resource*, resource_free)): nil",
            "   resource_free(value)",
            "end",
            "local function peek(borrows pair: Pair): nil",
            "   print(pair.left.value)",
            "end",
            "local function poke(exclusive pair: Pair): nil",
            "   print(pair.left.value)",
            "end",
            "local pair = new Pair(left = resource_new(), right = resource_new())",
            "consume(pair.left)",
        },
        "\n"
    )
    testAssert.eq(codes(PAIR .. "\npeek(pair)\nown.drop(pair)"), "NUPP2602", "a borrows parameter")
    testAssert.eq(codes(PAIR .. "\npoke(pair)\nown.drop(pair)"), "NUPP2602", "an exclusive parameter")
    testAssert.eq(codes(PAIR .. "\npair:peek()\nown.drop(pair)"), "NUPP2602", "a method receiver")
    assertClean(PAIR .. "\nprint(pair.right.value)\nown.drop(pair)")
end

-- A loan names a place, and a place written as a field or index path has no entry
-- of its own, so the exclusive argument check found nothing to compare against
-- and let a writer in under a live view of the whole value. The region check now
-- counts a borrow of the whole root as overlapping every region below it.
function M.anExclusivePathArgumentIsCheckedAgainstLiveBorrowsOfItsRoot()
    local ROOTED = table.concat(
        {
            "local record Slot",
            "   n: integer",
            "end",
            "local record Root",
            "   one: Slot",
            "   items: {Slot}",
            "end",
            "local function excl(exclusive s: Slot): nil",
            "   s.n = s.n + 1",
            "end",
            "local function view(borrows r: Root): Root borrows (r)",
            "   return r",
            "end",
            "local function exclView(exclusive r: Root): Root borrows (r)",
            "   return r",
            "end",
            "local function viewSlot(borrows s: Slot): Slot borrows (s)",
            "   return s",
            "end",
            "local root = new Root(one = new Slot(n = 3), items = {new Slot(n = 1)})",
        },
        "\n"
    )
    testAssert.eq(
        codes(ROOTED .. "\nlocal a = view(root)\nexcl(root.one)\nprint(a.one.n)"),
        "NUPP2607",
        "a field under a whole view"
    )
    testAssert.eq(
        codes(ROOTED .. "\nlocal a = view(root)\nexcl(root.items[1])\nprint(a.one.n)"),
        "NUPP2607",
        "an index under a whole view"
    )
    testAssert.eq(
        codes(ROOTED .. "\nlocal w = exclView(root)\nviewSlot(root.one)\nprint(w.one.n)"),
        "NUPP2607",
        "a shared field view under a whole exclusive view"
    )
    assertClean(ROOTED .. "\nlocal b = viewSlot(root.one)\nexcl(root.items[1])\nprint(b.n)")
    assertClean(ROOTED .. "\ndo\n   local a = view(root)\n   print(a.one.n)\nend\nexcl(root.one)")
end

function M.doExpressionCarriesBorrowProvenance()
    assertClean(
        RESOURCE .. "\n" .. [[
local owner = resource_new()
local view = do yield borrow(owner) end
print(view.value)
]]
    )
    local escaped = codes(
        RESOURCE
        .. "\n"
        .. [[
local view = do
    local owner = resource_new()
    yield borrow(owner)
end
print(view.value)
]]
    )
    assert(escaped:find("NUPP2608", 1, true), escaped)
    local moved = codes(
        RESOURCE
        .. "\n"
        .. [[
local function transfer(flag: boolean): nil
    local owner = resource_new()
    local result = do
        if flag then yield owner end
        yield owner
    end
    print(owner.value)
    own.drop(result)
end
]]
    )
    assert(moved:find("NUPP2601", 1, true), moved)
end

function M.unsafeAnnotationKeepsOwnershipChecksAndOperandGrammar()
    local source = RESOURCE
        .. "\n"
        .. [[
local raw = resource_create()
local owner = @unsafe own.adopt<affine(resource*, resource_free)>(raw)
local released = @unsafe own.release(owner)
local restored = @unsafe own.adopt<affine(resource*, resource_free)>(released)
own.drop(restored)
]]
    assertClean(source)
    testAssert.eq(codes(source .. "\nlocal again = @unsafe own.release(owner)"), "NUPP2601")
    testAssert.eq(codes("local n = @unsafe own.release(1)"), "NUPP2602 NUPP2602")
    testAssert.eq(codes("local n = @unsafe own.adopt<integer>(1)"), "NUPP2602")
    testAssert.eq(codes([[local p: int32* = nil as any
@unsafe local n: string = p[0]
]]), "NUPP2001")
    testAssert.eq(
        codes(
            RESOURCE
            .. "\n"
            .. [[
local owner = resource_new()
@unsafe do local box = {owner = owner} end
resource_free(owner)
]]
        ),
        "NUPP2603"
    )
    for _, expression in ipairs({
        "own.release(first + second)",
        "own.release((first or second))",
        "own.adopt<Owner>((first or second))"
    }) do
        local parsed = parser.parse("local v = @unsafe " .. expression)
        testAssert.eq(#parsed.errors, 0)
        local node = parsed.root.blocks[1].stats[1].exprs[1]
        testAssert.eq(node.kind, "call")
        assert(node.expressionAnnotations)
        testAssert.eq(node.args.exprs[1].kind, expression == "own.release(first + second)" and "binop" or "paren")
    end
    assertClean([[local unsafe, adopt, release = print, print, print
unsafe(1) adopt(2) release(3)
]])
end

function M.unsafeAnnotationsPreserveCleanupAcrossTransfersAndExits()
    local source = [[
local log = ''
local record Resource id: string end
local function close(takes value: Resource): nil log = log .. value.id end
local function open(id: string): affine(Resource, close) return new Resource(id = id) end
local raw = @unsafe own.release(open('a'))
local owner = @unsafe own.adopt<affine(Resource, close)>(raw)
own.drop(owner)
local function run(): integer
    return @unsafe do
        local held = open('y')
        yield 7
    end
end
local answer = run()
@unsafe for i = 1, 3 do
    local held = open('b')
    break
end
local function returning(): integer
    @unsafe do
        local held = open('r')
        return 8
    end
end
local returned = returning()
@unsafe do local held = open('d') end
return answer, returned, log
]]
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg)
    local answer, returned, log = program.run(result, "test")
    testAssert.eq(answer, 7)
    testAssert.eq(returned, 8)
    testAssert.eq(log, "aybrd")
end

function M.columnPointerReborrowsKeepTheirAncestorsAndRejectSiblings()
    local prelude = [[
local soa = require("nupp.soa")
local struct Particle
    x: float
    y: float
end
cdef function update(exclusive x: float*, exclusive y: float*)
cdef function one(exclusive x: float*)
local particles = soa.alloc(ffi.typeof<Particle>(), 2)
local rows = particles:write()
local xs = rows.x
local ys = rows.y
local xp, count = xs:ref()
local yp, otherCount = ys:ref()
]]
    assertClean(prelude .. [[
@unsafe do update(xp as float*, yp as float*) end
print(count, otherCount)
]])
    local bad = codes(prelude .. [[
local other = xp
@unsafe do one(xp as float*) end
print(other)
]])
    assert(bad:find("NUPP2607", 1, true), "a same-column sibling must still conflict: " .. bad)
    bad = codes(prelude .. [[
@unsafe do update(xp as float*, xp as float*) end
]])
    assert(bad:find("NUPP2607", 1, true), "exclusive native arguments must not overlap: " .. bad)
    bad = codes(prelude .. [[
own.drop(xs)
@unsafe do one(xp as float*) end
]])
    assert(bad:find("NUPP2602", 1, true), "a pointer keeps its column owner alive: " .. bad)
end

function M.explicitAffineClaimAndTransparentGenericBound()
    local source = [[
local function releaseId(takes id: integer): nil end
local function acquireId(): affine(integer, releaseId) return 7 end
local function consume<C is own.Affine<releaseId>>(takes value: C): nil
    print(value)
    own.drop(value)
end

consume(acquireId())

local record Resource is own.Affine<self.finish>
    function finish(takes self): nil end
end
local function acquire(): Resource return new Resource() end
local owner: Resource = acquire()
own.drop(owner)
]]
    assertClean(source)
    local leak = codes(source:gsub("    own.drop%(value%)\n", ""))
    assert(leak:find("NUPP2603", 1, true), "a consuming bounded value must be discharged: " .. leak)
    local bad = codes(
        [[
local function releaseId(takes id: integer): nil end
local record Incidental
    function close(takes self): nil end
end
local function accept<C is own.Affine<releaseId>>(takes value: C): nil end
accept(new Incidental())
]]
    )
    assert(bad:find("NUPP2116", 1, true), "a compatible method alone is not an Affine claim: " .. bad)
end

function M.closeableInheritsAffineAndAllowsSuspendingClose()
    local source = [[
local park: function(): nil = nil as any
local interface Stream is own.Closeable
    next: function(exclusive self: Stream): Stream borrows (self)
end
local record Input is Stream
    function close(takes self): nil park() end
    function next(exclusive self): Stream borrows (self)
        return self
    end
end
local input = new Input()
input:next()
own.drop(input)
]]
    assertClean(source)
    local bad = codes(source:gsub("own.drop%(input%)", "@nosuspend do own.drop(input) end"))
    assert(bad:find("NUPP2701", 1, true), "a suspending close cannot run in a nosuspend region: " .. bad)
    assertClean(
        [[
local record Child is own.Closeable
    @effects(suspends = false) function close(takes self): nil end
end
local record Parent
    child: Child
end
@nosuspend do
    local parent = new Parent(child = new Child())
end
]]
    )
    bad = codes(
        [[
local record Incidental
    function close(takes self): nil end
end
local function accept<C is own.Closeable>(takes value: C): nil end
accept(new Incidental())
]]
    )
    assert(bad:find("NUPP2116", 1, true), "close alone must not claim Closeable: " .. bad)
end

function M.contextualNoSuspendFrameCallback()
    local frame = [[
local type FrameBody = @nosuspend function(number): boolean
local interface Window
    runFrames: function(self, scoped frame: FrameBody): nil
end
local function animate(win: Window): nil
    win:runFrames(function(delta: number): boolean
        %s
        return delta > 0
    end)
end
return animate
]]
    assertClean(frame:format("local elapsed = delta"))
    local bad = codes(frame:format("coroutine.yield()"))
    assert(bad:find("NUPP2701", 1, true), "a yielding callback cannot fill a FrameBody slot: " .. bad)
end

function M.genericForOwnsFreshHeaderValuesForWholeLoop()
    local source = [[
local events: {string} = {}
local function releaseStep(takes step: function(integer, integer?): integer?): nil
    events[#events + 1] = "step"
end
local function releaseState(takes state: integer): nil
    events[#events + 1] = "state"
end
local function acquireStep(): affine(function(integer, integer?): integer?, releaseStep)
    return function(_state: integer, control: integer?): integer?
        if control == nil then return 1 end
        return nil
    end
end
local function acquireState(): affine(integer, releaseState) return 7 end
for n in acquireStep(), acquireState(), nil do
    events[#events + 1] = tostring(n)
    break
end
return table.concat(events, ",")
]]
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, problem = program.load(result, "ownership-for-header")
    assert(chunk, tostring(problem))
    testAssert.eq(chunk(), "1,state,step")
end

function M.genericForBorrowsANamedOwnerAndRejectsOwnedControl()
    local source = [[
local events: {string} = {}
local function releaseStep(takes step: function(integer, integer?): integer?): nil
    events[#events + 1] = "step"
end
local function acquireStep(): affine(function(integer, integer?): integer?, releaseStep)
    return function(_state: integer, control: integer?): integer?
        if control == nil then return 1 end
        return nil
    end
end
local step = acquireStep()
for n in step, 7, nil do break end
events[#events + 1] = "after"
own.drop(step)
return table.concat(events, ",")
]]
    local result, diags = checked(source)
    testAssert.eq(#diags, 0, diags[1] and diags[1].msg or "check")
    local chunk, problem = program.load(result, "ownership-for-borrow")
    assert(chunk, tostring(problem))
    testAssert.eq(chunk(), "after,step")

    local bad = codes(
        [[
local function release(takes id: integer): nil end
local function acquire(): affine(integer, release) return 0 end
local function step(_state: nil, _control: integer?): integer? return nil end
for n in step, nil, acquire() do end
]]
    )
    testAssert.eq(bad, "NUPP2622")
end

function M.genericForHeaderOwnersCloseOnEveryExit()
    local prelude = [[
local events: {string} = {}
local function releaseStep(takes step: function(integer, integer?): integer?): nil
    events[#events + 1] = "step"
end
local function releaseState(takes state: integer): nil
    events[#events + 1] = "state"
end
local function acquireStep(): affine(function(integer, integer?): integer?, releaseStep)
    return function(_state: integer, control: integer?): integer?
        if control == nil then return 1 end
        return nil
    end
end
local function acquireState(): affine(integer, releaseState) return 7 end
]]
    local cases = {
        {
            name = "exhaustion",
            body = [[
local function run(): nil
    for n in acquireStep(), acquireState(), nil do events[#events + 1] = tostring(n) end
    events[#events + 1] = "after"
end
run()
]],
            want = "1,state,step,after",
        },
        {
            name = "return",
            body = [[
local function run(): nil
    for _n in acquireStep(), acquireState(), nil do return end
end
run()
events[#events + 1] = "after"
]],
            want = "state,step,after",
        },
        {
            name = "goto",
            body = [[
local function run(): nil
    for _n in acquireStep(), acquireState(), nil do goto done end
    ::done::
    events[#events + 1] = "after"
end
run()
]],
            want = "state,step,after",
        },
        {
            name = "error",
            body = [[
local function run(): nil
    for _n in acquireStep(), acquireState(), nil do error("stop") end
end
local ok = pcall(run)
events[#events + 1] = ok and "missed" or "caught"
]],
            want = "state,step,caught",
        },
        {
            name = "later-header-error",
            body = [[
local function fail(): integer error("stop") end
local function run(): nil
    for _n in acquireStep(), fail(), nil do end
end
local ok = pcall(run)
events[#events + 1] = ok and "missed" or "caught"
]],
            want = "step,caught",
        },
    }
    for _, case in ipairs(cases) do
        local got = runGenerated(prelude .. case.body .. "return table.concat(events, ',')", "for-header-" .. case.name)
        testAssert.eq(got, case.want, case.name)
    end
end

function M.genericForHeaderOwnerRefusesRawYield()
    local bad = codes(
        [[
local function releaseStep(takes step: function(): integer?): nil end
local function acquireStep(): affine(function(): integer?, releaseStep)
    return function(): integer? return nil end
end
for value in acquireStep() do
    coroutine.yield(value)
end
]]
    )
    assert(bad:find("NUPP2603", 1, true), "a raw yield must not strand the header owner: " .. bad)
end

function M.genericForOwnsAnInherentlyAffineCallableRecord()
    local got = runGenerated(
        [[
local events: {string} = {}
local record Iterator is own.Closeable
    current: integer
    function close(takes self): nil
        events[#events + 1] = "close"
    end
    metamethod __call: function(self): integer?
end
Iterator.__call = function(self: Iterator): integer?
    self.current = self.current + 1
    if self.current > 1 then return nil end
    return self.current
end
for value in new Iterator(current = 0) do
    events[#events + 1] = tostring(value)
end
return table.concat(events, ",")
]],
        "for-header-closeable"
    )
    testAssert.eq(got, "1,close")
end

function M.ownershipIntrinsicsCannotBeStoredAsValues()
    for _, expression in ipairs({"own.adopt", "own.release", "own.drop"}) do
        local bad = codes("local intrinsic = " .. expression .. "\nprint(intrinsic)")
        assert(bad ~= "", expression .. " became a first-class value")
    end
end

-- An alias for a generic interface names the same type the interface does, in a
-- borrowed parameter as anywhere else. The alias's arguments used to be resolved
-- under that parameter's loan, so a Closeable binder lost its cleanup through the
-- alias, and a method written against the alias no longer fit the contract the
-- interface itself spelled.
function M.anAliasAppliedInAParameterKeepsItsArgumentsOwnership()
    assertClean(
        table.concat(
            {
                "local interface Sink<S>",
                "    apply: function(self, exclusive state: S): nil",
                "end",
                "local type Alias<S> = Sink<S>",
                "local interface Uses",
                "    run: function<S is own.Closeable>(self, sink: Sink<S>): nil",
                "end",
                "local record Impl is Uses",
                "    function run<S is own.Closeable>(self, sink: Alias<S>): nil",
                "    end",
                "end",
                "print(new Impl())",
            },
            "\n"
        )
    )
end

function M.lowercaseQualifiedOwnershipKeepsBorrowProvenanceAndRefusals()
    for _, root in ipairs({"own", "api"}) do
        local prefix = root == "api" and 'local api = require("own")\n' or ""
        local body = RESOURCE
            .. "\n"
            .. [[
local function recover(borrows source: resource*, raw: resource*): resource* borrows (source)
    @unsafe do return ROOT.borrowfrom(raw, source) end
end
]]
        assertClean(prefix .. body:gsub("ROOT", root))
        testAssert.eq(codes(prefix .. body:gsub("ROOT", root):gsub("@unsafe do", "do")), "NUPP2604")
    end
    local cst = require("nupp.compiler.syntax.cst")
    testAssert.eq(cst.ownershipIntrinsicName("borrowfrom"), "borrowFrom")
    testAssert.eq(cst.ownershipIntrinsicName("attemptall"), "attemptAll")
    for _, retired in ipairs({"borrowFrom", "attemptAll"}) do
        testAssert.eq(cst.ownershipIntrinsicName(retired), nil)
        local bare = parser.parse(retired .. "(1)", "bare-owner.nupp")
        testAssert.eq(cst.ownershipIntrinsicSpelling(bare.root.blocks[1].stats[1].expr.obj), retired)
    end
    for _, bare in ipairs({"borrowfrom", "attemptall"}) do
        local parsed = parser.parse(bare .. "(1)", "bare-owner.nupp")
        testAssert.eq(cst.ownershipIntrinsicSpelling(parsed.root.blocks[1].stats[1].expr.obj), nil)
    end
    local source = [[
local own: {borrowfrom: function(integer, integer): integer, attemptall: function(integer): integer} = {
    borrowfrom = function(value: integer, source: integer): integer return value + source end,
    attemptall = function(value: integer): integer return value + 1 end
}
return own.borrowfrom(2, 3), own.attemptall(5)
]]
    local a, b = runGenerated(source, "lowercase-own-shadow")
    testAssert.eq(a, 5)
    testAssert.eq(b, 6)
end

function M.lowercaseAttemptallKeepsEveryCleanupAndOrderingRefusal()
    local source = [[
local record Resource id: integer end
local calls = ""
local function stop(value: Resource): nil
    calls = calls .. "stop"
    error("failed")
end
local function finish(value: Resource): nil calls = calls .. ",finish" end
local function close(takes value: Resource): nil own.attemptall(value, stop, finish) end
local function open(): affine(Resource, close) return new Resource(id = 1) end
local ok = pcall(function() local value = open() own.drop(value) end)
return calls, ok
]]
    local calls, ok = runGenerated(source, "lowercase-attemptall")
    testAssert.eq(calls, "stop,finish")
    testAssert.eq(ok, false)
    testAssert.eq(
        codes(
            [[
local record Resource end
local function take(takes value: Resource): nil end
local function last(value: Resource): nil end
local function close(takes value: Resource): nil own.attemptall(value, take, last) end
]]
        ),
        "NUPP2615"
    )
end

function M.consumingScalarAdaptersKeepTheirBuffersAlive()
    for _, expression in ipairs({"buffer:writer():scalar()",}) do
        local target = expression:find("writer", 1, true) and "ScalarWriter" or "ScalarReader"
        local source = "local function escape(): affine(io."
            .. target
            .. ")\n"
            .. "    local buffer = io.newbuffer()\n"
            .. "    return "
            .. expression
            .. "\nend"
        testAssert.eq(codes(source), "NUPP2608", expression)
    end
end

function M.scalarReadersCanOwnIndependentBufferSnapshots()
    assertClean(
        [[
local function snapshot(): affine(io.ScalarReader)
    local buffer = io.newbuffer()
    return buffer:reader():scalar()
end
]]
    )
end

function M.consumingFunctionsKeepForeignLoansInOwnedResults()
    testAssert.eq(
        codes(
            [[
local function wrap(takes writer: io.Writer): affine(io.ScalarWriter)
    return writer:scalar()
end
local function escape(): affine(io.ScalarWriter)
    local buffer = io.newbuffer()
    local writer = buffer:writer()
    return wrap(writer)
end
]]
        ),
        "NUPP2608"
    )
end

function M.consumingScalarWritersKeepExclusiveBufferLoans()
    local got = codes(
        [[
local buffer = io.newbuffer()
local scalar = buffer:writer():scalar()
local overlapping = buffer:writer()
scalar:writeuint8(1)
]]
    )
    assert(got:find("NUPP2607", 1, true), got)
end

function M.scalarWriterReborrowsKeepTheirImmediateHolder()
    assertClean(
        [[
local function append(borrows writer: io.ScalarWriter): nil
    writer:writeuint8(33)
end
local buffer = io.newbuffer()
local writer = buffer:writer():scalar()
append(writer:writebytes(":"))
writer:writebytes(":"):writeuint8(33)
]]
    )
end

return M
