local fixture = require("helpers.projectfixture")
local testAssert = fixture.testAssert
local project = fixture.project
local store = fixture.store
local write = fixture.write
local read = fixture.read
local contentCacheDir = fixture.contentCacheDir
local exists = fixture.exists
local tempProject = fixture.tempProject
local remove = fixture.remove

local hostSystem = require("helpers.projectfixture").hostSystem
local compiledRuntimeSources = require("helpers.projectfixture").compiledRuntimeSources

local M = {}

function M.exportedComptimeTypeFunctionsInvalidateAndPersistSafely()
    local optional = table.concat(
        {
            "local M = {}",
            "@comptime local function AddNil(T: type): type",
            "   return types.optional(T)",
            "end",
            "@comptime function M.Maybe(T: type): type",
            "   return AddNil(T)",
            "end",
            "return M",
        },
        "\n"
    )
    local main = table.concat(
        {
            "local gen = require('gen')",
            "local direct: gen.Maybe(string) = nil",
            "local function choose<T>(value: T, fallback: gen.Maybe(T)): gen.Maybe(T)",
            "   return fallback",
            "end",
            "local answer: string? = choose('yes', nil)",
            "return answer, direct",
        },
        "\n"
    )
    local dir = tempProject({
        ["nupp.lua"] = [[
return {include = {"src"}, build = {outDir = "out", entries = {"main"}}}
]],
        ["src/gen.nupp"] = optional,
        ["src/main.nupp"] = main,
    })

    testAssert.eq(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "a consumer executes closed and inferred exported type calls"
    )
    local cache = contentCacheDir(dir, "out") .. "/type-functions.buf"
    assert(exists(cache), "the type-function result store is persisted")

    -- Rechecking a changed consumer admits a validated persisted result. Damage is a
    -- miss, never a different type answer.
    write(dir .. "/src/main.nupp", main .. "\n-- force a consumer check\n")
    testAssert.eq(project.check(dir, {stats = {}, diagnostics = {}}), 0, "a fresh checker accepts persisted blueprints")
    write(cache, "not a type-function store")
    write(dir .. "/src/main.nupp", main .. "\n-- force another consumer check\n")
    testAssert.eq(
        project.check(dir, {
            stats = {},
            diagnostics = {}
        }),
        0,
        "a damaged result store falls back to evaluation"
    )

    -- The sealed helper closure is part of the exported interface. Changing its
    -- behavior rechecks the unchanged consumer and changes the generated answer.
    write(dir .. "/src/gen.nupp", optional:gsub("return types.optional%(T%)", "return T"))
    local diagnostics = {}
    assert(
        project.check(dir, {
            stats = {},
            diagnostics = diagnostics
        }) ~= 0,
        "a semantic private-helper edit invalidates the consumer"
    )
    local sawArgumentFailure = false
    for _, diagnostic in ipairs(diagnostics) do
        if diagnostic.code == "NUPP2006" then
            sawArgumentFailure = true
        end
    end
    assert(sawArgumentFailure, "the consumer observes the changed generated type")

    remove(dir)
end

-- A cache is only ever an optimization, so every way of damaging it has to
-- land on the same answer as not having one.
function M.checkSurvivesADamagedCache()
    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        [
            "src/main.nupp"
        ] = table.concat({"local lib = require('lib')", "local value: string = lib.answer()", "return value",}, "\n"),
        [
            "src/lib.nupp"
        ] = table.concat(
            {"local function answer(): number", "   return 1", "end", "return { answer = answer }",},
            "\n"
        ),
    })

    local function answerOf()
        local diags = {}
        local code = project.check(dir, {stats = {}, diagnostics = diags})
        local parts = {tostring(code)}
        for _, d in ipairs(diags) do
            parts[#parts + 1] = ("%s@%d:%d %s"):format(tostring(d.code), d.line or 0, d.col or 0, tostring(d.msg))
        end

        return table.concat(parts, "\n")
    end

    local cold = answerOf()
    assert(cold:sub(1, 1) ~= "0", "the fixture is meant to have an error in it")
    testAssert.eq(answerOf(), cold, "a warm cache gives the cold answer")

    for _, damage in ipairs({"not a buffer at all", "", "\0\0\0\0"}) do
        write(contentCacheDir(dir, "out") .. "/headers.buf", damage)
        write(dir .. "/out/cache/checks.buf", damage)
        testAssert.eq(answerOf(), cold, "a damaged cache gives the cold answer")
    end

    -- Damage the store cannot see for itself: a value that decodes, under the
    -- right stamp, into something that is not a check state. A build validates
    -- the state it reads back, and a check crashed on these instead.
    local shapes = {
        "a string",
        {},
        {version = 5, modules = 5, dependencies = {}, outputs = {}, targets = {}},
        {version = 5, modules = {main = "a record"}, dependencies = {}, outputs = {}, targets = {}},
        {version = 5, modules = {}, dependencies = {}, outputs = {}, targets = {app = {1}}},
    }

    -- The stamp carries the module compiler, so it is read from the state the last
    -- check wrote rather than spelled here, with the codec the store writes it in.
    local function checkStamp()
        local file = assert(io.open(dir .. "/out/cache/checks.buf", "rb"))
        local codec = rawget(_G, "__nupp_plain_codec") or require("nupp.serde.internal.binarycodec")
        local envelope = codec.decode(file:read("*a"))
        file:close()

        return envelope.slots[1].stamp
    end

    for index, shape in ipairs(shapes) do
        local doctored = store.openValue(dir .. "/out/cache/checks.buf", checkStamp())
        doctored.set(shape)
        doctored.save()
        local ok, answer = pcall(answerOf)
        assert(ok, "wrongly shaped check state " .. index .. " crashed the check: " .. tostring(answer))
        testAssert.eq(answer, cold, "wrongly shaped check state " .. index .. " gives the cold answer")
    end

    remove(contentCacheDir(dir, "out"))
    remove(dir .. "/out/cache")
    testAssert.eq(answerOf(), cold, "no cache at all gives the cold answer")
    remove(dir)
end

function M.ownershipContractsInvalidateIncrementalInterfaces()
    local function library(mode)
        return table.concat(
            {"cdef function inspect(" .. mode .. " value: cstring)", "return { inspect = inspect }",},
            "\n"
        )
    end

    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
        ["src/lib.nupp"] = library("borrows"),
    })

    testAssert.eq(project.build(dir), 0)
    write(dir .. "/src/lib.nupp", library("takes"))
    local changed = {}
    testAssert.eq(project.build(dir, {stats = changed}), 0)
    testAssert.eq(changed.checkedModules, 2, "ownership-mode interface changes recheck dependents")
    remove(dir)
end

function M.namedCleanupsInvalidateIncrementalInterfaces()
    local function library(cleanup)
        return table.concat(
            {
                "cdef function create_c(): voidptr",
                "cdef function first_cleanup(takes value: voidptr)",
                "cdef function second_cleanup(takes value: voidptr)",
                "local function create(): affine(voidptr, " .. cleanup .. ")",
                "   return create_c()",
                "end",
                "return { create = create }",
            },
            "\n"
        )
    end

    local dir = tempProject({
        ["nupp.lua"] = [[
return {
   include = {"src"},
   build = {outDir = "out", entries = {"main"}},
}
]],
        ["src/main.nupp"] = "local lib = require('lib')\nreturn lib\n",
        ["src/lib.nupp"] = library("first_cleanup"),
    })

    testAssert.eq(project.build(dir), 0)
    write(dir .. "/src/lib.nupp", library("second_cleanup"))
    local changed = {}
    testAssert.eq(project.build(dir, {stats = changed}), 0)
    testAssert.eq(changed.checkedModules, 2, "a changed cleanup rechecks dependents")
    remove(dir)
end

return M
