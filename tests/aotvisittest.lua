-- The scalar child mapper is the optimizer's single structural authority.

local cst = require("nupp.compiler.cst")
local effects = require("nupp.compiler.aot.effects")
local parser = require("nupp.compiler.parser")
local visit = require("nupp.compiler.aot.visit")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))

local M = {}

local function localValue(name)
    return {op = "local", name = name, cName = name, type = "u32"}
end

local function replacement(child)
    if child.op == "local" then
        return {op = "constant_i32", value = "7", type = child.type}
    end
    return child
end

function M.rewritesEveryPreviouslyOmittedExpressionChild()
    local substring = {
        op = "lua_substring",
        bytes = localValue("bytes"),
        first = localValue("first"),
        last = localValue("last"),
        type = "lua_string",
    }
    visit.expressionChildren(substring, replacement)
    assert(substring.bytes.op == "constant_i32")
    assert(substring.first.op == "constant_i32")
    assert(substring.last.op == "constant_i32")

    local tableGet = {op = "lua_table_get_index", table = localValue("table"), key = localValue("key"), type = "f64",}
    visit.expressionChildren(tableGet, replacement)
    assert(tableGet.table.op == "constant_i32")
    assert(tableGet.key.op == "constant_i32")

    local buffer = {op = "lua_string_buffer", initial = localValue("initial"), type = "lua_string_buffer"}
    visit.expressionChildren(buffer, replacement)
    assert(buffer.initial.op == "constant_i32")
    local finish = {op = "lua_string_buffer_finish", buffer = localValue("buffer"), type = "lua_string"}
    visit.expressionChildren(finish, replacement)
    assert(finish.buffer.op == "constant_i32")
end

function M.rewritesEveryBuilderEventChildInExpressionsAndStatements()
    local function event()
        return {
            op = "lua_builder_decimal64",
            builder = localValue("builder"),
            mode = "eager",
            sourceBytes = localValue("sourceBytes"),
            start = localValue("start"),
            length = localValue("length"),
            escaped = localValue("escaped"),
            value = localValue("value"),
            negative = localValue("negative"),
            exponent = localValue("exponent"),
            exact = localValue("exact"),
            capacity = localValue("capacity"),
            scratch = localValue("scratch"),
            escapeScratch = localValue("escapeScratch"),
            escapeIndex = localValue("escapeIndex"),
            escapeCount = localValue("escapeCount"),
            type = "lua_effect",
        }
    end

    local expression = event()
    visit.expressionChildren(expression, replacement)
    local statement = event()
    visit.statementExpressions(statement, replacement)
    for _, node in ipairs({expression, statement}) do
        for _, field in ipairs({
            "builder",
            "sourceBytes",
            "start",
            "length",
            "escaped",
            "value",
            "negative",
            "exponent",
            "exact",
            "capacity",
            "scratch",
            "escapeScratch",
            "escapeIndex",
            "escapeCount",
        }) do
            assert(node[field].op == "constant_i32", field)
        end
    end
end

local function sourceDeclarations()
    local handle = assert(io.open(HERE .. "/../src/nupp/compiler/aot/scalar.nupp", "rb"))
    local source = handle:read("*a")
    handle:close()
    local parsed = parser.parse(source, "src/nupp/compiler/aot/scalar.nupp")
    assert(#parsed.errors == 0)
    local records, aliases = {}, {}
    local function walk(node)
        if not node or cst.isToken(node) then
            return
        end
        if node.kind == "recordDecl" then
            local record = {fields = {}}
            records[node[4].text] = record
            for _, child in ipairs(node) do
                if not cst.isToken(child) and child.kind == "fieldDecl" then
                    record.fields[
                        #record.fields + 1
                    ] = {name = child[1].text, type = cst.textOf(child[3]):gsub("%s+", "")}
                end
            end
        elseif node.kind == "typeAlias" then
            aliases[node[4].text] = cst.textOf(node[6]):gsub("%s+", "")
        end
        for _, child in ipairs(node) do
            walk(child)
        end
    end

    walk(parsed.root)

    return records, aliases
end

local function namesIn(text)
    local names = {}
    for name in text:gmatch("scalarIR%.([%w_]+)") do
        names[name] = true
    end

    return names
end

local function literals(text)
    local values = {}
    for value in text:gmatch("'([^']+)'") do
        values[#values + 1] = value
    end

    return values
end

local function assertSameSet(actual, expected, label)
    for value in pairs(expected) do
        assert(actual[value] == true, label .. " misses " .. value)
    end
    for value, present in pairs(actual) do
        if present then
            assert(expected[value] == true, label .. " has unknown " .. value)
        end
    end
end

function M.mapperAndEffectVocabulariesMatchTheScalarDeclarations()
    local records, aliases = sourceDeclarations()
    local expressionRecords = namesIn(aliases.Expr)
    local statementRecords = namesIn(aliases.Statement)

    local function recordOps(name)
        local record = assert(records[name], name)
        for _, field in ipairs(record.fields) do
            if field.name == "op" then
                local alias = field.type:match("^scalarIR%.([%w_]+)$")
                return literals(alias and aliases[alias] or field.type)
            end
        end

        return {}
    end

    local expressionOps, statementOps = {}, {}
    for name in pairs(expressionRecords) do
        for _, op in ipairs(recordOps(name)) do
            expressionOps[op] = true
        end
    end
    for name in pairs(statementRecords) do
        for _, op in ipairs(recordOps(name)) do
            statementOps[op] = true
        end
    end
    assertSameSet(effects.expressionOpcodes(), expressionOps, "effects expressions")
    assertSameSet(effects.statementOpcodes(), statementOps, "effects statements")

    local function auditRecord(name, op, mapper)
        local expected = {}
        local active = {}
        local makeRecord, makeValue
        local function sentinel(path)
            expected[path] = true
            return {op = "constant", value = "0.0", type = "f64", _auditPath = path}
        end

        -- Lists get two elements so a mapper that visits only the first is
        -- caught, not just one that skips the list entirely.
        makeValue = function(typeText, path)
            if typeText:find("scalarIR.Expr", 1, true) then
                if typeText:sub(1, 1) == "{" then
                    return {sentinel(path .. "[1]"), sentinel(path .. "[2]")}
                end
                return sentinel(path)
            end
            local referred = typeText:match("scalarIR%.([%w_]+)")
            if referred and expressionRecords[referred] then
                if typeText:sub(1, 1) == "{" then
                    return {sentinel(path .. "[1]"), sentinel(path .. "[2]")}
                end
                return sentinel(path)
            elseif referred and records[referred] and referred ~= "Source" and not active[referred] then
                if typeText:sub(1, 1) == "{" then
                    return {makeRecord(referred, nil, path .. "[1]"), makeRecord(referred, nil, path .. "[2]")}
                end
                return makeRecord(referred, nil, path)
            end
            -- A named scalarIR type the resolver cannot place would silently
            -- under-cover the audit; refuse it instead of defaulting. Source and
            -- guarded recursion are known Expr-free, and a named alias must not
            -- hide expressions behind its name.
            if referred and not records[referred] and referred ~= "Type" then
                local alias = aliases[referred]
                assert(alias, "the audit cannot classify " .. typeText)
                assert(not alias:find("Expr", 1, true), "alias " .. referred .. " hides expressions from the audit")
            end
            if typeText:sub(1, 1) == "{" then
                return {}
            elseif typeText:find("boolean", 1, true) then
                return false
            elseif typeText:find("integer", 1, true) or typeText:find("number", 1, true) then
                return 0
            end

            return "f64"
        end
        makeRecord = function(recordName, selectedOp, prefix)
            active[recordName] = true
            local value = {}
            for _, field in ipairs(records[recordName].fields) do
                if field.name == "op" then
                    value.op = selectedOp
                elseif field.name ~= "source" then
                    value[field.name] = makeValue(field.type, prefix .. "." .. field.name)
                end
            end
            active[recordName] = nil

            return value
        end

        local node = makeRecord(name, op, op)
        local observed = {}
        mapper(node, function(child)
            assert(child._auditPath, op .. " produced an undeclared child")
            assert(not observed[child._auditPath], op .. " duplicated " .. child._auditPath)
            observed[child._auditPath] = true
            return child
        end)
        assertSameSet(observed, expected, op .. " child mapper")
    end

    for name in pairs(expressionRecords) do
        for _, op in ipairs(recordOps(name)) do
            auditRecord(name, op, visit.expressionChildren)
        end
    end
    for name in pairs(statementRecords) do
        for _, op in ipairs(recordOps(name)) do
            auditRecord(name, op, visit.statementExpressions)
        end
    end
end

-- The audit above covers direct children; block recursion lives in the
-- observing walk and needs its own witness, or a dropped elseBody descent
-- would pass every mapper check.
function M.observingWalkReachesEveryNestedBlockAndEveryListElement()
    local function let(name)
        return {op = "let", name = name, cName = name, value = localValue(name), type = "u32"}
    end

    local program = {
        body = {
            {
                op = "if",
                clauses = {
                    {condition = localValue("c1"), body = {let("inThen")}},
                    {condition = localValue("c2"), body = {let("inElseif")}},
                },
                elseBody = {let("inElseFirst"), let("inElseSecond")},
            },
            {op = "while", condition = localValue("w"), body = {let("inWhile")}},
            {
                op = "fornum",
                from = localValue("from"),
                to = localValue("to"),
                binding = {name = "i", cName = "i", type = "i32"},
                body = {let("inFor")},
            },
            {op = "block", body = {let("inBlock")}},
        },
    }
    local seen = {}
    visit.program(program, {
        scalarStatement = function(statement)
            if statement.op == "let" then
                seen[statement.cName] = true
            end
        end
    })
    for _, name in ipairs({"inThen", "inElseif", "inElseFirst", "inElseSecond", "inWhile", "inFor", "inBlock",}) do
        assert(seen[name], "the observing walk missed " .. name)
    end
end

function M.pointerSpansSeeLoadsBeneathWideArithmetic()
    local emit = require("nupp.compiler.aot.emit")
    local program = {
        body = {
            {
                op = "let",
                name = "wide",
                cName = "wide",
                type = "i64",
                value = {
                    op = "i64_add",
                    left = {
                        op = "numeric_cast",
                        value = {op = "load", span = "values", index = "i", type = "i32"},
                        type = "i64",
                    },
                    right = {op = "constant_i64", value = "1", type = "i64"},
                    type = "i64",
                },
            }
        },
    }
    local used = emit.pointerSpans(program)
    assert(used.values == true, "a span read beneath 64-bit arithmetic must count as used")
end

return M
