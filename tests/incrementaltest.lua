local testAssert = require("nupp.test")
local query = require("nupp.compiler.project.query")
local incremental = require("nupp.compiler.project.incremental")

local M = {}

function M.memoizationAndInvalidation()
    local q = query.new()
    q:setInput("src", "a", 10)
    q:define("double", function(self, key)
        return self:get("src", key) * 2
    end)
    testAssert.equal(q:get("double", "a"), 20)
    testAssert.equal(q:get("double", "a"), 20)
    testAssert.equal(q.stats.double, 1, "memoized within revision")
    q:setInput("src", "a", 21)
    testAssert.equal(q:get("double", "a"), 42)
    testAssert.equal(q.stats.double, 2, "recomputed after input change")
end

function M.earlyCutoff()
    local q = query.new()
    q:setInput("src", "a", 10)
    -- parity only changes when crossing even/odd — downstream must not
    -- recompute when parity is stable
    q:define("parity", function(self, key)
        return self:get("src", key) % 2
    end)
    q:define("report", function(self, key)
        return "parity is " .. self:get("parity", key)
    end)
    testAssert.equal(q:get("report", "a"), "parity is 0")
    q:setInput("src", "a", 12) -- still even
    testAssert.equal(q:get("report", "a"), "parity is 0")
    testAssert.equal(q.stats.parity, 2, "parity recomputed")
    testAssert.equal(q.stats.report, 1, "report NOT recomputed (cutoff)")
    q:setInput("src", "a", 13) -- odd: real change propagates
    testAssert.equal(q:get("report", "a"), "parity is 1")
    testAssert.equal(q.stats.report, 2)
end

function M.validationDoesNotLeakTransitiveDependenciesIntoCallers()
    local q = query.new()
    q:setInput("source", "trigger", 1)
    q:setInput("source", "wanted", 10)
    q:setInput("source", "unrelated", 20)
    q:define("aggregate", function(self)
        return {wanted = self:get("source", "wanted"), unrelated = self:get("source", "unrelated"),}
    end)
    q:define("wanted", function(self)
        return self:get("aggregate", "root").wanted
    end)
    q:define("nested", function(self)
        return self:get("wanted", "root")
    end)
    q:define("outer", function(self)
        return self:get("source", "trigger") + self:get("nested", "root")
    end)

    testAssert.equal(q:get("outer", "root"), 11)
    q:setInput("source", "trigger", 2)
    q:setInput("source", "unrelated", 21)
    testAssert.equal(q:get("outer", "root"), 12)
    testAssert.equal(q.stats.outer, 2, "the direct trigger recomputes the caller")

    q:setInput("source", "unrelated", 22)
    testAssert.equal(q:get("outer", "root"), 12)
    testAssert.equal(q.stats.outer, 2, "validation of a nested query does not make its aggregate a direct dependency")
end

-- The compiler-level behavior: editing a dependency's BODY must not
-- recheck the dependent; editing its INTERFACE must.
function M.interfaceCutoffAcrossModules()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    local depV1 = table.concat(
        {"local function scale(n: number): number", "   return n * 2", "end", "return { scale = scale }",},
        "\n"
    )
    write(depPath, depV1)
    write(mainPath, table.concat({"local dep = require('dep')", "local x: number = dep.scale(21)", "return x",}, "\n"))

    local inc = incremental.new(dir)
    local r = inc.checkFile(mainPath)
    testAssert.equal(#r.diags, 0, "cold check clean")
    local coldChecks = inc.q.stats.checkModule
    testAssert.equal(coldChecks, 2, "main + dep checked cold")

    -- body edit: same interface
    inc.changeDocument(depPath, (depV1:gsub("n %* 2", "n * 3")))
    local r2 = inc.checkFile(mainPath)
    testAssert.equal(#r2.diags, 0)
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 1, "only dep rechecked after a body edit (interface cutoff)")

    -- interface edit: return type changes, dependent must recheck and fail
    inc.changeDocument(depPath, (depV1:gsub("%): number", "): string"):gsub("n %* 2", "tostring(n)")))
    local r3 = inc.checkFile(mainPath)
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 3, "dep AND main rechecked after an interface edit")
    testAssert.equal(r3.diags[1] and r3.diags[1].code, "NUPP2001", "dependent sees the new interface")

    os.execute("rm -rf '" .. dir .. "'")
end

-- A check reaches each import through the query graph, so a long require chain
-- used to be checked by recursion as deep as the chain, and past about a thousand
-- modules the Lua stack ran out. A deep graph is now checked from the bottom.
function M.aRequireChainDeeperThanTheStackIsChecked()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local count = 1500

    local function write(path, text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    local function module(index, body)
        local lines = {"module m" .. index, ""}
        if index > 0 then
            lines[#lines + 1] = ('const below = require("m%d")'):format(index - 1)
        end
        lines[#lines + 1] = "export function value(): number"
        lines[#lines + 1] = "    return " .. body
        lines[#lines + 1] = "end"

        return table.concat(lines, "\n") .. "\n"
    end

    for index = 0, count - 1 do
        write(("%s/m%d.nupp"):format(dir, index), module(index, index > 0 and "below.value() + 1" or "0"))
    end

    local inc = incremental.new(dir)
    local top = ("%s/m%d.nupp"):format(dir, count - 1)
    local ok, r = pcall(inc.checkFile, top)
    assert(ok, "the chain is checked rather than overflowing: " .. tostring(r))
    testAssert.equal(#r.diags, 0, r.diags[1] and r.diags[1].msg or "clean")

    -- An interface edit at the bottom rechecks the whole chain above it.
    inc.changeDocument(
        dir .. "/m0.nupp",
        (module(0, "0"):gsub("%(%): number", "(): string"):gsub("return 0", 'return "0"'))
    )
    ok, r = pcall(inc.checkFile, top)
    assert(ok, "the chain is rechecked rather than overflowing: " .. tostring(r))
    local bottom = inc.checkFile(dir .. "/m1.nupp")
    testAssert.equal(bottom.diags[1] and bottom.diags[1].code, "NUPP2003", "the edit reaches the module above it")

    os.execute("rm -rf '" .. dir .. "'")
end

function M.recursiveDerivedGraphRechecksAcrossThreeModules()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local modelPath = dir .. "/model.nupp"
    local bridgePath = dir .. "/bridge.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, text)
        local file = assert(io.open(path, "wb"))
        file:write(text)
        file:close()
    end

    local model = table.concat(
        {
            "module model",
            "",
            "export record Node",
            "   name: string",
            "   children: {Node}",
            "end",
            "local revision = 1",
        },
        "\n"
    )
    write(modelPath, model)
    write(
        bridgePath,
        table.concat(
            {
                "module bridge",
                "local model = require('model')",
                "export function binding(): nupp.serde.Binding<model.Node>",
                "   return nupp.serde.binding(model.Node)",
                "end",
            },
            "\n"
        )
    )
    write(
        mainPath,
        table.concat(
            {
                "local model = require('model')",
                "local bridge = require('bridge')",
                "local binding: nupp.serde.Binding<model.Node> = bridge.binding()",
                "local root = new model.Node(name = 'root', children = {",
                "   new model.Node(name = 'leaf', children = {}),",
                "})",
                "return binding, root",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir, {cache = false})
    local cold = inc.checkFile(mainPath)
    testAssert.equal(
        #cold.diags,
        0,
        "three-module recursive derive checks cold: " .. (
            cold.diags[1] and (cold.diags[1].code .. " " .. cold.diags[1].msg) or "clean"
        )
    )
    local coldChecks = inc.q.stats.checkModule
    testAssert.equal(coldChecks, 3, "model, bridge, and consumer checked cold")

    inc.changeDocument(modelPath, model:gsub("revision = 1", "revision = 2"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "recursive derive survives a dependency body edit")
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 1, "unchanged derived interface cuts off the two consumers")

    inc.changeDocument(modelPath, model:gsub("   children: {Node}", "   children: {Node}\n   tag: string?"))
    local changed = inc.checkFile(mainPath)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 4,
        "a derived record interface change rechecks all three modules"
    )
    testAssert.equal(#changed.diags, 0, "the recursive derive remains coherent after all three modules recheck")

    os.execute("rm -rf '" .. dir .. "'")
end

function M.changingADeriveProviderReplansItsClaim()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local modelPath = dir .. "/model.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local model = table.concat(
        {"module model", "@derive(nupp.derive.Debug)", "export record Config", "   value: string", "end",},
        "\n"
    )
    write(modelPath, model)
    write(
        mainPath,
        table.concat(
            {
                "local model = require('model')",
                "local config = new model.Config(value = 'x')",
                "return config:debug()",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "the first provider claim checks")

    inc.changeDocument(modelPath, model:gsub("@derive%(nupp.derive.Debug%)", ""))
    local changed = inc.checkFile(mainPath)
    testAssert.equal(
        changed.diags[1] and changed.diags[1].code,
        "NUPP2004",
        "the reused nominal drops the old provider contract"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.countedPointerLogicalSignaturesCrossModuleSummaries()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/native.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local dependency = table.concat(
        {
            "cdef function counted_copy(",
            "   borrows output: int32* countedBy(count),",
            "   borrows input: const int32* countedBy(count),",
            "   count: uint64",
            ") from'missing-counted-fixture'",
            "local bodyOnly = 1",
            "return { copy = counted_copy, bodyOnly = bodyOnly }",
        },
        "\n"
    )
    write(depPath, dependency)
    write(
        mainPath,
        table.concat(
            {
                "local native = require('native')",
                "local spans = require('nupp.mem.span')",
                "local output = ffi.new<int32[4]>()",
                "local input = ffi.new<int32[4]>()",
                "local writer = spans.writeCarray(output, 4)",
                "local reader = spans.fromCarray(input, 4)",
                "native.copy(writer, reader)",
                "nupp.drop(writer)",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "a consumer sees the exported logical span signature")
    local coldChecks = inc.q.stats.checkModule
    testAssert.equal(coldChecks, 2, "the declaration and consumer check cold")

    inc.changeDocument(depPath, dependency:gsub("bodyOnly = 1", "bodyOnly = 2"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "the logical signature survives a dependency body edit")
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 1,
        "the unchanged counted-pointer interface cuts off its consumer"
    )

    inc.persist()
    local warm = incremental.new(dir)
    testAssert.equal(
        #warm.checkFile(mainPath).diags,
        0,
        "a fresh graph reconstructs the counted-pointer module interface"
    )
    assert(warm.headerStore.stats.hits >= 2, "the fresh graph reads both module headers from the persistent cache")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.deriveRecipesMemoizeAndPublishBehaviorChanges()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local dep = table.concat(
        {
            "local dep = {}",
            "@derive(nupp.derive.Debug)",
            "record dep.Config",
            "   entries: {[string]: string} = {}",
            "end",
            "local function body(): integer",
            "   return 1",
            "end",
            "return dep",
        },
        "\n"
    )
    write(depPath, dep)
    write(
        mainPath,
        table.concat({"local dep = require('dep')", "local config = new dep.Config()", "return config:debug()",}, "\n")
    )

    local inc = incremental.new(dir, {cache = false})
    local cold = inc.checkFile(mainPath)
    testAssert.equal(#cold.diags, 0, "derived dependency checks cold")
    testAssert.equal(inc.deriveStats().executions, 1, "one cold derive recipe query")
    local coldChecks = inc.q.stats.checkModule
    local coldFingerprint = inc.checkFile(depPath).exports.deriveInterfaceFingerprint

    inc.changeDocument(depPath, dep:gsub("return 1", "return 2"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "body edit stays clean")
    local warm = inc.deriveStats()
    testAssert.equal(warm.executions, 1, "a body-only edit reuses the canonical recipe query")
    assert(warm.cacheHits >= 1, "the warm recipe records a cache hit")
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 1, "unchanged derive interface cuts off its consumer")

    inc.changeDocument(depPath, dep:gsub("%{%[string%]%: string%}", "{[integer]: string}"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "behavior edit stays well typed")
    testAssert.equal(inc.deriveStats().executions, 2, "a reached field-type edit computes a new plan")
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 3,
        "changed derive behavior invalidates the requiring module"
    )
    local changed = inc.checkFile(depPath)
    assert(changed.exports.deriveInterfaceFingerprint, "the module publishes an explicit derive interface")
    assert(
        changed.exports.deriveInterfaceFingerprint ~= coldFingerprint,
        "the checked result publishes the changed behavior envelope"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.deriveDocumentationChangesInvalidateGeneratedBehavior()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local providerPath = dir .. "/provider.nupp"
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    write(
        providerPath,
        table.concat(
            {
                "local M = {}",
                "interface M.Documented",
                "   documentation: function(self): string",
                "end",
                "function M.returnText(text: string): string return text end",
                "@comptime function M.derive(info: nupp.derive.Info): nupp.derive.Result<M.Documented>",
                "   return nupp.derive.implement{methods = {documentation = nupp.derive.forward{",
                "      helper = nupp.derive.helper(M, 'returnText'),",
                "      arguments = {nupp.derive.constant(info.documentation or '')},",
                "   }}}",
                "end",
                "return M",
            },
            "\n"
        )
    )
    local dep = table.concat(
        {
            "local provider = require('provider')",
            "local dep = {}",
            "--- First documentation.",
            "@derive(provider.derive)",
            "record dep.Config",
            "   value: integer",
            "end",
            "return dep",
        },
        "\n"
    )
    write(depPath, dep)
    write(
        mainPath,
        table.concat(
            {
                "local dep = require('dep')",
                "local config = new dep.Config(value = 1)",
                "return config:documentation()",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "documented derive checks cold")
    testAssert.equal(inc.deriveStats().executions, 1, "one documented derive recipe is materialized")
    local coldChecks = inc.q.stats.checkModule
    local coldFingerprint = inc.checkFile(depPath).exports.deriveInterfaceFingerprint

    inc.changeDocument(depPath, dep:gsub("First documentation", "Second documentation"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "changed derive documentation stays clean")
    testAssert.equal(inc.deriveStats().executions, 2, "changed documentation materializes a new recipe")
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 2, "changed documentation rechecks the dependent")
    assert(
        inc.checkFile(depPath).exports.deriveInterfaceFingerprint ~= coldFingerprint,
        "changed documentation kept the generated behavior envelope"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.fieldDefaultChangesInvalidateModuleConsumers()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local dep = table.concat(
        {"local dep = {}", "record dep.Config", "   value: integer = 1", "end", "return dep",},
        "\n"
    )
    write(depPath, dep)
    write(mainPath, table.concat({"local dep = require('dep')", "return new dep.Config()",}, "\n"))

    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "defaulted dependency checks cold")
    local coldChecks = inc.q.stats.checkModule
    inc.changeDocument(depPath, dep:gsub("= 1", "= 2"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "changed default stays clean")
    testAssert.equal(inc.q.stats.checkModule, coldChecks + 2, "a changed construction default rechecks its consumer")

    os.execute("rm -rf '" .. dir .. "'")
end

function M.deprecationMetadataInvalidatesModuleDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, text)
        local file = assert(io.open(path, "wb"))
        file:write(text)
        file:close()
    end

    local dep = table.concat({"local M = {}", "function M.answer(): number", "   return 42", "end", "return M",}, "\n")
    write(depPath, dep)
    write(mainPath, table.concat({"local dep = require('dep')", "return dep.answer()",}, "\n"))

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "current API starts clean")
    local coldChecks = inc.q.stats.checkModule

    inc.changeDocument(
        depPath,
        dep:gsub("function M.answer", '@deprecated(replacement = "dep.currentAnswer")\nfunction M.answer')
    )
    local changed = inc.checkFile(mainPath)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 2,
        "deprecation metadata rechecks the dependency and dependent"
    )
    testAssert.equal(
        changed.diags[1] and changed.diags[1].code,
        "NUPP2513",
        "the dependent observes new deprecation metadata"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.deprecationMetadataInvalidatesProjectTypeDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local modelPath = dir .. "/model.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, text)
        local file = assert(io.open(path, "wb"))
        file:write(text)
        file:close()
    end

    local model = table.concat({"global record Shared", "   value: number", "end",}, "\n")
    write(modelPath, model)
    write(mainPath, "local item: Shared? = nil\nreturn item\n")

    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "project type starts current")
    local coldChecks = inc.q.stats.checkModule
    inc.changeDocument(modelPath, '@deprecated(replacement = "Current")\n' .. model)
    local changed = inc.checkFile(mainPath)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 2,
        "deprecation metadata rechecks the declaration and dependent"
    )
    testAssert.equal(
        changed.diags[1] and changed.diags[1].code,
        "NUPP2513",
        "the dependent observes project deprecation metadata"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.publicPackChangesInvalidateTypeDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local dep = table.concat(
        {"local m = {}", "function m.pair(): (number, string)", "   return 1, 'one'", "end", "return m",},
        "\n"
    )
    write(depPath, dep)
    write(
        mainPath,
        table.concat(
            {
                "local dep = require('dep')",
                "local n, s = dep.pair()",
                "local exactNumber: number = n",
                "local exactString: string = s",
                "return exactNumber, exactString",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "initial pack interface checks")
    local coldChecks = inc.q.stats.checkModule
    inc.changeDocument(
        depPath,
        dep:gsub("%(number, string%)", "(string, number)"):gsub("return 1, 'one'", "return 'one', 1")
    )
    local changed = inc.checkFile(mainPath)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 2,
        "a public result-pack change rechecks dependency and dependent"
    )
    testAssert.equal(
        changed.diags[1] and changed.diags[1].code,
        "NUPP2001",
        "the dependent observes the changed result slots"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.overlayClearRevertsToDisk()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local path = dir .. "/m.nupp"
    local f = assert(io.open(path, "wb"))
    f:write("return { ok = 1 }")
    f:close()

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(path).diags, 0)
    inc.changeDocument(path, "local x: number = 'broken'\nreturn x")
    testAssert.equal(inc.checkFile(path).diags[1].code, "NUPP2001", "overlay wins")
    inc.closeDocument(path)
    testAssert.equal(#inc.checkFile(path).diags, 0, "disk content restored")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A build hashes the text its check saw rather than the file as it now stands, and
-- that only says which source an artifact came from while one session answers with
-- one text per file. A module is read twice by a build -- the checker takes its tree
-- when whatever requires it is checked, and the module build reaches it again on its
-- own turn -- and a source edited between the two used to be recorded at content the
-- build never compiled, which left every later build reusing the older artifact for
-- it.
function M.aSessionReadsAFileOnce()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local path = dir .. "/m.nupp"

    local function write(text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    write("return { ok = 1 }\n")

    local inc = incremental.new(dir)
    local first = inc.fileText(path)
    testAssert.equal(first, "return { ok = 1 }\n", "the text the check will see")
    write("return { ok = 2 }\n")
    testAssert.equal(
        inc.fileText(path),
        first,
        "a file rewritten under a running session still reads as what it checked"
    )
    testAssert.equal(#inc.checkFile(path).diags, 0)

    -- Nothing about that outlives the session, and a session told about the change
    -- reads it now: it is one answer per session, not a stale one.
    inc.diskChanged(path, 2)
    testAssert.equal(inc.fileText(path), "return { ok = 2 }\n", "a watcher event re-reads it")
    testAssert.equal(
        incremental.new(dir).fileText(path),
        "return { ok = 2 }\n",
        "and the next session starts from disk"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.diskWatcherChangesInvalidateQueriesAndProjectFiles()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local mainPath = dir .. "/main.nupp"
    local globalsPath = dir .. "/globals.nupp"

    local function write(path, text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    write(mainPath, "local value: Watched = 1\nreturn value\n")

    local inc = incremental.new(dir)
    testAssert.equal(
        inc.checkFile(mainPath).diags[1].code,
        "NUPP2101",
        "missing watched declaration starts as an error"
    )
    write(globalsPath, "global type Watched = number\n")
    inc.diskChanged(globalsPath, 1)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "created disk file joins the project index")

    write(globalsPath, "global type Watched = string\n")
    inc.diskChanged(globalsPath, 2)
    testAssert.equal(
        inc.checkFile(mainPath).diags[1].code,
        "NUPP2001",
        "changed disk file invalidates dependent checks"
    )

    os.remove(globalsPath)
    inc.diskChanged(globalsPath, 3)
    testAssert.equal(inc.checkFile(mainPath).diags[1].code, "NUPP2101", "deleted disk file leaves the project index")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.diskWatcherPreservesOpenOverlay()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local path = dir .. "/main.nupp"

    local function write(text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    write("local value: number = 1\nreturn value\n")
    local inc = incremental.new(dir)
    inc.openDocument(path, "local value: number = 2\nreturn value\n")
    write("local value: number = 'disk error'\nreturn value\n")
    inc.diskChanged(path, 2)
    testAssert.equal(#inc.checkFile(path).diags, 0, "disk event does not replace an editor overlay")
    inc.closeDocument(path)
    testAssert.equal(
        inc.checkFile(path).diags[1].code,
        "NUPP2001",
        "closing the overlay observes the changed disk file"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.projectIndexTracksOverlaysAndDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local modelPath = dir .. "/model.g.nupp"
    local mainPath = dir .. "/main.g.nupp"
    local modelFile = assert(io.open(modelPath, "wb"))
    modelFile:write("local record Shared\n   value: number\nend\n")
    modelFile:close()
    local mainFile = assert(io.open(mainPath, "wb"))
    mainFile:write(
        table.concat({"local item: Shared = new Shared()", "local value: number = item.value", "return value",}, "\n")
    )
    mainFile:close()

    local inc = incremental.new(dir)
    testAssert.equal(inc.checkFile(mainPath).diags[1].code, "NUPP2101", "disk-private declaration is hidden")
    inc.openDocument(modelPath, "global record Shared\n   value: number\nend\n")
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "unsaved export enters the project index")
    inc.changeDocument(modelPath, "global record Shared\n   value: string\nend\n")
    testAssert.equal(inc.checkFile(mainPath).diags[1].code, "NUPP2001", "export change rechecks its dependent")
    inc.closeDocument(modelPath)
    testAssert.equal(inc.checkFile(mainPath).diags[1].code, "NUPP2101", "closing the overlay restores disk visibility")

    os.execute("rm -rf '" .. dir .. "'")
end

function M.newOverlayFilesJoinProjectIndex()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local mainPath = dir .. "/main.nupp"
    local mainFile = assert(io.open(mainPath, "wb"))
    mainFile:write("local value: Added?\nreturn value\n")
    mainFile:close()

    local inc = incremental.new(dir)
    testAssert.equal(inc.checkFile(mainPath).diags[1].code, "NUPP2101")
    local addedPath = dir .. "/added.nupp"
    inc.openDocument(addedPath, "global type Added = number\n")
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "new unsaved file joins project index")
    inc.closeDocument(addedPath)
    testAssert.equal(
        inc.checkFile(mainPath).diags[1].code,
        "NUPP2101",
        "closing new unsaved file removes it from project index"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.reflectionDependsOnlyOnTheExportedTypeItReads()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local reflectedPath = dir .. "/reflected.nupp"
    local unrelatedPath = dir .. "/unrelated.nupp"
    local mainPath = dir .. "/main.nupp"

    local function write(path, source)
        local file = assert(io.open(path, "wb"))
        file:write(source)
        file:close()
    end

    local reflected = table.concat({"global record Reflected", "   name: string", "end", "return {}",}, "\n")
    local unrelated = table.concat({"global record Unrelated", "   value: number", "end", "return {}",}, "\n")
    write(reflectedPath, reflected)
    write(unrelatedPath, unrelated)
    write(
        mainPath,
        table.concat(
            {
                "const SUMMARY = comptime do",
                "   local info = nupp.reflect(Reflected)",
                "   return info.fields[1].name",
                "end",
                "return SUMMARY",
            },
            "\n"
        )
    )

    local inc = incremental.new(dir, {cache = false})
    local initial = inc.checkFile(mainPath)
    local initialCodes = {}
    for _, diagnostic in ipairs(initial.diags) do
        initialCodes[#initialCodes + 1] = diagnostic.code .. ": " .. diagnostic.msg
    end
    testAssert.equal(
        #initial.diags,
        0,
        "reflected type checks" .. (#initialCodes > 0 and "\n" .. table.concat(initialCodes, "\n") or "")
    )
    local coldChecks = inc.q.stats.checkModule

    inc.changeDocument(reflectedPath, reflected:gsub("return {}", "local bodyOnly = 1\nreturn {}"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 1,
        "a body edit rechecks the declaration but not its reflecting module"
    )

    inc.changeDocument(unrelatedPath, unrelated:gsub("value: number", "value: string"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 1,
        "an unrelated exported field does not recheck the reflecting module"
    )

    inc.changeDocument(reflectedPath, reflected:gsub("name: string", "name: string\n   count: integer"))
    testAssert.equal(#inc.checkFile(mainPath).diags, 0)
    testAssert.equal(
        inc.q.stats.checkModule,
        coldChecks + 3,
        "the declaring and reflecting modules recheck after a reflected field changes"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.removingGlobalOverlayInvalidatesDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local globalsPath = dir .. "/globals.nupp"
    local mainPath = dir .. "/main.nupp"
    local globalsFile = assert(io.open(globalsPath, "wb"))
    globalsFile:write("global type SharedId = number\n")
    globalsFile:close()
    local mainFile = assert(io.open(mainPath, "wb"))
    mainFile:write("local value: SharedId = 1\nreturn value\n")
    mainFile:close()

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "global export is visible")
    inc.changeDocument(globalsPath, "local type SharedId = number\n")
    testAssert.equal(
        inc.checkFile(mainPath).diags[1].code,
        "NUPP2101",
        "removed global export does not survive in ambient state"
    )

    os.execute("rm -rf '" .. dir .. "'")
end

function M.bundledModuleTypesResolveThroughTheIncrementalGraph()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")
    local path = dir .. "/main.nupp"
    local file = assert(io.open(path, "wb"))
    file:write(
        table.concat(
            {
                [[local buffer = require("string.buffer")]],
                "local record Thing",
                "   buf: buffer.Buffer",
                "end",
                "local thing = new Thing(buf = buffer.new())",
                "return thing.buf:tostring()",
            },
            "\n"
        )
    )
    file:close()

    local inc = incremental.new(dir, {cache = false})
    local result = inc.checkFile(path)
    testAssert.equal(#result.diags, 0, "bundled type exports survive an earlier value-side lookup")

    os.execute("rm -rf '" .. dir .. "'")
end

-- A bundled module is loaded when something asks for it. Together they cost
-- about as much as the prelude, and a file that does not require `ffi` is not
-- made any more correct by the compiler having worked out what `ffi` would
-- have meant. Both halves matter and only one of them is obvious: the loading
-- has to be lazy, and it also has to happen at most once either way, because
-- the miss is what an ordinary unresolved name hits on every lookup.
function M.bundledModulesAreLoadedWhenSomethingAsksForThem()
    local envMod = require("nupp.compiler.project.env")
    -- The engine calls the checker module itself, so counting what it checks means
    -- replacing the function there rather than on the tests' fragment wrapper.
    local check = require("nupp.compiler.check")
    local checked = {}
    local original = check.check
    check.check = function(result, filename, ...)
        checked[filename] = (checked[filename] or 0) + 1
        return original(result, filename, ...)
    end

    local dir = "/tmp/nupp-lazy-decls-" .. tostring(os.time())
    os.execute("mkdir -p '" .. dir .. "'")

    -- Whatever happens, the checker goes back. Counting what gets checked
    -- means replacing `check.check` for the length of this test, and a failure
    -- part way through used to leave the replacement installed for every test
    -- after it -- which does not read as this test's fault when the suite
    -- crashes four tests later.
    local ok, err = pcall(function()
        local env = envMod.new(dir, {cache = false})
        testAssert.equal(checked["ffi"], nil, "building an environment does not check ffi")
        testAssert.equal(checked["nupp.profile.zone"], nil, "nor the standard library")

        -- Asking is what loads it, and asking twice does not check it twice.
        assert(env.bundled["ffi"], "ffi is still there when wanted")
        testAssert.equal(checked["ffi"], 1, "asking for ffi checks it")
        assert(env.bundled["ffi"], "and it is still there the second time")
        testAssert.equal(checked["ffi"], 1, "asking again does not check it again")

        -- A name nothing bundles is remembered as absent rather than looked for
        -- again, which is what every unresolved name in a project would
        -- otherwise do on every lookup.
        testAssert.equal(env.bundled["not.a.bundled.module"], false, "an unbundled name is absent, not a failure")
        testAssert.equal(rawget(env.bundled, "not.a.bundled.module"), false, "and the absence is remembered")
    end)

    check.check = original
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(err, 0)
    end
end

--- Staging a generated module, checking it and dropping it again is what catalog
--- validation does once per service provider, and what an editor does with any
--- scratch buffer. It changes the project's file set, which changes the project
--- index -- but it changes nothing about any other module, so nothing else should
--- be checked again. Counted rather than timed: before the index was read one
--- module name at a time, every checked module depended on the whole index, and
--- each of these rounds rechecked all of them.
function M.stagingAGeneratedModuleRechecksNothingElse()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")

    local function write(path, text)
        local f = assert(io.open(path, "wb"))
        f:write(text)
        f:close()
    end

    local depPath = dir .. "/dep.nupp"
    local mainPath = dir .. "/main.nupp"
    write(
        depPath,
        table.concat(
            {"module dep", "", "export function scale(n: number): number", "    return n * 2", "end", "",},
            "\n"
        )
    )
    write(
        mainPath,
        table.concat(
            {"module main", "", "local dep = require(\"dep\")", "", "export const doubled = dep.scale(21)", "",},
            "\n"
        )
    )

    local inc = incremental.new(dir)
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "cold check clean")
    local settled = inc.q.stats.checkModule
    testAssert.equal(settled, 2, "main + dep checked cold")

    local rounds = 4
    for i = 1, rounds do
        local staged = dir .. "/staged" .. i .. ".nupp"
        inc.openGeneratedDocument(staged, "module staged" .. i .. "\n\nexport const value = " .. i .. "\n")
        testAssert.equal(#inc.checkFile(staged).diags, 0, "the staged module checks clean")
        inc.closeDocument(staged)
        testAssert.equal(#inc.checkFile(mainPath).diags, 0, "and the project still checks clean")
    end

    testAssert.equal(
        inc.q.stats.checkModule,
        settled + rounds,
        "only the staged modules were checked; no project module was rechecked"
    )

    -- The narrowed answers still say what they always said. A second file
    -- declaring `dep` is a registration conflict, and both files have to report it.
    local rivalPath = dir .. "/rival.nupp"
    inc.openDocument(rivalPath, "module dep\n\nexport const other = 1\n")
    local rival = inc.checkFile(rivalPath)
    testAssert.equal(
        rival.diags[1] and rival.diags[1].code,
        "NUPP1002",
        "a duplicate module declaration is still reported"
    )
    inc.closeDocument(rivalPath)
    testAssert.equal(#inc.checkFile(depPath).diags, 0, "and stops being reported once the rival is gone")

    os.execute("rm -rf '" .. dir .. "'")
end

--- A file in a require cycle checked first, the way a build walks its files, is the
--- one whose interface the cycle reads on its re-entrant edge. That read must not be
--- what a later dependent in the same revision sees: it was nil, and the dependent
--- reported `no field "base" in unknown` instead of the real mismatch.
function M.aRequireCycleEnteredByFileLeavesItsInterfaceForLaterDependents()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "'")

    local function write(path, text)
        local file = assert(io.open(dir .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    write(
        "cycle_a.g.nupp",
        table.concat(
            {
                "local cycleB = require('cycle_b')",
                "local cycleA = {}",
                "function cycleA.base(): number return 1 end",
                "function cycleA.value(): number return cycleB.value() + 1 end",
                "return cycleA",
            },
            "\n"
        )
    )
    write(
        "cycle_b.g.nupp",
        table.concat(
            {
                "local cycleA = require('cycle_a')",
                "local cycleB = {}",
                "function cycleB.value(): number return cycleA.base() + 1 end",
                "return cycleB",
            },
            "\n"
        )
    )
    write("user.nupp", "local cycleA = require('cycle_a')\nlocal wrong: string = cycleA.base()\nreturn wrong\n")

    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(dir .. "/cycle_a.g.nupp").diags, 0, "the cycle's first member checks clean")
    testAssert.equal(#inc.checkFile(dir .. "/cycle_b.g.nupp").diags, 0, "and so does its second")
    local user = inc.checkFile(dir .. "/user.nupp").diags
    testAssert.equal(user[1] and user[1].code, "NUPP2001", "the dependent sees the member's real result type")
    testAssert.equal(#user, 1, "and nothing else")

    os.execute("rm -rf '" .. dir .. "'")
end

--- Validating a memo brings each of its dependencies up to date, and a `require`
--- cycle makes one of those lead back to the entry being validated. The re-entrant
--- edge has to report what that entry last changed at rather than validating it
--- again; without that, validation recurses until the stack runs out.
-- A record keeps its identity across rechecks through its project-index skeleton,
-- and it used to keep the members the check before had published on it too. The
-- first pass skips a method the record already lists, so a recheck neither resolved
-- those signatures nor recorded the project reads they make, and a method deleted
-- from the source was still there to call.
function M.aRecheckSeesOnlyTheMembersItsSourceDeclares()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "/pkg'")
    local path = dir .. "/pkg/b.nupp"

    local function source(withOld)
        return table.concat(
            {
                "local m = {}",
                "record m.R",
                "    v: integer",
                "end",
                withOld and "function m.R.old(): integer return 1 end" or "",
                "function m.R.use(): integer",
                "    return m.R.old()",
                "end",
                "return m",
            },
            "\n"
        )
    end

    local file = assert(io.open(path, "wb"))
    file:write(source(true))
    file:close()
    local inc = incremental.new(dir, {cache = false})
    testAssert.equal(#inc.checkFile(path).diags, 0, "the module checks cold")
    inc.changeDocument(path, source(false))
    local rechecked = inc.checkFile(path).diags
    local cold = incremental.new(dir, {cache = false})
    cold.openDocument(path, source(false))
    local fresh = cold.checkFile(path).diags
    testAssert.equal(#fresh > 0, true, "a cold check refuses the deleted method")
    testAssert.equal(#rechecked, #fresh, "and so does a recheck")
    testAssert.equal(rechecked[1] and rechecked[1].code, fresh[1] and fresh[1].code, "with the same diagnostic")

    os.execute("rm -rf '" .. dir .. "'")
end

-- A record method's signature is resolved in the first pass over its block, before
-- the block's locals are bound. `alias.T` there used to look for a module called
-- `alias`, or `pkg.alias` beside the file, rather than the module the local requires,
-- and an unbound `{type Thing}` selection fell through to a project global. The
-- statement itself then disagreed with what its earlier callers had been checked
-- against.
function M.aMethodSignatureNamesWhatItsLocalsRequire()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "/pkg'")

    local function write(name, lines)
        local file = assert(io.open(dir .. "/pkg/" .. name, "wb"))
        file:write(table.concat(lines, "\n"))
        file:close()
    end

    write("dep.nupp", {
        "local dep = {}",
        "record dep.T",
        "    n: integer",
        "end",
        "record dep.Thing",
        "    n: integer",
        "end",
        "return dep",
    })
    write("alias.nupp", {"local alias = {}", "record alias.T", "    s: string", "end", "return alias"})
    write("thing.nupp", {"global record Thing", "    s: string", "end", "return {}"})
    write("b.nupp", {
        "local m = {}",
        "local alias = require('pkg.dep')",
        "const {type Thing} = require('pkg.dep')",
        "record m.R",
        "    v: integer",
        "end",
        "function m.R.first(x: alias.T, y: Thing): integer",
        "    return m.R.make(x, y)",
        "end",
        "function m.R.make(x: alias.T, y: Thing): integer",
        "    return x.n + y.n",
        "end",
        "return m",
    })

    local inc = incremental.new(dir, {cache = false})
    local diags = inc.checkFile(dir .. "/pkg/b.nupp").diags
    testAssert.equal(#diags, 0, "the methods take pkg.dep's types: " .. tostring(diags[1] and diags[1].msg))

    os.execute("rm -rf '" .. dir .. "'")
end

-- The ownership a record claims through `is` is read in the first pass too, and
-- `is alias.Named` there was looked up the same way: as `pkg.alias` beside the file
-- rather than the module the local requires. Loading that module only because it
-- shared a local's name re-entered the check that was asking, and a cycle back
-- through it left the requiring module's exports half built -- the standard
-- library's `structure.Construction` loaded a project's own `structure.nupp`.
function M.aRecordClaimNamesWhatItsLocalsRequire()
    local dir = os.tmpname()
    os.remove(dir)
    os.execute("mkdir -p '" .. dir .. "/pkg'")

    local function write(name, lines)
        local file = assert(io.open(dir .. "/" .. name, "wb"))
        file:write(table.concat(lines, "\n"))
        file:close()
    end

    write("pkg/dep.nupp", {"module pkg.dep", "export interface Named", "    name: function(self): string", "end"})
    write("pkg/b.nupp", {
        "module pkg.b",
        "local alias = require('pkg.dep')",
        "export record Options",
        "    n: integer = 0",
        "end",
        "export record Tag is alias.Named",
        "    @readonly text: string",
        "    function name(self): string",
        "        return self.text",
        "    end",
        "end",
    })
    write("pkg/alias.nupp", {"module pkg.alias", "local b = require('pkg.b')", "export const options: b.Options? = nil"})
    write("main.nupp", {"local b = require('pkg.b')", "local o: b.Options = new b.Options()", "print(o.n)"})

    local inc = incremental.new(dir, {cache = false})
    local diags = inc.checkFile(dir .. "/main.nupp").diags
    testAssert.equal(#diags, 0, "pkg.b's exports are whole: " .. tostring(diags[1] and diags[1].msg))

    os.execute("rm -rf '" .. dir .. "'")
end

function M.validationTerminatesOnADependencyCycle()
    local q = query.new()
    q:setInput("text", "a", 1)
    q:setInput("text", "b", 1)
    -- The cyclic edge is read before the input, so validating one entry reaches the
    -- other before it reaches anything that could tell it it is stale.
    q:define("checked", function(self, key)
        self:get("checked", key == "a" and "b" or "a")

        return self:get("text", key)
    end)
    testAssert.equal(q:get("checked", "a"), 1)
    testAssert.equal(q:get("checked", "b"), 1)
    q:setInput("text", "b", 2)
    testAssert.equal(q:get("checked", "a"), 1, "the cycle revalidates rather than recursing forever")
    testAssert.equal(q:get("checked", "b"), 2, "and the change on the far side of it is still seen")
end

function M.cycleGuardsKeepDifferentlyTypedKeysSeparate()
    local q = query.new()
    q:define("value", function(self, key)
        if type(key) == "number" then
            return self:get("value", tostring(key))
        end

        return "string key"
    end)

    testAssert.equal(q:get("value", 1), "string key", "numeric and string keys are distinct computations")
    testAssert.equal(q.stats.value, 2, "both differently typed keys compute")
end

-- A build stages a compiler-carried module by putting its source on a path, so it
-- can be linked. That is how far the build has got, not a change to what the name
-- means, and a worker never stages at all: so it moves nothing a checked module
-- read, and nothing is checked again for it. It used to join the project, which
-- moved the index and re-checked the carried modules into fresh copies of their
-- types, and every module requiring one was checked again -- once per staging.
-- Anything else staged there is a project file, and is seen.
function M.stagingACarriedModuleChecksNothingAgain()
    local dir = os.tmpname()
    os.remove(dir)
    local staged = dir .. "/build/cache/runtime-source"
    os.execute("mkdir -p '" .. staged .. "/nupp/io/files'")
    local mainPath = dir .. "/main.nupp"
    local file = assert(io.open(mainPath, "wb"))
    file:write(
        table.concat(
            {
                "const {type Observers} = require('nupp.events')",
                "local events = require('nupp.events')",
                "local files = require('nupp.io.files')",
                "local m = {}",
                "record m.Holder",
                "   observers: Observers<integer>",
                "end",
                "function m.build(path: string): m.Holder",
                "   print(files.exists(path))",
                "   return new m.Holder(observers = events.newObservers())",
                "end",
                "return m",
            },
            "\n"
        )
    )
    file:close()

    local inc = incremental.new(dir, {cache = false, runtimeSourceRoots = {staged}})
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "checks cold")
    local checks = inc.q.stats.checkModule

    local source = assert(require("nupp.compiler.bundled").source("/nupp/io/files/init.nupp"))
    inc.env.roots[#inc.env.roots + 1] = staged
    local stagedPath = staged .. "/nupp/io/files/init.nupp"
    local copy = assert(io.open(stagedPath, "wb"))
    copy:write(source)
    copy:close()
    inc.stageCarriedDocument("nupp.io.files", stagedPath, source)
    testAssert.equal(inc.modulePath("nupp.io.files"), stagedPath, "the build finds the staged copy to link")
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "still clean with the module staged")
    testAssert.equal(inc.q.stats.checkModule, checks, "staging the carried copy checks nothing again")

    -- A staged file that is not the carried source is a project file like any other.
    os.execute("mkdir -p '" .. staged .. "/demo'")
    local extra = assert(io.open(staged .. "/demo/extra.nupp", "wb"))
    extra:write("return {value = 1}")
    extra:close()
    inc.stageCarriedDocument("demo.extra", staged .. "/demo/extra.nupp", "return {value = 1}")
    testAssert.equal(inc.modulePath("demo.extra"), staged .. "/demo/extra.nupp", "the staged project file resolves")
    assert(inc.q.stats.checkModule == checks, "nothing requiring it was checked")

    -- Nor is a staged copy whose text is not what the compiler carries: it answers for
    -- the name, and what requires the name is checked against it.
    local events = assert(require("nupp.compiler.bundled").source("/nupp/events.nupp"))
    os.execute("mkdir -p '" .. staged .. "/nupp'")
    local changed = assert(io.open(staged .. "/nupp/events.nupp", "wb"))
    changed:write(events .. "\n-- edited\n")
    changed:close()
    inc.stageCarriedDocument("nupp.events", staged .. "/nupp/events.nupp", events .. "\n-- edited\n")
    testAssert.equal(#inc.checkFile(mainPath).diags, 0, "the edited copy still checks")
    assert(inc.q.stats.checkModule > checks, "a copy that differs is checked, and so is what requires it")

    os.execute("rm -rf '" .. dir .. "'")
end

function M.importedInliningObservesBodiesOnlyDuringOptimization()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local dep, main = dir .. "/dep.nupp", dir .. "/main.nupp"

    local function write(path, source)
        local out = assert(io.open(path, "w"));
        out:write(source);
        out:close()
    end

    local provider = "local M = {}\nfunction M.scale(value: number): number return value * 2 end\nreturn M"
    write(dep, provider)
    write(
        main,
        "local D = require('dep')\n@jit\nlocal function work(value: number): number return D.scale(value) end\nreturn work"
    )
    local ok, err = pcall(function()
        local inc = incremental.new(dir, {cache = false})
        local checked = inc.checkFile(main)

        local function bodyDependency()
            for _, edge in ipairs(inc.projectDependencies(main)) do
                if edge.name == "moduleCallableFact" and edge.key == "dep\0scale\0inlineBody" then
                    return edge.fingerprint
                end
            end
        end

        assert(not bodyDependency(), "checking does not consume an optimization body")
        local optimize = require("nupp.compiler.lua.optimize")
        local gen = require("nupp.compiler.lua.gen")
        optimize.run(checked.result, {level = 1})
        local before = assert(bodyDependency(), "inlining records its exact body dependency")
        local first = gen.generate(checked.result, main)
        assert(first:find("value * 2", 1, true), first)
        local count = inc.q.stats.checkModule
        inc.changeDocument(dep, provider:gsub("value %* 2", "value * 3"))
        local nextCheck = inc.checkFile(main)
        testAssert.equal(inc.q.stats.checkModule, count + 1, "a private body change does not recheck the importer")
        optimize.run(nextCheck.result, {level = 1})
        assert(bodyDependency() ~= before, "the emission dependency changed")
        local second = gen.generate(nextCheck.result, main)
        assert(second:find("value * 3", 1, true), "re-emission uses the new body: " .. second)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(err, 0)
    end
end

function M.importedConstantFoldingRefreshesAfterPrivateBodyChanges()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'"))
    local dep, main = dir .. "/dep.nupp", dir .. "/main.nupp"

    local function write(path, source)
        local out = assert(io.open(path, "w"));
        out:write(source);
        out:close()
    end

    local provider = "local M = {}\nfunction M.scale(value: number): number return value * 2 end\nreturn M"
    write(dep, provider)
    write(main, "local D = require('dep')\nreturn D.scale(2) + 1")
    local ok, err = pcall(function()
        local inc = incremental.new(dir, {cache = false})
        local checked = inc.checkFile(main)

        local function bodyDependency()
            for _, edge in ipairs(inc.projectDependencies(main)) do
                if edge.name == "moduleCallableFact" and edge.key == "dep\0scale\0inlineBody" then
                    return edge.fingerprint
                end
            end
        end

        assert(not bodyDependency(), "checking does not consume an optimization body")
        local optimize = require("nupp.compiler.lua.optimize")
        local gen = require("nupp.compiler.lua.gen")
        optimize.run(checked.result, {level = 1})
        local before = assert(bodyDependency(), "inlining records its exact body dependency")
        local first = gen.generate(checked.result, main)
        assert(first:find("return 5", 1, true), first)
        local count = inc.q.stats.checkModule
        inc.changeDocument(dep, provider:gsub("value %* 2", "value * 3"))
        local nextCheck = inc.checkFile(main)
        testAssert.equal(inc.q.stats.checkModule, count + 1, "a private body change does not recheck the importer")
        optimize.run(nextCheck.result, {level = 1})
        assert(bodyDependency() ~= before, "the emission dependency changed")
        local second = gen.generate(nextCheck.result, main)
        assert(second:find("return 7", 1, true), "re-emission uses the new body: " .. second)
    end)
    os.execute("rm -rf '" .. dir .. "'")
    if not ok then
        error(err, 0)
    end
end

return M
