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
        error(("%s:\n  want: %s\n  got:  %s"):format(label or "mismatch", tostring(want), tostring(got)), 2)
    end
end

local function diagsOf(src, registry)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax")
    local out = {}
    for j, d in ipairs(check.check(result, "test.g.nupp", env, {annotations = registry})) do
        out[j] = d.code
    end

    return table.concat(out, " ")
end

local M = {}

function M.builtinCliCannotBeReplacedByTheFormerBootstrapPath()
    for _, source in ipairs({
        "src/nupp/compiler/cli/annotation.g.nupp",
        "/checkout/src/nupp/compiler/cli/annotation.g.nupp",
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
        assertEq(defined, nil, "a source file cannot replace builtin cli")
        assert(problem and problem:find("already defined", 1, true), problem)
        assertEq(registry:get("cli"), builtin, "the builtin remains registered")
    end
end

local function checked(src)
    local result = parser.parse(src, "test.g.nupp")
    assertEq(#result.errors, 0, "syntax")
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
    assertEq(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    readonly value: integer",
                    "end",
                    "local record Genuine is Token",
                    "    readonly value: integer",
                    "end",
                    "local token: Token = new Genuine(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        ""
    )

    assertEq(
        checked(
            table.concat(
                {
                    "local sealed interface Token",
                    "    readonly value: integer",
                    "end",
                    "local record Shaped",
                    "    readonly value: integer",
                    "end",
                    "local token: Token = new Shaped(value = 1)",
                    "print(token.value)",
                },
                "\n"
            )
        ),
        "NUPP2001"
    )

    assertEq(
        checked(
            table.concat(
                {
                    "local record Shaped",
                    "    readonly value: integer",
                    "end",
                    "local token: Token = new Shaped(value = 1)",
                    "local sealed interface Token",
                    "    readonly value: integer",
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

function M.sealedIsAKeywordNotAnAnnotation()
    local result = parser.parse("@sealed\nlocal interface Token end", "test.g.nupp")
    assert(#result.errors > 0, "@sealed must be rejected as syntax")
end

function M.partitionContractsRequireASealedInterfaceAndRealFields()
    assertEq(
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

    assertEq(
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
    assertEq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.effectContract.reads[1], "value")
    assertEq(declaration.body.effectSummary.returns["1=value"], true)
end

function M.effectContractsCannotHideBodyEffects()
    assertEq(
        checked(
            table.concat({"@effects()", "local function mutate(values: {integer})", "    values[1] = 2", "end",}, "\n")
        ),
        "NUPP2112"
    )
    assertEq(
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
    assertEq(codes, "")
    local wrapped = result.root.blocks[1].stats[2].stat
    assertEq(wrapped.body.effectSummary.returns["1=value"], true)
end

function M.effectMembersHaveClosedShapes()
    assertEq(checked("@effects(reads = true)\nlocal function f() end"), "NUPP2112")
    assertEq(checked("@effects(allocates = {})\nlocal function f() end"), "NUPP2112")
    assertEq(checked("@effects(mystery = true)\nlocal function f() end"), "NUPP2112")
end

function M.relaxationsUseAClosedSetOfObservableGuarantees()
    local codes, result = checked(
        table.concat({'@relax("frames", "error-site")', "local function dispatch() end",}, "\n")
    )
    assertEq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.relaxedGuarantees.frames, true)
    assertEq(declaration.relaxedGuarantees["error-site"], true)
    assertEq(checked('@relax("magic")\nlocal function dispatch() end'), "NUPP2112")
end

function M.numericRelaxationsRemainExplicitPerFunctionGrants()
    local codes, result = checked(
        table.concat({'@relax("fp-contract", "fp-transcendentals")', "local function inference() end",}, "\n")
    )
    assertEq(codes, "")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.relaxedGuarantees["fp-contract"], true)
    assertEq(declaration.relaxedGuarantees["fp-transcendentals"], true)
end

function M.constMarksBodylessDeclarationBindings()
    local source = table.concat({"const service: function(): integer", "return {service = service}",}, "\n")
    local result = parser.parse(source, "service.d.nupp")
    assertEq(#result.errors, 0, "syntax")
    local diags = check.check(result, "service.d.nupp", envMod.new(HERE .. "/.."))
    assertEq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1]
    assertEq(declaration.isConst, true)
    assertEq(declaration.names[1].definition.constant, true)
end

function M.stableIsNoLongerABuiltInAnnotation()
    assertEq(checked("@stable\nlocal service = 1"), "NUPP2111")
end

function M.effectContractsAttachToDeclarationBindings()
    local source = table.concat(
        {'@effects(raises = true)', "const fail: function(message: string): never", "return {fail = fail}",},
        "\n"
    )
    local result = parser.parse(source, "failure.d.nupp")
    assertEq(#result.errors, 0, "syntax")
    local diags = check.check(result, "failure.d.nupp", envMod.new(HERE .. "/.."))
    assertEq(#diags, 0, "diagnostics")
    local declaration = result.root.blocks[1].stats[1].stat
    assertEq(declaration.names[1].definition.effectContract.raises, true)
    assertEq(declaration.names[1].definition.constant, true)
end

function M.constDeclarationBindingsCannotBeReassigned()
    local codes = checked(table.concat({"ipairs = function(values)", "    return next, values, nil", "end",}, "\n"))
    assert(codes:find("NUPP2008", 1, true), codes)
end

function M.unknownAnnotationsAreErrors()
    assertEq(diagsOf("@inline local function f() end"), "NUPP2111")
end

function M.newAnnotationsCanBeDefined()
    local registry = annotations.new()
    local definition, err = registry:define({name = "inline", arguments = "none", targets = {"function"},})
    assert(definition, err)
    assertEq(diagsOf("@inline local function f() end", registry), "")
end

function M.projectEnvironmentsOwnAnExtensibleRegistry()
    local projectEnv = envMod.new(HERE .. "/..")
    assert(projectEnv.annotations:define({name = "profile", arguments = "none", targets = {"function"},}))
    local result = parser.parse("@profile local function f() end", "test")
    assertEq(#result.errors, 0, "syntax")
    assertEq(#check.check(result, "test.g.nupp", projectEnv), 0)
end

function M.customAnnotationsCanLimitTheirTargets()
    local registry = annotations.new()
    assert(registry:define({name = "entity", arguments = "none", targets = {"record"},}))
    assertEq(diagsOf("@entity local record E end", registry), "")
    assertEq(diagsOf("@entity local function f() end", registry), "NUPP2112")
end

function M.definitionTargetsAreValidated()
    local registry = annotations.new()
    local definition, err = registry:define({name = "bad", arguments = "none", targets = {"expression"},})
    assertEq(definition, nil)
    assert(err:find("expression annotations must be compiler-registered", 1, true), err)
end

function M.reservedAnnotationsAreNotSilentlyErased()
    assertEq(diagsOf("@jit local function f() end"), "")
    assertEq(diagsOf("@comptime const function f() end"), "NUPP2111")
    assertEq(diagsOf("const comptime function f() end"), "")
end

function M.attachmentTargetsAreChecked()
    assertEq(diagsOf("@jit local x = 1"), "NUPP2112")
    -- Named functions are a valid attachment target because exported helpers use
    -- `function M.f()`. A bare global is rejected by the comptime declaration rule.
    assertEq(diagsOf("comptime function f() end"), "NUPP2411")
end

function M.argumentContractsAreChecked()
    assertEq(diagsOf("@jit(on) local function f() end"), "NUPP2112")
    -- a name that is neither a lint nor a code names no lint to allow
    assertEq(diagsOf("@allow(not_a_lint) local x = 1"), "NUPP2108")
end

function M.deprecatedMetadataIsTypedAndTargeted()
    assertEq(
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
    assertEq(checked("@deprecated(reason = 42)\nfunction legacy() end"), "NUPP2115")
    assertEq(checked("@deprecated\ndo end"), "NUPP2112")
end

function M.syntaxAnnotationsAreTypedButDoNotConstrainBindings()
    local codes, result = checked(table.concat({'@syntax("json")', "local document: {integer} = {1}",}, "\n"))
    assertEq(codes, "")
    assertEq(result.root.blocks[1].stats[1].stat.embeddedStringFormat, "json")
    assertEq(checked('@syntax(42)\nlocal value = 1'), "NUPP2115")
    assertEq(checked('@syntax("json")\ndo end'), "NUPP2112")
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
    assertEq(codes, "NUPP2513 NUPP2513 NUPP2513 NUPP2513")
    assertEq(diagnostics[1].help, "use Box instead")
    assertEq(diagnostics[3].help, "use current instead")
    assert(diagnostics[2].msg:find("old field", 1, true), diagnostics[2].msg)
end

function M.deprecatedLintCanBeAllowed()
    assertEq(
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
    assertEq(diagsOf(callback), "NUPP2502")

    local allowedCallback = callback:gsub("local function run%(%)", '@allow("jit-callback")\nlocal function run()')
    assertEq(diagsOf(allowedCallback), "")

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
    assertEq(diagsOf(disabled), "")

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
    assertEq(diagsOf(coldBoundary), "")

    local variadic = table.concat(
        {
            "cdef function printf(format: cstring, ...): int32",
            "local function run() printf('%d', 1) end",
            "return run",
        },
        "\n"
    )
    assertEq(diagsOf(variadic), "NUPP2514")

    local required = table.concat(
        {
            "cdef function printf(format: cstring, ...): int32",
            "@jit",
            "local function run() printf('%d', 1) end",
            "return run",
        },
        "\n"
    )
    assertEq(diagsOf(required), "NUPP2707")

    local requiredAllowed = required:gsub("@jit", '@allow("jit-boundary")\n@jit')
    assertEq(diagsOf(requiredAllowed), "NUPP2707")
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
    assertEq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assert(definition, "annotation definition is recorded")
    assertEq(definition.members.format.type.tag, "string")
    assertEq(definition.members.version.optional, true)
end

function M.annotationMembersAreChecked()
    local prefix = table.concat(
        {'@annotation(targets = {"record"})', "local record serializable", "    format: string", "end",},
        "\n"
    ) .. "\n"
    assertEq(checked(prefix .. "@serializable\nlocal record Missing end"), "NUPP2115")
    assertEq(checked(prefix .. "@serializable(format = 42)\nlocal record Wrong end"), "NUPP2115")
    assertEq(checked(prefix .. '@serializable(other = "json")\nlocal record Unknown end'), "NUPP2115 NUPP2115")
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
    assertEq(checked(src), "")
    assertEq(checked(src .. "\n@range(min = 1, max = 2)\nlocal record Bad end"), "NUPP2112")
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
    assertEq(codes, "")
    local definition = result.root.blocks[1].stats[1].stat.annotationDefinition
    assertEq(definition.singleValue, "text")
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
    assertEq(checked(src), "NUPP2114")
    assertEq(checked("local record Plain\n@annotationValue\nx: string\nend"), "NUPP2114")
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
    assertEq(checked(src), "NUPP2115")
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
    assertEq(codes, "")

    local users = {}
    for _, token in ipairs(result.tokens) do
        if token.text == "User" then
            users[#users + 1] = token
        end
    end
    assertEq(#users, 2, "User tokens")
    assert(users[1].definition, "type declaration has a definition")
    assert(users[2].definition == users[1].definition, "@ref value links to the type declaration")
    assertEq(users[2].semanticKind, "type", "@ref semantic kind")
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
    assertEq(checked(prefix .. "@relatesTo(Missing)\nlocal record Bad end"), "NUPP2115")
    assertEq(checked(prefix .. "@relatesTo(42)\nlocal record Bad end"), "NUPP2115")
    assertEq(checked(prefix .. "local record User end\n@relatesTo(User)\nlocal record Bad end"), "NUPP2115")
end

function M.refIsRestrictedToAnnotationDefinitionMembers()
    assertEq(checked("local record Plain\n    @ref\n    target: any\nend"), "NUPP2114")
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
    assertEq(#errors, 0, "format diagnostics")
    assert(formatted:find('@documentation("A user")', 1, true), formatted)
    assert(not formatted:find("@documentation(text", 1, true), formatted)
    assertEq(fmt.format(formatted, "test"), formatted, "format idempotency")
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
    assertEq(codes, "")
    local lua, errors = gen.generate(result, "test")
    assertEq(#errors, 0, "generation diagnostics")
    assert(not lua:find("documentation", 1, true), lua)
    assert(lua:find("const User = {}", 1, true), lua)
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
    assertEq(codes, "")
    assertEq(result.moduleExports.values.tag, nil)
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
    assertEq(#check.check(first, filename, projectEnv), 0, "first revision")

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
    assertEq(#check.check(second, filename, projectEnv), 0, "second revision")
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
        assertEq(checked(POINTERS .. "local value = " .. expression), "", expression)
    end
    for _, expression in ipairs({"@unsafe p[0] + q[0]", "(@unsafe p)[0]", "@unsafe -p[0] ^ q[0]",}) do
        assertEq(checked(POINTERS .. "local value = " .. expression), "NUPP2604", expression)
    end
    local parsed = parser.parse("local v = @unsafe -p[0] as number + q[0]")
    assertEq(#parsed.errors, 0)
    local sum = parsed.root.blocks[1].stats[1].exprs[1]
    assertEq(sum.kind, "binop")
    assert(sum.lhs.expressionAnnotations)
    assert(not sum.rhs.expressionAnnotations)
    assertEq(sum.lhs.kind, "castExpr")
    assertEq(sum.lhs.expr.kind, "unop")
    local power = parser.parse("local v = @unsafe -p[0] ^ q[0]").root.blocks[1].stats[1].exprs[1]
    assertEq(power.kind, "unop")
    assertEq(power.operand.kind, "binop")
    assertEq(power.expressionPermissionOperand, power.operand.lhs)
end

function M.expressionAnnotationsPreserveSemanticTokenKinds()
    local parsed = parser.parse("local unsafe = 1; local value = @unsafe new Box(value = unsafe)")
    assertEq(#parsed.errors, 0)
    local kinds = require("nupp.compiler.lsp.semantic").syntaxKinds(parsed)
    local decorators, keywords = 0, 0
    for _, token in ipairs(parsed.tokens) do
        if token.text == "unsafe" and kinds[token] == "decorator" then
            decorators = decorators + 1
        elseif token.text == "unsafe" then
            assert(kinds[token] ~= "nuppKeyword", "ordinary identifiers stay identifiers")
        elseif token.text == "new" then
            assertEq(kinds[token], "nuppKeyword")
            keywords = keywords + 1
        end
    end
    assertEq(decorators, 1)
    assertEq(keywords, 1)
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
        assertEq(checked(POINTERS .. "@unsafe " .. statement), "", statement)
        assertEq(
            checked(POINTERS .. "@unsafe " .. statement .. "\nlocal outside = q[0]"),
            "NUPP2604",
            "permission ends after " .. statement
        )
    end
    assertEq(checked(POINTERS .. "@unsafe local a = p[0]\nlocal result: number = a"), "")
    for _, annotations_ in ipairs({'@allow("unused-binding") @unsafe', '@unsafe @allow("unused-binding")'}) do
        assertEq(checked(POINTERS .. annotations_ .. " local a = p[0]"), "")
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
        assertEq(checked(POINTERS .. "@unsafe do " .. statement .. " end"), "NUPP2604", statement)
        assertEq(
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
    assertEq(
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
    assertEq(defined, nil)
    assert(problem:find("already defined", 1, true))
    assertEq(checked([[
@annotation(targets = {"statement"})
record unsafe end
]]), "NUPP2114")
    assertEq(checked([[
@annotation(targets = {"statement"})
record marker end
local a = @marker 1
]]), "NUPP2112")
    assertEq(checked("local a = @allow(unused-binding) 1"), "NUPP2112")
end

function M.anonymousChecksKeepUnsafeBuiltinAndImmutable()
    local registry = annotations.new()
    local builtin = registry:get("unsafe")
    for _, source in ipairs({"@unsafe do end", "local value = @unsafe 1", "@unsafe local value = 1"}) do
        local parsed = parser.parse(source)
        assertEq(#parsed.errors, 0, source)
        local diagnostics = check.check(parsed, nil, nil, {annotations = registry, strict = false})
        assertEq(#diagnostics, 0, source)
        assertEq(registry:get("unsafe"), builtin, "anonymous checks preserve the built-in definition")
    end
    local replacement = registry:define({name = "unsafe", arguments = "none", targets = {"statement"}})
    assertEq(replacement, nil, "a user definition still cannot replace unsafe")
end

function M.contextualFunctionTypesStillValidateExpressionAnnotations()
    for _, source in ipairs({
        "local f: function(): integer = @unsafe function() return 1 end",
        "local f: function(): integer = @unsafe || -> 1",
        "local function take(f: function(): integer) end; take(@unsafe function() return 1 end)",
        "local function take(f: function(): integer) end; take(@unsafe || -> 1)",
    }) do
        local codes, _, diagnostics = checked(source)
        assertEq(codes, "NUPP2112", source)
        assertEq(diagnostics[1].col, assert(source:find("@unsafe", 1, true)) + 1)
    end
end

function M.unsafePreservesOtherRegionRestrictionsAndExits()
    assertEq(checked('nosuspend do @unsafe coroutine.yield() end'), 'NUPP2701')
    assertEq(checked('noalloc do @unsafe local value = {} end'), 'NUPP2710')
    assertEq(checked("noraise do @unsafe error('failed') end"), 'NUPP2711')
    for _, body in ipairs({
        '@unsafe do return 1 end',
        '@unsafe if true then return 1 else return 2 end',
        '@unsafe while true do end',
        '@unsafe repeat until false',
    }) do
        assertEq(checked('local function f(): integer ' .. body .. ' end'), '', body)
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
    assertEq(codes_, "")
    local expected = "4|5|4|5|2|4|5|4,5,4,5,1,2,6,7,8,9,4,5,4,5"
    for _, dialect in ipairs({"luajit", "lua51"}) do
        for _, level in ipairs({0, 1, 2}) do
            local fresh = parser.parse(source, "test.g.nupp")
            local diagnostics = check.check(fresh, "test.g.nupp", env, {dialect = dialect})
            assertEq(#diagnostics, 0, diagnostics[1] and diagnostics[1].msg)
            require("nupp.compiler.optimize").run(fresh, {level = level, dialect = dialect, filename = "test.g.nupp"})
            local output, errors = gen.generate(fresh, "test.g.nupp")
            assertEq(#errors, 0, errors[1] and errors[1].msg)
            assert(not output:find("@unsafe", 1, true), output)
            local chunk = assert(loadstring(output))
            local values = {chunk()}
            assertEq(table.concat(values, "|"), expected, dialect .. " O" .. level)
        end
    end
    local formatted, diagnostics = fmt.format(source, "test.g.nupp")
    assertEq(#(diagnostics or {}), 0)
    assertEq(checked(formatted), "")
    assertEq(fmt.format(formatted, "test.g.nupp"), formatted, "formatting idempotence")
end

return M
