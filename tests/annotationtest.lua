-- Statement annotations are an extensible, checked language surface. The
-- parser accepts their general shape; the registry decides what exists.
local parser = require("nupp.parser")
local check = require("fragment")
local envMod = require("nupp.env")
local annotations = require("nupp.annotations")
local fmt = require("nupp.fmt")
local gen = require("nupp.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function assertEq(got, want, label)
    if got ~= want then
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch",
            tostring(want), tostring(got)), 2)
    end
end

local function diagsOf(src, registry)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax")
    local out = {}
    for j, d in ipairs(check.check(result, "test.g.nupp", env,
        {annotations = registry})) do
        out[j] = d.code
    end
    return table.concat(out, " ")
end

local M = {}

local function checked(src)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax")
    local projectEnv = envMod.new(HERE .. "/..")
    local diags = check.check(result, "test.g.nupp", projectEnv)
    local codes = {}
    for j, diagnostic in ipairs(diags) do codes[j] = diagnostic.code end
    return table.concat(codes, " "), result, diags
end

function M.effectContractsAreNormalizedAndVerified()
    local source = table.concat({
        '@effects(reads = {"value"}, returns = {"1=value"})',
        "local function identity(value: table): table",
        "    return value",
        "end",
    }, "\n")
    local codes, result = checked(source)
    assertEq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.effectContract.reads[1], "value")
    assertEq(declaration.body.effectSummary.returns["1=value"], true)
end

function M.effectContractsCannotHideBodyEffects()
    assertEq(checked(table.concat({
        "@effects()",
        "local function mutate(values: {integer})",
        "    values[1] = 2",
        "end",
    }, "\n")), "NUPP2112")
    assertEq(checked(table.concat({
        "@effects()",
        "local function opaque(value: table)",
        "    unknown(value)",
        "end",
    }, "\n")), "NUPP2112")
end

function M.returnAliasesPropagateThroughVisibleCalls()
    local source = table.concat({
        '@effects(reads = {"value"}, returns = {"1=value"})',
        "local function same(value: table): table return value end",
        '@effects(reads = {"value"}, returns = {"1=value"})',
        "local function wrapped(value: table): table return same(value) end",
    }, "\n")
    local codes, result = checked(source)
    assertEq(codes, "")
    local wrapped = result.root.blocks[1].stats[2].stat
    assertEq(wrapped.body.effectSummary.returns["1=value"], true)
end

function M.effectMembersHaveClosedShapes()
    assertEq(checked("@effects(reads = true)\nlocal function f() end"),
        "NUPP2112")
    assertEq(checked("@effects(allocates = {})\nlocal function f() end"),
        "NUPP2112")
    assertEq(checked("@effects(mystery = true)\nlocal function f() end"),
        "NUPP2112")
end

function M.relaxationsUseAClosedSetOfObservableGuarantees()
    local codes, result = checked(table.concat({
        '@relax("frames", "error-site")',
        "local function dispatch() end",
    }, "\n"))
    assertEq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.relaxedGuarantees.frames, true)
    assertEq(declaration.relaxedGuarantees["error-site"], true)
    assertEq(checked('@relax("magic")\nlocal function dispatch() end'),
        "NUPP2112")
end

function M.constMarksBodylessDeclarationBindings()
    local source = table.concat({
        "const service: function(): integer",
        "return {service = service}",
    }, "\n")
    local result = parser.parse(source, "service.d.nupp")
    assertEq(#result.errors, 0, "syntax")
    local diags = check.check(result, "service.d.nupp",
        envMod.new(HERE .. "/.."))
    assertEq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1]
    assertEq(declaration.isConst, true)
    assertEq(declaration.names[1].definition.constant, true)
end

function M.stableIsNoLongerABuiltInAnnotation()
    assertEq(checked("@stable\nlocal service = 1"), "NUPP2111")
end

function M.effectContractsAttachToDeclarationBindings()
    local source = table.concat({
        '@effects(raises = true)',
        "const fail: function(message: string): never",
        "return {fail = fail}",
    }, "\n")
    local result = parser.parse(source, "failure.d.nupp")
    assertEq(#result.errors, 0, "syntax")
    local diags = check.check(result, "failure.d.nupp",
        envMod.new(HERE .. "/.."))
    assertEq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.names[1].definition.effectContract.raises, true)
    assertEq(declaration.names[1].definition.constant, true)
end

function M.constDeclarationBindingsCannotBeReassigned()
    local codes = checked(table.concat({
        "ipairs = function(values)",
        "    return next, values, nil",
        "end",
    }, "\n"))
    assert(codes:find("NUPP2008", 1, true), codes)
end

function M.unknownAnnotationsAreErrors()
    assertEq(diagsOf("@inline local function f() end"), "NUPP2111")
end

function M.newAnnotationsCanBeDefined()
    local registry = annotations.new()
    local definition, err = registry:define{
        name = "inline",
        arguments = "none",
        targets = {"function"},
    }
    assert(definition, err)
    assertEq(diagsOf("@inline local function f() end", registry), "")
end

function M.projectEnvironmentsOwnAnExtensibleRegistry()
    local projectEnv = envMod.new(HERE .. "/..")
    assert(projectEnv.annotations:define{
        name = "profile",
        arguments = "none",
        targets = {"function"},
    })
    local result = parser.parse("@profile local function f() end", "test")
    assertEq(#result.errors, 0, "syntax")
    assertEq(#check.check(result, "test.g.nupp", projectEnv), 0)
end

function M.customAnnotationsCanLimitTheirTargets()
    local registry = annotations.new()
    assert(registry:define{
        name = "entity",
        arguments = "none",
        targets = {"record"},
    })
    assertEq(diagsOf("@entity local record E end", registry), "")
    assertEq(diagsOf("@entity local function f() end", registry), "NUPP2112")
end

function M.definitionTargetsAreValidated()
    local registry = annotations.new()
    local definition, err = registry:define{
        name = "bad",
        arguments = "none",
        targets = {"expression"},
    }
    assertEq(definition, nil)
    assert(err:find("unknown annotation target", 1, true), err)
end

function M.reservedAnnotationsAreNotSilentlyErased()
    assertEq(diagsOf("@jit local function f() end"), "NUPP2113")
    assertEq(diagsOf("@comptime const function f() end"), "NUPP2113")
end

function M.attachmentTargetsAreChecked()
    assertEq(diagsOf("@jit local x = 1"), "NUPP2112")
    assertEq(diagsOf("@comptime function f() end"), "NUPP2112")
end

function M.argumentContractsAreChecked()
    assertEq(diagsOf("@jit(on) local function f() end"), "NUPP2112")
    -- a name that is neither a lint nor a code names no lint to allow
    assertEq(diagsOf("@allow(not_a_lint) local x = 1"), "NUPP2108")
end

function M.stackedAnnotationsUseTheUnderlyingStatementAsTheirTarget()
    assertEq(diagsOf("@allow @jit local function f() end"), "NUPP2113")
end

function M.annotationRecordsDefineTypedMetadata()
    local src = table.concat({
        '@annotation(targets = {"record", "struct"})',
        "local record serializable",
        "    format: string",
        "    version: integer?",
        "end",
        '@serializable(format = "json")',
        "local record User",
        "    id: uint64",
        "end",
    }, "\n")
    local codes, result = checked(src)
    assertEq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assert(definition, "annotation definition is recorded")
    assertEq(definition.members.format.type.tag, "string")
    assertEq(definition.members.version.optional, true)
end

function M.annotationMembersAreChecked()
    local prefix = table.concat({
        '@annotation(targets = {"record"})',
        "local record serializable",
        "    format: string",
        "end",
    }, "\n") .. "\n"
    assertEq(checked(prefix .. "@serializable\nlocal record Missing end"),
        "NUPP2115")
    assertEq(checked(prefix
        .. "@serializable(format = 42)\nlocal record Wrong end"), "NUPP2115")
    assertEq(checked(prefix
        .. '@serializable(other = "json")\nlocal record Unknown end'),
        "NUPP2115 NUPP2115")
end

function M.annotationTargetsIncludeFields()
    local src = table.concat({
        '@annotation(targets = {"field"})',
        "local record range",
        "    min: number",
        "    max: number",
        "end",
        "local record Config",
        "    @range(min = 1, max = 65535)",
        "    port: integer",
        "end",
    }, "\n")
    assertEq(checked(src), "")
    assertEq(checked(src .. "\n@range(min = 1, max = 2)\nlocal record Bad end"),
        "NUPP2112")
end

function M.annotationValueDesignatesThePositionalMember()
    local src = table.concat({
        '@annotation(targets = {"record"})',
        "local record documentation",
        "    @annotationValue",
        "    text: string",
        "end",
        '@documentation("A user")',
        "local record User end",
    }, "\n")
    local codes, result = checked(src)
    assertEq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assertEq(definition.singleValue, "text")
end

function M.onlyOneAnnotationValueIsAllowed()
    local src = table.concat({
        '@annotation(targets = {"record"})',
        "local record bad",
        "    @annotationValue",
        "    first: string",
        "    @annotationValue",
        "    second: string",
        "end",
    }, "\n")
    assertEq(checked(src), "NUPP2114")
    assertEq(checked("local record Plain\n@annotationValue\nx: string\nend"),
        "NUPP2114")
end

function M.annotationValuesAreCompileTimeConstants()
    local src = table.concat({
        '@annotation(targets = {"record"})',
        "local record documentation",
        "    @annotationValue",
        "    text: string",
        "end",
        "local runtime = 'no'",
        "@documentation(runtime)",
        "local record User end",
    }, "\n")
    assertEq(checked(src), "NUPP2115")
end

function M.annotationReferencesResolveTypes()
    local src = table.concat({
        '@annotation(targets = {"record"})',
        "local record relatesTo",
        "    @annotationValue",
        "    @ref",
        "    target: any",
        "end",
        "local record User end",
        "@relatesTo(User)",
        "local record Post end",
    }, "\n")
    local codes, result = checked(src)
    assertEq(codes, "")

    local users = {}
    for _, token in ipairs(result.tokens) do
        if token.text == "User" then users[#users + 1] = token end
    end
    assertEq(#users, 2, "User tokens")
    assert(users[1].definition, "type declaration has a definition")
    assert(users[2].definition == users[1].definition,
        "@ref value links to the type declaration")
    assertEq(users[2].semanticKind, "type", "@ref semantic kind")
end

function M.annotationReferencesMustNameCompatibleTypes()
    local prefix = table.concat({
        '@annotation(targets = {"record"})',
        "local record relatesTo",
        "    @annotationValue",
        "    @ref",
        "    target: number",
        "end",
    }, "\n") .. "\n"
    assertEq(checked(prefix .. "@relatesTo(Missing)\nlocal record Bad end"),
        "NUPP2115")
    assertEq(checked(prefix .. "@relatesTo(42)\nlocal record Bad end"),
        "NUPP2115")
    assertEq(checked(prefix
        .. "local record User end\n@relatesTo(User)\nlocal record Bad end"),
        "NUPP2115")
end

function M.refIsRestrictedToAnnotationDefinitionMembers()
    assertEq(checked("local record Plain\n    @ref\n    target: any\nend"),
        "NUPP2114")
end

function M.formatterPrefersTheSingleValueSpelling()
    local src = table.concat({
        '@annotation(targets={"record"})',
        "local record documentation",
        "@annotationValue",
        "text:string",
        "end",
        '@documentation(text = "A user")',
        "local record User end",
    }, "\n")
    local formatted, errors = fmt.format(src, "test")
    assertEq(#errors, 0, "format diagnostics")
    assert(formatted:find('@documentation("A user")', 1, true), formatted)
    assert(not formatted:find("@documentation(text", 1, true), formatted)
    assertEq(fmt.format(formatted, "test"), formatted, "format idempotency")
end

function M.annotationDefinitionsAndApplicationsErase()
    local src = table.concat({
        '@annotation(targets = {"record"})',
        "local record documentation",
        "    @annotationValue",
        "    text: string",
        "end",
        '@documentation("A user")',
        "local record User end",
        "return User",
    }, "\n")
    local codes, result = checked(src)
    assertEq(codes, "")
    local lua, errors = gen.generate(result, "test")
    assertEq(#errors, 0, "generation diagnostics")
    assert(not lua:find("documentation", 1, true), lua)
    assert(lua:find("const User = {}", 1, true), lua)
end

function M.annotationStructsDoNotPublishRuntimeConstructors()
    local codes, result = checked(table.concat({
        '@annotation(targets = {"record"})',
        "local struct tag",
        "    value: string",
        "end",
        '@tag(value = "entity")',
        "local record Entity end",
    }, "\n"))
    assertEq(codes, "")
    assertEq(result.moduleExports.values.tag, nil)
end

function M.annotationDefinitionsReplaceTheirPreviousFileRevision()
    local projectEnv = envMod.new(HERE .. "/..")
    local filename = "changing.nupp"
    local first = parser.parse(table.concat({
        '@annotation(targets = {"record"})',
        "local record label",
        "    value: string",
        "end",
        '@label(value = "first")',
        "local record First end",
    }, "\n"), filename)
    assertEq(#check.check(first, filename, projectEnv), 0, "first revision")

    local second = parser.parse(table.concat({
        '@annotation(targets = {"record"})',
        "local record label",
        "    value: integer",
        "end",
        "@label(value = 2)",
        "local record Second end",
    }, "\n"), filename)
    assertEq(#check.check(second, filename, projectEnv), 0, "second revision")
end

return M
