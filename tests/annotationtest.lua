-- Statement annotations are an extensible, checked language surface. The
-- parser accepts their general shape; the registry decides what exists.
local parser = require("nupp.compiler.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.env")
local annotations = require("nupp.compiler.annotations")
local fmt = require("nupp.compiler.fmt")
local gen = require("nupp.compiler.gen")

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

function M.sealedInterfacesRequireDeclaredConformance()
    assertEq(checked(table.concat({
        "local sealed interface Token",
        "    readonly value: integer",
        "end",
        "local record Genuine is Token",
        "    readonly value: integer",
        "end",
        "local token: Token = new Genuine(value = 1)",
        "print(token.value)",
    }, "\n")), "")

    assertEq(checked(table.concat({
        "local sealed interface Token",
        "    readonly value: integer",
        "end",
        "local record Shaped",
        "    readonly value: integer",
        "end",
        "local token: Token = new Shaped(value = 1)",
        "print(token.value)",
    }, "\n")), "NUPP2001")

    assertEq(checked(table.concat({
        "local record Shaped",
        "    readonly value: integer",
        "end",
        "local token: Token = new Shaped(value = 1)",
        "local sealed interface Token",
        "    readonly value: integer",
        "end",
        "print(token.value)",
    }, "\n")), "NUPP2001", "sealing applies to forward references")
end

function M.sealedIsAKeywordNotAnAnnotation()
    local result = parser.parse("@sealed\nlocal interface Token end", "test.g.nupp")
    assert(#result.errors > 0, "@sealed must be rejected as syntax")
end

function M.partitionContractsRequireASealedInterfaceAndRealFields()
    assertEq(checked(table.concat({
        "local record Pair left: integer right: integer end",
        "local interface Splitter",
        "    @partition(left, right)",
        "    split: function(self: Splitter): Pair",
        "end",
    }, "\n")), "NUPP2602")

    assertEq(checked(table.concat({
        "local record Pair left: integer right: integer end",
        "local sealed interface Splitter",
        "    @partition(left, missing)",
        "    split: function(self: Splitter): Pair",
        "end",
    }, "\n")), "NUPP2602")
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
    assertEq(diagsOf("@jit local function f() end"), "")
    assertEq(diagsOf("@comptime const function f() end"), "")
end

function M.attachmentTargetsAreChecked()
    assertEq(diagsOf("@jit local x = 1"), "NUPP2112")
    -- Named functions are a valid attachment target because exported helpers use
    -- `function M.f()`. A bare global is rejected by the comptime declaration rule.
    assertEq(diagsOf("@comptime function f() end"), "NUPP2411")
end

function M.argumentContractsAreChecked()
    assertEq(diagsOf("@jit(on) local function f() end"), "NUPP2112")
    -- a name that is neither a lint nor a code names no lint to allow
    assertEq(diagsOf("@allow(not_a_lint) local x = 1"), "NUPP2108")
end

function M.deprecatedMetadataIsTypedAndTargeted()
    assertEq(checked(table.concat({
        '@deprecated(reason = "compatibility", replacement = "current")',
        "local function legacy(): integer return 1 end",
        "return legacy()",
    }, "\n")), "NUPP2513")
    assertEq(checked("@deprecated(reason = 42)\nfunction legacy() end"),
        "NUPP2115")
    assertEq(checked("@deprecated\ndo end"), "NUPP2112")
end

function M.syntaxAnnotationsAreTypedButDoNotConstrainBindings()
    local codes, result = checked(table.concat({
        '@syntax("json")',
        "local document: {integer} = {1}",
    }, "\n"))
    assertEq(codes, "")
    assertEq(result.root.blocks[1].stats[1].stat.embeddedStringFormat, "json")
    assertEq(checked('@syntax(42)\nlocal value = 1'), "NUPP2115")
    assertEq(checked('@syntax("json")\ndo end'), "NUPP2112")
end

function M.deprecatedUsesReportAcrossApiKinds()
    local codes, _, diagnostics = checked(table.concat({
        '@deprecated(reason = "kept for compatibility", replacement = "current")',
        "local function legacy(): integer return 1 end",
        "local function current(): integer return 2 end",
        "local record Box",
        '    @deprecated("old field")',
        "    old: integer",
        "    current: integer",
        "end",
        '@deprecated(replacement = "Box")',
        "local type OldBox = Box",
        "local value: OldBox = new Box(old = legacy(), current = current())",
        "return value.old",
    }, "\n"))
    assertEq(codes, "NUPP2513 NUPP2513 NUPP2513 NUPP2513")
    assertEq(diagnostics[1].help, "use Box instead")
    assertEq(diagnostics[3].help, "use current instead")
    assert(diagnostics[2].msg:find("old field", 1, true), diagnostics[2].msg)
end

function M.deprecatedLintCanBeAllowed()
    assertEq(checked(table.concat({
        "@deprecated local type Old = string",
        '@allow("deprecated")',
        "do",
        '    local value: Old = "ok"',
        "    print(value)",
        "end",
    }, "\n")), "")
end

function M.deprecatedAnnotationsEmitNoRuntimeBehavior()
    local codes, result = checked(table.concat({
        '@deprecated(reason = "compatibility", replacement = "current")',
        "local function legacy(): integer return 1 end",
        "return legacy()",
    }, "\n"))
    assertEq(codes, "NUPP2513")
    local lua, errors = gen.generate(result, "test")
    assertEq(#errors, 0, "generation diagnostics")
    assert(not lua:find("deprecated", 1, true), lua)
    assert(not lua:find("compatibility", 1, true), lua)
end

function M.stackedAnnotationsUseTheUnderlyingStatementAsTheirTarget()
    assertEq(diagsOf("@allow @jit local function f() end"), "")
end

function M.jitChecksSemanticCFunctionBoundaries()
    local callback = table.concat({
        "local type Visitor = function(int32)",
        "cdef function each(fn: Visitor, n: int32)",
        "local function visit(value: int32) print(value) end",
        "local function run() each(visit, 1) end",
        "return run",
    }, "\n")
    assertEq(diagsOf(callback), "NUPP2502")

    local allowedCallback = callback:gsub(
        "local function run%(%)", '@allow("jit-callback")\nlocal function run()'
    )
    assertEq(diagsOf(allowedCallback), "")

    local disabled = table.concat({
        "cdef function each(fn: function(int32), n: int32)",
        "local function visit(value: int32) print(value) end",
        "jit.off(visit)",
        "local function run() each(visit, 1) end",
        "return run",
    }, "\n")
    assertEq(diagsOf(disabled), "")

    local coldBoundary = table.concat({
        "cdef function each(fn: function(int32), n: int32)",
        "local function visit(value: int32) print(value) end",
        "local function run() each(visit, 1) end",
        "jit.off(run)",
        "return run",
    }, "\n")
    assertEq(diagsOf(coldBoundary), "")

    local variadic = table.concat({
        "cdef function printf(format: cstring, ...): int32",
        "local function run() printf('%d', 1) end",
        "return run",
    }, "\n")
    assertEq(diagsOf(variadic), "NUPP2514")

    local required = table.concat({
        "cdef function printf(format: cstring, ...): int32",
        "@jit",
        "local function run() printf('%d', 1) end",
        "return run",
    }, "\n")
    assertEq(diagsOf(required), "NUPP2707")

    local requiredAllowed = required:gsub("@jit", '@allow("jit-boundary")\n@jit')
    assertEq(diagsOf(requiredAllowed), "NUPP2707")
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
