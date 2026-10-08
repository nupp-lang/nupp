local testAssert = require("nupp.test")
-- Statement annotations are an extensible, checked language surface. The
-- parser accepts their general shape; the registry decides what exists.
local parser = require("nupp.compiler.syntax.parser")
local check = require("fragment")
local envMod = require("nupp.compiler.project.env")
local annotations = require("nupp.compiler.annotations")
local fmt = require("nupp.tools.fmt")
local gen = require("nupp.compiler.lua.gen")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
local env = envMod.new(HERE .. "/..")

local function diagsOf(src, registry)
    local result = parser.parse(src, "test.g.nupp")
    testAssert.equal(#result.errors, 0, "syntax")
    local out = {}
    for j, d in ipairs(check.check(result, "test.g.nupp", env, {annotations = registry})) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local checked
local M = {}

function M.policyAnnotationsComposeAcrossTypesDeclarationsMembersAndRegions()
    local source = [[
local sealed interface Resource is nupp.Affine<self.close>
    close: @nosuspend function(takes self: Resource): nil
end

local record Box
    @private
    @readonly
    value: integer

    @writeonly
    [string]: integer
end

@comptime
local function build(): integer
    return 1
end

local result = comptime do
    return build()
end

@nosuspend
@noalloc
@noraise
do
    local _ = result
end
]]
    testAssert.equal(checked(source), "")
    testAssert.equal(checked("local f: @comptime @nosuspend @sendable function(): nil"), "")
    testAssert.equal(checked("local f: @nosuspend ((function(): nil) | integer)"), "NUPP2112")
    testAssert.equal(checked("local f: @nosuspend @nosuspend function(): nil"), "NUPP2112")
end

function M.typeQualifiersPreserveBorrowedFunctionResults()
    testAssert.equal(checked("local value: @nosuspend function<V>(borrows owner: V): V borrows (owner)"), "")
    testAssert.equal(checked("local value: @sendable function<V>(borrows owner: V): V borrows (owner)"), "")
end

function M.namedCoroutineFunctionTypeWorksOnBodylessCallableField()
    testAssert.equal(
        checked(
            [[
local type Feed = thread<(number), (boolean), (number), (string)>
local type Producer = function(number): string yields(number) resumes(boolean)
local interface Worker
    run: Producer
end
local function start(worker: Worker): Feed
    return coroutine.create(worker.run)
end
]]
        ),
        ""
    )
    testAssert.equal(checked("@coroutine(Feed)\nlocal function worker(): nil end"), "NUPP2111")
end

function M.builtinCliCannotBeReplacedByTheFormerBootstrapPath()
    for _, source in ipairs({
        "src/nupp/tools/cli/annotation.g.nupp",
        "/checkout/src/nupp/tools/cli/annotation.g.nupp",
        "C:\\checkout\\src\\nupp\\compiler\\cli\\annotation.g.nupp",
    }) do
        local registry = annotations.new()
        local builtin = registry:get("cli")
        local defined, problem = registry:define({
            name = "cli",
            source = source,
            arguments = "typed",
            targets = {"record", "field"}
        })
        testAssert.equal(defined, nil, "a source file cannot replace builtin cli")
        assert(problem and problem:find("already defined", 1, true), problem)
        testAssert.equal(registry:get("cli"), builtin, "the builtin remains registered")
    end
end

checked = function(src)
    local result = parser.parse(src, "test.g.nupp")
    testAssert.equal(#result.errors, 0, "syntax")
    -- The environment this file already shares, rather than another one built
    -- exactly like it: building one means checking the prelude from source.
    local diags = check.check(result, "test.g.nupp", env)
    local codes = {}
    for j, diagnostic in ipairs(diags) do
        codes[j] = diagnostic.code
    end

    return table.concat(codes, " "), result, diags
end

function M.sealedInterfacesRequireDeclaredConformance()
    testAssert.equal(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    @readonly value: integer",
                    "end",
                    "local record Genuine is Token",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = new Genuine(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        ""
    )

    testAssert.equal(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    @readonly value: integer",
                    "end",
                    "local record Shaped",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = new Shaped(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )

    testAssert.equal(
        checked(
            table.concat(
                {
                    "local record Shaped",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = new Shaped(value = 1)",
                    "local sealed interface Token",
                    "    @readonly value: integer",
                    "end",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        "NUPP2001",
        "sealing applies to forward references"
    )
end

function M.sealedAnnotationIsRemoved()
    testAssert.equal(checked("@sealed\nlocal interface Token end"), "NUPP2111")
end

function M.ownershipAnnotationTwinsAreRemoved()
    testAssert.equal(checked("@affine\nlocal interface Owner end"), "NUPP2111")
    testAssert.equal(checked("local record Owner\n@terminal close: function(takes self: Owner): nil\nend"), "NUPP2111")
end

function M.partitionContractsRequireASealedInterfaceAndRealFields()
    testAssert.equal(
        checked(
            table.concat(
                {
                    "local record Pair left: integer right: integer end",
                    "local interface Splitter",
                    "    @partition(left, right)",
                    "    split: function(self: Splitter): Pair",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )

    testAssert.equal(
        checked(
            table.concat(
                {
                    "local record Pair left: integer right: integer end",
                    "local sealed interface Splitter",
                    "    @partition(left, missing)",
                    "    split: function(self: Splitter): Pair",
                    "end",
                },
                "\n"
            )
        ),
        "NUPP2602"
    )
end

function M.effectContractsAreNormalizedAndVerified()
    local source = table.concat(
        {
            '@effects(reads = {"value"}, returns = {"1=value"})',
            "local function identity(value: table): table",
            "    return value",
            "end",
        },
        "\n"
    )
    local codes, result = checked(source)
    testAssert.equal(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.equal(declaration.effectContract.reads[1], "value")
    testAssert.equal(declaration.body.effectSummary.returns["1=value"], true)
end

function M.effectContractsCannotHideBodyEffects()
    testAssert.equal(
        checked(
            table.concat({"@effects()", "local function mutate(values: {integer})", "    values[1] = 2", "end",}, "\n")
        ),
        "NUPP2112"
    )
    testAssert.equal(
        checked(
            table.concat({"@effects()", "local function opaque(value: table)", "    unknown(value)", "end",}, "\n")
        ),
        "NUPP2112"
    )
end

function M.returnAliasesPropagateThroughVisibleCalls()
    local source = table.concat(
        {
            '@effects(reads = {"value"}, returns = {"1=value"})',
            "local function same(value: table): table return value end",
            '@effects(reads = {"value"}, returns = {"1=value"})',
            "local function wrapped(value: table): table return same(value) end",
        },
        "\n"
    )
    local codes, result = checked(source)
    testAssert.equal(codes, "")
    local wrapped = result.root.blocks[1].stats[2].stat
    testAssert.equal(wrapped.body.effectSummary.returns["1=value"], true)
end

function M.effectMembersHaveClosedShapes()
    testAssert.equal(checked("@effects(reads = true)\nlocal function f() end"), "NUPP2112")
    testAssert.equal(checked("@effects(allocates = {})\nlocal function f() end"), "NUPP2112")
    testAssert.equal(checked("@effects(mystery = true)\nlocal function f() end"), "NUPP2112")
    -- `yields` is no member: suspension is spelled `suspends`, and the old name is as
    -- unknown as any other.
    local codes, _, diags = checked("@effects(yields = false)\nlocal function f() end")
    testAssert.equal(codes, "NUPP2112")
    testAssert.equal(#(diags[1].fixes or {}), 0, "the retired spelling is not special-cased")
end

function M.relaxationsUseAClosedSetOfObservableGuarantees()
    local codes, result = checked(
        table.concat({'@relax("frames", "error-site")', "local function dispatch() end",}, "\n")
    )
    testAssert.equal(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.equal(declaration.relaxedGuarantees.frames, true)
    testAssert.equal(declaration.relaxedGuarantees["error-site"], true)
    testAssert.equal(checked('@relax("magic")\nlocal function dispatch() end'), "NUPP2112")
end

function M.numericRelaxationsRemainExplicitPerFunctionGrants()
    local codes, result = checked(
        table.concat({'@relax("fp-contract", "fp-transcendentals")', "local function inference() end",}, "\n")
    )
    testAssert.equal(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.equal(declaration.relaxedGuarantees["fp-contract"], true)
    testAssert.equal(declaration.relaxedGuarantees["fp-transcendentals"], true)
end

function M.constMarksBodylessDeclarationBindings()
    local source = table.concat({"const service: function(): integer", "return {service = service}",}, "\n")
    local result = parser.parse(source, "service.d.nupp")
    testAssert.equal(#result.errors, 0, "syntax")
    local diags = check.check(result, "service.d.nupp", envMod.new(HERE .. "/.."))
    testAssert.equal(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1]
    testAssert.equal(declaration.isConst, true)
    testAssert.equal(declaration.names[1].definition.constant, true)
end

function M.stableIsNoLongerABuiltInAnnotation()
    testAssert.equal(checked("@stable\nlocal service = 1"), "NUPP2111")
end

function M.effectContractsAttachToDeclarationBindings()
    local source = table.concat(
        {'@effects(raises = true)', "const fail: function(message: string): never", "return {fail = fail}",},
        "\n"
    )
    local result = parser.parse(source, "failure.d.nupp")
    testAssert.equal(#result.errors, 0, "syntax")
    local diags = check.check(result, "failure.d.nupp", envMod.new(HERE .. "/.."))
    testAssert.equal(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.equal(declaration.names[1].definition.effectContract.raises, true)
    testAssert.equal(declaration.names[1].definition.constant, true)
end

function M.constDeclarationBindingsCannotBeReassigned()
    local codes = checked(table.concat({"ipairs = function(values)", "    return next, values, nil", "end",}, "\n"))
    assert(codes:find("NUPP2008", 1, true), codes)
end

function M.unknownAnnotationsAreErrors()
    testAssert.equal(diagsOf("@inline local function f() end"), "NUPP2111")
end

function M.newAnnotationsCanBeDefined()
    local registry = annotations.new()
    local definition, err = registry:define({name = "inline", arguments = "none", targets = {"function"},})
    assert(definition, err)
    testAssert.equal(diagsOf("@inline local function f() end", registry), "")
end

function M.projectEnvironmentsOwnAnExtensibleRegistry()
    local projectEnv = envMod.new(HERE .. "/..")
    assert(projectEnv.annotations:define({name = "profile", arguments = "none", targets = {"function"},}))
    local result = parser.parse("@profile local function f() end", "test")
    testAssert.equal(#result.errors, 0, "syntax")
    testAssert.equal(#check.check(result, "test.g.nupp", projectEnv), 0)
end

function M.customAnnotationsCanLimitTheirTargets()
    local registry = annotations.new()
    assert(registry:define({name = "entity", arguments = "none", targets = {"record"},}))
    testAssert.equal(diagsOf("@entity local record E end", registry), "")
    testAssert.equal(diagsOf("@entity local function f() end", registry), "NUPP2112")

    local assignment = assert(registry:define({name = "tracked", arguments = "none", targets = {"assignment"},}))
    assert(registry:accepts(assignment, {kind = "compoundAssign"}), "compound assignment is an assignment target")
end

function M.definitionTargetsAreValidated()
    local registry = annotations.new()
    local definition, err = registry:define({name = "bad", arguments = "none", targets = {"expression"},})
    testAssert.equal(definition, nil)
    assert(err:find("expression annotations must be compiler-registered", 1, true), err)
end

function M.reservedAnnotationsAreNotSilentlyErased()
    testAssert.equal(diagsOf("@jit local function f() end"), "")
    testAssert.equal(diagsOf("@comptime const function f() end"), "")
    testAssert.equal(diagsOf("@comptime const function f() end"), "")
end

function M.attachmentTargetsAreChecked()
    testAssert.equal(diagsOf("@jit local x = 1"), "NUPP2112")
    -- Named functions are a valid attachment target because exported helpers use
    -- `function M.f()`. A bare global is rejected by the comptime declaration rule.
    testAssert.equal(diagsOf("@comptime function f() end"), "NUPP2411")
end

function M.argumentContractsAreChecked()
    testAssert.equal(diagsOf("@jit(on) local function f() end"), "NUPP2112")
    -- a name that is neither a lint nor a code names no lint to allow
    testAssert.equal(diagsOf("@allow(not_a_lint) local x = 1"), "NUPP2108")
end

function M.deprecatedMetadataIsTypedAndTargeted()
    testAssert.equal(
        checked(
            table.concat(
                {
                    '@deprecated(reason = "compatibility", replacement = "current")',
                    "local function legacy(): integer return 1 end",
                    "return legacy()",
                },
                "\n"
            )
        ),
        "NUPP2513"
    )
    testAssert.equal(checked("@deprecated(reason = 42)\nfunction legacy() end"), "NUPP2115")
    testAssert.equal(checked("@deprecated\ndo end"), "NUPP2112")
end

function M.syntaxAnnotationsAreTypedButDoNotConstrainBindings()
    local codes, result = checked(table.concat({'@syntax("json")', "local document: {integer} = {1}",}, "\n"))
    testAssert.equal(codes, "")
    testAssert.equal(result.root.blocks[1].stats[1].stat.embeddedStringFormat, "json")
    testAssert.equal(checked('@syntax(42)\nlocal value = 1'), "NUPP2115")
    testAssert.equal(checked('@syntax("json")\ndo end'), "NUPP2112")
end

function M.deprecatedUsesReportAcrossApiKinds()
    local codes, _, diagnostics = checked(
        table.concat(
            {
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
            },
            "\n"
        )
    )
    testAssert.equal(codes, "NUPP2513 NUPP2513 NUPP2513 NUPP2513")
    testAssert.equal(diagnostics[1].help, "use Box instead")
    testAssert.equal(diagnostics[3].help, "use current instead")
    assert(diagnostics[2].msg:find("old field", 1, true), diagnostics[2].msg)
end

function M.deprecatedLintCanBeAllowed()
    testAssert.equal(
        checked(
            table.concat(
                {
                    "@deprecated local type Old = string",
                    '@allow("deprecated")',
                    "do",
                    '    local value: Old = "ok"',
                    "    print(value)",
                    "end",
                },
                "\n"
            )
        ),
        ""
    )
end

function M.deprecatedAnnotationsEmitNoRuntimeBehavior()
    local codes, result = checked(
        table.concat(
            {
                '@deprecated(reason = "compatibility", replacement = "current")',
                "local function legacy(): integer return 1 end",
                "return legacy()",
            },
            "\n"
        )
    )
    testAssert.equal(codes, "NUPP2513")
    local lua, errors = gen.generate(result, "test")
    testAssert.equal(#errors, 0, "generation diagnostics")
    assert(not lua:find("deprecated", 1, true), lua)
    assert(not lua:find("compatibility", 1, true), lua)
end

function M.stackedAnnotationsUseTheUnderlyingStatementAsTheirTarget()
    testAssert.equal(diagsOf("@allow @jit local function f() end"), "")
end

function M.jitChecksSemanticCFunctionBoundaries()
    local callback = table.concat(
        {
            "local type Visitor = function(int32)",
            "cdef function each(fn: Visitor, n: int32)",
            "local function visit(value: int32) print(value) end",
            "local function run() each(visit, 1) end",
            "return run",
        },
        "\n"
    )
    testAssert.equal(diagsOf(callback), "NUPP2502")

    local allowedCallback = callback:gsub("local function run%(%)", '@allow("jit-callback")\nlocal function run()')
    testAssert.equal(diagsOf(allowedCallback), "")

    local disabled = table.concat(
        {
            "cdef function each(fn: function(int32), n: int32)",
            "local function visit(value: int32) print(value) end",
            "jit.off(visit)",
            "local function run() each(visit, 1) end",
            "return run",
        },
        "\n"
    )
    testAssert.equal(diagsOf(disabled), "")

    local coldBoundary = table.concat(
        {
            "cdef function each(fn: function(int32), n: int32)",
            "local function visit(value: int32) print(value) end",
            "local function run() each(visit, 1) end",
            "jit.off(run)",
            "return run",
        },
        "\n"
    )
    testAssert.equal(diagsOf(coldBoundary), "")

    local variadic = table.concat(
        {
            "cdef function printf(format: cstring, ...): int32",
            "local function run() printf('%d', 1) end",
            "return run",
        },
        "\n"
    )
    testAssert.equal(diagsOf(variadic), "NUPP2514")

    local required = table.concat(
        {
            "cdef function printf(format: cstring, ...): int32",
            "@jit",
            "local function run() printf('%d', 1) end",
            "return run",
        },
        "\n"
    )
    testAssert.equal(diagsOf(required), "NUPP2707")

    local requiredAllowed = required:gsub("@jit", '@allow("jit-boundary")\n@jit')
    testAssert.equal(diagsOf(requiredAllowed), "NUPP2707")
end

function M.annotationRecordsDefineTypedMetadata()
    local src = table.concat(
        {
            '@annotation(targets = {"record", "struct"})',
            "local record serializable",
            "    format: string",
            "    version: integer?",
            "end",
            '@serializable(format = "json")',
            "local record User",
            "    id: uint64",
            "end",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.equal(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assert(definition, "annotation definition is recorded")
    testAssert.equal(definition.members.format.type.tag, "string")
    testAssert.equal(definition.members.version.optional, true)
end

function M.annotationMembersAreChecked()
    local prefix = table.concat(
        {'@annotation(targets = {"record"})', "local record serializable", "    format: string", "end",},
        "\n"
    ) .. "\n"
    testAssert.equal(checked(prefix .. "@serializable\nlocal record Missing end"), "NUPP2115")
    testAssert.equal(checked(prefix .. "@serializable(format = 42)\nlocal record Wrong end"), "NUPP2115")
    testAssert.equal(checked(prefix .. '@serializable(other = "json")\nlocal record Unknown end'), "NUPP2115 NUPP2115")
end

function M.annotationTargetsIncludeFields()
    local src = table.concat(
        {
            '@annotation(targets = {"field"})',
            "local record range",
            "    min: number",
            "    max: number",
            "end",
            "local record Config",
            "    @range(min = 1, max = 65535)",
            "    port: integer",
            "end",
        },
        "\n"
    )
    testAssert.equal(checked(src), "")
    testAssert.equal(checked(src .. "\n@range(min = 1, max = 2)\nlocal record Bad end"), "NUPP2112")
end

function M.annotationValueDesignatesThePositionalMember()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationValue",
            "    text: string",
            "end",
            '@documentation("A user")',
            "local record User end",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.equal(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    testAssert.equal(definition.singleValue, "text")
end

function M.onlyOneAnnotationValueIsAllowed()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record bad",
            "    @annotationValue",
            "    first: string",
            "    @annotationValue",
            "    second: string",
            "end",
        },
        "\n"
    )
    testAssert.equal(checked(src), "NUPP2114")
    testAssert.equal(checked("local record Plain\n@annotationValue\nx: string\nend"), "NUPP2114")
end

function M.annotationValuesAreCompileTimeConstants()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationValue",
            "    text: string",
            "end",
            "local runtime = 'no'",
            "@documentation(runtime)",
            "local record User end",
        },
        "\n"
    )
    testAssert.equal(checked(src), "NUPP2115")
end

function M.annotationReferencesResolveTypes()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record relatesTo",
            "    @annotationValue",
            "    @ref",
            "    target: any",
            "end",
            "local record User end",
            "@relatesTo(User)",
            "local record Post end",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.equal(codes, "")

    local users = {}
    for _, token in ipairs(result.tokens) do
        if token.text == "User" then
            users[#users + 1] = token
        end
    end
    testAssert.equal(#users, 2, "User tokens")
    assert(users[1].definition, "type declaration has a definition")
    assert(users[2].definition == users[1].definition, "@ref value links to the type declaration")
    testAssert.equal(users[2].semanticKind, "type", "@ref semantic kind")
end

function M.annotationReferencesMustNameCompatibleTypes()
    local prefix = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record relatesTo",
            "    @annotationValue",
            "    @ref",
            "    target: number",
            "end",
        },
        "\n"
    ) .. "\n"
    testAssert.equal(checked(prefix .. "@relatesTo(Missing)\nlocal record Bad end"), "NUPP2115")
    testAssert.equal(checked(prefix .. "@relatesTo(42)\nlocal record Bad end"), "NUPP2115")
    testAssert.equal(checked(prefix .. "local record User end\n@relatesTo(User)\nlocal record Bad end"), "NUPP2115")
end

function M.refIsRestrictedToAnnotationDefinitionMembers()
    testAssert.equal(checked("local record Plain\n    @ref\n    target: any\nend"), "NUPP2114")
end

function M.formatterPrefersTheSingleValueSpelling()
    local src = table.concat(
        {
            '@annotation(targets={"record"})',
            "local record documentation",
            "@annotationValue",
            "text:string",
            "end",
            '@documentation(text = "A user")',
            "local record User end",
        },
        "\n"
    )
    local formatted, errors = fmt.format(src, "test")
    testAssert.equal(#errors, 0, "format diagnostics")
    assert(formatted:find('@documentation("A user")', 1, true), formatted)
    assert(not formatted:find("@documentation(text", 1, true), formatted)
    testAssert.equal(fmt.format(formatted, "test"), formatted, "format idempotency")
end

function M.annotationDefinitionsAndApplicationsErase()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationValue",
            "    text: string",
            "end",
            '@documentation("A user")',
            "local record User end",
            "return User",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.equal(codes, "")
    local lua, errors = gen.generate(result, "test")
    testAssert.equal(#errors, 0, "generation diagnostics")
    assert(not lua:find("documentation", 1, true), lua)
    assert(lua:find("local User = {}", 1, true), lua)
end

function M.annotationStructsDoNotPublishRuntimeConstructors()
    local codes, result = checked(
        table.concat(
            {
                '@annotation(targets = {"record"})',
                "local struct tag",
                "    value: string",
                "end",
                '@tag(value = "entity")',
                "local record Entity end",
            },
            "\n"
        )
    )
    testAssert.equal(codes, "")
    testAssert.equal(result.moduleExports.values.tag, nil)
end

function M.annotationDefinitionsReplaceTheirPreviousFileRevision()
    local projectEnv = envMod.new(HERE .. "/..")
    local filename = "changing.nupp"
    local first = parser.parse(
        table.concat(
            {
                '@annotation(targets = {"record"})',
                "local record label",
                "    value: string",
                "end",
                '@label(value = "first")',
                "local record First end",
            },
            "\n"
        ),
        filename
    )
    testAssert.equal(#check.check(first, filename, projectEnv), 0, "first revision")

    local second = parser.parse(
        table.concat(
            {
                '@annotation(targets = {"record"})',
                "local record label",
                "    value: integer",
                "end",
                "@label(value = 2)",
                "local record Second end",
            },
            "\n"
        ),
        filename
    )
    testAssert.equal(#check.check(second, filename, projectEnv), 0, "second revision")
end

local POINTERS = [[
local p: int32* = nil as any
local q: int32* = nil as any
]]

function M.unsafeExpressionBoundaries()
    for _, expression in ipairs({
        "@unsafe p[0]",
        "@unsafe(p[0])",
        "@unsafe (p[0] + q[0])",
        "@unsafe -p[0]",
        "@unsafe p[0] as number",
        "@unsafe print(p[0])",
        "@unsafe do yield p[0] end",
        '@unsafe switch p[0] do case 1 where q[0] > 0 -> q[0] else -> p[0] end',
        "@unsafe @unsafe p[0]",
    }) do
        testAssert.equal(checked(POINTERS .. "local value = " .. expression), "", expression)
    end
    for _, expression in ipairs({"@unsafe p[0] + q[0]", "(@unsafe p)[0]", "@unsafe -p[0] ^ q[0]",}) do
        testAssert.equal(checked(POINTERS .. "local value = " .. expression), "NUPP2604", expression)
    end
    local parsed = parser.parse("local v = @unsafe -p[0] as number + q[0]")
    testAssert.equal(#parsed.errors, 0)
    local sum = parsed.root.blocks[1].stats[1].exprs[1]
    testAssert.equal(sum.kind, "binop")
    assert(sum.lhs.expressionAnnotations)
    assert(not sum.rhs.expressionAnnotations)
    testAssert.equal(sum.lhs.kind, "castExpr")
    testAssert.equal(sum.lhs.expr.kind, "unop")
    local power = parser.parse("local v = @unsafe -p[0] ^ q[0]").root.blocks[1].stats[1].exprs[1]
    testAssert.equal(power.kind, "unop")
    testAssert.equal(power.operand.kind, "binop")
    testAssert.equal(power.expressionPermissionOperand, power.operand.lhs)
end

function M.expressionAnnotationsPreserveSemanticTokenKinds()
    local parsed = parser.parse("local unsafe = 1; local value = @unsafe new Box(value = unsafe)")
    testAssert.equal(#parsed.errors, 0)
    local kinds = require("nupp.tools.lsp.semantic").syntaxKinds(parsed)
    local decorators, keywords = 0, 0
    for _, token in ipairs(parsed.tokens) do
        if token.text == "unsafe" and kinds[token] == "decorator" then
            decorators = decorators + 1
        elseif token.text == "unsafe" then
            assert(kinds[token] ~= "nuppKeyword", "ordinary identifiers stay identifiers")
        elseif token.text == "new" then
            testAssert.equal(kinds[token], "nuppKeyword")
            keywords = keywords + 1
        end
    end
    testAssert.equal(decorators, 1)
    testAssert.equal(keywords, 1)
end

function M.unsafeStatementTargetsAndSiblingBoundaries()
    for _, statement in ipairs({
        "do local a = p[0] end",
        "if p[0] > 0 then p[0] = q[0] elseif q[0] > 0 then q[0] = p[0] else p[0] = 0 end",
        "for i = p[0], q[0], p[1] do p[i] = q[i] end",
        "for i in iterator(p[0]) do p[i] = q[i] end",
        "while p[0] > 0 do p[0] = q[0] end",
        "repeat p[0] = q[0] until p[0] == q[0]",
        "local a = p[0]",
        "const a = p[0]",
        "p[q[0]] = q[p[0]]",
        "p[0] += q[0]",
        "print(p[0], q[0])",
    }) do
        testAssert.equal(checked(POINTERS .. "@unsafe " .. statement), "", statement)
        testAssert.equal(
            checked(POINTERS .. "@unsafe " .. statement .. "\nlocal outside = q[0]"),
            "NUPP2604",
            "permission ends after " .. statement
        )
    end
    testAssert.equal(checked(POINTERS .. "@unsafe local a = p[0]\nlocal result: number = a"), "")
    for _, annotations_ in ipairs({'@allow("unused-binding") @unsafe', '@unsafe @allow("unused-binding")'}) do
        testAssert.equal(checked(POINTERS .. annotations_ .. " local a = p[0]"), "")
    end
end

function M.unsafePermissionStopsAtEveryFunctionBody()
    for _, statement in ipairs({
        "local function later() return p[0] end",
        "local later = function() return p[0] end",
        "local later = || -> p[0]",
        "local value = (function() return p[0] end)()",
        "local value = (|| -> p[0])()",
    }) do
        testAssert.equal(checked(POINTERS .. "@unsafe do " .. statement .. " end"), "NUPP2604", statement)
        testAssert.equal(
            checked(
                POINTERS
                .. "@unsafe do "
                .. statement:gsub("return p", "return @unsafe p"):gsub("-> p", "-> @unsafe p")
                .. " end"
            ),
            "",
            statement
        )
    end
    testAssert.equal(
        checked(
            POINTERS
            .. [[
@unsafe do
    local function later() return @unsafe p[0] end
    local inside = q[0]
end
local outside = p[0]
]]
        ),
        "NUPP2604"
    )
end

function M.unsafeRejectsUnsupportedTargetsAndCannotBeRedefined()
    for _, source in ipairs({
        "@unsafe local function f() end",
        "@unsafe function f() end",
        "@unsafe local type T = number",
        "@unsafe local record R end",
        "@unsafe cdef function f()",
        "local record R @unsafe x: number end",
        "local f = @unsafe function() end",
        "local f = @unsafe || -> 1",
        "local f = @unsafe (function() end)",
        "@unsafe return 1",
        "local v = do @unsafe yield 1 end",
    }) do
        local codes_ = checked(source)
        assert(codes_:find("NUPP2112", 1, true), source .. ": " .. codes_)
    end
    for _, source in ipairs({"@!unsafe do end", "@unsafe(enabled = true) do end"}) do
        local parsed = parser.parse(source)
        assert(#parsed.errors > 0, source)
    end
    local registry = annotations.new()
    local defined, problem = registry:define({name = "unsafe", arguments = "none", targets = {"statement"}})
    testAssert.equal(defined, nil)
    assert(problem:find("already defined", 1, true))
    testAssert.equal(checked([[
@annotation(targets = {"statement"})
record unsafe end
]]), "NUPP2114")
    testAssert.equal(checked([[
@annotation(targets = {"statement"})
record marker end
local a = @marker 1
]]), "NUPP2112")
    testAssert.equal(checked("local a = @allow(unused-binding) 1"), "NUPP2112")
end

function M.anonymousChecksKeepUnsafeBuiltinAndImmutable()
    local registry = annotations.new()
    local builtin = registry:get("unsafe")
    for _, source in ipairs({"@unsafe do end", "local value = @unsafe 1", "@unsafe local value = 1"}) do
        local parsed = parser.parse(source)
        testAssert.equal(#parsed.errors, 0, source)
        local diagnostics = check.check(parsed, nil, nil, {annotations = registry, strict = false})
        testAssert.equal(#diagnostics, 0, source)
        testAssert.equal(registry:get("unsafe"), builtin, "anonymous checks preserve the built-in definition")
    end
    local replacement = registry:define({name = "unsafe", arguments = "none", targets = {"statement"}})
    testAssert.equal(replacement, nil, "a user definition still cannot replace unsafe")
end

function M.contextualFunctionTypesStillValidateExpressionAnnotations()
    for _, source in ipairs({
        "local f: function(): integer = @unsafe function() return 1 end",
        "local f: function(): integer = @unsafe || -> 1",
        "local function take(f: function(): integer) end; take(@unsafe function() return 1 end)",
        "local function take(f: function(): integer) end; take(@unsafe || -> 1)",
    }) do
        local codes, _, diagnostics = checked(source)
        testAssert.equal(codes, "NUPP2112", source)
        testAssert.equal(diagnostics[1].col, assert(source:find("@unsafe", 1, true)) + 1)
    end
end

function M.unsafePreservesOtherRegionRestrictionsAndExits()
    testAssert.equal(checked('@nosuspend do @unsafe coroutine.yield() end'), 'NUPP2701')
    testAssert.equal(checked('@noalloc do @unsafe local value = {} end'), 'NUPP2710')
    testAssert.equal(checked("@noraise do @unsafe error('failed') end"), 'NUPP2711')
    for _, body in ipairs({
        '@unsafe do return 1 end',
        '@unsafe if true then return 1 else return 2 end',
        '@unsafe while true do end',
        '@unsafe repeat until false',
    }) do
        testAssert.equal(checked('local function f(): integer ' .. body .. ' end'), '', body)
    end
end

function M.unsafeCannotBypassAotOrComptimeAdmission()
    for _, body in ipairs({"@unsafe do end", "return @unsafe 1", "@unsafe local value = 1"}) do
        local codes_ = checked("@aot local function f(): number " .. body .. " end")
        assert(codes_:find("NUPP2903", 1, true), codes_)
    end
    local codes_ = checked("local x = comptime do return @unsafe ffi.new('int[1]') end")
    assert(codes_:find("NUPP2410", 1, true), codes_)
end

function M.unsafePreservesValuesOrderLazinessAndResultCounts()
    local source = [[
local log = {}
local function one(n: integer): integer
    log[#log + 1] = n
    return n
end
local function pair(): integer, integer
    return one(4), one(5)
end
local exponent = @unsafe -2 ^ 2
assert(exponent == -4)
local casted = @unsafe -2 as number
assert(casted == -2)
local a, b = @unsafe pair()
local values = {@unsafe pair()}
local chosen = @unsafe switch one(1) do
    case 1 -> do yield one(2) end
    else -> one(99)
end
local lazy = false and @unsafe one(98)
local other = true or @unsafe one(97)
local absent: any = nil
local skipped = @unsafe absent?.(one(96))
assert(skipped == nil)
local present: any = one
local called = @unsafe present?.(6)
assert(called == 6)
local target: {integer} = {}
local function destination(): {integer}
    one(7)
    return target
end
@unsafe destination()[one(8)] = one(9)
assert(target[8] == 9)
local function join(a: integer, b: integer): integer
    return a * 10 + b
end
assert(join(@unsafe pair()) == 45)
local function forward(): integer, integer
    return @unsafe pair()
end
local c, d = forward()
return a, b, values[1], values[2], chosen, c, d, table.concat(log, ',')
]]
    local codes_, result = checked(source)
    testAssert.equal(codes_, "")
    local expected = "4|5|4|5|2|4|5|4,5,4,5,1,2,6,7,8,9,4,5,4,5"
    for _, level in ipairs({0, 1, 2}) do
        local fresh = parser.parse(source, "test.g.nupp")
        local diagnostics = check.check(fresh, "test.g.nupp", env)
        testAssert.equal(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
        require("nupp.compiler.lua.optimize").run(fresh, {level = level, filename = "test.g.nupp"})
        local output, errors = gen.generate(fresh, "test.g.nupp")
        testAssert.equal(#errors, 0, errors[1] and errors[1].msg)
        assert(not output:find("@unsafe", 1, true), output)
        local chunk = assert(loadstring(output))
        local values = {chunk()}
        testAssert.equal(table.concat(values, "|"), expected, "O" .. level)
    end
    local formatted, diagnostics = fmt.format(source, "test.g.nupp")
    testAssert.equal(#(diagnostics or {}), 0)
    testAssert.equal(checked(formatted), "")
    testAssert.equal(fmt.format(formatted, "test.g.nupp"), formatted, "formatting idempotence")
end

return M
