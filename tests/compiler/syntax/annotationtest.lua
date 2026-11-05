local testAssert = require("assert")
-- Statement annotations are an extensible, checked language surface. The
-- parser accepts their general shape; the registry decides what exists.
local parser = require("nupp.compiler.syntax.parser")
local check = require("helpers.fragment")
local envMod = require("nupp.compiler.project.env")
local annotations = require("nupp.compiler.annotations")
local fmt = require("nupp.tools.fmt")
local program = require("program")

local HERE = require("helpers.paths").tests
local env = envMod.new(HERE .. "/..")

local function diagsOf(src, registry)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax")
    local out = {}
    for j, d in ipairs(check.check(result, "test.nupp", env, {annotations = registry})) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local checked
local M = {}

function M.policyAnnotationsComposeAcrossTypesDeclarationsMembersAndRegions()
    local source = [[
local sealed interface Resource is own.Affine<self.close>
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
    testAssert.eq(checked(source), "")
    testAssert.eq(checked("local f: @comptime @nosuspend @sendable function(): nil"), "")
    testAssert.eq(checked("local f: @nosuspend ((function(): nil) | integer)"), "NUPP2112")
    testAssert.eq(checked("local f: @nosuspend @nosuspend function(): nil"), "NUPP2112")
end

function M.typeQualifiersPreserveBorrowedFunctionResults()
    testAssert.eq(checked("local value: @nosuspend function<V>(borrows owner: V): V borrows (owner)"), "")
    testAssert.eq(checked("local value: @sendable function<V>(borrows owner: V): V borrows (owner)"), "")
end

function M.namedCoroutineFunctionTypeWorksOnBodylessCallableField()
    testAssert.eq(
        checked(
            [[
local type Feed = thread<(number), (boolean), (number), (string)>
local type Producer = function(number) yields(number) resumes(boolean): string
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
    testAssert.eq(checked("@coroutine(Feed)\nlocal function worker(): nil end"), "NUPP2111")
end

function M.builtinCliCannotBeReplacedByTheFormerBootstrapPath()
    for _, source in ipairs({
        "src/nupp/tools/cli/annotation.nupp",
        "/checkout/src/nupp/tools/cli/annotation.nupp",
        "C:\\checkout\\src\\nupp\\compiler\\cli\\annotation.nupp",
    }) do
        local registry = annotations.new()
        local builtin = registry:get("cli")
        local defined, problem = registry:define({
            name = "cli",
            source = source,
            arguments = "typed",
            targets = {"record", "field"}
        })
        testAssert.eq(defined, nil, "a source file cannot replace builtin cli")
        assert(problem and problem:find("already defined", 1, true), problem)
        testAssert.eq(registry:get("cli"), builtin, "the builtin remains registered")
    end
end

checked = function(src)
    local result = parser.parse(src, "test.nupp")
    testAssert.eq(#result.errors, 0, "syntax")
    -- The environment this file already shares, rather than another one built
    -- exactly like it: building one means checking the prelude from source.
    local diags = check.check(result, "test.nupp", env)
    local codes = {}
    for j, diagnostic in ipairs(diags) do
        codes[j] = diagnostic.code
    end

    return table.concat(codes, " "), result, diags
end

function M.sealedInterfacesRequireDeclaredConformance()
    testAssert.eq(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    @readonly value: integer",
                    "end",
                    "local record Genuine is Token",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = Genuine(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        ""
    )

    testAssert.eq(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    @readonly value: integer",
                    "end",
                    "local record Shaped",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = Shaped(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )

    testAssert.eq(
        checked(
            table.concat(
                {
                    "local record Shaped",
                    "    @readonly value: integer",
                    "end",
                    "local token: Token = Shaped(value = 1)",
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
    testAssert.eq(checked("@sealed\nlocal interface Token end"), "NUPP2111")
end

function M.ownershipAnnotationTwinsAreRemoved()
    testAssert.eq(checked("@affine\nlocal interface Owner end"), "NUPP2111")
    testAssert.eq(checked("local record Owner\n@terminal close: function(takes self: Owner): nil\nend"), "NUPP2111")
end

function M.partitionContractsRequireASealedInterfaceAndRealFields()
    testAssert.eq(
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

    testAssert.eq(
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
    testAssert.eq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.eq(declaration.effectContract.reads[1], "value")
    testAssert.eq(declaration.body.effectSummary.returns["1=value"], true)
end

function M.effectContractsCannotHideBodyEffects()
    testAssert.eq(
        checked(
            table.concat({"@effects()", "local function mutate(values: {integer})", "    values[1] = 2", "end",}, "\n")
        ),
        "NUPP2112"
    )
    testAssert.eq(
        checked(
            table.concat(
                {"@effects()", "local function opaque(value: table, callback: any)", "    callback(value)", "end",},
                "\n"
            )
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
    testAssert.eq(codes, "")
    local wrapped = result.root.blocks[1].stats[2].stat
    testAssert.eq(wrapped.body.effectSummary.returns["1=value"], true)
end

function M.effectMembersHaveClosedShapes()
    testAssert.eq(checked("@effects(reads = true)\nlocal function f() end"), "NUPP2112")
    testAssert.eq(checked("@effects(allocates = {})\nlocal function f() end"), "NUPP2112")
    testAssert.eq(checked("@effects(mystery = true)\nlocal function f() end"), "NUPP2112")
    -- `yields` is no member: suspension is spelled `suspends`, and the old name is as
    -- unknown as any other.
    local codes, _, diags = checked("@effects(yields = false)\nlocal function f() end")
    testAssert.eq(codes, "NUPP2112")
    testAssert.eq(#(diags[1].fixes or {}), 0, "the retired spelling is not special-cased")
end

function M.relaxationsUseAClosedSetOfObservableGuarantees()
    local codes, result = checked(
        table.concat({'@relax("frames", "error-site")', "local function dispatch() end",}, "\n")
    )
    testAssert.eq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.eq(declaration.relaxedGuarantees.frames, true)
    testAssert.eq(declaration.relaxedGuarantees["error-site"], true)
    testAssert.eq(checked('@relax("magic")\nlocal function dispatch() end'), "NUPP2112")
end

function M.numericRelaxationsRemainExplicitPerFunctionGrants()
    local codes, result = checked(
        table.concat({'@relax("fp-contract", "fp-transcendentals")', "local function inference() end",}, "\n")
    )
    testAssert.eq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.eq(declaration.relaxedGuarantees["fp-contract"], true)
    testAssert.eq(declaration.relaxedGuarantees["fp-transcendentals"], true)
end

function M.constMarksBodylessDeclarationBindings()
    local source = table.concat({"const service: function(): integer", "return {service = service}",}, "\n")
    local result = parser.parse(source, "service.d.nupp")
    testAssert.eq(#result.errors, 0, "syntax")
    local diags = check.check(result, "service.d.nupp", envMod.new(HERE .. "/.."))
    testAssert.eq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1]
    testAssert.eq(declaration.isConst, true)
    testAssert.eq(declaration.names[1].definition.constant, true)
end

function M.stableIsNoLongerABuiltInAnnotation()
    testAssert.eq(checked("@stable\nlocal service = 1"), "NUPP2111")
end

function M.effectContractsAttachToDeclarationBindings()
    local source = table.concat(
        {'@effects(raises = true)', "const fail: function(message: string): never", "return {fail = fail}",},
        "\n"
    )
    local result = parser.parse(source, "failure.d.nupp")
    testAssert.eq(#result.errors, 0, "syntax")
    local diags = check.check(result, "failure.d.nupp", envMod.new(HERE .. "/.."))
    testAssert.eq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1].stat
    testAssert.eq(declaration.names[1].definition.effectContract.raises, true)
    testAssert.eq(declaration.names[1].definition.constant, true)
end

function M.constDeclarationBindingsCannotBeReassigned()
    local codes = checked(table.concat({"ipairs = function(values)", "    return next, values, nil", "end",}, "\n"))
    assert(codes:find("NUPP2008", 1, true), codes)
end

function M.unknownAnnotationsAreErrors()
    testAssert.eq(diagsOf("@inline local function f() end"), "NUPP2111")
end

function M.newAnnotationsCanBeDefined()
    local registry = annotations.new()
    local definition, err = registry:define({name = "inline", arguments = "none", targets = {"function"},})
    assert(definition, err)
    testAssert.eq(diagsOf("@inline local function f() end", registry), "")
end

function M.fileDirectivesDoNotReserveUserAnnotationNames()
    testAssert.eq(
        diagsOf(
            table.concat(
                {
                    '@annotation(targets = {"record"})',
                    'record internal end',
                    '@annotation(targets = {"record"})',
                    'record nofmt end',
                    '@internal @nofmt local record Item end',
                },
                "\n"
            )
        ),
        ""
    )
end

function M.projectEnvironmentsOwnAnExtensibleRegistry()
    local projectEnv = envMod.new(HERE .. "/..")
    assert(projectEnv.annotations:define({name = "profile", arguments = "none", targets = {"function"},}))
    local result = parser.parse("@profile local function f() end", "test")
    testAssert.eq(#result.errors, 0, "syntax")
    testAssert.eq(#check.check(result, "test.nupp", projectEnv), 0)
end

function M.customAnnotationsCanLimitTheirTargets()
    local registry = annotations.new()
    assert(registry:define({name = "entity", arguments = "none", targets = {"record"},}))
    testAssert.eq(diagsOf("@entity local record E end", registry), "")
    testAssert.eq(diagsOf("@entity local function f() end", registry), "NUPP2112")

    local assignment = assert(registry:define({name = "tracked", arguments = "none", targets = {"assignment"},}))
    assert(registry:accepts(assignment, {kind = "compoundAssign"}), "compound assignment is an assignment target")
end

function M.definitionTargetsAreValidated()
    local registry = annotations.new()
    local definition, err = registry:define({name = "bad", arguments = "none", targets = {"expression"},})
    testAssert.eq(definition, nil)
    assert(err:find("expression annotations must be compiler-registered", 1, true), err)
end

function M.reservedAnnotationsAreNotSilentlyErased()
    testAssert.eq(diagsOf("@comptime const function f() end"), "")
    testAssert.eq(diagsOf("@comptime const function f() end"), "")
end

function M.attachmentTargetsAreChecked()
    testAssert.eq(diagsOf("@aot local x = 1"), "NUPP2112")
    -- Named functions are a valid attachment target because exported helpers use
    -- `function M.f()`. A bare global is rejected by the comptime declaration rule.
    testAssert.eq(diagsOf("@comptime function f() end"), "NUPP2411")
end

function M.argumentContractsAreChecked()
    testAssert.eq(diagsOf("@noraise(on) do end"), "NUPP2112")
    -- a name that is neither a lint nor a code names no lint to allow
    testAssert.eq(diagsOf("@allow(not_a_lint) local x = 1"), "NUPP2108")
end

function M.deprecatedMetadataIsTypedAndTargeted()
    testAssert.eq(
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
    testAssert.eq(checked("@deprecated(reason = 42)\nfunction legacy() end"), "NUPP2115")
    testAssert.eq(checked("@deprecated\ndo end"), "NUPP2112")
end

function M.syntaxAnnotationsAreTypedButDoNotConstrainBindings()
    local codes, result = checked(table.concat({'@syntax("json")', "local document: {integer} = {1}",}, "\n"))
    testAssert.eq(codes, "")
    testAssert.eq(result.root.blocks[1].stats[1].stat.embeddedStringFormat, "json")
    testAssert.eq(checked('@syntax(42)\nlocal value = 1'), "NUPP2115")
    testAssert.eq(checked('@syntax("json")\ndo end'), "NUPP2112")
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
                "local value: OldBox = Box(old = legacy(), current = current())",
                "return value.old",
            },
            "\n"
        )
    )
    testAssert.eq(codes, "NUPP2513 NUPP2513 NUPP2513 NUPP2513")
    testAssert.eq(diagnostics[1].help, "use Box instead")
    testAssert.eq(diagnostics[3].help, "use current instead")
    assert(diagnostics[2].msg:find("old field", 1, true), diagnostics[2].msg)
end

function M.deprecatedLintCanBeAllowed()
    testAssert.eq(
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
    testAssert.eq(codes, "NUPP2513")
    local image = program.image(result, "test")
    assert(not image:find("deprecated", 1, true), image)
    assert(not image:find("compatibility", 1, true), image)
end

function M.stackedAnnotationsUseTheUnderlyingStatementAsTheirTarget()
    testAssert.eq(diagsOf("@allow @aot local function f() end"), "")
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
    testAssert.eq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assert(definition, "annotation definition is recorded")
    testAssert.eq(definition.members.format.type.tag, "string")
    testAssert.eq(definition.members.version.optional, true)
end

function M.annotationMembersAreChecked()
    local prefix = table.concat(
        {'@annotation(targets = {"record"})', "local record serializable", "    format: string", "end",},
        "\n"
    ) .. "\n"
    testAssert.eq(checked(prefix .. "@serializable\nlocal record Missing end"), "NUPP2115")
    testAssert.eq(checked(prefix .. "@serializable(format = 42)\nlocal record Wrong end"), "NUPP2115")
    testAssert.eq(checked(prefix .. '@serializable(other = "json")\nlocal record Unknown end'), "NUPP2115 NUPP2115")
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
    testAssert.eq(checked(src), "")
    testAssert.eq(checked(src .. "\n@range(min = 1, max = 2)\nlocal record Bad end"), "NUPP2112")
end

function M.annotationValueDesignatesThePositionalMember()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationvalue",
            "    text: string",
            "end",
            '@documentation("A user")',
            "local record User end",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.eq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    testAssert.eq(definition.singleValue, "text")
end

function M.lowercaseAnnotationValueUsesTheExistingDefinition()
    local registry = annotations.new()
    testAssert.eq(registry:get("annotationvalue"), registry.byname.annotationvalue)
    assert(registry:get("annotationvalue"))
    testAssert.eq(registry:get("annotationValue"), nil)
    testAssert.eq(registry.byname.annotationValue, nil, "the preceding builtin is retired")
    local replacement = registry:define({name = "annotationvalue", arguments = "none", targets = {"field"}})
    testAssert.eq(replacement, nil, "the accepted key cannot replace the builtin")
    local prefix = [[
@annotation(targets = {"record"})
local record documentation
    @annotationvalue
    text: string
end
]]
    local codes, result = checked(prefix .. '@documentation("A user")\nlocal record User end')
    testAssert.eq(codes, "")
    testAssert.eq(result.root.blocks[1].stats[1].stat.annotationDefinition.singleValue, "text")
    testAssert.eq(checked(prefix .. '@documentation(42)\nlocal record User end'), "NUPP2115")
    testAssert.eq(checked("local record Plain\n@annotationvalue\nx: string\nend"), "NUPP2114")
    testAssert.eq(
        checked(
            [[
@annotation(targets = {"record"})
local record documentation
    @annotationvalue
    first: string
    @annotationvalue
    second: string
end
]]
        ),
        "NUPP2114"
    )
end

function M.lowercaseCliMembersKeepCanonicalMetadataAndRejectMixedDuplicates()
    local codes, result = checked(
        [[
@cli(preserveunknown = true, stopatfirstargument = true)
local record Options
    @cli(constantaliases = {auto = "auto"}, arity = "optionalattached")
    format: string
    @cli(arity = "attachedonly")
    output: string
end
]]
    )
    testAssert.eq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat

    local function values(target)
        local found = {}
        for _, argument in ipairs(target.semanticAnnotations[1].arguments) do
            found[argument.name] = argument.value
        end

        return found
    end

    local recordValues = values(declaration)
    testAssert.eq(recordValues.preserveunknown, true)
    testAssert.eq(recordValues.stopatfirstargument, true)
    testAssert.eq(recordValues.preserveUnknown, nil)
    testAssert.eq(recordValues.stopAtFirstArgument, nil)
    local fieldValues = values(declaration.entries[1])
    testAssert.eq(fieldValues.constantaliases.auto, "auto")
    testAssert.eq(fieldValues.constantAliases, nil)
    testAssert.eq(fieldValues.arity, "optionalattached", "canonical arity is retained at the parser boundary")
    for _, members in ipairs({
        "preserveunknown = true, preserveUnknown = false",
        "preserveUnknown = true, preserveunknown = false",
        "stopatfirstargument = true, stopAtFirstArgument = false",
        "stopAtFirstArgument = true, stopatfirstargument = false",
        'constantaliases = {a = "a"}, constantAliases = {b = "b"}',
        'constantAliases = {a = "a"}, constantaliases = {b = "b"}',
    }) do
        testAssert.eq(checked("@cli(" .. members .. ")\nlocal record Duplicate end"), "NUPP2115")
    end
    testAssert.eq(
        checked("@cli(preserveunknown = true, preserveunknown = false)\nlocal record Duplicate end"),
        "NUPP2115"
    )
    testAssert.eq(checked('@cli(preserveunknown = "yes")\nlocal record Bad end'), "NUPP2115")
    testAssert.eq(checked('@cli(stopatfirstarg = true)\nlocal record Bad end'), "NUPP2115")
    testAssert.eq(checked('@cli(arity = "optionalattachedextra")\nlocal record Bad end'), "NUPP2115")
end

function M.onlyOneAnnotationValueIsAllowed()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record bad",
            "    @annotationvalue",
            "    first: string",
            "    @annotationvalue",
            "    second: string",
            "end",
        },
        "\n"
    )
    testAssert.eq(checked(src), "NUPP2114")
    testAssert.eq(checked("local record Plain\n@annotationvalue\nx: string\nend"), "NUPP2114")
end

function M.annotationValuesAreCompileTimeConstants()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationvalue",
            "    text: string",
            "end",
            "local runtime = 'no'",
            "@documentation(runtime)",
            "local record User end",
        },
        "\n"
    )
    testAssert.eq(checked(src), "NUPP2115")
end

function M.annotationReferencesResolveTypes()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record relatesTo",
            "    @annotationvalue",
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
    testAssert.eq(codes, "")

    local users = {}
    for _, token in ipairs(result.tokens) do
        if token.text == "User" then
            users[#users + 1] = token
        end
    end
    testAssert.eq(#users, 2, "User tokens")
    assert(users[1].definition, "type declaration has a definition")
    assert(users[2].definition == users[1].definition, "@ref value links to the type declaration")
    testAssert.eq(users[2].semanticKind, "type", "@ref semantic kind")
end

function M.annotationReferencesMustNameCompatibleTypes()
    local prefix = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record relatesTo",
            "    @annotationvalue",
            "    @ref",
            "    target: number",
            "end",
        },
        "\n"
    ) .. "\n"
    testAssert.eq(checked(prefix .. "@relatesTo(Missing)\nlocal record Bad end"), "NUPP2115")
    testAssert.eq(checked(prefix .. "@relatesTo(42)\nlocal record Bad end"), "NUPP2115")
    testAssert.eq(checked(prefix .. "local record User end\n@relatesTo(User)\nlocal record Bad end"), "NUPP2115")
end

function M.refIsRestrictedToAnnotationDefinitionMembers()
    testAssert.eq(checked("local record Plain\n    @ref\n    target: any\nend"), "NUPP2114")
end

function M.formatterPrefersTheSingleValueSpelling()
    local src = table.concat(
        {
            '@annotation(targets={"record"})',
            "local record documentation",
            "@annotationvalue",
            "text:string",
            "end",
            '@documentation(text = "A user")',
            "local record User end",
        },
        "\n"
    )
    local formatted, errors = fmt.format(src, "test")
    testAssert.eq(#errors, 0, "format diagnostics")
    assert(formatted:find('@documentation("A user")', 1, true), formatted)
    assert(not formatted:find("@documentation(text", 1, true), formatted)
    testAssert.eq(fmt.format(formatted, "test"), formatted, "format idempotency")
end

function M.annotationDefinitionsAndApplicationsErase()
    local src = table.concat(
        {
            '@annotation(targets = {"record"})',
            "local record documentation",
            "    @annotationvalue",
            "    text: string",
            "end",
            '@documentation("A user")',
            "local record User end",
            "return User",
        },
        "\n"
    )
    local codes, result = checked(src)
    testAssert.eq(codes, "")
    local image = program.image(result, "test")
    assert(not image:find("documentation", 1, true), image)
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
    testAssert.eq(codes, "")
    testAssert.eq(result.moduleExports.values.tag, nil)
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
    testAssert.eq(#check.check(first, filename, projectEnv), 0, "first revision")

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
    testAssert.eq(#check.check(second, filename, projectEnv), 0, "second revision")
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
        testAssert.eq(checked(POINTERS .. "local value = " .. expression), "", expression)
    end
    for _, expression in ipairs({"@unsafe p[0] + q[0]", "(@unsafe p)[0]", "@unsafe -p[0] ^ q[0]",}) do
        testAssert.eq(checked(POINTERS .. "local value = " .. expression), "NUPP2604", expression)
    end
    local parsed = parser.parse("local v = @unsafe -p[0] as number + q[0]")
    testAssert.eq(#parsed.errors, 0)
    local sum = parsed.root.blocks[1].stats[1].exprs[1]
    testAssert.eq(sum.kind, "binop")
    assert(sum.lhs.expressionAnnotations)
    assert(not sum.rhs.expressionAnnotations)
    testAssert.eq(sum.lhs.kind, "castExpr")
    testAssert.eq(sum.lhs.expr.kind, "unop")
    local power = parser.parse("local v = @unsafe -p[0] ^ q[0]").root.blocks[1].stats[1].exprs[1]
    testAssert.eq(power.kind, "unop")
    testAssert.eq(power.operand.kind, "binop")
    testAssert.eq(power.expressionPermissionOperand, power.operand.lhs)
end

function M.expressionAnnotationsPreserveSemanticTokenKinds()
    local parsed = parser.parse("local unsafe = 1; local new = unsafe; local value = @unsafe Box(value = new)")
    testAssert.eq(#parsed.errors, 0)
    local kinds = require("nupp.tools.lsp.semantic").syntaxKinds(parsed)
    local decorators, identifiers = 0, 0
    for _, token in ipairs(parsed.tokens) do
        if token.text == "unsafe" and kinds[token] == "decorator" then
            decorators = decorators + 1
        elseif token.text == "unsafe" then
            assert(kinds[token] ~= "nuppKeyword", "ordinary identifiers stay identifiers")
        elseif token.text == "new" then
            assert(kinds[token] ~= "nuppKeyword", "new is an ordinary identifier")
            identifiers = identifiers + 1
        end
    end
    testAssert.eq(decorators, 1)
    testAssert.eq(identifiers, 2)
end

function M.unsafeStatementTargetsAndSiblingBoundaries()
    for _, statement in ipairs({
        "do local a = p[0] end",
        "if p[0] > 0 then p[0] = q[0] elseif q[0] > 0 then q[0] = p[0] else p[0] = 0 end",
        "for i = p[0], q[0], p[1] do p[i] = q[i] end",
        "for i in ipairs({p[0]}) do p[i] = q[i] end",
        "while p[0] > 0 do p[0] = q[0] end",
        "repeat p[0] = q[0] until p[0] == q[0]",
        "local a = p[0]",
        "const a = p[0]",
        "p[q[0]] = q[p[0]]",
        "p[0] += q[0]",
        "print(p[0], q[0])",
    }) do
        testAssert.eq(checked(POINTERS .. "@unsafe " .. statement), "", statement)
        testAssert.eq(
            checked(POINTERS .. "@unsafe " .. statement .. "\nlocal outside = q[0]"),
            "NUPP2604",
            "permission ends after " .. statement
        )
    end
    testAssert.eq(checked(POINTERS .. "@unsafe local a = p[0]\nlocal result: number = a"), "")
    for _, annotations_ in ipairs({'@allow("unused-binding") @unsafe', '@unsafe @allow("unused-binding")'}) do
        testAssert.eq(checked(POINTERS .. annotations_ .. " local a = p[0]"), "")
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
        testAssert.eq(checked(POINTERS .. "@unsafe do " .. statement .. " end"), "NUPP2604", statement)
        testAssert.eq(
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
    testAssert.eq(
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
    testAssert.eq(defined, nil)
    assert(problem:find("already defined", 1, true))
    testAssert.eq(checked([[
@annotation(targets = {"statement"})
record unsafe end
]]), "NUPP2114")
    testAssert.eq(checked([[
@annotation(targets = {"statement"})
record marker end
local a = @marker 1
]]), "NUPP2112")
    testAssert.eq(checked("local a = @allow(unused-binding) 1"), "NUPP2112")
end

function M.anonymousChecksKeepUnsafeBuiltinAndImmutable()
    local registry = annotations.new()
    local builtin = registry:get("unsafe")
    for _, source in ipairs({"@unsafe do end", "local value = @unsafe 1", "@unsafe local value = 1"}) do
        local parsed = parser.parse(source)
        testAssert.eq(#parsed.errors, 0, source)
        local diagnostics = check.check(parsed, nil, nil, {annotations = registry, strict = false})
        testAssert.eq(#diagnostics, 0, source)
        testAssert.eq(registry:get("unsafe"), builtin, "anonymous checks preserve the built-in definition")
    end
    local replacement = registry:define({name = "unsafe", arguments = "none", targets = {"statement"}})
    testAssert.eq(replacement, nil, "a user definition still cannot replace unsafe")
end

function M.contextualFunctionTypesStillValidateExpressionAnnotations()
    for _, source in ipairs({
        "local f: function(): integer = @unsafe function() return 1 end",
        "local f: function(): integer = @unsafe || -> 1",
        "local function take(f: function(): integer) end; take(@unsafe function() return 1 end)",
        "local function take(f: function(): integer) end; take(@unsafe || -> 1)",
    }) do
        local codes, _, diagnostics = checked(source)
        testAssert.eq(codes, "NUPP2112", source)
        testAssert.eq(diagnostics[1].col, assert(source:find("@unsafe", 1, true)) + 1)
    end
end

function M.unsafePreservesOtherRegionRestrictionsAndExits()
    testAssert.eq(checked('@nosuspend do @unsafe coroutine.yield() end'), 'NUPP2701')
    testAssert.eq(checked('@noalloc do @unsafe local value = {} end'), 'NUPP2710')
    testAssert.eq(checked("@noraise do @unsafe error('failed') end"), 'NUPP2711')
    for _, body in ipairs({
        '@unsafe do return 1 end',
        '@unsafe if true then return 1 else return 2 end',
        '@unsafe while true do end',
        '@unsafe repeat until false',
    }) do
        testAssert.eq(checked('local function f(): integer ' .. body .. ' end'), '', body)
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
    testAssert.eq(codes_, "")
    local expected = "4|5|4|5|2|4|5|4,5,4,5,1,2,6,7,8,9,4,5,4,5"
    local values = {program.run(result, "test")}
    testAssert.eq(table.concat(values, "|"), expected)
    local formatted, diagnostics = fmt.format(source, "test.nupp")
    testAssert.eq(#(diagnostics or {}), 0)
    testAssert.eq(checked(formatted), "")
    testAssert.eq(fmt.format(formatted, "test.nupp"), formatted, "formatting idempotence")
end

function M.precedingBuiltinAnnotationNamesCanOnlyBeUserDefined()
    testAssert.eq(checked("local record Plain\n@annotationValue\nx: string\nend"), "NUPP2111")
    local registry = annotations.new()
    assert(registry:define({name = "annotationValue", arguments = "none", targets = {"field"}}))
    assert(registry:get("annotationValue"), "user annotation names are not globally reserved")
end

return M
