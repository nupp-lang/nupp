local doc = require("nupp.tools.doc")
local highlight = require("nupp.tools.doc.highlight")
local urls = require("nupp.tools.doc.urls")

local HERE = require("helpers.paths").absoluteTests
local NUPP = os.getenv("NUPP_TEST_BIN") or HERE .. "/../bin/nupp"

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return text
end

local function tempProject(files)
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "'") == 0)
    for name, text in pairs(files) do
        local sub = name:match("^(.*)/[^/]+$")
        if sub then
            assert(os.execute("mkdir -p '" .. dir .. "/" .. sub .. "'") == 0)
        end
        local f = assert(io.open(dir .. "/" .. name, "wb"))
        f:write(text)
        f:close()
    end

    return dir
end

local function capture(command)
    local pipe = assert(io.popen(command .. " 2>&1"))
    local output = pipe:read("*a")
    pipe:close()
    return output
end

local SOURCE = table.concat(
    {
        "--- Arithmetic helpers.",
        "--- See the [guide](../guide.html).",
        "--- @module",
        "--- Adds two values.",
        "--- @param left First",
        "---     value.",
        "--- @param right Second value.",
        "--- @return Their sum.",
        "function add(left: number, right: number): number",
        "   return left + right",
        "end",
        "",
        "--- A point in two dimensions.",
        "--- @typearg T Coordinate representation.",
        "record Point<T>",
        "   --- Horizontal coordinate.",
        "   x: number",
        "   --- Vertical coordinate.",
        "   y: number",
        "end",
    },
    "\n"
) .. "\n"

local M = {}

local function renderMarkdownItem(out, item)
    out[#out + 1] = require("nupp.tools.doc.html").markdownHtml(
        require("nupp.tools.doc.markdown").items({
            item
        }),
        nil,
        0
    )
end

function M.moduleDocumentationPrecedesItsDeclaration()
    for _, source in ipairs({
        "--[[Module description.]]\nmodule example\n",
        "--[=[Module description.]=]\nmodule example\nexport const value = 1\n",
        "@!internal\n\n--[[Module description.]]\nmodule example\nexport const value = 1\n",
        "--[[Module description.]]\nmodule example\n--- A value.\nexport const value = 1\n",
    }) do
        local module, errors = doc.extract(source, "src/example.nupp", "example", {includePrivate = true})
        assert(module, errors and errors[1] and errors[1].msg)
        assert(#errors == 0)
        assert(module.text == "Module description.", module.text)
    end
end

function M.moduleDocumentationKeepsNamespaceTagsAttached()
    local source = "@!internal\n\n--[[Public description.]]\n--- @namespace public\n"
        .. "module implementation\nexport function value(): integer return 1 end\n"
    local module, errors, projections = doc.extract(source, "src/implementation.nupp", "implementation")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#errors == 0)
    assert(module.text == "Public description.", module.text)
    assert(projections and #projections == 1)
    assert(projections[1].name == "public")
    assert(projections[1].text == "Public description.", projections[1].text)
end

function M.moduleDocumentationDoesNotConsumeFollowingComments()
    -- This deliberately misplaced block is an implementation comment.
    local source = "module example\n" .. "--[[Implementation note.]]\nexport const value = 1\n"
    local module = assert(doc.extract(source, "src/example.nupp", "example"))
    assert(module.text == "", module.text)
    module = assert(doc.extract("-- Ordinary header.\nmodule example\n", "src/example.nupp", "example"))
    assert(module.text == "", module.text)
    module = assert(doc.extract("--[[Undeclared module.]]\nlocal value = 1\n", "src/example.nupp", "example"))
    assert(module.text == "Undeclared module.", module.text)
    module = assert(doc.extract("--[[Empty module.]]\n", "src/example.nupp", "example"))
    assert(module.text == "Empty module.", module.text)
end

function M.apiOverviewUsesBalancedColumnsAndKindBadges()
    local markdown = require("nupp.tools.doc.markdown")
    local html = require("nupp.tools.doc.html")
    local entries = {}
    for index = 1, 25 do
        entries[index] = "[`item" .. index .. "`](#item" .. index .. ")"
    end
    entries[1] = entries[1] .. markdown.overviewBadge("record")
    entries[2] = entries[2] .. markdown.overviewBadge("type")
    local source = markdown.overview({{title = "Types", entries = entries}})
    assert(source:find("**types**", 1, true), source)
    local rendered = html.markdownHtml(source, nil, 0)
    assert(rendered:find('class="nuppdoc-overview nuppdoc-overview-3"', 1, true), rendered)
    assert(rendered:find('nuppdoc-kind-record nuppdoc-overview-badge" title="Record">R</abbr>', 1, true), rendered)
    assert(rendered:find('nuppdoc-kind-type nuppdoc-overview-badge" title="Type alias">T</abbr>', 1, true), rendered)
    for index = 25, 9, -1 do
        entries[index] = nil
    end
    assert(
        html.markdownHtml(
            markdown.overview({
                {title = "Types", entries = entries}
            })
        ):find('class="nuppdoc-overview nuppdoc-overview-1"', 1, true)
    )
    entries[9] = "[`item9`](#item9)"
    assert(
        html.markdownHtml(
            markdown.overview({
                {title = "Types", entries = entries}
            })
        ):find('class="nuppdoc-overview nuppdoc-overview-2"', 1, true)
    )
end

function M.typeMemberOverviewsShareModuleColumnsAndGroupKinds()
    local module, errors = doc.extract(
        [[
export record Catalog
    zeta: string
    alpha: string
    constructor(self) end
    function zetaMethod(self): nil end
    function alphaMethod(self, value: string): nil end
    function alphaMethod(self, value: number): nil end
    metamethod __call: function(self): integer
    type Mode = "small" | "large"
    record Entry
        value: string
    end
end
]],
        "src/catalog.nupp",
        "catalog"
    )
    assert(module, errors and errors[1] and errors[1].msg)
    local markdown = doc.markdown({module})
    local overview = assert(markdown:match("#### Members\n\n(::: api%-overview.-\n:::)"), markdown)
    local last = 0
    for _, title in ipairs({"Methods", "Constructors", "Metamethods", "Types", "Fields"}) do
        local position = assert(overview:find("**" .. title:lower() .. "**", 1, true), title)
        assert(position > last, "member groups out of order")
        last = position
    end
    assert(
        overview:find(
            "- [`alphaMethod`](#catalog.Catalog.alphaMethod)\n- [`alphaMethod`](#catalog.Catalog.alphaMethod-overload-2)",
            1,
            true
        ),
        overview
    )
    assert(
        overview:find("[`alphaMethod`]", 1, true) < overview:find("[`zetaMethod`]", 1, true),
        "methods must be alphabetized"
    )
    assert(overview:find("[`alpha`]", 1, true) < overview:find("[`zeta`]", 1, true), "fields must be alphabetized")
    assert(overview:find("[`Entry`](#catalog.Catalog.Entry)", 1, true), overview)
    assert(overview:find("[`__call`](#catalog.Catalog.__call)", 1, true), overview)
    assert(overview:find('title="Record">R</abbr>', 1, true), overview)
    assert(overview:find('title="Type alias">T</abbr>', 1, true), overview)
    assert(not markdown:find("| Name | Kind | Description |", 1, true), "member overview still uses a table")
    local rendered = require("nupp.tools.doc.html").markdownHtml(markdown)
    assert(not rendered:find("<hr%s*/?>"), "type overviews must not add horizontal rules")
    assert(
        rendered:find('class="nuppdoc-overview nuppdoc-overview-2"', 1, true),
        "nine members must use the shared two-column layout"
    )
    assert(rendered:find('href="#catalog.Catalog.alphaMethod-overload-2"', 1, true), rendered)
    assert(rendered:find('<a href="#catalog.Catalog.__call"><code>__call</code></a>', 1, true), rendered)
end

function M.extractsStructuredDocsFromTheParserCST()
    local module, errors = doc.extract(SOURCE, "src/math.nupp", "math")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#errors == 0)
    assert(module.text == "Arithmetic helpers.\nSee the [guide](../guide.html).\nAdds two values.", module.text)
    assert(#module.items == 2, "expected function and record")
    local add = module.items[1]
    assert(add.name == "add" and add.kind == "function")
    assert(add.signature == "function add(left: number, right: number): number", add.signature)
    assert(add.params[1].text == "First value.")
    assert(add.returns[1].text == "Their sum.")
    local point = module.items[2]
    assert(point.name == "Point" and #point.members == 2)
    assert(point.typeargs[1].text == "Coordinate representation.")
    assert(point.members[1].text == "Horizontal coordinate.")
end

function M.callableModulesDocumentHelpersAndPublishedSuiteMembers()
    local source = [[
module assert
local suite = {}
local private = {}

--- Requires equal values.
--- @param actual the value to compare
--- @param expected the required value
--- @return the actual value
--- @raises string when values differ
--- @export
local function equal(actual: any, expected: any, message: string?): any
    return actual
end
--- Requires different values.
--- @export
local function notEqual(actual: any, unwanted: any, message: string?): any end
--- Requires structurally equal values.
--- @export
local function deepEqual(actual: any, expected: any, message: string?): any end
--- Requires a matching string.
--- @export
local function matches(value: any, pattern: string, message: string?): string end
--- Requires an error.
--- @export
local function raises(fn: function(...: any): any, pattern: string?): any end

--- Skips the current case.
function suite.skip(reason: string): never end
--- Recognizes a skipped case.
function suite.isSkip(value: any): boolean end
--- Returns the skip reason.
function suite.skipReason(value: any): string? end
--- Builds named cases.
function suite.cases(rows: {any}, name: function(any, integer): string, run: function(any, integer): any): any end
--- Records an unexecuted case.
function suite.notExecuted(reason: string): never end
--- Recognizes an unexecuted case.
function suite.isNotExecuted(value: any): boolean end
--- Returns the unexecuted reason.
function suite.notExecutedReason(value: any): string? end
--- Requires a capability.
function suite.requireCapability(name: string, available: boolean, evidence: any?): nil end
--- Records a fact.
function suite.fact(name: string, value: any): nil end
--- Records a metric.
function suite.metric(name: string, value: number, unit: string?): nil end
--- Records completed work.
function suite.work(name: string, count: integer): nil end
--- Resolves a fixture.
function suite.fixture(key: string, produce: function(string): any): (string, any, boolean) end

function private.hidden(): nil end
local callable = {eq = equal, ne = notEqual, deepeq = deepEqual, matches = matches, raises = raises}
callable.suite = suite
export = setmetatable(callable, {__call = original})
]]
    local module, errors = doc.extract(source, "src/assert.nupp", "assert")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#module.items == 17, "a callable module lost helpers or exposed private declarations")
    local expected = {
        eq = "local function eq(actual: any, expected: any, message: string?): any",
        ne = "local function ne(actual: any, unwanted: any, message: string?): any",
        deepeq = "local function deepeq(actual: any, expected: any, message: string?): any",
        matches = "local function matches(value: any, pattern: string, message: string?): string",
        raises = "local function raises(fn: function(...: any): any, pattern: string?): any",
        ["suite.skip"] = "function suite.skip(reason: string): never",
        ["suite.isSkip"] = "function suite.isSkip(value: any): boolean",
        ["suite.skipReason"] = "function suite.skipReason(value: any): string?",
        [
            "suite.cases"
        ] = "function suite.cases(rows: {any}, name: function(any, integer): string, run: function(any, integer): any): any",
        ["suite.notExecuted"] = "function suite.notExecuted(reason: string): never",
        ["suite.isNotExecuted"] = "function suite.isNotExecuted(value: any): boolean",
        ["suite.notExecutedReason"] = "function suite.notExecutedReason(value: any): string?",
        [
            "suite.requireCapability"
        ] = "function suite.requireCapability(name: string, available: boolean, evidence: any?): nil",
        ["suite.fact"] = "function suite.fact(name: string, value: any): nil",
        ["suite.metric"] = "function suite.metric(name: string, value: number, unit: string?): nil",
        ["suite.work"] = "function suite.work(name: string, count: integer): nil",
        ["suite.fixture"] = "function suite.fixture(key: string, produce: function(string): any): string, any, boolean",
    }
    for _, item in ipairs(module.items) do
        assert(item.kind == "function", item.name .. " lost its function signature")
        assert(item.signature == expected[item.name], item.signature)
        assert(item.path == "assert." .. item.name, item.path)
        assert(item.doc.text ~= "", item.name .. " lost its documentation")
        assert(#item.params > 0, item.name .. " lost its parameter details")
        assert(#item.returns > 0, item.name .. " lost its result details")
        if item.name == "eq" then
            assert(item.params[1].text == "the value to compare")
            assert(item.returns[1].text == "the actual value")
            assert(#item.raises == 1 and item.raises[1].type == "string")
        end
        expected[item.name] = nil
    end
    assert(next(expected) == nil, "a callable helper or nested suite member is missing")
end

function M.callableTableAliasesUsePublicKeysWithoutChangingTheirContracts()
    local source = [[
module operations
local type Callable = {map: function(any): any}
--- Returns the input value.
--- @param value the original value
--- @return the same value
--- @raises string when a value is refused
local function _translate<T>(borrows value: T, label: "_translate"): T
    return value
end
local callable = {map = _translate, again = _translate, ["bracket"] = _translate} as Callable
export = setmetatable(callable, {__call = original})
]]
    local module = assert(doc.extract(source, "src/operations.nupp", "operations"))
    assert(#module.items == 3, "public aliases replace the private implementation name")
    local names = {}
    for _, item in ipairs(module.items) do
        names[item.name] = true
        assert(item.path == "operations." .. item.name, item.path)
        assert(
            item.signature == 'local function ' .. item.name .. '<T>(borrows value: T, label: "_translate"): T',
            item.signature
        )
        assert(item.typeargs[1].name == "T" and item.params[1].mode == "borrows")
        assert(item.params[1].text == "the original value" and item.returns[1].text == "the same value")
        assert(item.raises[1].type == "string" and item.doc.text == "Returns the input value.")
    end
    assert(names.map and names.again and names.bracket and not names._translate)
end

function M.assignedModuleCallablesKeepTheirLocalOverloadsAndPublicNames()
    local source = [[
module operations
local api = {}
local foreign = {}
--- Applies the callback.
--- @param count the invocation count
--- @param body the scoped callback
--- @return the callback results
local invoke: function<R...>(scoped body: function(): R...): R...
    & function<R...>(count: integer, scoped body: function(): R...): R...
local hidden: function(): nil
api.run = invoke
api.again = invoke
foreign.hidden = hidden
return api
]]
    local module, errors = doc.extract(source, "src/operations.nupp", "operations")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#module.items == 2, "only assignments onto the exported table publish local callables")
    local names = {}
    for _, item in ipairs(module.items) do
        names[item.name] = true
        assert(item.kind == "function" and item.path == "operations." .. item.name)
        assert(item.signature:find("local " .. item.name .. ": function<R...>", 1, true), item.signature)
        assert(item.signature:find("& function<R...>", 1, true), "an overload was lost")
        assert(#item.params == 2 and item.params[2].mode == "scoped")
        assert(item.params[1].text == "the invocation count" and item.returns[1].type == "R...")
        assert(item.doc.text == "Applies the callback.")
    end
    assert(names.run and names.again and not names.invoke and not names.hidden)
end

function M.overloadedMembersKeepEveryContractWithDistinctHtmlAnchors()
    local module = assert(
        doc.extract(
            [[
export record Codec
    --- Encodes a string.
    function encode(self, value: string): string return value end
    --- Encodes a number.
    function encode(self, value: number): string return tostring(value) end
end
]],
            "src/codec.nupp",
            "codec"
        )
    )
    local item = module.items[1]
    assert(#item.members == 2 and item.members[1].path == item.members[2].path)
    local out = {}
    renderMarkdownItem(out, item)
    local text = table.concat(out)
    local ids = {}
    for id in text:gmatch('id="([^"]+)"') do
        assert(not ids[id], "duplicate rendered anchor " .. id)
        ids[id] = true
    end
    assert(ids["codec.Codec.encode"] and ids["codec.Codec.encode-overload-2"])
    assert(text:find('href="#codec.Codec.encode-overload-2"', 1, true), "the overload summary lost its target")
    assert(text:find("Encodes a string.", 1, true) and text:find("Encodes a number.", 1, true))
    assert(item.members[2].path == "codec.Codec.encode", "rendering mutated the semantic member path")
end

function M.qualifiedDeclarationsCompleteSelfAliasesWithoutDuplicatingPublicContracts()
    local dir = tempProject({
        [
            "src/package/init.nupp"
        ] = [[
module package
local source = require("package.internal.contract")
--- The public resource.
export type Resource = package.Resource
export type Message = source.Message
]],
        [
            "src/contracts.nupp"
        ] = [[
module contracts
interface package.Resource
    close: function(self): nil
    interface Status
        interface Detail
            code: integer
        end
    end
end
]],
        [
            "src/package/internal/contract.nupp"
        ] = [[
@!internal
module package.internal.contract
export interface Message
    text: string
end
]],
        [
            "src/package/internal/implementation.nupp"
        ] = [[
@!internal
module package.internal.implementation
record package.Message
    implementationOnly: integer
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = assert(require("testjson").decode(readFile(dir .. "/api.json")))
    local items = {}
    for _, module in ipairs(model.modules) do
        if module.name == "package" then
            for _, item in ipairs(module.items) do
                assert(not items[item.path], "duplicate public declaration " .. item.path)
                items[item.path] = item
            end
        end
    end
    assert(items["package.Resource"].kind == "interface")
    assert(items["package.Resource"].members[1].name == "close")
    local status = items["package.Resource"].members[2]
    assert(status.path == "package.Resource.Status", status.path)
    local detail = status.members[1]
    assert(detail.path == "package.Resource.Status.Detail", detail.path)
    assert(detail.members[1].path == "package.Resource.Status.Detail.code", detail.members[1].path)
    assert(items["package.Resource"].doc.text == "The public resource.")
    assert(items["package.Message"].kind == "interface" and items["package.Message"].members[1].name == "text")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.moduleGroupsAndMemberSummariesKeepDistinctAnchors()
    local module = assert(
        doc.extract([[module types
export record Node
    members: {string}
end
]], "src/types.nupp", "types")
    )
    local rendered = require("nupp.tools.doc.html").markdownHtml(doc.markdown({module}), {}, 0)
    local seen = {}
    for id in rendered:gmatch(' id="([^"]+)"') do
        assert(not seen[id], "duplicate anchor " .. id)
        seen[id] = true
    end
    assert(seen.types and seen["types-group"] and seen["types.Node.members"])
    assert(seen["types.Node.members-overview"])
end

function M.builtinNestedMembersUsePublicPaths()
    local standard = assert(require("nupp.tools.doc.stdlib").page({path = "api"}))
    local checked = 0

    local function members(item)
        for _, member in ipairs(item.members or {}) do
            local expected = item.path .. "." .. member.name
            assert(member.path == expected, member.path .. " should be " .. expected)
            checked = checked + 1
            members(member)
        end
    end

    for _, library in ipairs(standard.modules) do
        for _, item in ipairs(library.items) do
            members(item)
        end
    end
    for _, item in ipairs(standard.typeItems) do
        members(item)
    end
    assert(checked > 100, "the builtin member inventory was not checked")
end

function M.builtinContractsCompleteSourceSelfAliasesOnlyOnce()
    local owned = assert(
        doc.extract(
            [[
module resources
--- The source-owned description.
export type Resource = resources.Resource
]],
            "src/resources.nupp",
            "resources"
        )
    )
    local builtin = assert(
        doc.extract(
            [[
interface resources.Resource
    close: function(self): nil
end
]],
            "decls/resources.d.nupp",
            "resources"
        )
    )
    local stdlib = require("nupp.tools.doc.stdlib")
    local modules = {owned}
    local page = {
        path = "api",
        title = "API reference",
        modules = {builtin},
        globalItems = {},
        typeItems = {},
        annotationItems = {},
        navigation = {globals = {}},
    }
    stdlib.merge(modules, page)
    stdlib.merge(modules, page)
    assert(#owned.items == 1, "merging the same builtin contract must be idempotent")
    local item = owned.items[1]
    assert(item.kind == "interface" and #item.members == 1 and item.members[1].name == "close")
    assert(item.doc.text == "The source-owned description.")
    assert(item.signature == "interface resources.Resource", item.signature)
end

function M.sourceOverloadsKeepTheirSignaturesWhenBuiltinDeclarationsDiffer()
    local owned = assert(
        doc.extract(
            [[
--- Reads a named resource.
function read(name: string): string return name end
--- Reads a numbered resource.
function read(index: integer): string return tostring(index) end
]],
            "src/resources.nupp",
            "resources"
        )
    )
    local builtin = assert(
        doc.extract(
            [[
--- Reads a host resource.
function read(handle: any, mode: string?): any end
]],
            "decls/resources.d.nupp",
            "resources"
        )
    )
    builtin.items[1].lua = true
    local page = {
        path = "api",
        title = "API reference",
        modules = {builtin},
        globalItems = {},
        typeItems = {},
        annotationItems = {},
        navigation = {globals = {}},
    }
    require("nupp.tools.doc.stdlib").merge({owned}, page)
    assert(#owned.items == 2, "a builtin signature must not become a third source overload")
    local signatures = {}
    for _, item in ipairs(owned.items) do
        signatures[item.signature] = true
        assert(item.doc.text ~= "Reads a host resource.", "builtin prose replaced authored prose")
    end
    assert(signatures["function read(name: string): string"])
    assert(signatures["function read(index: integer): string"])
    assert(owned.items[1].lua or owned.items[2].lua, "builtin Lua provenance disappeared")
end

function M.functionDocumentationKeepsCoroutineProtocolsBeforeResults()
    local source = [[
--- Produces a value and receives its continuation flag.
function produce(start: number) yields(number, string) resumes(boolean): string
    return 'done'
end
]]
    local module, errors = doc.extract(source, "src/producer.nupp", "producer")
    assert(module, errors and errors[1] and errors[1].msg)
    local produce = module.items[1]
    assert(
        produce.signature == "function produce(start: number) yields (number, string) resumes (boolean): string",
        produce.signature
    )
    assert(produce.returns[1].type == "string", "protocol packs changed the result contract")
end

-- An example is the one place a doc comment writes a line that looks like a tag and
-- is not one, so a fence has to suspend tag parsing rather than eat the annotation
-- the example exists to show.
function M.aFencedExampleKeepsAnAnnotationRatherThanReadingItAsATag()
    local source = table.concat(
        {
            "--- Renders a value.",
            "---",
            "--- ```nupp",
            "--- @derive(types.debug)",
            "--- local record Point",
            "---     x: integer",
            "--- end",
            "--- ```",
            "---",
            "--- @return the rendering",
            "function render(): string",
            "   return \"\"",
            "end",
        },
        "\n"
    ) .. "\n"
    local module = assert(doc.extract(source, "src/render.nupp", "render"))
    local render = module.items[1]
    assert(render and render.name == "render", "declaration missing")
    assert(
        render.doc.text:find("@derive(types.debug)", 1, true),
        "the annotation stays in the example: " .. render.doc.text
    )
    assert(render.doc.tags.derive == nil, "and never became a tag")
    assert(
        render.returns[1] and render.returns[1].text == "the rendering",
        "a tag written after the fence is still read"
    )
end

function M.tildeDocFencesSuspendTagParsingUntilTheirMatchingCloser()
    local parsed = require("nupp.compiler.syntax.docblock").parse({
        "Example:",
        "~~~~nupp",
        "@raises string shown, not declared",
        "~~~",
        "~~~~",
        "@raises string declared",
    })
    assert(parsed.text:find("@raises string shown, not declared", 1, true), parsed.text)
    assert(#parsed.raises == 1 and parsed.raises[1].type == "string")
    assert(parsed.raises[1].text == "declared")
end

local DECLARATIONS = table.concat(
    {
        "--[[",
        "# Numbers",
        "",
        "Declarations for the **number** library.",
        "]]",
        "",
        "--- Returns the largest argument.",
        "---",
        "--- @typearg V The compared type.",
        "--- @param ... The numbers to compare.",
        "--- @return The largest of them.",
        "local max: function<V>(...: V): V",
        "",
        "--- A counter.",
        "local record Counter",
        "   --- How far it has counted.",
        "   count: number",
        "",
        "   --- Advances the counter.",
        "   ---",
        "   --- @param by How much to add.",
        "   --- @return The counter itself.",
        "   step: function(c: Counter, by: number): Counter",
        "end",
    },
    "\n"
) .. "\n"

function M.documentsAFileHeaderLongCommentAsTheModule()
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num"))
    assert(module.text == "# Numbers\n\nDeclarations for the **number** library.", module.text)
end

function M.documentsTypedBindingsAsTheFunctionsTheyDeclare()
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num"))
    local max
    for _, item in ipairs(module.items) do
        if item.name == "max" then
            max = item
        end
    end
    assert(max, "typed function binding missing")
    assert(max.kind == "function", max.kind)
    assert(max.typeargs[1].name == "V" and max.typeargs[1].text == "The compared type.")
    assert(max.params[1].name == "..." and max.params[1].type == "V", max.params[1].type)
    assert(max.params[1].text == "The numbers to compare.", max.params[1].text)
    assert(max.returns[1].type == "V" and max.returns[1].text == "The largest of them.")
end

function M.parenthesizedCallablesKeepOverloadsMembersAndPhases()
    local module = assert(
        doc.extract(
            [[
--- Returns a value.
--- @typearg V the element type
local invoke: ((@nosuspend function<V>(value: V): V))
--- Selects a result.
--- @param value the input
--- @param label the optional label
--- @return the selected value
local choose: ((@nosuspend function(value: number): number)
    & ((@nosuspend function(value: number, label: string): string)))
local build: ((@comptime function(T: type): type)
    & ((@comptime function(T: type, flag: boolean): type)))
local mixed: ((@comptime function(T: type): type) & (function(value: number): number))
local value: (number & integer)
record Handlers
    apply: ((@nosuspend function(self: Handlers, value: number): number))
    build: ((@comptime function(T: type): type))
end
]],
            "src/overloads.d.nupp",
            "overloads"
        )
    )
    local items = {}
    for _, item in ipairs(module.items) do
        items[item.name] = item
    end
    assert(items.invoke.kind == "function" and items.invoke.typeargs[1].name == "V")
    assert(items.choose.kind == "function" and #items.choose.params == 2)
    assert(items.choose.params[2].name == "label" and items.choose.params[2].text == "the optional label")
    assert(items.choose.returns[1].type == "string" and items.choose.returns[1].text == "the selected value")
    assert(items.choose.signature:find("&", 1, true), "overload signature was flattened")
    assert(items.build.comptimeKind == "function" and #items.build.params == 2)
    assert(items.mixed.kind == "function" and items.mixed.comptimeKind == nil)
    assert(items.value.kind == "variable", "a non-callable intersection became a function")
    local members = {}
    for _, member in ipairs(items.Handlers.members) do
        members[member.name] = member
    end
    assert(members.apply.isFunction and #members.apply.params == 2)
    assert(members.build.isFunction and members.build.comptimeKind == "function")
    local model = require("testjson").decode(doc.json({module}))
    assert(model.modules[1].items[1].kind == "function")
end

function M.documentsComptimeCallablesAndTypeHandlesAsCompilerOnly()
    local source = table.concat(
        {
            "--- Builds a type.",
            "@comptime function newType(T: type): type",
            "   return T",
            "end",
            "",
            "--- Another type builder.",
            "local factory: @comptime function(T: type): type",
            "",
            "--- A type handle.",
            "local text: @comptime type",
            "",
            "--- Compiler operations.",
            "local record Compiler",
            "   --- Builds through a member.",
            "   build: @comptime function(T: type): type",
            "",
            "   --- Holds a type through a member.",
            "   value: @comptime type",
            "end",
        },
        "\n"
    ) .. "\n"
    local module = assert(doc.extract(source, "src/meta.d.nupp", "meta"))
    local items = {}
    for _, item in ipairs(module.items) do
        items[item.name] = item
    end

    assert(items.newType.kind == "function", items.newType.kind)
    assert(items.newType.comptimeKind == "function", items.newType.comptimeKind)
    assert(items.newType.signature == "@comptime function newType(T: type): type", items.newType.signature)
    assert(items.factory.kind == "function" and items.factory.comptimeKind == "function")
    assert(items.text.kind == "variable" and items.text.comptimeKind == "type")

    local members = {}
    for _, member in ipairs(items.Compiler.members) do
        members[member.name] = member
    end
    assert(members.build.isFunction and members.build.comptimeKind == "function")
    assert(not members.value.isFunction and members.value.comptimeKind == "type")

    local markdownRenderer = require("nupp.tools.doc.markdown")
    local htmlRenderer = require("nupp.tools.doc.html")
    local rendered = htmlRenderer.markdownHtml(markdownRenderer.items({items.Compiler}))
    assert(rendered:find("nuppdoc-kind-comptime-function", 1, true), rendered)
    assert(rendered:find("nuppdoc-kind-comptime-type", 1, true), rendered)

    local markdown = doc.markdown({module})
    assert(markdown:find("### `newType` _comptime function_", 1, true), markdown)
    assert(markdown:find("@comptime function(T: type): type", 1, true), markdown)
    assert(markdown:find("#### `build` _comptime function_", 1, true), markdown)
    assert(markdown:find("#### `value` _comptime type_", 1, true), markdown)

    local text = doc.json({module})
    -- One model, one document: keys go out sorted rather than in the order this
    -- process's string hash seed visits them. A string followed by a colon is a key.
    local last, index = {}, 1
    while index <= #text do
        local c = text:sub(index, index)
        if c == "{" then
            last[#last + 1] = ""
        elseif c == "}" then
            last[#last] = nil
        elseif c == '"' then
            local close = index + 1
            while text:sub(close, close) ~= '"' do
                close = close + (text:sub(close, close) == "\\" and 2 or 1)
            end
            local key = text:sub(index + 1, close - 1)
            if text:sub(close + 1, close + 1) == ":" then
                assert(key >= last[#last], key .. " is written after " .. last[#last] .. ":\n" .. text)
                last[#last] = key
            end
            index = close
        end
        index = index + 1
    end
    local model = require("testjson").decode(text)
    assert(model.schemaVersion == 3)
    local modelItems = {}
    for _, item in ipairs(model.modules[1].items) do
        modelItems[item.name] = item
    end
    assert(modelItems.newType.comptimeKind == "function")
    assert(modelItems.text.comptimeKind == "type")
end

function M.documentsFunctionTypedRecordFieldsAsMethods()
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num"))
    local counter
    for _, item in ipairs(module.items) do
        if item.name == "Counter" then
            counter = item
        end
    end
    assert(counter, "record missing")
    local step, count
    for _, member in ipairs(counter.members) do
        if member.name == "step" then
            step = member
        end
        if member.name == "count" then
            count = member
        end
    end
    assert(count and not count.isFunction, "data field must stay a field")
    assert(step and step.isFunction, "function-typed field must document as a method")
    assert(step.params[2].name == "by" and step.params[2].text == "How much to add.")
    assert(step.returns[1].text == "The counter itself.", step.returns[1].text)
    local rendered = {}
    renderMarkdownItem(rendered, counter)
    local html = table.concat(rendered)
    assert(html:find('>Arguments<a', 1, true) and html:find('<dl class="nuppdoc-api-details">', 1, true), html)
    assert(html:find('>Returns<a', 1, true), html)
    assert(html:find("How much to add.", 1, true) and html:find("The counter itself.", 1, true), html)
    local markdown = doc.markdown({module})
    assert(markdown:find("#### Members", 1, true), "member overview missing")
    assert(markdown:find("**methods**\n\n- [`step`](#num.Counter.step)", 1, true), markdown)
    assert(markdown:find("**fields**\n\n- [`count`](#num.Counter.count)", 1, true), markdown)
    assert(markdown:find("#### `step` _method_", 1, true), "method sub-heading missing")
    assert(markdown:find("##### Arguments", 1, true), "method arguments missing")
    assert(markdown:find('<a id="num.Counter.count"></a>', 1, true), "field anchor missing")
    assert(markdown:find("#### `count` _field_", 1, true), "field sub-heading missing")
end

function M.rendersFunctionArgumentsAndReturnsAsDescriptionLists()
    local module = assert(
        doc.extract(
            [[
--- Describes a value.
--- @param value The supplied value.
--- @return The value again.
export function identity(value: string): string return value end
]],
            "src/example.nupp",
            "example"
        )
    )
    local rendered = {}
    renderMarkdownItem(rendered, module.items[1])
    local html = table.concat(rendered)
    assert(html:find('>Arguments<a', 1, true) and html:find('<dl class="nuppdoc-api-details">', 1, true), html)
    assert(html:find('>Returns<a', 1, true), html)
    assert(html:find("<dt><code>value</code> - ", 1, true), html)
    assert(html:find("The supplied value.", 1, true), html)
    assert(html:find("The value again.", 1, true), html)
    local markdown = doc.markdown({module})
    assert(markdown:find("`value` - `string`\n:   The supplied value.", 1, true), markdown)
    assert(markdown:find("`string`\n:   The value again.", 1, true), markdown)
end

function M.rendersQuotedTypesWithoutDoubleEscaping()
    local module = assert(
        doc.extract(
            [[
export function choose(option: 'collect' | 'rock & roll'): 'collect' end
]],
            "src/example.nupp",
            "example"
        )
    )
    local rendered = {}
    renderMarkdownItem(rendered, module.items[1])
    local html = assert(table.concat(rendered):match('<dl class="nuppdoc%-api%-details">(.-)</dl>'))
    assert(html:find("&#39;collect&#39;", 1, true), html)
    assert(html:find("&#39;rock &amp; roll&#39;", 1, true), html)
    assert(not html:find("&amp;#39;", 1, true), html)
    assert(not html:find("&amp;amp;", 1, true), html)
end

function M.documentsReceiversAndOmitsNilOnlyReturns()
    local module = assert(
        doc.extract(
            [[
export record Box<T>
    constructor(self, value: T) end
    function clear(self): nil end
    function explicit(self: any): nil end
    function readonly(self: const Box<T>): nil end
    function pair(self): nil, string return nil, "value" end
end
export function free(self: any): nil end
export function callback(): function(): nil end
]],
            "src/example.nupp",
            "example"
        )
    )
    local items = {}
    for _, item in ipairs(module.items) do
        items[item.name] = item
    end
    local members = {}
    for _, member in ipairs(items.Box.members) do
        members[member.name] = member
    end
    assert(members.constructor.params[1].type == "example.Box<T>")
    assert(members.clear.params[1].type == "example.Box<T>")
    assert(members.explicit.params[1].type == "example.Box<T>")
    assert(members.readonly.params[1].type == "const example.Box<T>")
    assert(items.free.params[1].type == "any")
    local api = require("nupp.tools.doc.api")
    assert(not api.displaySignature(items.free):find(": nil", 1, true))
    assert(api.displaySignature(items.callback):find("function(): nil", 1, true))
    assert(not api.memberSpelling(members.clear):find(": nil", 1, true))
    assert(api.memberSpelling(members.pair):find(": nil, string", 1, true))
    local markdown = doc.markdown({module})
    assert(markdown:find('`self` - `example.Box<T>`', 1, true), markdown)
    local free = markdown:match("<a id=\"example.free\"></a>(.-)\n## ")
        or assert(markdown:match("<a id=\"example.free\"></a>(.*)"))
    assert(not free:find("Returns", 1, true), free)
    local rendered = require("nupp.tools.doc.html").markdownHtml(require("nupp.tools.doc.markdown").items({items.free}))
    assert(not rendered:find(">Returns<a", 1, true))
end

local NESTED_DECLARATIONS = table.concat(
    {
        "--- Holds a nested type.",
        "local record Config",
        "   --- Nested settings.",
        "   record Settings",
        "      --- Whether it is enabled.",
        "      enabled: boolean",
        "",
        "      --- Applies the settings.",
        "      --- @param text The text to apply to.",
        "      --- @return The result.",
        "      apply: function(self: Settings, text: string): string",
        "   end",
        "end",
    },
    "\n"
) .. "\n"

function M.documentsNestedTypesAsTheirOwnSubHeadingWithMembers()
    local module = assert(doc.extract(NESTED_DECLARATIONS, "src/config.d.nupp", "config"))
    local config
    for _, item in ipairs(module.items) do
        if item.name == "Config" then
            config = item
        end
    end
    assert(config, "record missing")
    local settings
    for _, member in ipairs(config.members) do
        if member.name == "Settings" then
            settings = member
        end
    end
    assert(settings and settings.isType, "nested type must document as a type, not a flattened field")
    local enabled, apply
    for _, member in ipairs(settings.members) do
        if member.name == "enabled" then
            enabled = member
        end
        if member.name == "apply" then
            apply = member
        end
    end
    assert(enabled and not enabled.isFunction, "nested type's own data field must stay a field")
    assert(apply and apply.isFunction, "nested type's own function-typed field must document as a method")
    assert(apply.returns[1] and apply.returns[1].text == "The result.", apply.returns[1] and apply.returns[1].text)
    local markdown = doc.markdown({module})
    assert(markdown:find("#### `Settings` _record_", 1, true), "nested type heading missing")
    assert(markdown:find("##### Members", 1, true), "nested type's own overview missing")
    assert(
        markdown:find("**methods**\n\n- [`apply`](#config.Config.Settings.apply)", 1, true),
        "nested type's own method list missing"
    )
    assert(markdown:find("##### `enabled` _field_", 1, true), "nested type's own field sub-heading missing")
    assert(
        markdown:find('<a id="config.Config.Settings.enabled"></a>', 1, true),
        "nested type's own field anchor missing"
    )
    local rendered = require("nupp.tools.doc.html").markdownHtml(markdown)
    for _, name in ipairs({"enabled", "apply"}) do
        local path = "config.Config.Settings." .. name
        assert(markdown:find("::: api-item " .. path .. "\n", 1, true), "member section missing")
        assert(
            rendered:find('<section class="nuppdoc-api-item" id="' .. path .. '"><h5>', 1, true),
            "member must use the shared section renderer and retain its heading level"
        )
        local _, anchors = rendered:gsub('id="' .. path:gsub("%.", "%%.") .. '"', "")
        assert(anchors == 1, "member anchor must occur exactly once")
        assert(rendered:find('href="#' .. path .. '"', 1, true), "member link missing")
    end
    assert(
        not markdown:find("::: api-item config.Config.Settings\n", 1, true),
        "nested type should retain its ordinary heading"
    )
    assert(rendered:find('id="config.Config.Settings.apply.arguments"', 1, true), "method argument scope missing")
end

local ANNOTATED_DECLARATIONS = table.concat(
    {
        "--- An open handle.",
        "local record Handle",
        "   --- Whether it is closed.",
        "   isReleased: function(self): boolean",
        "",
        "   --- Closes the handle.",
        "   --- @param self this handle",
        "   --- @return whether the close succeeded",
        "   @deprecated('use release')",
        "",
        "   close: function(takes self: Handle): boolean",
        "end",
    },
    "\n"
) .. "\n"

-- An annotation is parsed before the entry it modifies, so the `---` run written above
-- it attaches to the `@` rather than to the declaration underneath. Reading the entry
-- alone answered nothing, and the member silently lost its prose and every `@param` and
-- `@return` description while its unannotated siblings kept theirs.
function M.anAnnotatedMemberKeepsItsDocumentation()
    local module = assert(doc.extract(ANNOTATED_DECLARATIONS, "src/handle.d.nupp", "handle"))
    local handle
    for _, item in ipairs(module.items) do
        if item.name == "Handle" then
            handle = item
        end
    end
    assert(handle, "record missing")
    local close, isReleased
    for _, member in ipairs(handle.members) do
        if member.name == "close" then
            close = member
        end
        if member.name == "isReleased" then
            isReleased = member
        end
    end
    assert(isReleased and isReleased.text ~= "", "an unannotated member documents")
    assert(close, "the annotated member is missing entirely")
    assert(close.text == "Closes the handle.", close.text)
    assert(close.params[1] and close.params[1].text == "this handle", close.params[1] and close.params[1].text)
    assert(
        close.returns[1] and close.returns[1].text == "whether the close succeeded",
        close.returns[1] and close.returns[1].text
    )
end

-- Annotations and parameter modes are both public declaration metadata.
function M.documentsAnnotationsAndParameterModes()
    local module = assert(doc.extract(ANNOTATED_DECLARATIONS, "src/handle.d.nupp", "handle"))
    local handle
    for _, item in ipairs(module.items) do
        if item.name == "Handle" then
            handle = item
        end
    end
    assert(handle, "record missing")
    local close, isReleased
    for _, member in ipairs(handle.members) do
        if member.name == "close" then
            close = member
        end
        if member.name == "isReleased" then
            isReleased = member
        end
    end
    assert(
        close.annotations and close.annotations[1]:find("@deprecated", 1, true) == 1,
        close.annotations and close.annotations[1]
    )
    assert(not isReleased.annotations, "an unannotated member carries no annotations")
    assert(close.params[1].mode == "takes", tostring(close.params[1].mode))

    local markdown = doc.markdown({module})
    assert(markdown:find("`@deprecated", 1, true), "the annotation is not rendered")
    assert(markdown:find("`takes self` - `", 1, true), "the parameter mode is not rendered")
    local rendered = {}
    renderMarkdownItem(rendered, handle)
    assert(table.concat(rendered):find('class="nuppdoc-annotation">@deprecated', 1, true))
end

function M.documentsBorrowedResultsWithoutRepeatingTheirSources()
    local source = table.concat(
        {
            "--- Views a byte range.",
            "--- @param source The array backing the view.",
            "--- @return The checked view.",
            "function view(borrows source: uint8[?]): ByteSpan borrows (source)",
            "   return nil as ByteSpan",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/view.nupp", "view", {includePrivate = true}))
    local view = assert(module.items[1])
    assert(view.signature == "function view(borrows source: uint8[?]): ByteSpan", view.signature)
    assert(view.returns[1].type == "ByteSpan", view.returns[1].type)

    local markdown = doc.markdown({module})
    assert(markdown:find("function(borrows source: uint8[?]): ByteSpan", 1, true), markdown)
    assert(not markdown:find("ByteSpan borrows (source)", 1, true), markdown)
end

function M.documentsDeprecatedMigrationMetadata()
    local source = table.concat(
        {
            "--- The compatibility entry point.",
            '@deprecated(reason = "legacy protocol", replacement = "connect")',
            "function legacyConnect(): nil end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/client.nupp", "client", {includePrivate = true}))
    local item = module.items[1]
    assert(
        item.annotations and item.annotations[1] == '@deprecated(reason="legacy protocol", replacement="connect")',
        item.annotations and item.annotations[1]
    )
    local markdown = doc.markdown({module})
    assert(markdown:find("`@deprecated(reason=", 1, true), "deprecated metadata is not rendered")
    assert(markdown:find("replacement=", 1, true), "deprecated replacement is not rendered")
end

function M.documentsInheritedContractsMetamethodsAndInlineMethods()
    local source = table.concat(
        {
            "--- A callable task.",
            "record Task<T is Value> is Named, Runnable where true",
            "   --- Builds a task.",
            "   metamethod __call: function(self, value: T): self",
            "   --- Describes it.",
            "   --- @param prefix Leading text.",
            "   --- @return Description.",
            "   function describe(prefix: string): string",
            "      return prefix",
            "   end",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/task.nupp", "task", {includePrivate = true}))
    local task = module.items[1]
    assert(task.signature == "record Task<T is Value> is Named, Runnable where true", task.signature)
    assert(not task.signature:find("---", 1, true), task.signature)
    assert(task.members[1].name == "__call" and task.members[1].isMetamethod)
    assert(task.members[2].name == "describe" and task.members[2].isFunction)
    assert(task.members[2].params[1].name == "prefix")
end

function M.typeOverviewsIncludeImplementedContractsWithoutOwnMembers()
    local module, errors = doc.extract(
        [[
module contracts
export interface Named
    name: string
end
export interface Reader<T>
    read: function(self): T
end
export interface ChildReader<T> is Reader<T>
end
export record Task<T is Reader<string>> is Named, Reader<T>
    record Child is Named
    end
end
export record Unknown is External<string>
end
export record Plain
end
]],
        "src/contracts.nupp",
        "contracts"
    )
    assert(module, errors and errors[1] and errors[1].msg)
    local items = {}
    for _, item in ipairs(module.items) do
        items[item.name] = item
    end
    assert(items.Task.supertypes[1] == "Named")
    assert(items.Task.supertypes[2] == "Reader<T>")
    assert(items.Task.members[1].supertypes[1] == "Named")
    local markdown = doc.markdown({module})
    assert(
        markdown:find("**implements**\n\n- [`Named`](#contracts.Named)\n- [`Reader<T>`](#contracts.Reader)", 1, true),
        markdown
    )
    assert(
        markdown:find("##### Members\n\n::: api-overview\n**implements**\n\n- [`Named`](#contracts.Named)", 1, true),
        markdown
    )
    assert(markdown:find("**implements**\n\n- [`Reader<T>`](#contracts.Reader)", 1, true), markdown)
    assert(markdown:find("**implements**\n\n- `External<string>`", 1, true), markdown)
    assert(not markdown:find("](External", 1, true), "an undocumented contract must not become a broken link")
    local plain = require("nupp.tools.doc.markdown").items({items.Plain})
    assert(not plain:find("**implements**", 1, true), plain)
    local model = require("testjson").decode(doc.json({module}))
    for _, item in ipairs(model.modules[1].items) do
        if item.name == "Task" then
            assert(item.supertypes[2] == "Reader<T>")
            assert(item.members[1].supertypes[1] == "Named")
        end
    end
end

function M.implementedContractLinksSurvivePrivateAndNestedReexports()
    local dir = tempProject({
        ["src/contracts.nupp"] = [[
module contracts
export interface Reader<T>
    read: function(self): T
end
]],
        [
            "src/internal/model.nupp"
        ] = [[
module internal.model
local {type Reader as SourceReader} = require("contracts")
export record Worker<T> is SourceReader<T>
    record Child is SourceReader<string>
    end
end
export record Empty is SourceReader<string>
end
]],
        [
            "src/api.nupp"
        ] = [[
module api
local hidden = require("internal.model")
export type Worker<T> = hidden.Worker<T>
export record Holder
    type Empty = hidden.Empty
end
]],
        [
            "src/direct.nupp"
        ] = [[
module direct
local {type Reader as ImportedReader} = require("contracts")
export record Worker<T> is ImportedReader<T>
end
export record Holder
    record Child<T> is ImportedReader<T>
    end
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    local api = readFile(dir .. "/site/modules/api/llms.txt")
    local direct = readFile(dir .. "/site/modules/direct/llms.txt")
    local generic = "**implements**\n\n- [`contracts.Reader<T>`](../../modules/contracts/index.html#contracts.Reader)"
    assert(api:find(generic, 1, true), api)
    assert(direct:find(generic, 1, true), direct)
    local concrete = "**implements**\n\n- [`contracts.Reader<string>`](../../modules/contracts/index.html#contracts.Reader)"
    local _, count = api:gsub("%*%*implements%*%*", "")
    assert(count == 3, "root, nested record and nested alias must retain their contracts")
    assert(api:find(concrete, 1, true), api)
    assert(not api:find("SourceReader", 1, true) and not api:find("hidden.", 1, true), api)
    local html = readFile(dir .. "/site/modules/api/index.html")
    assert(
        html:find(
            '<a href="../../modules/contracts/index.html#contracts.Reader"><code>contracts.Reader&lt;T&gt;</code></a>',
            1,
            true
        ),
        html
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- A module's functions are the ones called through the module. A method belongs to
-- its type, whether the record declared it, the implementation carried the prose, or
-- the type it extends is one this module never documents.
function M.documentsMethodImplementationsUnderTheirOwnType()
    local source = table.concat(
        {
            "--- A worker.",
            "record job.Worker",
            "   --- Sends a value.",
            "   send: function(job.Worker, any)",
            "   stop: function(job.Worker)",
            "end",
            "",
            "function job.Worker:send(value: any): nil",
            "end",
            "",
            "--- Stops it.",
            "--- @raises string when it already stopped",
            "function job.Worker:stop(): nil",
            "end",
            "",
            "--- Starts one.",
            "function job.spawn(): job.Worker",
            "   return nil",
            "end",
            "",
            "function Elsewhere:extend(): nil",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/job.nupp", "job", {includePrivate = true}))
    local listed = {}
    for _, item in ipairs(module.items) do
        listed[item.name] = item
    end
    assert(
        not listed["job.Worker:send"] and not listed["job.Worker:stop"],
        "a method must not be listed among the module's own functions"
    )
    assert(listed["job.spawn"], "a module-level function must stay listed")
    local worker = assert(listed["Worker"], "record missing")
    local send, stop
    for _, member in ipairs(worker.members) do
        if member.name == "send" then
            send = member
        end
        if member.name == "stop" then
            stop = member
        end
    end
    assert(send and send.text == "Sends a value.", "the declaration keeps its prose")
    assert(stop and stop.text == "Stops it.", "the implementation supplies what it lacked")
    assert(stop.raises[1].type == "string", "raises must fold in too")
    assert(stop.raises[1].text == "when it already stopped", "with their condition")
    assert(#worker.members == 2, "folding must not duplicate a declared method")
    -- A method hung off a table this module never hands back has no spelling a reader
    -- could call it through, so listing it would only be noise.
    assert(not listed["Elsewhere:extend"], "a method on an unreachable table is not listed")
end

function M.foldsMethodsWrittenWithAnExplicitReceiverAndHidesAPrivateTypesOwn()
    local source = table.concat(
        {
            "--- A worker.",
            "--- @export",
            "record job.Worker",
            "   --- Sends a value.",
            "   send: function(borrows self: job.Worker, value: any): nil",
            "   stop: function(takes self: job.Worker): nil",
            "end",
            "",
            "function job.Worker.send(borrows self: job.Worker, value: any): nil",
            "end",
            "",
            "--- Stops it.",
            "--- @raises string when it already stopped",
            "function job.Worker.stop(takes self: job.Worker): nil",
            "end",
            "",
            "--- The sole runtime representation.",
            "local record WorkerImpl is job.Worker",
            "end",
            "",
            "--- Sends through the implementation.",
            "function WorkerImpl.send(borrows self: WorkerImpl, value: any): nil",
            "end",
            "",
            "--- Starts one.",
            "function job.spawn(): job.Worker",
            "   return nil",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/job.nupp", "job"))
    local listed = {}
    for _, item in ipairs(module.items) do
        listed[item.name] = item
    end
    assert(listed["job.spawn"], "a module-level function must stay listed")
    assert(
        not listed["job.Worker.send"] and not listed["job.Worker.stop"],
        "an explicit receiver is still a method, not a function of the module"
    )
    -- The type is private, so the reader has no value to call this on and no
    -- declaration to read it against. It goes wherever its type went.
    assert(not listed["WorkerImpl"], "a private type must stay out of the listing")
    assert(
        not listed["WorkerImpl.send"],
        "a private type's method must go with the type rather than list as a function"
    )
    local worker = assert(listed["Worker"], "record missing")
    local stop
    for _, member in ipairs(worker.members) do
        if member.name == "stop" then
            stop = member
        end
    end
    assert(#worker.members == 2, "folding must not duplicate a declared method")
    assert(stop and stop.text == "Stops it.", "the implementation supplies what it lacked")
    assert(stop.raises[1].type == "string", "raises must fold in too")
    assert(stop.raises[1].text == "when it already stopped", "with their condition")
end

-- An explicitly typed or owned receiver has to be written as an ordinary first
-- parameter in source. It is still a method at the call site, and the documentation
-- signature should show that surface rather than make `worker.send(...)` look like the
-- intended spelling.
function M.explicitSelfReceiversUseMethodSyntaxInSignatures()
    local module = assert(
        doc.extract(
            table.concat(
                {
                    "--- Sends through a worker declared in another module.",
                    "function job.Worker.send(exclusive self: job.Worker, value: any): nil",
                    "end",
                    "",
                    "--- Destroys a value passed as an ordinary argument.",
                    "function job.destroy<T>(takes self: T): nil",
                    "end",
                },
                "\n"
            ),
            "src/job.nupp",
            "job"
        )
    )
    local send = assert(module.items[1], "method missing")
    assert(send.name == "job.Worker.send", send.name)
    assert(send.signature == "function job.Worker:send(exclusive self: job.Worker, value: any): nil", send.signature)
    local destroy = assert(module.items[2], "function missing")
    assert(destroy.signature == "function job.destroy<T>(takes self: T): nil", destroy.signature)
    local markdown = doc.markdown({module})
    assert(markdown:find("function(exclusive self: job.Worker, value: any)", 1, true), markdown)
    assert(not markdown:find("function job.Worker.send", 1, true), markdown)
end

function M.omitsImplementationBodiesFromStructureSignatures()
    local source = table.concat(
        {
            "interface Named",
            "   function label(self): string",
            "      local prefix = 'name:'",
            "      return prefix .. self.name",
            "   end",
            "end",
            "record User is Named",
            "   name: string",
            "   constructor(name: string)",
            "      self.name = name",
            "   end",
            "   function label(self): string",
            "      return self.name",
            "   end",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/user.nupp", "user", {includePrivate = true}))
    local named, user
    for _, item in ipairs(module.items) do
        if item.name == "Named" then
            named = item
        end
        if item.name == "User" then
            user = item
        end
    end
    assert(named and user, "record and interface must both be documented")
    assert(named.signature == "interface Named", named.signature)
    assert(user.signature == "record User is Named", user.signature)
    local spellings = {named.signature, user.signature}
    for _, item in ipairs({named, user}) do
        for _, member in ipairs(item.members) do
            spellings[#spellings + 1] = member.type
        end
    end
    for _, spelling in ipairs(spellings) do
        assert(not spelling:find("prefix", 1, true), spelling)
        assert(not spelling:find("return", 1, true), spelling)
        assert(not spelling:find("self.name =", 1, true), spelling)
    end
end

function M.documentsDeclarationsWrappedInAnnotations()
    local source = table.concat(
        {
            "--- Opens an owned handle.",
            "--- @param path Where to open it.",
            "--- @return The owned handle.",
            "function resources.open(path: string): affine(io.File, close)",
            "   return assert(io.open(path))",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/resources.nupp", "resources"))
    assert(#module.items == 1, "the annotated function was not documented")
    local open = module.items[1]
    assert(open.name == "resources.open", open.name)
    assert(open.doc.text == "Opens an owned handle.", open.doc.text)
    assert(open.params[1].text == "Where to open it.", open.params[1].text)
    assert(open.returns[1].text == "The owned handle.", open.returns[1].text)
end

function M.hidesPrivateCleanupNamesFromSignatures()
    local source = table.concat(
        {
            "--- The library's own terminal.",
            "const __destroyReader: function(takes value: Reader): nil",
            "",
            "--- A terminal callers may name.",
            "const closeReader: function(takes value: Reader): nil",
            "",
            "--- Opens a reader over a string.",
            "function io.newReader(text: string): affine(Reader, __destroyReader)",
            "   return read(text)",
            "end",
            "",
            "--- Adopts a reader callers close themselves.",
            "function io.adopt(text: string): affine(Reader, closeReader)",
            "   return read(text)",
            "end",
            "",
            "--- Keeps a literal type unchanged.",
            'function io.literal(value: "affine(Reader, __destroyReader)"): string',
            "   return value",
            "end",
            "",
            "--- Keeps a long literal type unchanged.",
            "function io.longLiteral(value: [[affine(Reader, __destroyReader)]]): string",
            "   return value",
            "end",
            "",
            "--- Byte sources.",
            "record io.Bytes",
            "   --- Opens a reader over these bytes.",
            "   newReader: function(self: Bytes): affine(Reader, __destroyReader)",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/io.nupp", "io"))
    local byName = {}
    for _, item in ipairs(module.items) do
        byName[item.name] = item
    end
    assert(byName["io.__destroyReader"] == nil, "the private terminal was documented")
    local opened = assert(byName["io.newReader"], "the opening function was not documented")
    assert(opened.signature:find("affine(Reader, _)", 1, true), opened.signature)
    assert(not opened.signature:find("__destroyReader", 1, true), opened.signature)
    assert(opened.returns[1].type == "affine(Reader, _)", opened.returns[1].type)
    local adopted = assert(byName["io.adopt"], "the adopting function was not documented")
    assert(adopted.signature:find("affine(Reader, closeReader)", 1, true), adopted.signature)
    local literal = assert(byName["io.literal"], "the literal function was not documented")
    assert(literal.signature:find('"affine(Reader, __destroyReader)"', 1, true), literal.signature)
    local longLiteral = assert(byName["io.longLiteral"], "the long literal function was not documented")
    assert(longLiteral.signature:find("[[affine(Reader, __destroyReader)]]", 1, true), longLiteral.signature)
    local bytes = assert(byName["Bytes"], "the record was not documented")
    assert(bytes.signature == "record io.Bytes", bytes.signature)
    local newReader = assert(bytes.members[1], "the record's member was not documented")
    assert(newReader.type:find("affine(Reader, _)", 1, true), newReader.type)
    assert(not newReader.type:find("__destroyReader", 1, true), newReader.type)
end

function M.namespaceTagSynthesizesModulesFromAShapesFields()
    local source = table.concat(
        {
            "--- @namespace lib",
            "local lib: {",
            "   data: {",
            "      --- Encodes a value.",
            "      encode: function(value: any): string",
            "   },",
            "   --- Test-only helpers.",
            "   --- @internal",
            "   test: {",
            "      --- Should not appear in public documentation.",
            "      hidden: function(): nil",
            "   },",
            "   math: lib.MathLibrary",
            "}",
            "",
            "--- Scalar helpers.",
            "--- @internal",
            "record lib.MathLibrary",
            "   --- Vector helpers.",
            "   --- @namespace",
            "   vec2: lib.Vec2Library",
            "   --- Adds two numbers.",
            "   add: function(a: number, b: number): number",
            "end",
            "",
            "--- Vector helpers.",
            "--- @internal",
            "record lib.Vec2Library",
            "   --- Computes a length.",
            "   length: function(x: number, y: number): number",
            "end",
        },
        "\n"
    )
    local module, errors, extra = doc.extract(source, "src/lib.d.nupp", "lib")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#module.items == 0, "internal backing records leaked into public docs")
    assert(extra and #extra == 3, extra and #extra)
    local byName = {}
    for _, mod in ipairs(extra) do
        byName[mod.name] = mod
    end
    assert(byName["lib.data"], "an inline field becomes its own module")
    assert(byName["lib.data"].items[1].name == "encode")
    assert(byName["lib.data"].items[1].kind == "function")
    assert(byName["lib.data"].items[1].doc.text == "Encodes a value.")
    assert(not byName["lib.test"], "an internal namespace field leaked into public docs")
    assert(byName["lib.math"], "a field spelled by name follows it to the same file's record")
    assert(byName["lib.math"].items[1].name == "add")
    assert(byName["lib.math"].items[1].params[1].name == "a")
    assert(byName["lib.math.vec2"], "a tagged field becomes a nested module")
    assert(byName["lib.math.vec2"].text == "Vector helpers.")
    assert(byName["lib.math.vec2"].items[1].name == "length")

    local private, privateErrors, privateExtra = doc.extract(source, "src/lib.d.nupp", "lib", {includePrivate = true,})
    assert(private, privateErrors and privateErrors[1] and privateErrors[1].msg)
    assert(#private.items == 2, "private docs must retain internal declarations")
    local privateByName = {}
    for _, mod in ipairs(privateExtra or {}) do
        privateByName[mod.name] = mod
    end
    assert(privateByName["lib.test"], "private docs must retain internal namespace fields")
end

function M.namespaceTagsIgnoreWindowsLineEndings()
    local source = table.concat(
        {
            "--- Compiler facilities.",
            "--- @namespace nupp",
            "local nupp: {",
            "   --- Codec helpers.",
            "   codec: {",
            "      --- Encodes a value.",
            "      encode: function(value: any): string",
            "   }",
            "}",
        },
        "\r\n"
    ) .. "\r\n"
    local _, errors, extra = doc.extract(source, "prelude.d.nupp", "prelude")
    assert(not errors or #errors == 0, errors and errors[1] and errors[1].msg)
    assert(
        extra and extra[1] and extra[1].name == "nupp.codec",
        extra and extra[1] and extra[1].name or "namespace missing"
    )
end

function M.standardTypesApiMarksItsCompilerOnlyValues()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors, extra = doc.extract(
        source,
        "src/nupp/compiler/decls/prelude.d.nupp",
        "nupp.compiler.decls.prelude"
    )
    assert(module, errors and errors[1] and errors[1].msg)

    local types
    for _, candidate in ipairs(extra or {}) do
        if candidate.name == "types" then
            types = candidate
        end
    end
    assert(types, "the prelude did not document the types namespace")

    local foundType, foundFunction = false, false
    for _, item in ipairs(types.items) do
        if item.name == "string" then
            foundType = item.comptimeKind == "type"
        elseif item.name == "optional" then
            foundFunction = item.comptimeKind == "function"
        end
    end
    assert(foundType, "types.string lost its @comptime type kind")
    assert(foundFunction, "types.optional lost its @comptime function kind")
end

function M.constModuleMembersProjectTheirOriginalAliasContracts()
    local dir = tempProject({
        [
            "src/facade.nupp"
        ] = [[
module facade
local implementation = require("private.implementation")
local api = {}
const api.make = implementation.make
const api._secret = implementation.make
local hidden = {}
const hidden.leak = implementation.make
api.mutable = implementation.make
export = api
]],
        [
            "src/private/implementation.nupp"
        ] = [[
@!internal
module private.implementation
--- Keeps its generic value and returns a count.
export function make<T>(value: T): (T, integer)
    return value, 7
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = require("testjson").decode(readFile(dir .. "/api.json"))
    local items = {}
    for _, module in ipairs(model.modules) do
        assert(module.name == "facade", "the private implementation became public")
        for _, item in ipairs(module.items) do
            items[item.path] = item
        end
    end
    local maker = assert(items["facade.make"], "the const member is absent")
    assert(maker.kind == "function", maker.kind)
    assert(maker.signature:find("make<T>", 1, true), maker.signature)
    assert(maker.params[1].name == "value" and #maker.returns == 2, "generic input and result pack were lost")
    assert(maker.doc.text:find("Keeps its generic value", 1, true), "the original declaration prose was lost")
    assert(not items["facade.api.make"] and not items["facade._secret"], "private or local table names leaked")
    assert(not items["facade.hidden.leak"] and not items["facade.mutable"], "an unrelated assignment was projected")
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    local facade = readFile(dir .. "/site/modules/facade/index.html")
    local make = assert(facade:match('<section class="nuppdoc%-api%-item" id="facade%.make">(.-)</section>'))
    assert(make:find("Read-only binding", 1, true), "the public const alias lost its restriction")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.standardTypesPageCombinesBuildersAndRuntimeExports()
    local dir = tempProject({
        ["src/prelude.d.nupp"] = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp"),
        ["src/types/init.nupp"] = readFile(HERE .. "/../src/types/init.nupp"),
        ["src/types/derive.nupp"] = readFile(HERE .. "/../src/types/derive.nupp"),
        ["src/types/reflect.nupp"] = readFile(HERE .. "/../src/types/reflect.nupp"),
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    for _, name in ipairs({
        "types.string",
        "types.optional",
        "types.newstore",
        "types.derive.implement",
        "types.reflect.runtime"
    }) do
        assert(api:find('<a id="' .. name .. '"></a>', 1, true), name .. " is absent from the generated reference")
    end
    assert(not api:find('id="types.__', 1, true), "private compiler members leaked into the reference")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.spiReferenceShowsTheInterfaceArgumentRatherThanItsLowering()
    local path = "src/nupp/compiler/decls/lua.d.nupp"
    local source = readFile(HERE .. "/../" .. path)
    local _, errors, modules = doc.extract(source, path, "lua", {shapesAsModules = true})
    assert(not errors or #errors == 0, errors and errors[1] and errors[1].msg)
    local packageModule
    for _, module in ipairs(modules or {}) do
        if module.name == "package" then
            packageModule = module
        end
    end
    assert(packageModule, "the prelude must document package discovery")
    assert(packageModule.text:find("dependency order", 1, true))
    local providers
    for _, item in ipairs(packageModule.items) do
        if item.name == "providers" then
            providers = item
        end
    end
    assert(providers, "the package reference has no providers operation")
    assert(providers.signature == "providers(Interface): function(): Interface?")
    assert(#providers.typeargs == 0, "discovery infers the implementation type from its interface argument")
    assert(providers.params[1].name == "Interface" and providers.params[1].type == "interface declaration")
    assert(providers.params[1].text ~= "" and providers.returns[1].text ~= "")
    assert(providers.returns[1].type == "function(): Interface?")

    local ordinary = assert(
        doc.extract(
            [[
module custom
export function providers<I>(interface: string): function(): I?
    return function(): I? return nil end
end
]],
            "src/custom.nupp",
            "custom"
        )
    )
    assert(ordinary.items[1].params[1].type == "string", "unrelated functions keep their declared signature")
end

-- The public JSON module documents its own complete surface; the host declaration is
-- only an implementation boundary.
function M.standardJsonApiHasCompleteDocumentation()
    local path = "src/serde/json/init.nupp"
    local source = readFile(HERE .. "/../" .. path)
    local module, errors = doc.extract(source, path, "serde.json")
    assert(module, errors and errors[1] and errors[1].msg)

    local expected = {
        EncodedValue = true,
        EncodedString = true,
        JSONEncodable = true,
        Writer = true,
        decodevalue = true,
        pull = true,
        arrayof = true,
        asarray = true,
        asobject = true,
        isarray = true,
        encodevalue = true,
        encoded = true,
        encodedstring = true,
        numbertoken = true,
        verified = true,
        verifiedstring = true,
        newwriter = true,
        NULL = true,
        EMPTY_ARRAY = true,
        EMPTY_OBJECT = true,
    }
    local callable = {
        decodevalue = true,
        pull = true,
        arrayof = true,
        asarray = true,
        asobject = true,
        isarray = true,
        encodevalue = true,
        encoded = true,
        encodedstring = true,
        numbertoken = true,
        verified = true,
        verifiedstring = true,
        newwriter = true,
    }
    local writer
    for _, item in ipairs(module.items) do
        local prefix = "serde.json." .. item.name
        local valueMember = expected[item.name]
        expected[item.name] = nil
        if valueMember then
            assert(item.doc.text ~= "", prefix .. " has no documentation")
        end
        if valueMember and callable[item.name] then
            assert(item.doc.text:find("```nupp", 1, true), prefix .. " has no source example")
        end
        for _, param in ipairs(item.params or {}) do
            assert(param.text ~= "", prefix .. " parameter " .. param.name .. " has no documentation")
        end
        if item.name == "Writer" then
            writer = item
        end
    end
    assert(next(expected) == nil, "the JSON module is missing a documented API item")
    assert(writer, "the JSON module did not document serde.json.Writer")
    local valuesPath = "src/serde/json/spi.nupp"
    local values = assert(doc.extract(readFile(HERE .. "/../" .. valuesPath), valuesPath, "serde.json.spi"))
    for _, item in ipairs(values.items) do
        if item.name == "Writer" then
            writer = item
        end
    end
    assert(writer.members and #writer.members > 0, "the Writer contract has no documented members")
    for _, member in ipairs(writer.members or {}) do
        local prefix = "serde.json.Writer." .. member.name
        assert(member.text ~= "", prefix .. " has no documentation")
        assert(member.text:find("```nupp", 1, true), prefix .. " has no source example")
        for _, param in ipairs(member.params or {}) do
            assert(param.text ~= "", prefix .. " parameter " .. param.name .. " has no documentation")
        end
    end
end

function M.standardTaskApiHasModuleExamples()
    local path = "src/nupp/tasks.nupp"
    local source = readFile(HERE .. "/../" .. path)
    local module, errors = doc.extract(source, path, "nupp.tasks")
    assert(module, errors and errors[1] and errors[1].msg)

    local examples = select(2, module.text:gsub("```nupp", ""))
    assert(examples >= 2, "nupp.tasks needs structured-work and deadline examples")
end

-- Public UTF-8 and digest modules document their complete declared surface.
function M.standardDataApiHasCompleteDocumentation()
    local modules = {"src/utf8.nupp", "src/binary/digest/init.nupp",}
    for _, relative in ipairs(modules) do
        local source = assert(readFile(HERE .. "/../" .. relative), "no module at " .. relative)
        local name = relative:match("^src/(.+)%.nupp$"):gsub("/", "."):gsub("%.init$", "")
        local module, errors = doc.extract(source, relative, name)
        assert(module, errors and errors[1] and errors[1].msg)
        assert(module.text ~= "", name .. " has no module documentation")
        for _, item in ipairs(module.items) do
            local prefix = name .. "." .. item.name
            assert(item.doc.text ~= "", prefix .. " has no documentation")
            for _, param in ipairs(item.params) do
                assert(param.text ~= "", prefix .. " parameter " .. param.name .. " has no documentation")
            end
            for index, result in ipairs(item.returns) do
                assert(result.text ~= "", prefix .. " return " .. index .. " has no documentation")
            end
        end
    end
end

-- Public I/O overviews and their implementation declarations document the same
-- API even when the implementation module is private.
function M.standardIOApiHasCompleteDocumentation()
    local modules = {
        [
            "src/nupp/io.nupp"
        ] = {
            types = {
                Buffer = true,
                ByteView = true,
                Reader = true,
                Writer = true,
                ScalarReader = true,
                ScalarWriter = true,
            },
            functions = {newBuffer = true, newStringReader = true,},
        },
        [
            "src/io/internal/path.nupp"
        ] = {
            types = {Path = true,},
            functions = {newpath = true, cwd = true, sep = true,},
            overview = "src/nupp/runtime/standardio.nupp",
        },
        [
            "src/io/internal/uritypes.nupp"
        ] = {types = {URI = true,}, functions = {isuri = true,}, overview = "src/nupp/runtime/standardio.nupp",},
        [
            "src/io/files/init.nupp"
        ] = {
            types = {File = true, TemporaryPath = true, Info = true, Entry = true,},
            functions = {info = true, open = true, read = true, glob = true,},
        },
    }
    for relative, expected in pairs(modules) do
        local source = assert(readFile(HERE .. "/../" .. relative), "no module at " .. relative)
        local name = relative:match("src/(.+)%.nupp"):gsub("/", "."):gsub("%.init$", "")
        local module, errors = doc.extract(source, relative, name)
        assert(module, errors and errors[1] and errors[1].msg)
        local overview = module
        if expected.overview then
            overview = assert(
                doc.extract(readFile(HERE .. "/../" .. expected.overview), expected.overview, "nupp.runtime.standardio")
            )
        end
        assert(overview.text ~= "", name .. " has no public overview documentation")
        local foundTypes, foundFunctions = {}, {}
        for _, item in ipairs(module.items) do
            local prefix = name .. "." .. item.name
            assert(item.doc.text ~= "", prefix .. " has no documentation")
            if expected.types[item.name] then
                foundTypes[item.name] = true
            end
            if expected.functions[item.name] then
                foundFunctions[item.name] = true
            end
            for _, param in ipairs(item.params) do
                assert(param.text ~= "", prefix .. " parameter " .. param.name .. " has no documentation")
            end
            for index, result in ipairs(item.returns) do
                assert(result.text ~= "", prefix .. " return " .. index .. " has no documentation")
            end
        end
        for member in pairs(expected.types) do
            assert(foundTypes[member], name .. " did not document " .. member)
        end
        for member in pairs(expected.functions) do
            assert(foundFunctions[member], name .. " did not document " .. member)
        end
    end

    -- Paths are interned by `newpath`; direct construction is intentionally
    -- unavailable.
    local path = assert(readFile(HERE .. "/../src/nupp/runtime/standardio.nupp"))
    local module = assert(doc.extract(path, "src/nupp/runtime/standardio.nupp", "nupp.runtime.standardio"))
    local factory
    for _, item in ipairs(module.items) do
        if item.name == "newpath" then
            factory = item
        end
    end
    assert(factory, "io did not document newpath")
    assert(factory.doc.text:find("#### Examples", 1, true), "io.newpath has no examples")
    assert(
        factory.doc.text:find('io.newpath("src", "main.nupp")', 1, true),
        "io.newpath has no component-joining example"
    )

    -- URIs are likewise interned by `newuri`; their exported record is a value type,
    -- not a public construction surface.
    local uri = assert(readFile(HERE .. "/../src/nupp/runtime/standardio.nupp"))
    local uriModule = assert(doc.extract(uri, "src/nupp/runtime/standardio.nupp", "nupp.runtime.standardio"))
    local uriFactory
    for _, item in ipairs(uriModule.items) do
        if item.name == "newuri" then
            uriFactory = item
        end
    end
    assert(uriFactory, "io did not document newuri")
    assert(
        uriFactory.doc.text:find('io.newuri("https://example.com/a?b=1")', 1, true),
        "io.newuri has no parsing example"
    )
end

function M.standardReflectApiKeepsItsGraphAndMaterializerTogether()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors = doc.extract(source, "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude")
    assert(module, errors and errors[1] and errors[1].msg)

    local reflect
    for _, item in ipairs(module.items) do
        if item.name == "reflect" then
            reflect = item
        end
    end
    assert(reflect, "the prelude did not document types.reflect")

    local expected = {
        AnnotationArgument = true,
        Annotation = true,
        Field = true,
        Entry = true,
        Node = true,
        SoAField = true,
        SoAInfo = true,
        Info = true,
        FieldCodecBlueprint = true,
        FieldCodec = true,
        fieldcodec = true,
    }
    local examples = {
        AnnotationArgument = true,
        Field = true,
        Node = true,
        SoAInfo = true,
        Info = true,
        FieldCodec = true,
        fieldcodec = true,
    }
    local _, moduleExamples = reflect.doc.text:gsub("```nupp", "")
    assert(moduleExamples >= 2, "types.reflect needs root and graph examples")
    for _, member in ipairs(reflect.members) do
        if expected[member.name] then
            assert(member.text ~= "", "types.reflect." .. member.name .. " has no documentation")
            expected[member.name] = nil
        end
        if examples[member.name] then
            assert(member.text:find("```nupp", 1, true), "types.reflect." .. member.name .. " has no source example")
            examples[member.name] = nil
        end
        if member.name == "fieldcodec" then
            assert(member.comptimeKind == "function", "types.reflect.fieldcodec must document its comptime-only phase")
        end
    end
    for name in pairs(expected) do
        error("the prelude did not document types.reflect." .. name)
    end
    for name in pairs(examples) do
        error("the prelude did not keep the types.reflect." .. name .. " example")
    end
end

-- A host boundary is an implementation detail of the module that stands on it, so it
-- must never reach the documented surface. These used to be invisible by sitting
-- under nupp.compiler.decls, where the internal root hid them. They sit beside their
-- modules now, inside the namespace a reader browses, so each has to say so itself.
function M.hostBoundariesDeclareThemselvesInternal()
    local boundaries = {"src/nupp/workers/native.d.nupp", "src/binary/_representation.nupp",}
    for _, relative in ipairs(boundaries) do
        local source = readFile(HERE .. "/../" .. relative)
        assert(source, "no boundary at " .. relative)
        assert(
            source:find("@!internal", 1, true),
            relative .. " would be documented as part of the namespace it sits in"
        )
    end
end

function M.standardLibraryBackingRecordsStayInternal()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors, extra = doc.extract(
        source,
        "src/nupp/compiler/decls/prelude.d.nupp",
        "nupp.compiler.decls.prelude"
    )
    assert(module, errors and errors[1] and errors[1].msg)

    local expected = {["math.vec2"] = "add", ["math.quat"] = "mul",}
    for _, child in ipairs(extra or {}) do
        local member = expected[child.name]
        if member then
            local found = false
            for _, item in ipairs(child.items) do
                if item.name == member then
                    found = true
                end
            end
            assert(found, child.name .. " did not inherit " .. member)
            expected[child.name] = nil
        end
    end
    for name in pairs(expected) do
        error("the prelude did not synthesize " .. name)
    end

    for _, item in ipairs(module.items) do
        assert(not item.name:match("Library$"), "nupp." .. item.name .. " leaked its backing record")
    end

    local closeable
    for _, item in ipairs(module.items) do
        if item.name == "Closeable" then
            closeable = item
        end
    end
    assert(closeable, "the prelude did not document Closeable")
    assert(closeable.module == "own", "Closeable is not owned by the own module")
    assert(
        closeable.signature:find("interface own.Closeable is own.Affine<self.close>", 1, true),
        "Closeable lost its qualified declaration"
    )

    local private = assert(
        doc.extract(source, "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude", {
            includePrivate = true
        })
    )
    local topLevelLibraries, nestedLibraries = 0, 0
    for _, item in ipairs(private.items) do
        if item.name:match("Library$") then
            topLevelLibraries = topLevelLibraries + 1
        end
        for _, member in ipairs(item.members) do
            if member.name == "Library" then
                nestedLibraries = nestedLibraries + 1
            end
            for _, sub in ipairs(member.members or {}) do
                if sub.name == "Library" then
                    nestedLibraries = nestedLibraries + 1
                end
            end
        end
    end
    -- Math, Vec2, Quat and the four fixed-width namespaces retain private top-level
    -- backing records. Nothing nests one any more: Files.Library was the last, and it
    -- left with io.
    assert(topLevelLibraries == 7, "private docs lost top-level backing records")
    assert(nestedLibraries == 0, "private docs grew a nested backing record")
end

function M.namedNamespaceProjectsAPrivateDeclarationContract()
    local source = [[
--- Shared operations.
--- @internal
--- @namespace sample
record PrivateLibrary
    --- Produces the next value.
    --- @param value the input
    --- @return the next value
    next: function(value: integer): integer
end
]]
    local module, errors, namespaces = doc.extract(source, "sample.d.nupp", "private")
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#module.items == 0, "the backing record stays private")
    assert(#namespaces == 1 and namespaces[1].name == "sample")
    local item = namespaces[1].items[1]
    assert(item.name == "next" and item.path == "sample.next")
    assert(item.signature == "local next: function(value: integer): integer", item.signature)
    assert(item.params[1].text == "the input")
    assert(item.returns[1].text == "the next value")
    local private = assert(doc.extract(source, "sample.d.nupp", "private", {includePrivate = true}))
    assert(private.items[1].name == "PrivateLibrary")
end

function M.namedNamespaceProjectsAHostTableWithoutPublishingItsImplementation()
    local source = [[
@!internal
--- @namespace console
module package.internal.console
local implementation = {}
--- A message.
record implementation.Message text: string end
--- Writes a message.
function implementation.write(message: implementation.Message): nil end
--- The private host value.
--- @internal
implementation.value = {}
export = implementation
]]
    for _, includePrivate in ipairs({false, true}) do
        local original, errors, extra = doc.extract(source, "console.nupp", "package.internal.console", {
            includePrivate = includePrivate
        })
        assert(original and #errors == 0 and original.documentationInternal)
        assert(#extra == 1 and extra[1].name == "console" and not extra[1].documentationInternal)
        local listed = {}
        for _, item in ipairs(extra[1].items) do
            listed[item.name] = item
        end
        assert(
            listed.Message and listed.write and not listed.value,
            "only the existing public declarations project onto the host table"
        )
        assert(listed.write.path == "console.write")
        assert(listed.write.signature:find("console.write", 1, true), listed.write.signature)
        assert(listed.write.params[1].type == "console.Message", listed.write.params[1].type)
        assert(not listed.Message.signature:find("implementation.", 1, true), listed.Message.signature)
    end
end

function M.hostExtensionPagesKeepTheirContractsAndClockLinks()
    local fixture = {['guide.md'] = '# Extensions\n\nThe clock is [](os.monotonic).\n'}
    for _, name in ipairs({
        "nupp/runtime/standardio.nupp",
        "nupp/runtime/standardos.nupp",
        "io/cli.nupp",
        "nupp/cli/internal/terminal.nupp",
        "nupp/cli/internal/table.nupp",
    }) do
        fixture["src/" .. name] = readFile(HERE .. "/../src/" .. name)
    end
    local dir = tempProject(fixture)
    local config = {include = {"src"}}
    local settings = {sources = {"src"}, pages = {{path = "guide", source = "guide.md", title = "Extensions"}}}
    assert(doc.build(dir, config, settings, {format = "json", output = "api.json"}) == 0)
    local model = require("testjson").decode(readFile(dir .. "/api.json"))
    local modules = {}
    for _, module in ipairs(model.modules) do
        assert(not module.name:find("nupp.runtime.standard", 1, true), "the implementation remains private")
        modules[module.name] = module
    end
    local publicIO, publicOS = assert(modules.io, "io has no public page"), assert(modules.os, "os has no public page")
    local ioItems, osItems, terminalItems = {}, {}, {}
    for _, item in ipairs(publicIO.items) do
        ioItems[item.name] = item
    end
    for _, item in ipairs(publicOS.items) do
        osItems[item.name] = item
    end
    for _, item in ipairs(assert(modules["io.cli"], "terminal has no public page").items) do
        terminalItems[item.name] = item
    end
    for _, name in ipairs({"ColorMode", "Style", "Cell", "TableOptions", "Alignment", "Column"}) do
        assert(terminalItems[name], "the terminal type is missing: " .. name)
    end
    for _, name in ipairs({
        "style",
        "table",
        "writetable",
        "cell",
        "paintedcell",
        "annotatedcell",
        "severity",
        "setcolormode",
        "withcolormode",
        "colorenabled",
        "isterminal",
        "columns"
    }) do
        assert(terminalItems[name], "the terminal member is missing: " .. name)
        assert(
            terminalItems[name].signature:find("function io.cli.", 1, true)
            and not terminalItems[name].signature:find("terminalTypes.", 1, true)
            and not terminalItems[name].signature:find("tables.", 1, true),
            terminalItems[name].signature
        )
    end
    assert(
        #terminalItems.Style.members > 0 and #terminalItems.TableOptions.members > 0,
        "public type aliases retain their source contract members"
    )
    assert(not ioItems.value and not osItems.value, "private host-table values do not become public API")
    for _, name in ipairs({"Info", "info", "monotonic", "walltime", "uuid4", "uuid7"}) do
        assert(osItems[name], "the system member is missing: " .. name)
    end
    local fields = {}
    for _, field in ipairs(osItems.Info.members) do
        fields[field.name] = true
    end
    for _, name in ipairs({"platform", "arch", "endianness", "pointerbits", "parallelism"}) do
        assert(fields[name], "os.Info lost its field: " .. name)
    end
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)
    local guide = readFile(dir .. "/site/guide/index.html")
    assert(guide:find("modules/os/index.html#os.monotonic", 1, true), "the clock links to its public declaration")
    local osPage = readFile(dir .. "/site/modules/os/index.html")
    assert(osPage:find('id="os.monotonic"', 1, true), "the public clock anchor is missing")
    os.execute("rm -rf " .. string.format("%q", dir))
end

function M.standardMathApiHasCompleteDocumentation()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors, extra = doc.extract(
        source,
        "src/nupp/compiler/decls/prelude.d.nupp",
        "nupp.compiler.decls.prelude"
    )
    assert(module, errors and errors[1] and errors[1].msg)

    local mathModule, vec2Module, quatModule
    for _, candidate in ipairs(extra or {}) do
        if candidate.name == "math" then
            mathModule = candidate
        end
        if candidate.name == "math.vec2" then
            vec2Module = candidate
        end
        if candidate.name == "math.quat" then
            quatModule = candidate
        end
    end
    assert(mathModule, "the prelude did not synthesize math")
    assert(vec2Module, "the prelude did not synthesize math.vec2")
    assert(#vec2Module.items > 0, "math.vec2 has no operations")
    assert(quatModule, "the prelude did not synthesize math.quat")
    assert(#quatModule.items > 0, "math.quat has no operations")

    local function assertDocumented(documentedModule)
        for _, item in ipairs(documentedModule.items) do
            assert(item.doc.text ~= "", documentedModule.name .. "." .. item.name .. " has no documentation")
            for _, param in ipairs(item.params) do
                assert(
                    param.text ~= "",
                    documentedModule.name .. "." .. item.name .. " parameter " .. param.name .. " has no documentation"
                )
            end
            for index, result in ipairs(item.returns) do
                assert(
                    result.text ~= "",
                    documentedModule.name .. "." .. item.name .. " return " .. index .. " has no documentation"
                )
            end
        end
    end

    assertDocumented(mathModule)
    assertDocumented(vec2Module)
    assertDocumented(quatModule)
    for _, item in ipairs(mathModule.items) do
        assert(item.name ~= "vec2", "vec2 must be a nested module, not a value")
        assert(item.name ~= "quat", "quat must be a nested module, not a value")
    end
    for _, item in ipairs(module.items) do
        assert(
            item.name ~= "MathLibrary" and item.name ~= "Vec2Library" and item.name ~= "QuatLibrary",
            "math implementation library types must stay out of public docs"
        )
    end
end

-- Public modules claim to document exactly their public surface and may not leak
-- private storage into it.
local function assertDocumentedSurface(relativePath, moduleName, expected, recordCheck)
    local source = readFile(HERE .. "/../" .. relativePath)
    local module, errors = doc.extract(source, relativePath, moduleName)
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#errors == 0)
    assert(module.text ~= "", moduleName .. " has no module documentation")

    local wanted = 0
    for _ in pairs(expected) do
        wanted = wanted + 1
    end
    assert(#module.items == wanted, moduleName .. " must document exactly its public surface")
    for _, item in ipairs(module.items) do
        local prefix = item.path
        local want = expected[item.name]
        assert(want, prefix .. " is not part of the public API")
        expected[item.name] = nil
        local kind = want == "record" and "record" or "function"
        assert(item.kind == kind, prefix .. " is not documented as a " .. kind)
        assert(item.doc.text ~= "", prefix .. " has no documentation")
        for _, param in ipairs(item.params) do
            assert(param.text ~= "", prefix .. " parameter " .. param.name .. " has no documentation")
        end
        for index, result in ipairs(item.returns) do
            assert(result.text ~= "", prefix .. " return " .. index .. " has no documentation")
        end
        if want == "raises" then
            assert(#item.raises > 0, prefix .. " has no documented failure condition")
        end
        if want == "record" and recordCheck then
            recordCheck(item)
        end
    end
    assert(next(expected) == nil, moduleName .. " is missing part of its public API")
end

function M.documentsACdefOnlyWhereItReachesAReader()
    local plumbing = table.concat(
        {
            "local m = {}",
            "",
            "--- Allocates.",
            "cdef function malloc(size: uint64): voidptr",
            "",
            "cdef struct Header",
            "   size: uint64",
            "end",
            "",
            "--- Reserves a block.",
            "function m.reserve(size: uint64): voidptr",
            "   return malloc(size)",
            "end",
            "",
            "return m",
        },
        "\n"
    )
    local module = assert(doc.extract(plumbing, "src/m.nupp", "m"))
    local listed = {}
    for _, item in ipairs(module.items) do
        listed[item.name] = item
    end
    assert(listed.reserve and listed.reserve.path == "m.reserve", "the module's own function must stay listed")
    assert(
        not listed["malloc"] and not listed["Header"],
        "a cdef this module only calls is not part of what it publishes"
    )
    local complete = assert(doc.extract(plumbing, "src/m.nupp", "m", {includePrivate = true}))
    local everything = {}
    for _, item in ipairs(complete.items) do
        everything[item.name] = true
    end
    assert(everything["malloc"] and everything["Header"], "--all must still show them")

    -- A generated binding module hands its declarations straight back, which is the
    -- one way a name bound by `cdef` reaches whoever requires the module.
    local bindings = table.concat(
        {
            "--- Absolute value.",
            "cdef function labs(n: int32): int32",
            "",
            "cdef struct Point",
            "   x: float",
            "end",
            "",
            "return { labs = labs, Point = Point }",
        },
        "\n"
    )
    local published = assert(doc.extract(bindings, "src/libm.nupp", "libm"))
    local exported = {}
    for _, item in ipairs(published.items) do
        exported[item.name] = item.kind
    end
    assert(exported["labs"] == "function", "a returned cdef function must document")
    assert(exported["Point"] == "struct", "a returned cdef struct must document")

    -- A declaration file states what exists elsewhere, so every cdef in one is the
    -- surface it was written to describe.
    local declared = assert(doc.extract(plumbing, "src/m.d.nupp", "m"))
    local stated = {}
    for _, item in ipairs(declared.items) do
        stated[item.name] = true
    end
    assert(stated["malloc"] and stated["Header"], "a declaration file publishes its cdefs")
end

function M.hidesPrivateMembersUnlessExplicitlyIncluded()
    local source = table.concat(
        {
            "record Public",
            "   visible: number",
            "   _secret: number",
            "   function _calculate(): number",
            "      return 1",
            "   end",
            "end",
        },
        "\n"
    )
    local public = assert(doc.extract(source, "src/public.nupp", "public"))
    local publicRecord
    for _, item in ipairs(public.items) do
        if item.name == "Public" then
            publicRecord = item
        end
    end
    assert(#publicRecord.members == 1, "private record members leaked")
    assert(publicRecord.members[1].name == "visible")
    local complete = assert(doc.extract(source, "src/public.nupp", "public", {includePrivate = true}))
    local completeRecord
    for _, item in ipairs(complete.items) do
        if item.name == "Public" then
            completeRecord = item
        end
    end
    assert(#completeRecord.members == 3, "private record members were not included")
end

function M.hidesPrivateMembersFromTheRenderedDeclaration()
    local source = table.concat(
        {
            "record Public",
            "   visible: number",
            "   --- The cached total.",
            "   _secret: number",
            "   function _calculate(): number",
            "      return 1",
            "   end",
            "   --- @internal",
            "   spare: number",
            "   record _Backing",
            "      slot: number",
            "   end",
            "   type _Key = string",
            "end",
        },
        "\n"
    )

    local function renderedNames(options)
        local module = assert(doc.extract(source, "src/public.nupp", "public", options))
        local names = {}
        for _, item in ipairs(module.items) do
            if item.name == "Public" then
                for _, member in ipairs(item.members) do
                    names[member.name] = true
                end
            end
        end

        return names
    end

    local public = renderedNames(nil)
    assert(public.visible, "an ordinary member was dropped")
    for _, hidden in ipairs({"_secret", "_calculate", "_Backing", "_Key", "spare"}) do
        assert(not public[hidden], hidden .. " leaked into the rendered declaration")
    end
    local complete = renderedNames({includePrivate = true})
    for _, shown in ipairs({"_secret", "_calculate", "_Backing", "_Key", "spare"}) do
        assert(complete[shown], "private docs lost " .. shown)
    end
end

function M.documentsMetamethodsDespiteTheirUnderscoredNames()
    local source = table.concat(
        {
            "--- A point.",
            "record Point",
            "   x: number",
            "   _scratch: number",
            "   --- Compares two points.",
            "   metamethod __eq: function(self, other: Point): boolean",
            "   --- @internal",
            "   metamethod __len: function(self): number",
            "end",
        },
        "\n"
    )
    local module = assert(doc.extract(source, "src/point.nupp", "point"))
    local record
    for _, item in ipairs(module.items) do
        if item.name == "Point" then
            record = item
        end
    end
    local byName = {}
    for _, member in ipairs(record.members) do
        byName[member.name] = member
    end
    assert(byName.x, "an ordinary field was dropped")
    assert(not byName._scratch, "a private field leaked")
    assert(byName.__eq, "a metamethod was hidden by the underscore rule")
    assert(byName.__eq.isMetamethod, "__eq was not marked as a metamethod")
    assert(byName.__eq.text == "Compares two points.", byName.__eq.text)
    assert(not byName.__len, "an @internal metamethod leaked")
    assert(record.signature == "record Point", record.signature)
end

function M.hidesModulesNamedInternal()
    local dir = tempProject({
        ["src/visible.nupp"] = "function visible(): number return 1 end\n",
        ["src/internal.nupp"] = "function secret(): number return 2 end\n",
        ["src/lib/internal/cache.nupp"] = "function cache(): number return 3 end\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "markdown", output = "public.md"}) == 0)
    local public = readFile(dir .. "/public.md")
    assert(public:find("# `visible`", 1, true), public)
    assert(not public:find("# `internal`", 1, true), public)
    assert(not public:find("# `lib.internal.cache`", 1, true), public)

    assert(
        doc.build(dir, config, {sources = {"src"}, includePrivate = true}, {
            format = "markdown",
            output = "complete.md"
        }) == 0
    )
    local complete = readFile(dir .. "/complete.md")
    assert(complete:find("# `internal`", 1, true), complete)
    assert(complete:find("# `lib.internal.cache`", 1, true), complete)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.hidesNamespacesNamedInternal()
    local source = table.concat(
        {
            "--- @namespace lib",
            "local lib: {",
            "   --- Rendering.",
            "   graphics: {",
            "      --- Draws a frame.",
            "      draw: function(): boolean",
            "   },",
            "   --- Implementation detail.",
            "   internal: {",
            "      --- Caches a result.",
            "      cache: function(): boolean",
            "   },",
            "}",
        },
        "\n"
    )
    local module, errors, extra = doc.extract(source, "src/lib.d.nupp", "lib")
    assert(module, errors and errors[1] and errors[1].msg)
    local byName = {}
    for _, mod in ipairs(extra or {}) do
        byName[mod.name] = mod
    end
    assert(byName["lib.graphics"], "a public namespace was dropped")
    assert(not byName["lib.internal"], "a namespace named internal leaked into public docs")

    local private, privateErrors, privateExtra = doc.extract(source, "src/lib.d.nupp", "lib", {includePrivate = true,})
    assert(private, privateErrors and privateErrors[1] and privateErrors[1].msg)
    local privateByName = {}
    for _, mod in ipairs(privateExtra or {}) do
        privateByName[mod.name] = mod
    end
    assert(privateByName["lib.internal"], "private docs must retain a namespace named internal")
end

function M.keepsMarkdownInsideDescriptionCells()
    local module = assert(
        doc.extract(
            table.concat(
                {
                    "--- Adds.",
                    "--- @param left The `left` value.",
                    "function add(left: number): number return left end",
                },
                "\n"
            ),
            "src/math.nupp",
            "math"
        )
    )
    local markdown = doc.markdown({module})
    assert(markdown:find(":   The `left` value.", 1, true), markdown)
end

function M.markdownMatchesTheNuppdocShape()
    local module = assert(doc.extract(SOURCE, "src/math.nupp", "math"))
    local markdown = doc.markdown({module}, "Example API")
    assert(markdown:find("# `math`", 1, true))
    assert(markdown:find("```nupp\nfunction(", 1, true))
    -- the declaration is the first thing under the member heading
    assert(
        markdown:find("```nupp\nfunction(left: number, right: number): number\n```\n\nArithmetic helpers.", 1, true),
        markdown
    )
    assert(markdown:find("#### Arguments", 1, true))
    assert(markdown:find("#### Type parameters", 1, true))
    assert(markdown:find('<a id="math.Point"></a>', 1, true))
end

function M.highlightsLjppWithTheNativeLexer()
    local html = doc.highlight(
        table.concat(
            {
                "--- Construct a point.",
                "local record Box",
                "   @readonly point: Point",
                "   @writeonly replacement: Point",
                "   point: Point",
                "end",
                "do",
                "   local box = openBox()",
                "   inspect(box)",
                "end",
                "local function make(point: Point): Point",
                "   return point ?? new Point(x = 1)",
                "end",
            },
            "\n"
        )
    )
    assert(html:find("nuppdoc-token-comment", 1, true))
    assert(html:find("nuppdoc-token-keyword", 1, true))
    assert(html:find("nuppdoc-token-function", 1, true))
    assert(html:find("nuppdoc-token-type", 1, true))
    assert(html:find("nuppdoc-token-number", 1, true))
    assert(html:find("nuppdoc-token-operator", 1, true))
    assert(html:find("keyword-record", 1, true), html)
    assert(html:find('nuppdoc-token-meta">readonly<', 1, true), html)
    assert(html:find('nuppdoc-token-meta">writeonly<', 1, true), html)
    assert(html:find("keyword-local", 1, true), html)
    assert(not html:find("<a ", 1, true), html)
end

function M.highlightsCurrentNuppSyntaxWithTheParser()
    assert(require("nupp.tools.syntaxstyle").spans("local =", "broken.nupp") == nil)
    local html = doc.highlight(
        table.concat(
            {
                "@!internal",
                "local interface Factory<P...>",
                "   constructor(self, ...: P...)",
                "   end",
                "   satisfies |self| -> self.ready",
                "end",
                "local function worker()",
                "   yields (number) resumes (boolean): const unknown & Serializable",
                "   return new Factory()",
                "end",
            },
            "\n"
        )
    )
    assert(html:find("nuppdoc-token-meta", 1, true), html)
    assert(html:find(">internal</span>", 1, true), html)
    assert(html:find("keyword-constructor", 1, true), html)
    assert(html:find("keyword-satisfies", 1, true), html)
    assert(html:find("keyword-yields", 1, true), html)
    assert(html:find("keyword-resumes", 1, true), html)
    assert(html:find("keyword-new", 1, true), html)
    assert(html:find("nuppdoc-token-type", 1, true), html)
end

function M.routedLinksLeaveCodeExamplesUntouched()
    local page = {source = "docs/start.md", path = "start", title = "Start"}
    local pages = {page, {source = "docs/guide.md", path = "guide", title = "Guide"},}
    local markdown = "[Guide](guide.md)\n[`Guide`](guide.md)\n`[Guide](guide.md)`\n```md\n[Guide](guide.md)\n```\n"
    local rewritten = urls.rewriteConfiguredPageLinks(markdown, page, pages, "start/index.html")
    assert(rewritten:find("[Guide](../guide/index.html)", 1, true), rewritten)
    assert(rewritten:find("[`Guide`](../guide/index.html)", 1, true), rewritten)
    assert(rewritten:find("`[Guide](guide.md)`", 1, true), rewritten)
    assert(rewritten:find("```md\n[Guide](guide.md)\n```", 1, true), rewritten)
end

function M.generatedApiPointersResolveWithoutInventingASourceFile()
    local page = {source = "docs/learn/language/annotations.md", path = "learn/language/annotations"}
    local pages = {page, {path = "api", title = "API reference", api = true}}
    local markdown = "[`@aot`](../../api.md#annotation-aot)"
    local rewritten = urls.rewriteConfiguredPageLinks(markdown, page, pages, "learn/language/annotations/index.html")
    assert(rewritten == "[`@aot`](../../../api/index.html#annotation-aot)", rewritten)
    assert(not pages[2].source, "a generated API pointer pretended to be a handwritten file")
end

function M.highlightsAssociatedTypeAndDirectiveKeywordsWithTheParser()
    local html = doc.highlight(
        table.concat(
            {
                "interface Matcher",
                "    associated type Result = R",
                "end",
                "local compiled = comptime do return 1 end",
                "@nosuspend do end",
            },
            "\n"
        )
    )
    assert(html:find("keyword-associated", 1, true), html)
    assert(html:find("keyword-type", 1, true), html)
    -- `comptime`/`@nosuspend` get the directive colour, not the ordinary keyword one.
    assert(html:find('class="token directive nuppdoc-token-meta">comptime<', 1, true), html)
    assert(
        html:find(
            'class="token directive nuppdoc-token-meta">@</span><span class="token directive nuppdoc-token-meta">nosuspend<',
            1,
            true
        ),
        html
    )
    assert(not html:find("keyword-comptime", 1, true), html)
    assert(not html:find("keyword-nosuspend", 1, true), html)
end

function M.codeExamplesStayHighlightedWithoutAutomaticLinks()
    local markdown = table.concat({"```nupp", "local item: Widget = createWidget()", "```", "", "[](Widget)",}, "\n")
    local html = require("nupp.tools.doc.html").markdownHtml(markdown, {Widget = "#widget", createWidget = "#create"})
    local code = assert(html:match("<pre>(.-)</pre>"), html)
    assert(code:find("nuppdoc-token-", 1, true), code)
    assert(not code:find("<a ", 1, true), code)
    assert(html:find('href="#widget"', 1, true), "explicit symbol link is missing")

    local details = require(
        "nupp.tools.doc.html"
    ).markdownHtml("#### Arguments\n\n`item` - `Widget`\n:   a widget\n", {Widget = "#widget"}, 0, "example")
    local term = assert(details:match("<dt>(.-)</dt>"), details)
    assert(term:find("nuppdoc-token-", 1, true), term)
    assert(not term:find("<a ", 1, true), term)
end

function M.scintilluaLexerUnderstandsCurrentNuppSyntax()
    local root = HERE .. "/.."
    highlight.configureScintillua(root, {lexers = "docs/lexers"})
    local html = assert(
        highlight.scintilluaSource(
            table.concat(
                {
                    "@!internal",
                    "local type Events<T> = {@readonly [K in keyof T as `${K}Changed`]: @nosuspend function(value: T.[K]): nil}",
                    "local type Writable<T> = {@writeonly [K in writekeyof T]: writeof T.[K]}",
                    "local type First<T> = T.[1]",
                    "local function worker<P..., const Format: string>(...: unpackof Arguments<Format>)",
                    "   yields (number) resumes (boolean): unpackof Results<Format>",
                    "   return new Factory(count = 1_000)",
                    "end",
                    "local function preserve(scoped callback: function(): nil, takes value: affine(voidptr)): voidptr preserves value return value end",
                    "local compiled = comptime do return {answer = 42} end",
                    "@nosuspend do end",
                    "do local installation = coroutine.sus.host.install(cancel) ; cancel() end",
                    "local with = 1; print(with)",
                    "local sealed interface Token end",
                    "interface Matcher",
                    "    associated type Result = R",
                    "end",
                },
                "\n"
            ),
            "nupp"
        )
    )
    assert(html:find("nuppdoc-token-meta", 1, true), html)
    for _, keyword in ipairs({"keyof", "preserves", "scoped", "unpackof", "writekeyof", "writeof", "sealed",}) do
        assert(html:find("keyword-" .. keyword, 1, true), html)
    end
    assert(not html:find("keyword-with", 1, true), html)
    assert(html:find("keyword-yields", 1, true), html)
    assert(html:find("keyword-resumes", 1, true), html)
    assert(html:find("keyword-new", 1, true), html)
    assert(html:find("keyword-associated-type", 1, true), html)
    assert(html:find("nuppdoc-token-type", 1, true), html)
    assert(html:find("nuppdoc-token-number", 1, true), html)
    -- `comptime`/`@nosuspend` get the directive colour, not the ordinary keyword one.
    assert(html:find('class="token directive nuppdoc-token-meta">comptime<', 1, true), html)
    assert(html:find('class="token directive nuppdoc-token-meta">@nosuspend<', 1, true), html)
end

-- Without a manifest the command falls back to documenting ".", which drags
-- in every checkout, cache and worktree the project happens to contain.
-- `local` in a .d.nupp is not privacy: the prelude's bindings become globals
-- and a bundled module's locals are what it returns, so the file is public
-- surface throughout. An ordinary module keeps the opposite default.
function M.documentsDeclarationFilesWithoutAskingForEverything()
    local declarations = table.concat(
        {
            "--- The shared limit.",
            "--- @return The limit.",
            "local limit: function(): number",
            "",
            "--- An implementation detail.",
            "--- @local",
            "local hidden: function(): number",
        },
        "\n"
    ) .. "\n"
    local module = assert(doc.extract(declarations, "src/lib.d.nupp", "lib"))
    local names = {}
    for _, item in ipairs(module.items) do
        names[item.name] = true
    end
    assert(names.limit, "a declaration file must document without --include-private")
    assert(not names.hidden, "@local must still opt a declaration out")
    local plain = assert(doc.extract(declarations, "src/lib.nupp", "lib"))
    assert(#plain.items == 0, "an ordinary module must keep its locals private")
end

function M.documentsTheProjectSourcesRatherThanTheWholeTree()
    local dir = tempProject({
        ["nupp.lua"] = "return { include = {\"src\"} }\n",
        ["src/math.nupp"] = SOURCE,
        ["src/.worktree/copy.nupp"] = "--- A hidden copy.\nfunction copied(): number return 1 end\n",
        ["scratch/extra.nupp"] = "--- Outside the include list.\nfunction extra(): number return 2 end\n",
    })
    local output = capture(("cd '%s' && '%s' doc --kind markdown -o api.md"):format(dir, NUPP))
    assert(output == "", output)
    local api = readFile(dir .. "/api.md")
    assert(api:find("# `math`", 1, true), api)
    assert(not api:find("copied", 1, true), "documented a hidden directory")
    assert(not api:find("extra", 1, true), "documented outside the include list")
    os.execute("rm -rf '" .. dir .. "'")
end

-- `scope:spawn(arguments..., f)` is what a caller writes, and the compiler rotates it
-- into the declaration's callable-first order. The reference prints the call.
function M.literalComptimeShapesDocumentTheirActualMemberTypes()
    local source = [[
module contract
const types = require("types")
@comptime
local function Handle(F: type): type
    if types.kind(F) ~= "function" then
        return types.error("a handle needs a function")
    end
    return types.shape({
        --- Returns the complete body result pack.
        {name = "await", read = types.functiontype(types.pack({types.any}), types.results(F))},
        {name = "done", read = types.functiontype(types.pack({types.any}), types.pack({types.bool}))},
        {name = "label", read = types.literal("types.Reader")},
    })
end
export type Task<G> = Handle(G)
]]
    local module = assert(doc.extract(source, "src/contract.nupp", "contract"))
    local task = assert(module.items[1])
    local members = {}
    for _, member in ipairs(task.members) do
        members[member.name] = member
    end
    assert(members.await and members.await.isFunction, "the actual shape declares await")
    assert(members.await.type == "function(any): unpackof types.results(G)", members.await.type)
    assert(members.await.returns[1].type == "unpackof types.results(G)")
    assert(members.await.text == "Returns the complete body result pack.")
    assert(members.done.returns[1].type == "boolean", members.done.type)
    assert(members.label.type == '"types.Reader"', members.label.type)

    for _, unknown in ipairs({
        source:gsub("types.shape%({", "types.shape(descriptors or {", 1),
        source:gsub('require%("types"%)', 'require("other")', 1),
        source:gsub("local function Handle%(F: type%)", "local function Handle(F: type, types: table)", 1),
        source:gsub("return types.shape", "F = types.integer\n    return types.shape", 1),
        source:gsub("return types.shape", "local F = types.integer\n    return types.shape", 1),
        source:gsub("return types.shape", "types.shape = other\n    return types.shape", 1),
        source:gsub("return types.shape", 'types["functiontype"] = other\n    return types.shape', 1),
        source:gsub("@comptime\n", "types.shape = other\n@comptime\n", 1),
        (source:gsub("@comptime\n", "", 1)),
    }) do
        local opaque = assert(doc.extract(unknown, "src/contract.nupp", "contract"))
        assert(#opaque.items[1].members == 0, "unknown or shadowed builders stay opaque")
    end
end

function M.coroutineWorkerDocsRetainScopesAndTaskResultPacks()
    local dir = tempProject({["nupp.lua"] = "return {}\n"})
    local root = HERE .. "/.."
    local ok, problem = doc.build(
        root,
        {include = {"src"}},
        {
            sources = {
                "src/nupp/tasks.nupp",
                "src/nupp/workers/spi.nupp",
                "src/nupp/runtime/standardcoroutine.nupp",
                "src/coroutine/workers/init.nupp",
            },
        },
        {format = "json", output = dir .. "/api.json"}
    )
    assert(ok == 0, tostring(problem))
    local json = require("serde.json")
    local model = assert(json.decodevalue(readFile(dir .. "/api.json")))
    local modules = {}
    for _, module in ipairs(model.modules) do
        modules[module.name] = module
    end
    local items = {}
    for _, item in ipairs(assert(modules.coroutine).items) do
        items[item.name] = item
    end
    local scope = {}
    for _, member in ipairs(assert(items.Scope).members) do
        scope[member.name] = member
    end
    assert(scope.work and scope.spawn and scope.cancel and scope.close, "scope owns worker creation and settlement")
    assert(not scope.fork, "the preceding public worker-creation name is absent")
    local task = {}
    for _, member in ipairs(assert(items.Task).members) do
        task[member.name] = member
    end
    assert(task.await and task.isdone and task.status and task.cancel, "task methods come from the actual type builder")
    assert(task.await.type:find("unpackof types.results(F)", 1, true), task.await.type)
    assert(task.status.type:find('"cancelled"', 1, true), task.status.type)
    assert(modules["coroutine.workers"].text:find("coroutine.Scope.work", 1, true))
    assert(modules["coroutine.workers"].text:find("coroutine.Task", 1, true))
    assert(not modules["nupp.tasks"] and not modules["nupp.workers.spi"], "implementation modules stay private")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.reloadDocsDescribeThePublicWatchBoundary()
    local page = assert(require("nupp.tools.doc.stdlib").page({path = "api"}))
    local reload, debugModule
    for _, module in ipairs(page.modules) do
        if module.name == "debug" then
            debugModule = module
        end
        if module.name == "debug.reload" then
            reload = module
        end
        assert(module.name ~= "nupp.hotreload", "the retired public route is absent")
    end
    assert(reload and #reload.items == 2, "reload publishes generation and poll")
    local names = {}
    for _, item in ipairs(reload.items) do
        names[item.name] = item.kind
    end
    assert(names.generation == "function" and names.poll == "function")
    local pollType
    for _, item in ipairs(assert(debugModule).items) do
        if item.path == "debug.ReloadPoll" then
            pollType = item
        end
    end
    assert(pollType and #pollType.members == 6, "the poll result has one documented public contract")
end

function M.aRotatedCallSurfaceIsPrintedInCallOrder()
    local path = HERE .. "/../src/nupp/tasks.nupp"
    local module = assert(doc.extract(readFile(path), path, "nupp.tasks"))
    local members = {}
    for _, item in ipairs(module.items) do
        for _, member in ipairs(item.members or {}) do
            members[member.path] = member
        end
    end
    local spawn = assert(members["nupp.tasks.Scope.spawn"], "Scope:spawn is documented")
    assert(
        spawn.type:find("(borrows self: nupp.tasks.Scope, ...: unpackof Parameters(F), takes body: F)", 1, true),
        "the body comes after its arguments: " .. spawn.type
    )
    assert(
        spawn.type:find("(borrows self: nupp.tasks.Scope, name: string, takes body: F)", 1, true),
        "and after the name in the named overload: " .. spawn.type
    )
    assert(spawn.params[#spawn.params].name == "body", "the parameter table follows the same order")
    local work = assert(members["nupp.tasks.Scope.work"], "Scope:work is documented")
    assert(work.type:find("Submitted(F), F)", 1, true), "work takes its callable last: " .. work.type)
    local cancel = assert(members["nupp.tasks.Scope.cancel"], "Scope:cancel is documented")
    assert(
        cancel.type:find("(borrows self: nupp.tasks.Scope, reason: string?)", 1, true),
        "an ordinary member keeps its order: " .. cancel.type
    )
end

-- What to produce is `--kind`, so every argument is a source path: a leading word
-- that happens to name a format is a path like any other.
function M.theKindIsAnOptionAndEveryArgumentIsAPath()
    local dir = tempProject({["nupp.lua"] = "return { include = {\"src\"} }\n", ["src/math.nupp"] = SOURCE})
    local output = capture(("cd '%s' && '%s' doc --kind json -o api.json src"):format(dir, NUPP))
    assert(output == "", output)
    assert(readFile(dir .. "/api.json"):find('"modules"', 1, true), "--kind json writes the JSON model")

    local function status(arguments)
        local pipe = assert(io.popen(("cd '%s' && '%s' doc %s 2>&1; echo rc=$?"):format(dir, NUPP, arguments)))
        local text = pipe:read("*a")
        pipe:close()
        return text
    end

    local positional = status("json -o other.json")
    assert(positional:find("rc=1", 1, true), "json is a source path now, and there is none: " .. positional)
    assert(positional:find("no source file or directory named json", 1, true), "and says so: " .. positional)
    assert(not io.open(dir .. "/other.json", "rb"), "and no document was written")
    local alias = status("--kind md -o api.md")
    assert(alias:find("rc=2", 1, true), "md is not a kind: " .. alias)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A manifest that is there and does not load is an error, as it is for every other
-- command, not the same thing as having none: read as absent, it documented the whole
-- tree under the wrong module names and exited 0.
function M.aManifestThatDoesNotLoadStopsTheRun()
    for _, manifest in ipairs({"return { include = { \"src\" }, build = 5\n", "return 5\n", "error('boom')\n",}) do
        local dir = tempProject({["nupp.lua"] = manifest, ["src/math.nupp"] = SOURCE})
        local pipe = assert(
            io.popen(("cd '%s' && '%s' doc --kind markdown -o api.md 2>&1; echo rc=$?"):format(dir, NUPP))
        )
        local output = pipe:read("*a")
        pipe:close()
        assert(output:find("rc=1", 1, true), manifest .. output)
        assert(output:find("nupp.lua", 1, true), output)
        assert(not output:find("nupp: nupp:", 1, true), output)
        assert(not io.open(dir .. "/api.md", "rb"), "a broken manifest still wrote documentation")
        os.execute("rm -rf '" .. dir .. "'")
    end
end

function M.hidesPrivateSourcePathsUnlessExplicitlyIncluded()
    local dir = tempProject({
        ["src/visible.nupp"] = "function visible(): number return 1 end\n",
        ["src/_hidden.nupp"] = "function hidden(): number return 2 end\n",
        ["src/internal/secret.nupp"] = "function secret(): number return 3 end\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "markdown", output = "public.md"}) == 0)
    local public = readFile(dir .. "/public.md")
    assert(public:find("# `visible`", 1, true), public)
    assert(not public:find("# `_hidden`", 1, true), public)
    assert(not public:find("# `internal.secret`", 1, true), public)

    assert(
        doc.build(dir, config, {sources = {"src"}, includePrivate = true}, {
            format = "markdown",
            output = "complete.md"
        }) == 0
    )
    local complete = readFile(dir .. "/complete.md")
    assert(complete:find("# `_hidden`", 1, true), complete)
    assert(complete:find("# `internal.secret`", 1, true), complete)
    os.execute("rm -rf '" .. dir .. "'")
end

-- `doc --all` selected unexported declarations while the manifest's
-- `includePrivate` selected internal modules, and neither reached the other.
-- One flag now covers both.
function M.includePrivateCoversUnexportedDeclarationsAndInternalModules()
    local dir = tempProject({
        ["nupp.lua"] = "return {include = {\"src\"}}\n",
        [
            "src/shown.nupp"
        ] = "module shown\nexport function visible(): number return 1 end\n"
        .. "local function unexported(): number return 2 end\n",
        ["src/internal/secret.nupp"] = "function secret(): number return 3 end\n",
    })
    local public = capture(("cd '%s' && '%s' doc --kind markdown -o public.md src"):format(dir, NUPP))
    local publicText = readFile(dir .. "/public.md")
    assert(publicText:find("visible", 1, true), public .. publicText)
    assert(not publicText:find("unexported", 1, true), publicText)
    assert(not publicText:find("internal.secret", 1, true), publicText)
    local complete = capture(
        ("cd '%s' && '%s' doc --kind markdown --include-private -o complete.md src"):format(dir, NUPP)
    )
    local completeText = readFile(dir .. "/complete.md")
    assert(completeText:find("unexported", 1, true), complete .. completeText)
    assert(completeText:find("internal.secret", 1, true), completeText)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.internalInitHidesItsDocumentationTree()
    local dir = tempProject({
        ["src/nupp/compiler/init.nupp"] = "@!internal\nreturn {}\n",
        ["src/nupp/compiler/syntax/parser.nupp"] = "function parse(): number return 1 end\n",
        ["src/public.nupp"] = "function visible(): number return 2 end\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "markdown", output = "public.md"}) == 0)
    local public = readFile(dir .. "/public.md")
    assert(public:find("# `public`", 1, true), public)
    assert(not public:find("# `nupp.compiler`", 1, true), public)
    assert(not public:find("# `nupp.compiler.syntax.parser`", 1, true), public)

    assert(
        doc.build(dir, config, {sources = {"src"}, includePrivate = true}, {
            format = "markdown",
            output = "complete.md"
        }) == 0
    )
    local complete = readFile(dir .. "/complete.md")
    assert(complete:find("# `nupp.compiler`", 1, true), complete)
    assert(complete:find("# `nupp.compiler.syntax.parser`", 1, true), complete)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.hoistsQualifiedTypesOutOfHiddenDeclarationModules()
    local dir = tempProject({
        [
            "src/nupp/init.nupp"
        ] = table.concat(
            {"--[[", "The public namespace.", "]]", "", "--- Makes a codec.", "function newJSON(): nupp.JSON end",},
            "\n"
        ) .. "\n",
        ["src/nupp/compiler/init.nupp"] = "@!internal\nreturn {}\n",
        [
            "src/nupp/compiler/prelude.d.nupp"
        ] = table.concat(
            {"--- One JSON codec.", "interface nupp.JSON", "   encode: function(value: any): string", "end",},
            "\n"
        ) .. "\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    local public = readFile(dir .. "/site/modules/nupp/index.html")
    assert(public:find('<section class="nuppdoc-api-item" id="nupp.JSON">', 1, true), public)
    assert(not public:find("nuppdoc-code-link", 1, true), "qualified return type was automatically linked")
    assert(
        not io.open(dir .. "/site/modules/nupp/compiler/prelude/index.html", "rb"),
        "the hidden declaration module was documented"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aNamingConventionIsNotAConstructor()
    -- Construction is `new`, and a `constructor` declaration documents inside the
    -- record it belongs to. A module function is a function whatever it is named,
    -- so nothing reads `newEngine` as a kind of its own.
    local files = {
        [
            "src/engine.nupp"
        ] = table.concat(
            {
                "--[[",
                "The engine.",
                "]]",
                "",
                "--- Starts one.",
                "function newEngine(): nil end",
                "",
                "--- Builds one.",
                "function makeEngine(): nil end",
            },
            "\n"
        ) .. "\n",
    }
    local dir = tempProject(files)
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    local page = readFile(dir .. "/site/modules/engine/index.html")
    local markdown = readFile(dir .. "/site/modules/engine.md")
    os.execute("rm -rf '" .. dir .. "'")

    assert(not page:find("Constructors", 1, true), page)
    assert(not markdown:find("Constructors", 1, true), markdown)
    assert(not page:find("nuppdoc-kind-constructor", 1, true), page)
    local functionsAt = assert(page:find('<h2 id="functions">Functions', 1, true))
    assert(page:find('id="engine.newEngine"><h3>', functionsAt, true), page)
    assert(page:find('id="engine.makeEngine"><h3>', functionsAt, true), page)
    assert(markdown:find("### `newEngine` _function_", 1, true), markdown)
    assert(markdown:find("### `makeEngine` _function_", 1, true), markdown)
end

function M.markdownLinksNestedModulesAndReferences()
    local dir = tempProject({
        [
            "src/engine/init.nupp"
        ] = table.concat(
            {
                "--[[",
                "The engine. Sound comes out of [](engine.audio), and a run holds one",
                "[](engine.Engine).",
                "]]",
                "",
                "--- Starts the engine.",
                "function start(): nil end",
                "",
                "--- A running engine.",
                "record Engine",
                "   running: boolean",
                "end",
            },
            "\n"
        ) .. "\n",
        ["src/engine/audio.nupp"] = "--[[\nAudio helpers.\n]]\nfunction play(): nil end\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    -- one document holds every module, so every reference in it resolves
    assert(api:find('<a id="engine"></a>', 1, true), api)
    assert(api:find("**submodules**", 1, true), api)
    assert(
        assert(api:find("**functions**", 1, true)) < assert(api:find("**submodules**", 1, true)),
        "functions must precede submodules in the module overview"
    )
    assert(api:find("[`audio`](#engine.audio)", 1, true), api)
    assert(api:find("[`engine.audio`](#engine.audio), and a run holds one", 1, true), api)
    assert(api:find("[`engine.Engine`](#engine.Engine)", 1, true), api)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.namespaceBackedDeclarationsBelongOnlyToTheirSubmodule()
    local dir = tempProject({
        [
            "src/nupp.nupp"
        ] = table.concat(
            {
                "--- @namespace nupp",
                "--- @export",
                "local nupp: {",
                "   --- Widget construction.",
                "   --- @namespace",
                "   widgets: nupp.widgets",
                "}",
                "",
                "--- Constructs widgets.",
                "record nupp.widgets",
                "   --- Selects the widget size.",
                "   type Mode = 'small' | 'large'",
                "",
                "   --- Constructs a widget.",
                "   create: function(source: string): nupp.widgets.Widget<any>",
                "",
                "   --- A configured widget.",
                "   record Widget<T>",
                "      --- Reads a value.",
                "      read: function(self, subject: string): T?",
                "   end",
                "end",
            },
            "\n"
        ) .. "\n",
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    local nestedAt = assert(api:find('<a id="nupp.widgets"></a>', 1, true), api)
    local parent = api:sub(1, nestedAt - 1)
    local nested = api:sub(nestedAt)
    assert(parent:find("**submodules**", 1, true), parent)
    assert(parent:find("[`widgets`](#nupp.widgets)", 1, true), parent)
    assert(not parent:find("### `widgets` _record_", 1, true), parent)
    assert(not parent:find("record nupp.widgets", 1, true), parent)
    assert(nested:find("Constructs widgets%."), nested)
    assert(nested:find("### `Mode` _type_", 1, true), nested)
    assert(nested:find("### `Widget` _record_", 1, true), nested)
    assert(nested:find("### `create` _function_", 1, true), nested)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aNamespaceAndTheModuleImplementingItShareOnePage()
    local dir = tempProject({
        [
            "src/types.nupp"
        ] = table.concat(
            {
                "--- @namespace types",
                "--- @export",
                "local types: {",
                "   --- Generates checked members on a declaration.",
                "   --- @namespace",
                "   derive: types.derive",
                "}",
                "",
                "record types.derive",
                "   --- Declares what a provider generates.",
                "   implement: function(): boolean",
                "",
                "   --- Renders the declaration fields.",
                "   Debug: function(): boolean",
                "end",
            },
            "\n"
        ) .. "\n",
        [
            "src/types/derive.nupp"
        ] = table.concat(
            {
                "local derive = {}",
                "",
                "function derive.Debug(): boolean",
                "   return true",
                "end",
                "",
                "return derive",
            },
            "\n"
        ) .. "\n",
    })
    local config, settings = {include = {"src"}}, {sources = {"src"}}
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)
    local page = readFile(dir .. "/site/modules/types/derive/index.html")
    assert(page:find("Generates checked members on a declaration%."), page)
    assert(page:find('id="types.derive.implement"', 1, true), page)
    local _, anchors = page:gsub('id="types%.derive%.Debug"', "")
    assert(anchors == 1, page)
    assert(page:find("Renders the declaration fields%."), page)
    assert(doc.build(dir, config, settings, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    local _, sections = api:gsub('<a id="types%.derive"></a>', "")
    assert(sections == 1, api)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.docsBuildTargetWritesSiteAndMarkdown()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {
   include = {"src"},
   build = {default = "docs", targets = {
      docs = {kind = "docs", sources = {"src"}, format = "both",
         outDir = "site", title = "Example API"},
   }},
}
]],
        ["src/math.nupp"] = SOURCE,
    })
    local checked = capture(("cd '%s' && '%s' check --target docs"):format(dir, NUPP))
    assert(checked == "", checked)
    assert(not io.open(dir .. "/site/index.html", "rb"), "checking a docs target must not write output")
    local output = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
    assert(output == "", output)
    local html = readFile(dir .. "/site/modules/math/index.html")
    assert(html:find("nuppdoc%-shell"), "Nuppdoc layout class missing")
    assert(html:find('<span class="nuppdoc-mark">++</span>', 1, true), "default header mark missing")
    assert(html:find('id="math.add"', 1, true), "API anchor missing")
    assert(html:find('<a href="../guide.html">guide</a>', 1, true), "Markdown link missing")
    assert(html:find("nuppdoc-token-keyword", 1, true), "NUPP syntax highlighting missing")
    assert(readFile(dir .. "/site/api.md"):find("# `math`", 1, true))
    assert(readFile(dir .. "/site/assets/style.css"):find("%-%-nuppdoc%-dark%-accent"), "Nuppdoc theme tokens missing")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.jsonDocumentationExposesTheParseOnlyModel()
    local json = require("testjson")
    local dir = tempProject({["src/math.nupp"] = SOURCE})
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = json.decode(readFile(dir .. "/api.json"))
    assert(model.schemaVersion == 3, "documentation model version missing")
    assert(model.modules[1].name == "math", "module name missing from JSON model")
    assert(model.modules[1].items[1].name == "add", "declaration missing from JSON model")
    assert(model.modules[1].items[1].params[1].name == "left", "parameter missing from JSON model")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A manifest's outDir says where its own format goes. Asking for another format
-- used to write there anyway, so `nupp doc json` wrote one file over the site
-- directory and the next docs build could not recreate it.
function M.anotherFormatDoesNotWriteOverTheConfiguredSite()
    local dir = tempProject({["src/math.nupp"] = SOURCE})
    local settings = {sources = {"src"}, format = "site", outDir = "site"}
    assert(doc.build(dir, {include = {"src"}}, settings, {}) == 0)
    assert(readFile(dir .. "/site/index.html"), "the configured site was not written")
    assert(doc.build(dir, {include = {"src"}}, settings, {format = "json"}) == 0)
    assert(readFile(dir .. "/build/docs.json"), "json did not go to its own default")
    assert(readFile(dir .. "/site/index.html"), "json replaced the configured site")
    os.execute("rm -rf '" .. dir .. "'")
end

local ALIASED_PHASES = table.concat(
    {
        "module game.internal.phases",
        "",
        "--[[",
        "The frame order.",
        "]]",
        "",
        "--- A phase name.",
        "export type Phase = string",
        "",
        "--- Names the first phase.",
        "export const First: Phase = \"First\"",
        "",
        "--- Returns a phase by its position.",
        "--- @param index the one-based position",
        "--- @return the phase, or nil past the last one",
        "export function at(index: integer): Phase?",
        "   if index == 1 then",
        "      return First",
        "   end",
        "",
        "   return nil",
        "end",
    },
    "\n"
) .. "\n"

local function aliasModel(files)
    local json = require("testjson")
    local dir = tempProject(files)
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = json.decode(readFile(dir .. "/api.json"))
    os.execute("rm -rf '" .. dir .. "'")
    local byName = {}
    for _, module in ipairs(model.modules) do
        byName[module.name] = module
    end

    return byName
end

-- `export const phases = phasevalues` publishes `game.phases.First`, which the checker
-- resolves and a parse of the aliasing file alone cannot describe. The values behind
-- the name have to reach the reader through it, because the module they are written in
-- is internal and has no page.
function M.aModuleAliasConstDocumentsTheNamespaceItPublishes()
    local byName = aliasModel({
        ["src/game/internal/phases.nupp"] = ALIASED_PHASES,
        [
            "src/game/init.nupp"
        ] = table.concat(
            {
                "module game",
                "",
                'local phasevalues = require("game.internal.phases")',
                "",
                "--- A frame phase.",
                "export type Phase = phasevalues.Phase",
                "",
                "--- The ordered frame phase constants.",
                "export const phases = phasevalues",
            },
            "\n"
        ) .. "\n",
    })
    assert(byName["game"], "the aliasing module is missing")
    assert(not byName["game.internal.phases"], "an internal module must stay off the site")
    for _, item in ipairs(byName["game"].items) do
        assert(item.name ~= "phases", "the bare alias declaration outlived the module it published")
    end
    local namespace = byName["game.phases"]
    assert(namespace, "the alias published no module")
    assert(namespace.text == "The ordered frame phase constants.", namespace.text)
    local byItem = {}
    for _, item in ipairs(namespace.items) do
        byItem[item.name] = item
    end
    assert(byItem.First and byItem.First.kind == "variable", "an aliased constant is missing")
    assert(byItem.First.doc.text == "Names the first phase.", "an aliased constant lost its documentation")
    assert(byItem.at and byItem.at.kind == "function", "an aliased function is missing")
    assert(byItem.at.params[1].name == "index", "an aliased function lost its parameters")
    -- A value binding carries no types, so `game.phases.Phase` is a spelling the
    -- checker rejects. The type the module means to re-export is its own `export type`
    -- alias.
    assert(not byItem.Phase, "a type reached the page through a value binding")
    local aliasedType = nil
    for _, item in ipairs(byName["game"].items) do
        if item.name == "Phase" then
            aliasedType = item
        end
    end
    assert(aliasedType and aliasedType.kind == "type", "the exported type alias is missing")
end

function M.privateExportTablesDoNotPublishTypesOnMatchingPublicRoots()
    local byName = aliasModel({
        [
            "src/widget/init.nupp"
        ] = [[
module widget
local model = require("widget.internal.model")
--- A visible value.
export type Value = model.Value
]],
        [
            "src/widget/internal/model.nupp"
        ] = [[
@!internal
module widget.internal.model
local widget = {}
--- A value shared with the public facade.
record widget.Value
    --- The stored number.
    count: integer
end
--- A provider-only handle.
record widget.Hidden
    --- The private integration hook.
    integration: function(): nil
end
export = widget
]],
    })
    local module = assert(byName.widget, "the public facade is missing")
    assert(not byName["widget.internal.model"], "the private implementation has a public page")
    assert(#module.items == 1, "a matching local table published private declarations")
    local value = module.items[1]
    assert(value.name == "Value" and value.path == "widget.Value", "the explicit alias is missing")
    assert(#value.members == 1 and value.members[1].name == "count", "the explicit alias lost its contract")
end

-- An aliased module the site already shows keeps its one page. The declaration says
-- what it holds by naming it, which the symbol index links, rather than by being
-- copied.
function M.aModuleAliasNamesATargetTheSiteAlreadyDocuments()
    local byName = aliasModel({
        [
            "src/game/phasevalues.nupp"
        ] = ALIASED_PHASES:gsub("module game%.internal%.phases", "module game.phasevalues", 1),
        [
            "src/game/init.nupp"
        ] = table.concat(
            {
                "module game",
                "",
                'local phasevalues = require("game.phasevalues")',
                "",
                "--- The ordered frame phase constants.",
                "export const phases = phasevalues",
            },
            "\n"
        ) .. "\n",
    })
    assert(byName["game.phasevalues"], "the aliased module lost its own page")
    assert(not byName["game.phases"], "a documented module was copied onto a second page")
    local alias = nil
    for _, item in ipairs(byName["game"].items) do
        if item.name == "phases" then
            alias = item
        end
    end
    assert(alias, "the alias declaration is missing")
    assert(alias.signature == "const phases = game.phasevalues", alias.signature)
end

function M.aPageDirectoryPublishesEveryDocumentAndGeneratesItsIndex()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        [
            "docs/adrs/index.md"
        ] = table.concat(
            {"---", 'title: "ADR 0: Index"', "---", "", "# ADR 0: Index", "", "Why things are the way they are.",},
            "\n"
        ) .. "\n",
        [
            "docs/adrs/0001-process.md"
        ] = table.concat(
            {
                "---",
                "title: Proposal process",
                "status: Active",
                "created: 2026-08-19",
                "---",
                "",
                "## Summary",
                "",
                "How to write one. See [the other](0002-widgets.md).",
            },
            "\n"
        ) .. "\n",
        -- Written second and numbered second, and never named anywhere but here:
        -- a document is published by existing, which is the whole point of a
        -- directory entry over a list of pages.
        [
            "docs/adrs/0002-widgets.md"
        ] = table.concat(
            {"---", "title: Widgets", "status: Draft", "---", "", "## Summary", "", "Widgets.",},
            "\n"
        ) .. "\n",
    })
    local config = {include = {"src"}}
    local settings = {sources = {"src"}, pages = {{path = "adrs", title = "ADRs", directory = "docs/adrs"},}}
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    local index = readFile(dir .. "/site/adrs/index.html")
    assert(index:find("Why things are the way they are.", 1, true), "the index lost the prose it was written with")
    assert(
        index:find('<a href="../adrs/0001-process/index.html">Proposal process</a>', 1, true),
        "the generated index did not list and link a document"
    )
    assert(index:find(">Widgets</a>", 1, true), "a document nothing named was left out of the index")
    assert(index:find(">Draft<", 1, true), "the index lost a status")
    assert(
        not index:find("0002-widgets/index.html\">Widgets</a></li>", 1, true),
        "a collection document was listed in the sidebar beside its index"
    )

    local first = readFile(dir .. "/site/adrs/0001-process/index.html")
    assert(first:find(">ADR 1: Proposal process<", 1, true), "the number and title were not generated into the heading")
    assert(first:find("Status:", 1, true) and first:find("Active", 1, true), "the frontmatter status was not rendered")
    assert(
        first:find('href="../../adrs/0002-widgets/index.html"', 1, true),
        "a link between two documents was not rewritten to its route"
    )
    assert(not first:find("title: Proposal process", 1, true), "the frontmatter block was rendered as prose")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A tree of pages, published by being written rather than by being listed. The
-- manifest names the pattern; every route, title, and place in the navigation is
-- the file's own, which is what keeps a page added on a Tuesday from being a page
-- the site quietly never shows.
function M.aPageTreePublishesEveryFileAtTheRouteItSitsAt()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        ["docs/index.md"] = "---\norder: 0\n---\n\n# Welcome\n\nThe front page.\n",
        [
            "docs/guides/build.md"
        ] = table.concat(
            {
                "---",
                "order: 20",
                "title: Build system",
                "redirects: guides/building",
                "---",
                "",
                "# Project builds",
                "",
                "See [the tour](../tour.md).",
            },
            "\n"
        ) .. "\n",
        -- No order, so it follows the pages that name one.
        ["docs/guides/zzz.md"] = "# Last of all\n",
        ["docs/tour.md"] = "---\norder: 10\n---\n\n# Tour\n",
        -- Written for whoever writes the docs, and excluded by the entry.
        ["docs/style.md"] = "# House style\n",
    })
    local config = {include = {"src"}}
    local settings = {sources = {"src"}, pages = {{glob = "docs/**.md", exclude = {"docs/style.md"}},}}
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    local home = readFile(dir .. "/site/index.html")
    assert(home:find("The front page.", 1, true), "index.md is the route the tree is named from")
    local build = readFile(dir .. "/site/guides/build/index.html")
    assert(build:find("Project builds", 1, true), "a page publishes at the path it sits at")
    assert(
        build:find('href="../../tour/index.html"', 1, true),
        "a relative link between two swept pages resolves to a route"
    )
    assert(not io.open(dir .. "/site/style/index.html", "rb"), "an excluded file was published anyway")
    local moved = readFile(dir .. "/site/guides/building/index.html")
    assert(moved:find("guides/build/index.html", 1, true), "a frontmatter redirect left no stub: " .. moved)

    -- Navigation is `order`, and a page that names none follows the ones that do.
    -- The sidebar titles a page by its frontmatter where it has one, and by its
    -- heading where it does not.
    local sidebar = build:match('<aside class="nuppdoc%-sidebar".-</aside>')
    assert(sidebar, "the page has a sidebar")
    assert(sidebar:find(">Build system<", 1, true), "frontmatter titles the navigation entry: " .. sidebar)
    assert(not sidebar:find(">Project builds<", 1, true), "the heading titled it anyway: " .. sidebar)
    assert(
        sidebar:find(">Build system<", 1, true) < sidebar:find(">Last of all<", 1, true),
        "an unordered page came before an ordered one"
    )
    local tour = readFile(dir .. "/site/tour/index.html")
    assert(
        tour:find("Next", 1, true) and tour:find("Build system", 1, true),
        "the page order follows `order` rather than the directory listing"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- A collection is a tree the manifest already publishes another way, and a sweep
-- over the directory holding it must not publish every document a second time at
-- a route of its own.
function M.aPageTreeLeavesACollectionToItsOwnEntry()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        ["docs/index.md"] = "# Welcome\n",
        ["docs/adrs/index.md"] = "# Proposals\n",
        ["docs/adrs/0001-process.md"] = "---\ntitle: Process\n---\n\n## Summary\n",
    })
    local config = {include = {"src"}}
    local settings = {
        sources = {"src"},
        pages = {{glob = "docs/**.md"}, {path = "reference/adrs", title = "ADRs", directory = "docs/adrs"},}
    }
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    assert(
        io.open(dir .. "/site/reference/adrs/0001-process/index.html", "rb"),
        "the collection publishes its documents"
    )
        :close()
    assert(
        not io.open(dir .. "/site/adrs/0001-process/index.html", "rb"),
        "the sweep published a collection document a second time"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

-- A directory names a sidebar section and a page inside it is a link in that
-- section. The page's own last path segment names the page, so a directory of
-- four guides must not read as four sections holding one link each -- which is
-- what it read as while every segment of a route opened a section of its own.
function M.aPageTreeSectionsDirectoriesRatherThanPages()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        ["docs/index.md"] = "# Welcome\n",
        ["docs/getting-started/installation.md"] = "---\norder: 10\n---\n\n# Installation\n",
        ["docs/getting-started/tour.md"] = "---\norder: 20\n---\n\n# Tour\n",
        ["docs/guides/integrations/index.md"] = "---\norder: 30\n---\n\n# Integrations\n",
        ["docs/guides/integrations/love.md"] = "---\norder: 40\n---\n\n# LOVE\n",
    })
    local config = {include = {"src"}}
    local settings = {sources = {"src"}, pages = {{glob = "docs/**.md"}}}
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    local page = readFile(dir .. "/site/getting-started/tour/index.html")
    local sidebar = assert(page:match('<aside class="nuppdoc%-sidebar".-</aside>'), "the page has a sidebar")
    assert(
        sidebar:find("<summary>Getting started</summary>", 1, true),
        "a directory did not name a section: " .. sidebar
    )
    assert(not sidebar:find("<summary>Tour</summary>", 1, true), "a page opened a section of its own: " .. sidebar)
    assert(
        not sidebar:find("<summary>Installation</summary>", 1, true),
        "a page opened a section of its own: " .. sidebar
    )
    assert(
        sidebar:find(">Installation</a>", 1, true) and sidebar:find(">Tour</a>", 1, true),
        "the directory's pages are links in its section: " .. sidebar
    )

    -- A directory holding other pages still names a section, and its own index is
    -- what that name links to rather than an entry repeated inside it.
    local nested = assert(sidebar:match("<summary>Guides</summary>.*"), sidebar)
    assert(
        nested:find('<summary class="nuppdoc-sidebar-section-link">', 1, true),
        "a directory below a directory lost its section: " .. sidebar
    )
    assert(
        nested:find(">Integrations</a>", 1, true) < nested:find(">LOVE</a>", 1, true),
        "the section is not named by its own page: " .. sidebar
    )
    assert(
        select(2, nested:gsub(">Integrations</a>", "")) == 1,
        "the section index was repeated as an entry inside it: " .. sidebar
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.siteBuildRemovesFilesItNoLongerProduces()
    local dir = tempProject({["src/math.nupp"] = SOURCE, ["docs/guide.md"] = "# Guide\n",})
    local config = {include = {"src"}}
    local first = {sources = {"src"}, pages = {{path = "guide/old", title = "Old guide", source = "docs/guide.md"},}}
    assert(doc.build(dir, config, first, {format = "site", output = "site"}) == 0)
    -- Closed explicitly: Windows refuses to delete a file a handle is still open on,
    -- and an unclosed one here would still be waiting on the garbage collector when
    -- the next build tries to remove this exact file below.
    local firstRoute = assert(io.open(dir .. "/site/guide/old/index.html", "rb"), "first route missing")
    firstRoute:close()

    assert(doc.build(dir, config, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    assert(
        not io.open(dir .. "/site/guide/old/index.html", "rb"),
        "a route omitted by the next successful build survived"
    )
    assert(not io.open(dir .. "/site/guide/old", "rb"), "the empty route directory survived")
    local currentOutput = assert(
        io.open(dir .. "/site/modules/math/index.html", "rb"),
        "the new site lost a current output"
    )
    currentOutput:close()
    os.execute("rm -rf '" .. dir .. "'")
end

-- The record of the last build's files is read back from the output directory, which
-- may have been committed or unpacked from somewhere else. Only its entries strictly
-- below the output are the site's to remove: not a sibling, not a directory whose name
-- merely starts with the output's, and not one that climbs back out through `..`.
function M.siteRemovalStaysInsideItsOutputDirectory()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        ["victim.txt"] = "SENTINEL\n",
        ["site2/victim.txt"] = "SENTINEL\n",
        ["site/keep/victim.txt"] = "SENTINEL\n",
    })
    local config = {include = {"src"}}
    local record = assert(io.open(dir .. "/site/.nupp-doc-files.json", "wb"))
    record:write(
        '["'
        .. dir
        .. '/site/../victim.txt", "'
        .. dir
        .. '/victim.txt", "'
        .. dir
        .. '/site2/victim.txt", "'
        .. dir
        .. '/site/keep/../../victim.txt", "'
        .. dir
        .. '/site/./keep/..", 5, "site/../victim.txt"]\n'
    )
    record:close()
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    for _, name in ipairs({"victim.txt", "site2/victim.txt", "site/keep/victim.txt"}) do
        local handle = io.open(dir .. "/" .. name, "rb")
        assert(handle, "a recorded path outside the site removed " .. name)
        handle:close()
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.siteMatchesTheNuppdocPageModel()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {
   include = {"src"},
   build = {default = "docs", targets = {
      docs = {kind = "docs", sources = {"src"}, format = "site",
         outDir = "site", title = "Example API", name = "Example",
         description = "A small documented project.",
         public = "docs/public",
         customCss = "docs/site.css",
         logo = "images/project.svg",
         github = "https://github.com/example/project",
         pages = {
            {path = "", title = "Example", source = "docs/index.md",
               layout = "home"},
            {path = "guide", title = "Guide", source = "docs/guide.md"},
            {path = "reference/details", title = "Details",
               source = "docs/details.md"},
            {path = "modules/math", title = "Arithmetic",
               source = "docs/math-overview.md"},
         },
      },
   }},
}
]],
        -- The hero and the showcase are the page's own Markdown, between markers,
        -- rather than tables in the manifest beside it.
        [
            "docs/index.md"
        ] = table.concat(
            {
                "<!-- nupp:hero -->",
                "",
                "# Build with Nupp",
                "",
                "Typed LuaJIT programs without ceremony.",
                "",
                "A brief welcome.",
                "",
                "[Get started](guide)",
                "",
                "![Example project icon](images/project.svg)",
                "",
                "<!-- /nupp:hero -->",
                "",
                "Welcome to the project.",
                "",
                "<!-- nupp:features -->",
                "",
                "## Fast",
                "",
                "Parse-only docs.",
                "",
                "```nupp",
                "local speed: number = 1",
                "```",
                "",
                "<!-- /nupp:features -->",
                "",
                "## More details",
            },
            "\n"
        ) .. "\n",
        [
            "docs/math-overview.md"
        ] = table.concat(
            {
                "Hand-written prose above the generated API.",
                "",
                "## Where to start",
                "",
                "With [](math.add), and then the [guide](guide.md).",
                "",
                "See [guide.md](guide.md) for the setup instructions.",
            },
            "\n"
        ) .. "\n",
        ["docs/public/images/project.svg"] = "<svg><title>Example</title></svg>\n",
        ["docs/site.css"] = ":root{--example-project-accent:#315f58}\n",
        [
            "docs/guide.md"
        ] = table.concat(
            {
                "# Guide",
                "",
                "Human-readable setup instructions.",
                "",
                "Start from [](math.add), or from [the engine](engine).",
                "",
                "A reference in a code span is shown rather than made: `[](math.add)`.",
                "",
                "````",
                "```nupp",
                "local x = 1",
                "```",
                "<<< @docs/snippet.abnf",
                "````",
                "",
                "## After the fence",
                "",
                "Still part of the page.",
                "",
                "::: note Before you begin",
                "Use **Lunamark** inside this callout.",
                ":::",
                "",
                "## Checked workflows",
                "",
                "Build and run the example.",
                "Read the [details](details.md).",
                "",
                "```lua",
                "local answer = 42 -- highlighted Lua",
                "```",
                "",
                "```nupp",
                "local point: Point",
                "```",
                "",
                "```nupp:playground",
                "local record Resource end",
                "do",
                "   local resource = openResource()",
                "   inspect(resource)",
                "end",
                "```",
                "",
                "```lua:line-numbers",
                "local first = 1",
                "local second = 2",
                "```",
                "",
                "```lua:line-numbers=41 [Excerpt]",
                "local offset = true",
                "```",
                "",
                "```glsl",
                "uniform vec4 color;",
                "```",
                "",
                "::: code-group",
                "```nupp [Nupp]",
                "local record Resource end",
                "do",
                "   local resource = openResource()",
                "   inspect(resource)",
                "end",
                "```",
                "",
                "```lua [Generated Lua]",
                "local resource = openResource()",
                "own.drop(resource)",
                "```",
                ":::",
                "",
            },
            "\n"
        ),
        ["docs/details.md"] = "# Details\n\nA deeper reference.\n\n" .. "<<< @docs/snippet.abnf\n",
        ["docs/snippet.abnf"] = 'rule = "literal" / other\n',
        ["src/math.nupp"] = SOURCE,
        [
            "src/engine/init.nupp"
        ] = table.concat(
            {
                "--[[",
                "Engine entry point.",
                "",
                "Sound comes out of [audio](engine.audio).",
                "]]",
                "",
                "--- A running engine.",
                "record Engine",
                "   running: boolean",
                "end",
                "",
                "--- Starts an engine. Hands back an [](engine.Engine) whose",
                "--- [](engine.Engine.running) is already true, and never [](nothing.at.all).",
                "function newEngine(): Engine end",
                "",
                "--- Boots the engine.",
                "function boot(): nil end",
            },
            "\n"
        ) .. "\n",
        ["src/engine/audio.nupp"] = "--[[\nAudio helpers.\n]]\nfunction play(): nil end\n",
        ["src/engine/render.nupp"] = "--- Rendering helpers.\nfunction draw(): nil end\n",
        -- no engine/gpu module of its own, so that name documents as a namespace
        ["src/engine/gpu/vulkan.nupp"] = "--[[\nThe Vulkan backend.\n]]\n" .. "function submit(): nil end\n",
    })
    local output = capture(("cd '%s' && '%s' build"):format(dir, NUPP))
    assert(output == "", output)

    local home = readFile(dir .. "/site/index.html")
    assert(home:find("nuppdoc%-home%-hero"), home)
    assert(home:find("Build with Nupp", 1, true), home)
    assert(
        home:find("Typed LuaJIT programs", 1, true) < home:find("A brief welcome.", 1, true),
        "hero content must follow the tagline"
    )
    assert(
        home:find("A brief welcome.", 1, true) < home:find('class="nuppdoc-hero-image"', 1, true),
        "hero content must remain beside the image"
    )
    assert(
        home:find('class="nuppdoc-hero-image"', 1, true) < home:find("Welcome to the project", 1, true),
        "home Markdown must follow the hero"
    )
    assert(home:find("nuppdoc%-feature%-showcase"), home)
    assert(home:find("language%-nupp"), home)
    -- The showcase sits where the marker was, so it follows the introduction above
    -- it and precedes whatever the page wrote below. It supplies no heading of its
    -- own: a home page titles its own sections.
    assert(not home:find("Nupp Features", 1, true), "the showcase must not emit a heading of its own")
    assert(
        home:find("Welcome to the project", 1, true) < home:find("nuppdoc%-feature%-showcase"),
        "features must follow the marked home introduction"
    )
    assert(
        home:find("nuppdoc%-feature%-showcase") < home:find("More details", 1, true),
        "features must precede the rest of the page"
    )
    assert(home:find('class="nuppdoc-logo" src="images/project.svg"', 1, true), home)
    assert(home:find('src="images/project.svg"', 1, true), home)
    assert(readFile(dir .. "/site/images/project.svg"):find("Example", 1, true))
    assert(home:find('href="https://github.com/example/project"', 1, true), home)
    assert(home:find('href="llms.txt"', 1, true), home)
    assert(home:find('class="nuppdoc-search-button"', 1, true), home)
    assert(home:find('data-nuppdoc-search-index="assets/search-index.js"', 1, true), home)
    assert(home:find('<a href="modules/engine/index.html">API</a>', 1, true), home)
    assert(not home:find('<h2 id="modules">Modules</h2>', 1, true), home)
    assert(not home:find('class="nuppdoc-module-grid"', 1, true), home)

    local guide = readFile(dir .. "/site/guide/index.html")
    assert(guide:find('class="nuppdoc-logo" src="../images/project.svg"', 1, true), guide)
    assert(guide:find('<span class="nuppdoc-brand-name">Example</span>', 1, true), guide)
    assert(guide:find('class="nuppdoc%-breadcrumbs"'), guide)
    assert(guide:find('class="nuppdoc-breadcrumb-home"', 1, true), guide)
    assert(guide:find('aria-current="page">Guide', 1, true), guide)
    assert(guide:find('data-panel-toggle="sidebar"', 1, true), guide)
    assert(guide:find('data-panel-toggle="outline"', 1, true), guide)
    assert(guide:find('data-mobile-nav-toggle', 1, true), guide)
    local searchAt = assert(guide:find('data-nuppdoc-search', 1, true))
    local outlineAt = assert(guide:find('data-mobile-outline-toggle', 1, true))
    assert(searchAt < outlineAt, guide)
    assert(guide:find('M8 6.5h12M8 12h12M8 17.5h12', outlineAt, true), guide)
    assert(guide:find('aria-controls="nuppdoc-sidebar"', 1, true), guide)
    -- a route naming nothing below it is a link rather than a section that opens
    -- onto itself, and the sidebar opens the section holding the page being read
    -- and leaves the rest shut, so its sections are what a reader sees first
    assert(guide:find('<li><a aria-current="page" href="../guide/index.html">Guide</a>', 1, true), guide)
    assert(guide:find('<details><summary>Reference</summary>', 1, true), guide)
    assert(guide:find('<details><summary>API reference</summary>', 1, true), guide)
    -- API library branches start collapsed, including the current branch.
    assert(
        guide:match(
            '<details><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine">'
        ),
        "a top-level module branch must start collapsed"
    )
    assert(
        guide:match(
            '<details><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine%.gpu">'
        ),
        "a nested module branch away from the page must stay shut"
    )
    assert(guide:find('class="nuppdoc-page-nav"', 1, true), guide)
    assert(guide:find("Previous", 1, true), guide)
    assert(guide:find("Next", 1, true), guide)
    assert(guide:find("nuppdoc-token-keyword", 1, true), "Scintillua did not highlight Lua")
    assert(guide:find("nuppdoc-token-type", 1, true), "Scintillua did not highlight GLSL")
    assert(guide:find('class="nuppdoc-code-group" role="radiogroup"', 1, true), "code tabs missing")
    assert(guide:find('class="nuppdoc-admonition nuppdoc-admonition-note"', 1, true), "admonition missing")
    assert(guide:find('<p class="nuppdoc-admonition-title">Before you begin</p>', 1, true), guide)
    assert(guide:find("Use <strong>Lunamark</strong> inside this callout.", 1, true), guide)
    assert(guide:find('class="nuppdoc-code-tab"', 1, true), "code-tab labels missing")
    assert(guide:find('class="nuppdoc-code-block has-line-numbers"', 1, true), guide)
    assert(
        guide:find(
            '<span class="nuppdoc-line-numbers" aria-hidden="true">' .. "<span>1</span><span>2</span></span>",
            1,
            true
        ),
        guide
    )
    -- an excerpt numbers from where it was cut, and still takes a caption
    assert(guide:find("<span>41</span></span>", 1, true), guide)
    assert(guide:find("<figcaption>Excerpt</figcaption>", 1, true), guide)
    -- a fence without the option is left alone
    assert(guide:find('<div class="nuppdoc-code-block" data-lang="glsl">', 1, true), guide)
    assert(guide:find(">Nupp</label>", 1, true), guide)
    assert(guide:find(">Generated Lua</label>", 1, true), guide)
    -- the one fence that asked for an editor got one, and the plain Nupp fences
    -- around it -- including the tab inside the code group -- stayed text
    assert(guide:find('class="nuppdoc-playground"', 1, true), guide)
    assert(select(2, guide:gsub("<nupp%-playground", "")) == 1, guide)
    assert(guide:find('<div class="nuppdoc-code-block" data-lang="nupp"><pre>', 1, true), guide)
    assert(guide:find("<nupp-playground", 1, true), guide)
    assert(not guide:find("<iframe", 1, true), guide)
    assert(guide:find('data-source="local%20record%20Resource%20end', 1, true), guide)
    assert(guide:find('<script type="module" src="/playground/doc-app.js"></script>', 1, true), guide)
    assert(guide:find("keyword-local", 1, true), guide)
    assert(guide:find(">Point</span>", 1, true), "custom-page example lost its type highlighting")
    assert(not guide:find("nuppdoc-code-link", 1, true), "custom-page example was automatically linked")
    assert(
        guide:find('href="../reference/details/index.html"', 1, true),
        "configured Markdown page link was not rewritten to its public route"
    )
    assert(guide:find('href="llms.txt"', 1, true), guide)
    assert(readFile(dir .. "/site/guide/llms.txt"):find("# Guide", 1, true))

    -- `<<< @path` fetches another file's bytes at build time rather than a page
    -- carrying a copy that can drift from it
    local details = readFile(dir .. "/site/reference/details/index.html")
    assert(details:find('<div class="nuppdoc-code-block" data-lang="abnf">', 1, true), details)
    assert(details:find('rule = &quot;literal&quot; / other', 1, true), details)
    assert(not details:find("<<<", 1, true), "embed directive was left in the rendered page")

    local module = readFile(dir .. "/site/modules/math/index.html")
    assert(module:find("nuppdoc-overview", 1, true), module)
    -- A module page opens the API reference, while its library branches stay
    -- collapsed even along the path to the current module.
    assert(module:find('<details open><summary>API reference</summary>', 1, true), module)
    assert(module:find('<li><a href="../../guide/index.html">Guide</a></li>', 1, true), module)
    assert(
        module:match(
            '<details><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine">'
        ),
        "a top-level module branch must start collapsed"
    )
    assert(
        module:match(
            '<details><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine%.gpu">'
        ),
        "an unrelated nested module branch was left open"
    )
    -- Tealdoc-style category headings group the detailed declarations, and each
    -- declaration is one heading level beneath its group. The fragment still names the
    -- whole entry, so a link lands on the declaration heading.
    local typesAt = assert(module:find('<section class="nuppdoc-api-group"><h2 id="types">Types', 1, true))
    local functionsAt = assert(module:find('<section class="nuppdoc-api-group"><h2 id="functions">Functions', 1, true))
    local pointAt = assert(module:find('<section class="nuppdoc-api-item" id="math.Point"><h3>', typesAt, true))
    local addAt = assert(module:find('<section class="nuppdoc-api-item" id="math.add"><h3>', functionsAt, true))
    assert(functionsAt < addAt and addAt < typesAt and typesAt < pointAt, module)
    assert(module:find("<strong>functions</strong>", 1, true) < module:find("<strong>types</strong>", 1, true), module)
    assert(not module:find('<section class="nuppdoc-api-item" id="math.add"><h2>', 1, true), module)
    assert(
        module:find('<a href="#math.Point.x"><code>x</code></a>', 1, true),
        "the member overview must link each member to its own section"
    )
    -- A declaration that documents members is a section of the outline in its own
    -- right, closed until the reader is inside it, so a record's fields and methods
    -- are reachable from the contents rather than only by scrolling.
    assert(
        module:find(
            '<li class="nuppdoc-outline-section"><details open><summary>'
            .. '<a href="#types" title="Types">Types</a></summary><ol>'
            .. '<li class="nuppdoc-outline-section"><details><summary>'
            .. '<a href="#math.Point" title="Point">Point</a></summary><ol>'
            .. '<li><a href="#math.Point.x" title="x">x</a></li>',
            1,
            true
        ),
        module
    )
    assert(
        module:find(
            '<li class="nuppdoc-outline-section"><details open><summary>'
            .. '<a href="#functions" title="Functions">Functions</a></summary><ol><li>'
            .. '<a href="#math.add" title="add">add</a>',
            1,
            true
        ),
        module
    )
    assert(module:find('id="nuppdoc-outline" aria-label="On this page"', 1, true), module)
    local outline = assert(module:match('<aside class="nuppdoc%-outline"(.-)</aside>'))
    assert(outline:find('href="#functions"', 1, true) < outline:find('href="#types"', 1, true), outline)
    local moduleMarkdown = readFile(dir .. "/site/modules/math.md")
    local markdownFunctionsAt = assert(moduleMarkdown:find("\n## Functions\n", 1, true))
    local markdownTypesAt = assert(moduleMarkdown:find("\n## Types\n", markdownFunctionsAt, true))
    assert(moduleMarkdown:find("\n### `add`", markdownFunctionsAt, true) < markdownTypesAt, moduleMarkdown)
    assert(moduleMarkdown:find("\n### `Point`", markdownTypesAt, true), moduleMarkdown)
    assert(not moduleMarkdown:find("\n## Records\n", 1, true), moduleMarkdown)
    assert(not moduleMarkdown:find("\n## Variables\n", 1, true), moduleMarkdown)
    assert(module:find("Functions", 1, true), module)
    assert(module:find("Types", 1, true), module)
    assert(module:find("nuppdoc%-kind%-badge"), module)
    assert(module:find("Previous", 1, true), module)

    -- a configured page whose path is a module's route is that module's
    -- overview: prose above the generated API rather than a second page beside it
    assert(module:find("<h1 id=\"math\"><code>math</code>", 1, true), module)
    assert(module:find("Hand-written prose above the generated API.", 1, true), module)
    assert(module:find('<h2 id="where-to-start">Where to start', 1, true), module)
    -- it is ordinary page markdown, so both kinds of link still resolve
    assert(
        module:find('<a href="../../modules/math/index.html#math.add">' .. "<code>math.add</code></a>", 1, true),
        module
    )
    assert(module:find('<a href="../../guide/index.html">guide</a>', 1, true), module)
    -- a link that names the file it points at is titled by the page it reaches,
    -- so prose never sends the reader to a filename
    assert(module:find('<a href="../../guide/index.html">Guide</a>', 1, true), module)
    -- the prose comes before the generated contents, and its headings are in the
    -- outline above them
    assert(
        module:find("Where to start", 1, true) < module:find("nuppdoc-overview", 1, true),
        "the overview must open the page"
    )
    assert(module:find('<a href="#where-to-start" title="Where to start">', 1, true), module)
    -- and there is one page at that route, not two
    assert(not io.open(dir .. "/site/modules/math/index.html/index.html"))
    local homePage = readFile(dir .. "/site/index.html")
    assert(not homePage:find(">Arithmetic</a>", 1, true), "the overview was also listed as a standalone page")
    assert(readFile(dir .. "/site/modules/math/llms.txt"):find("Hand-written prose above the generated API.", 1, true))
    local nestedModule = readFile(dir .. "/site/modules/engine/render/index.html")
    assert(nestedModule:find('class="nuppdoc-module-branch"', 1, true), nestedModule)
    assert(nestedModule:find('<code>render</code>', 1, true), nestedModule)
    assert(
        nestedModule:find(
            '<details><summary class="nuppdoc-module-branch-link">'
            .. '<a href="../../../modules/engine/index.html" aria-label="engine">'
            .. "<code>engine</code></a></summary>",
            1,
            true
        ),
        nestedModule
    )
    assert(not nestedModule:find("nuppdoc-module-overview", 1, true), "the module tree still renders an overview entry")
    local branchModule = readFile(dir .. "/site/modules/engine/index.html")
    assert(
        branchModule:find(
            '<summary class="nuppdoc-module-branch-link">'
            .. '<a aria-current="page" href="../../modules/engine/index.html"',
            1,
            true
        ),
        branchModule
    )

    -- The Markdown overview links directly to each child module.
    assert(branchModule:find('href="../../modules/engine/audio/index.html"', 1, true), branchModule)
    assert(branchModule:find('href="../../modules/engine/render/index.html"', 1, true), branchModule)
    assert(branchModule:find('href="../../modules/engine/gpu/index.html"', 1, true), branchModule)
    assert(branchModule:find('<a href="#overview" title="Overview">', 1, true), branchModule)

    local namespace = readFile(dir .. "/site/modules/engine/gpu/index.html")
    assert(namespace:find('<h1 id="engine.gpu"><code>engine.gpu</code>', 1, true), namespace)
    assert(namespace:find("Nothing is required by this name itself", 1, true), namespace)
    assert(namespace:find('href="../../../modules/engine/gpu/vulkan/index.html"', 1, true), namespace)
    -- it holds no declarations, and nothing ever suggested it would
    assert(not namespace:find("No public declarations", 1, true), namespace)
    assert(not namespace:find("Module contents", 1, true), namespace)
    -- and no page gets a redirect stub from a former URL
    local stub = io.open(dir .. "/site/modules/engine/gpu.html")
    if stub then
        stub:close()
    end
    assert(not stub, "a namespace was given a legacy redirect")

    -- a function that hands back an instance is a function, whatever it is named
    assert(not branchModule:find("<h3>Constructors</h3>", 1, true), branchModule)
    assert(branchModule:find("<strong>functions</strong>", 1, true), branchModule)
    assert(branchModule:find('<a href="#engine.newEngine"><code>newEngine</code></a>', 1, true), branchModule)
    assert(branchModule:find('<a href="#engine.boot"><code>boot</code></a>', 1, true), branchModule)

    -- a markdown link whose target names a module, a declaration, or a member is
    -- resolved to whatever documents it, so a reference is written as the name
    assert(branchModule:find('<a href="../../modules/engine/audio/index.html">audio</a>', 1, true), branchModule)
    assert(
        branchModule:find(
            '<a href="../../modules/engine/index.html#engine.Engine">' .. "<code>engine.Engine</code></a>",
            1,
            true
        ),
        branchModule
    )
    assert(
        branchModule:find(
            '<a href="../../modules/engine/index.html#engine.Engine.running">'
            .. "<code>engine.Engine.running</code></a>",
            1,
            true
        ),
        branchModule
    )
    -- a name nothing documents still renders, rather than becoming an empty link
    assert(branchModule:find("never <code>nothing.at.all</code>", 1, true), branchModule)
    assert(guide:find('<a href="../modules/math/index.html#math.add">' .. "<code>math.add</code></a>", 1, true), guide)
    assert(guide:find('<a href="../modules/engine/index.html">the engine</a>', 1, true), guide)
    -- a reference inside a code span is a page showing the syntax, not using it
    assert(guide:find("<code>[](math.add)</code>", 1, true), guide)

    -- a fence longer than the ones it holds keeps them, so a page can show a fenced
    -- block and an embed directive without either being acted on
    assert(guide:find("```nupp\nlocal x = 1\n```\n&lt;&lt;&lt; @docs/snippet.abnf", 1, true), guide)
    assert(not guide:find("literal&quot; / other", 1, true), "an embed directive inside a fence was expanded")
    -- and everything after the fence is still on the page
    assert(guide:find('id="after-the-fence"', 1, true), "the four-backtick fence swallowed the rest of the page")

    assert(readFile(dir .. "/site/modules/math/llms.txt"):find("# `math`", 1, true))
    local engineMarkdown = readFile(dir .. "/site/modules/engine/llms.txt")
    assert(engineMarkdown:find("**submodules**", 1, true), engineMarkdown)
    assert(engineMarkdown:find("[`gpu`](../../modules/engine/gpu/index.html)", 1, true), engineMarkdown)
    assert(readFile(dir .. "/site/modules/engine/gpu/llms.txt"):find("# `engine.gpu`", 1, true))
    -- The downloadable Markdown retains the same navigable references as the site.
    assert(
        engineMarkdown:find("[`engine.Engine`](../../modules/engine/index.html#engine.Engine)", 1, true),
        engineMarkdown
    )
    assert(engineMarkdown:find("[audio](../../modules/engine/audio/index.html)", 1, true), engineMarkdown)
    assert(readFile(dir .. "/site/llms.txt"):find("Complete documentation", 1, true))
    assert(readFile(dir .. "/site/llms-full.txt"):find("Guide", 1, true))
    local search = readFile(dir .. "/site/assets/search-index.js")
    assert(search:find("Guide › Checked workflows", 1, true), search)
    assert(search:find("Human%-readable setup instructions"), search)
    assert(search:find("API › add", 1, true), search)
    assert(search:find("API › Point.x", 1, true), search)
    local script = readFile(dir .. "/site/assets/site.js")
    assert(script:find("Search pages, headings, functions, and types.", 1, true), script)
    assert(script:find('event.key.toLowerCase() === "k"', 1, true), script)
    assert(script:find('sidebar?.querySelector(\'a[aria-current="page"]\')', 1, true), script)
    assert(script:find("sidebar.scrollTop +=", 1, true), script)
    assert(script:find('const mobileNavHistoryKey = "nuppMobileNavOpen"', 1, true), script)
    assert(script:find("history.pushState(", 1, true), script)
    assert(script:find("addEventListener(\"popstate\"", 1, true), script)
    local css = readFile(dir .. "/site/assets/style.css")
    -- theme.css is a plain, hand-editable stylesheet now (see
    -- nupp.tools.doc.assets), so these check for the rules themselves rather
    -- than for one exact whitespace style: `compact` collapses the incidental
    -- spacing a formatter adds around punctuation, leaving selectors, properties,
    -- and values comparable to the minified strings below either way.
    local compact = css:gsub("%s*([{}:;,()])%s*", "%1"):gsub("%s+", " ")
    assert(compact:find("is%-mobile%-nav%-open"), css)
    assert(compact:find("%-%-nuppdoc%-hero%-glow%-color"), css)
    assert(compact:find("color%-mix%(in srgb,var%(%-%-nuppdoc%-hero%-glow%-color%)"), css)
    assert(compact:find("nuppdoc%-code%-tab%-input:checked"), css)
    assert(compact:find("nuppdoc%-admonition%-warning"), css)
    assert(compact:find("@media print", 1, true), css)
    assert(compact:find("%-%-example%-project%-accent:#315f58"), css)
    assert(compact:find("clip%-path:circle%(50%% at 50%% 50%%%)"), css)
    assert(compact:find("filter:drop%-shadow"), css)
    assert(compact:find("nuppdoc%-mobile%-outline%-toggle"), css)
    assert(compact:find("is%-mobile%-outline%-open"), css)
    assert(compact:find("html%{font%-size:16px%}"), "the root defines the prose size")
    local contentRules, explicitSize = 0, false
    for declarations in compact:gmatch("%.nuppdoc%-content%{([^}]*)%}") do
        contentRules = contentRules + 1
        if declarations:find("font-size:", 1, true) then
            assert(declarations:find("font-size:1rem", 1, true), "prose uses the root font size")
            explicitSize = true
        end
    end
    assert(contentRules > 0 and explicitSize, "the content size was checked")
    -- one mechanism clears the sticky header; two would stack into twice the gap
    assert(compact:find("scroll%-margin%-top:calc%(var%(%-%-nuppdoc%-header%-height%) ?%+ ?1%.4rem%)"), css)
    assert(not compact:find("scroll-padding-top", 1, true), css)
    -- The spaces around that `+` are load-bearing: `calc(a+b)` is not valid CSS.
    -- `compact` closes up the one before the operator and leaves the one after it,
    -- so it cannot say whether the declaration a browser receives is well formed,
    -- and the source is what answers that.
    assert(css:find("calc(var(--nuppdoc-header-height) + 1.4rem)", 1, true), css)

    -- The site is pre-release, so a module page leaves no stub at a former URL.
    local legacy = io.open(dir .. "/site/modules/math.html", "rb")
    if legacy then
        legacy:close()
    end
    assert(not legacy, "a module was given a redirect stub")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A generated page heads each declaration with its name and then the one word that
-- says what it is. The word is a badge beside the name, the way a module page renders
-- one, rather than trailing italics: italics are part of the heading's text, and the
-- outline and the search index beside the page were listing every declaration as its
-- name followed by its kind.
function M.headingKindsRenderAsBadgesAndStayOutOfTheOutline()
    local html = require("nupp.tools.doc.html")

    local rendered = html.markdownHtml("### `string.format` _function_", {})
    assert(rendered:find('<span class="nuppdoc-kind-badge nuppdoc-kind-function">function</span>', 1, true), rendered)
    assert(not rendered:find("<em>", 1, true), "the kind rendered as emphasis inside the heading")
    -- The slug still carries the kind: a generated page anchors its declarations by the
    -- name alone already, and the two would collide.
    assert(rendered:find('id="stringformat-function"', 1, true), rendered)
    assert(rendered:find('aria-label="Link to string.format"', 1, true), rendered)

    local outline = html.markdownOutline("### `string.format` _function_")
    assert(#outline == 1, "one heading")
    assert(outline[1].name == "string.format", outline[1].name)
    assert(outline[1].path == "stringformat-function", outline[1].path)

    -- A comptime kind is two words, and a badge is what a member heading gets too.
    local comptime = html.markdownHtml("#### `sizeof` _comptime function_", {})
    assert(comptime:find("nuppdoc-kind-comptime-function", 1, true), comptime)
    assert(comptime:find(">comptime</span>", 1, true), comptime)

    -- Nothing else loses its emphasis. A heading has to name a declaration in code
    -- before its trailing emphasis reads as a kind at all.
    local prose = html.markdownHtml("## Why _this_ matters", {})
    assert(prose:find("<em>this</em>", 1, true), prose)
    local trailing = html.markdownHtml("## Reading the output _carefully_", {})
    assert(trailing:find("<em>carefully</em>", 1, true), trailing)
    assert(html.markdownOutline("## Why _this_ matters")[1].name == "Why this matters")
end

-- Markdown is lunamark's now. These are the cases the pattern-based renderer
-- it replaced got wrong, so they are the ones worth pinning.
function M.markdownIsRenderedByLunamark()
    local html = require("nupp.tools.doc.html")
    local previousUtf8 = package.loaded["lua-utf8"]
    local cases = {
        {"**a *nested* b**", "<strong>a <em>nested</em> b</strong>"},
        {"a \\*escaped\\* b", "a *escaped* b"},
        {"[l](http://x.com/a(b))", '<a href="http://x.com/a(b)">l</a>'},
        {"a * b * c * d", "a * b * c * d"},
        {"use `a * b` here", "<code>a * b</code>"},
    }
    for _, case in ipairs(cases) do
        local out = html.markdownHtml(case[1], {})
        assert(out:find(case[2], 1, true), ("%s\n  want: %s\n  got:  %s"):format(case[1], case[2], out))
    end
    -- Every block wraps the same way whether or not the source ended in a blank
    -- line; a table cell full of summaries depends on it.
    assert(html.markdownHtml("one\n\ntwo", {}):find("<p>two</p>", 1, true))
    -- A Windows checkout presents Markdown with CRLF endings. Fences and the
    -- following block must survive the same parser path as an LF-only page.
    local windows = html.markdownHtml("## Try Nupp\r\n\r\n```playground\r\n```\r\n\r\nafter", {})
    assert(windows:find("nuppdoc-playground", 1, true), windows)
    assert(windows:find("<p>after</p>", 1, true), windows)
    -- A summary is a sentence, so the one paragraph around it goes.
    assert(html.inlineHtml("a **bold** one") == "a <strong>bold</strong> one")

    local entities = html.markdownHtml("&#x20AC; &copy;", {})
    assert(entities:find("€ ©", 1, true), entities)

    local asciiReference = html.markdownHtml("[label][TAG]\n\n[tag]: /ascii", {})
    assert(asciiReference:find('href="/ascii"', 1, true), asciiReference)
    local exactUnicode = html.markdownHtml("[label][CAFÉ]\n\n[CAFÉ]: /exact", {})
    assert(exactUnicode:find('href="/exact"', 1, true), exactUnicode)
    local differentUnicode = html.markdownHtml("[label][CAFÉ]\n\n[café]: /different", {})
    assert(not differentUnicode:find('href="/different"', 1, true), differentUnicode)
    assert(package.loaded["lua-utf8"] == previousUtf8, "the Lunamark adapter does not expose a lua-utf8 module")
end

-- Fenced regions are lifted out before lunamark sees them, which is what keeps
-- the fence options working: an info string is not something markdown parses.
function M.fencedBlocksKeepTheirOptions()
    local html = require("nupp.tools.doc.html")
    local labeled = html.markdownHtml("```lua [example.lua] :line-numbers=12\nprint(1)\n```", {})
    assert(labeled:find("nuppdoc-labeled-code", 1, true), labeled)
    assert(labeled:find("<figcaption>example.lua</figcaption>", 1, true), labeled)
    assert(labeled:find("has-line-numbers", 1, true), labeled)
    assert(labeled:find("<span>12</span>", 1, true), labeled)

    local group = html.markdownHtml(
        table.concat(
            {
                "::: code-group",
                "",
                "```lua [one]",
                "print(1)",
                "```",
                "",
                "```sh [two]",
                "echo",
                "```",
                "",
                ":::",
                "",
                "after",
            },
            "\n"
        ),
        {}
    )
    assert(group:find("nuppdoc-code-group", 1, true), group)
    assert(group:find(">one</label>", 1, true), group)
    assert(group:find(">two</label>", 1, true), group)
    -- and the prose on the far side of the block is still prose
    assert(group:find("<p>after</p>", 1, true), group)

    local tilde = html.markdownHtml("~~~lua [tilde.lua] :line-numbers=7\nprint(7)\n~~~", {})
    assert(tilde:find("<figcaption>tilde.lua</figcaption>", 1, true), tilde)
    assert(tilde:find("<span>7</span>", 1, true), tilde)

    local nearMiss = html.markdownHtml("```lua :line-numbers-extra\nprint(1)\n```", {})
    assert(not nearMiss:find("has-line-numbers", 1, true), nearMiss)
    local missingStart = html.markdownHtml("```lua :line-numbers=\nprint(1)\n```", {})
    assert(not missingStart:find("has-line-numbers", 1, true), missingStart)
    local invalidStart = html.markdownHtml("```lua :line-numbers=first\nprint(1)\n```", {})
    assert(not invalidStart:find("has-line-numbers", 1, true), invalidStart)
    local playgroundValue = html.markdownHtml("```nupp:playground=true\nprint(1)\n```", {})
    assert(not playgroundValue:find("nuppdoc-playground", 1, true), playgroundValue)
    local laterOption = html.markdownHtml("```lua [] [good.lua] :line-numbers-extra :line-numbers=9\nprint(1)\n```", {})
    assert(laterOption:find("<figcaption>good.lua</figcaption>", 1, true), laterOption)
    assert(laterOption:find("<span>9</span>", 1, true), laterOption)
end

-- A group where only some fences carry captions still shows every fence: the
-- uncaptioned ones tab under their language rather than silently vanishing.
function M.aCodeGroupKeepsItsUncaptionedFences()
    local html = require("nupp.tools.doc.html")
    local group = html.markdownHtml(
        table.concat(
            {"::: code-group", "", "```lua [one]", "print(1)", "```", "", "```sh", "echo hi", "```", "", ":::",},
            "\n"
        ),
        {}
    )
    assert(group:find(">one</label>", 1, true), group)
    assert(group:find(">sh</label>", 1, true), group)
    assert(group:find("echo", 1, true), group)
    local _, panels = group:gsub("nuppdoc%-code%-panel", "")
    assert(panels == 2, "expected both fences to render: " .. group)
end

-- The tab inputs live in their own row, so the panel is no longer its input's
-- next sibling; the theme has to pair each panel with the input at the same
-- position, or a tabbed group renders its tabs above nothing at all.
function M.themePairsCodeGroupPanelsWithTheirTabs()
    local doc = require("nupp.tools.doc")
    assert(
        doc.theme:find(
            ".nuppdoc-code-group:has(.nuppdoc-code-tabs>input:nth-of-type(1):checked)"
            .. " .nuppdoc-code-panel:nth-of-type(1)",
            1,
            true
        ),
        "panels are not re-paired"
    )
    assert(
        not doc.theme:find(".nuppdoc-code-tab-input:checked+.nuppdoc-code-tab+.nuppdoc-code-panel", 1, true),
        "the stale adjacent-sibling pairing is still in the theme"
    )
end

-- Documentation Markdown remains platform-spelled in .gitattributes, so a
-- Windows checkout hands every page over with CRLF endings. The block is
-- recognized by exact `---` lines, and a stray carriage return must not cost a
-- page its route, title, order, and redirects.
function M.frontmatterSurvivesWindowsLineEndings()
    local frontmatter = require("nupp.tools.doc.frontmatter")
    local fields, body = frontmatter.parse("---\r\ntitle: Guide\r\nredirects: old/guide\r\n---\r\n\r\nBody\r\n")
    assert(fields.title == "Guide", tostring(fields.title))
    assert(fields.redirects == "old/guide", tostring(fields.redirects))
    assert(body == "Body\n", ("%q"):format(body))
end

-- The same endings must not cost a collection's document its title and status.
function M.collectionFrontmatterSurvivesWindowsLineEndings()
    local collection = require("nupp.tools.doc.collection")
    local dir = tempProject({
        ["docs/adrs/0001-example.md"] = "---\r\ntitle: Example\r\nstatus: Draft\r\n" .. "---\r\n\r\n## Why\r\n",
    })
    local pages = assert(collection.expand(dir, {directory = "docs/adrs", path = "adrs", title = "ADRs",}))
    local page = pages[2]
    assert(page, "the collection published no document")
    assert(page.name == "Example", page.name)
    assert(page.status == "Draft", tostring(page.status))
    assert(page.title == "ADR 1: Example", page.title)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A Nupp example is highlighted text until it asks for an editor, and a request to
-- number an excerpt's lines outranks that ask.
function M.nuppFencesBecomeInlinePlaygroundsOnRequest()
    local html = require("nupp.tools.doc.html")
    local editable = html.markdownHtml("```nupp:playground\nlocal answer: integer = 42\n```", {})
    assert(editable:find('class="nuppdoc-playground"', 1, true), editable)
    assert(editable:find("<nupp-playground", 1, true), editable)
    assert(not editable:find("<iframe", 1, true), editable)
    assert(editable:find('data-source="local%20answer%3A%20integer%20%3D%2042', 1, true), editable)
    assert(
        editable:find(
            '<div class="nuppdoc-code-block" data-lang="nupp" data-reader-source' .. ' slot="reader-source">',
            1,
            true
        ),
        editable
    )
    assert(editable:find('<code class="language-nupp">local answer: integer = 42</code>', 1, true), editable)
    local plain = html.markdownHtml("```nupp\nlocal answer: integer\n```", {})
    assert(plain:find('class="nuppdoc-code-block"', 1, true), plain)
    assert(plain:find('class="language-nupp"', 1, true), plain)
    assert(not plain:find('nuppdoc-playground', 1, true), plain)

    local numbered = html.markdownHtml("```nupp:playground:line-numbers=41\nlocal answer = 42\n```", {})
    assert(numbered:find('class="nuppdoc-code-block has-line-numbers"', 1, true), numbered)
    assert(numbered:find("<span>41</span>", 1, true), numbered)
    assert(not numbered:find('nuppdoc-playground', 1, true), numbered)
end

-- Lunamark does not parse `:::` containers itself. The container is lifted out,
-- while its body goes through the same Lunamark parser as the surrounding page.
function M.aDeepDiveAdmonitionRendersCollapsed()
    local html = require("nupp.tools.doc.html")
    local out = html.markdownHtml("::: deepdive\nBecause **of this**.\n:::", {})
    assert(out:find('<details class="nuppdoc-admonition nuppdoc-admonition-deepdive">', 1, true), out)
    assert(out:find('<summary class="nuppdoc-admonition-title">Dive deeper</summary>', 1, true), out)
    assert(not out:find("<details open", 1, true), "a deep dive must arrive collapsed")
    assert(out:find("<strong>of this</strong>", 1, true), out)

    -- The other kinds keep their always-open aside.
    local note = html.markdownHtml("::: note\nSeen.\n:::", {})
    assert(note:find("<aside class=", 1, true), note)
    assert(not note:find("<details", 1, true), note)

    local seeAlso = html.markdownHtml("::: seealso\nElsewhere.\n:::", {})
    assert(seeAlso:find('<aside class="nuppdoc-admonition nuppdoc-admonition-seealso"', 1, true), seeAlso)
    assert(seeAlso:find(">See also</p>", 1, true), seeAlso)

    local titled = html.markdownHtml("::: deepdive Why the floor is a file name\nBecause.\n:::", {})
    assert(titled:find(">Why the floor is a file name</summary>", 1, true), titled)
end

function M.admonitionsKeepLunamarkMarkdown()
    local html = require("nupp.tools.doc.html")
    local out = html.markdownHtml(
        table.concat(
            {
                "::: warning Check this <title>",
                "Use **strong text**, [a link](https://example.com), and a list:",
                "",
                "- first",
                "- second",
                ":::",
                "",
                "after",
            },
            "\n"
        ),
        {}
    )
    assert(out:find('class="nuppdoc-admonition nuppdoc-admonition-warning"', 1, true), out)
    assert(out:find('aria-label="Check this &lt;title&gt;"', 1, true), out)
    assert(out:find("<strong>strong text</strong>", 1, true), out)
    assert(out:find('<a href="https://example.com">a link</a>', 1, true), out)
    assert(out:find("<li>first</li>", 1, true), out)
    assert(out:find("<p>after</p>", 1, true), out)

    local default = html.markdownHtml("::: tip\nUseful.\n:::", {})
    assert(default:find(">Tip</p>", 1, true), default)

    local nested = html.markdownHtml(
        table.concat(
            {"::: note", "Outside.", "", "::: tip", "Inside.", ":::", "", "```text", ":::", "```", ":::",},
            "\n"
        ),
        {}
    )
    assert(nested:find("nuppdoc-admonition-note", 1, true), nested)
    assert(nested:find("nuppdoc-admonition-tip", 1, true), nested)
    assert(nested:find("nuppdoc-code-block", 1, true), nested)
    assert(nested:find(":::<", 1, true), nested)
end

-- The id is Nupp's slug rather than lunamark's, and each heading keeps the
-- anchor the stylesheet draws.
function M.outlinesFollowExplicitHeadingAnchors()
    local html = require("nupp.tools.doc.html")
    local source = [[<a id="old-name"></a>
<a id="stable-name"></a>

## New name

## New name

<a id="unrelated"></a>
Body text ends the pending anchor.

## Plain

```nupp
-- ## Not a heading
```

## Last
]]
    local outline = html.markdownOutline(source)
    local rendered = html.markdownHtml(source, {}, 0)
    local expected = {"stable-name", "new-name", "plain", "last"}
    assert(#outline == #expected)
    for index, id in ipairs(expected) do
        assert(outline[index].path == id, outline[index].path)
        assert(rendered:find('id="' .. id .. '"', 1, true), rendered)
    end
    assert(rendered:find('id="old-name"', 1, true), "historical anchors stay available")
end

function M.headingsKeepTheirAnchors()
    local html = require("nupp.tools.doc.html")
    local out = html.markdownHtml("# One `two`\n\nbody", {})
    assert(out:find('id="one-two"', 1, true), out)
    assert(out:find('class="nuppdoc-header-anchor"', 1, true), out)
    assert(out:find("<h2 ", 1, true), out) -- shifted by one by default
    assert(html.markdownHtml("# One", {}, 0):find("<h1 ", 1, true))
end

-- The diagnostic index is generated from the compiler's own table, so it holds a
-- section for exactly the codes `nupp explain` can answer for and no manifest
-- lists them.
function M.diagnosticIndexCoversEveryDocumentedCode()
    local diagnostics = require("nupp.tools.doc.diagnostics")
    local explain = require("nupp.tools.explain")

    assert(diagnostics.page(nil) == nil)

    local page = assert(diagnostics.page({path = "diagnostics"}))
    assert(page.path == "diagnostics")
    assert(page.title == "Diagnostic index")

    local codes = explain.documented()
    assert(#codes > 0)
    local sections = 0
    for _ in page.markdown:gmatch("\n#### NUPP%d+\n") do
        sections = sections + 1
    end
    assert(sections == #codes, sections .. " sections for " .. #codes .. " codes")
    for _, code in ipairs(codes) do
        assert(page.markdown:find("#### " .. code .. "\n", 1, true), "no section for " .. code)
    end
end

-- A code with an example pair shows the program that reports it before the rule and
-- the correction after it, as highlighted text rather than an editor: an index is
-- searched, and text inside an editor frame is not findable.
function M.diagnosticSectionsShowBothProgramsAsText()
    local diagnostics = require("nupp.tools.doc.diagnostics")
    local page = assert(diagnostics.page({path = "diagnostics"}, {["docs/reference/lints.md"] = true}))

    local at = assert(page.markdown:find("#### NUPP2107\n", 1, true))
    local body = page.markdown:sub(at, (page.markdown:find("\n#### ", at + 5, true)))
    local reported = assert(body:find("```nupp [Reported]", 1, true))
    local accepted = assert(body:find("```nupp [Accepted]", 1, true))
    assert(reported < accepted)
    assert(not body:find(":playground", 1, true), "an index section embedded an editor")
    assert(body:find("`exhaustiveness` lint", 1, true), body)
    assert(body:find("](docs/reference/lints.md#exhaustiveness)", 1, true), body)
    assert(body:find("/playground/#source=", 1, true), body)
end

-- Every link the page writes has somewhere to land: a related code that has no
-- section is named rather than anchored, and so is a reference the site does not
-- publish.
function M.diagnosticIndexOnlyLinksWhatExists()
    local diagnostics = require("nupp.tools.doc.diagnostics")
    local page = assert(diagnostics.page({path = "diagnostics"}))

    assert(not page.markdown:find("](docs/", 1, true), "linked an unpublished page")
    local anchors = {}
    for code in page.markdown:gmatch("### (NUPP%d+)") do
        anchors["#" .. code:lower()] = true
    end
    local seen = 0
    for target in page.markdown:gmatch("%]%((#nupp%d+)%)") do
        assert(anchors[target], "link to missing section " .. target)
        seen = seen + 1
    end
    assert(seen > 0, "no related code was linked at all")
end

-- The standard library page is generated from the declarations the checker itself
-- loads, so it holds a section for every library the compiler carries without a
-- manifest naming one of them.
function M.annotationsUseTheRegistryAndTheCommonDeclarationModel()
    local annotationapi = require("nupp.tools.doc.annotationapi")
    local registry = require("nupp.compiler.annotations").new()
    local stdlib = require("nupp.tools.doc.stdlib")
    local json = require("testjson")
    local items, count = {}, 0
    local declarations = annotationapi.items()
    for _, item in ipairs(declarations) do
        items[item.name] = item
        assert(item.kind == "annotation", item.name)
    end
    for name, definition in pairs(registry.byname) do
        local item = assert(items["@" .. name], name)
        assert(item.annotation.arguments == definition.arguments, name)
        assert(table.concat(item.annotation.targets, ",") == table.concat(definition.targets, ","), name)
        assert(definition.docsPath == "docs/api.md#" .. item.path, name)
        count = count + 1
    end
    assert(#declarations == count + 2, "only the real registry and two file directives are published")
    assert(items["@!internal"].annotation.fileDirective and items["@!nofmt"].annotation.fileDirective)
    assert(not registry:get("internal") and not registry:get("nofmt"), "file directives reserved user annotation names")
    assert(items["@cli"].annotation.singleValue == "name")
    local members = {}
    for _, member in ipairs(items["@cli"].members) do
        members[member.name] = member
    end
    assert(members.complete.type == "type?" and members.complete.annotationMember.reference)
    assert(members.name.type == "string | nil" and members.name.annotationMember.optional)
    assert(items["@syntax"].members[1].name == "value" and items["@syntax"].members[1].type == "string")
    assert(require("nupp.tools.doc.api").displaySignature(items["@aot"]) == "@aot(...)")
    assert(not items["@syntax"].members[1].annotationMember.optional)
    local page = assert(stdlib.page({}))
    assert(#page.navigation.annotations == #declarations)
    assert(page.markdown:find('<a id="annotation-aot"></a>', 1, true))
    assert(page.markdown:find("## Annotations", 1, true))
    assert(page.markdown:find("### `@aot` _annotation_", 1, true))
    assert(page.markdown:find("#### Values", 1, true))
    assert(not page.markdown:find("@aot ...", 1, true), "annotation schemas were printed as record members")
    assert(
        page.markdown:find("required whole-function ahead-of-time compilation contract", 1, true),
        "the AOT contract prose was lost"
    )
    local model = json.decode(doc.json({}, declarations))
    assert(#model.annotations == #declarations)
    assert(model.annotations[1].annotation.fileDirective)
    assert(doc.markdown({}, nil, nil, nil, declarations):find("## `@aot` _annotation_", 1, true))
    local rendered = require("nupp.tools.doc.html").markdownHtml(page.markdown, {})
    assert(rendered:find('nuppdoc-kind-annotation">Annotation</span>', 1, true), rendered)
    local _, matchingIds = rendered:gsub('id="annotation%-annotation"', "")
    assert(matchingIds == 1, "the canonical annotation anchor collides with its heading")
    assert(rendered:find('id="annotation-aot"', 1, true), "a distinct explicit declaration anchor was removed")
end

function M.userAnnotationDefinitionsHaveTheSameDeclarationKind()
    local module, errors = doc.extract(
        table.concat(
            {
                "module metadata",
                "--- Retries a request.",
                '@annotation(targets = {"function"})',
                "record retry",
                "    @annotationvalue",
                "    attempts: integer",
                "end",
                "@jit",
                "function metadata.run(): nil end",
                "export = metadata",
            },
            "\n"
        ),
        "metadata.nupp",
        "metadata"
    )
    assert(module and #errors == 0, errors and errors[1] and errors[1].msg)
    local definition, run
    for _, item in ipairs(module.items) do
        if item.name == "retry" then
            definition = item
        end
        if item.name == "run" then
            run = item
        end
    end
    assert(definition and definition.kind == "annotation")
    assert(definition.annotation.targets[1] == "function")
    assert(definition.annotation.singleValue == "attempts")
    assert(run and run.kind == "function", "an application became a definition")
    assert(doc.markdown({module}):find("`retry` _annotation_", 1, true))
end

function M.exportedTablesUseCanonicalPublicNamesInEveryOutput()
    local examples = {
        {path = "src/io/cli.nupp", name = "io.cli", member = "application", hidden = "cliModule."},
        {
            path = "src/debug/bench.nupp",
            name = "debug.bench",
            member = "decodebaseline",
            hidden = "bench.decodeBaseline"
        },
    }
    for _, example in ipairs(examples) do
        local source = readFile(HERE .. "/../" .. example.path)
        local module, errors = doc.extract(source, example.path, example.name)
        assert(module and #errors == 0, errors and errors[1] and errors[1].msg)
        local found
        for _, item in ipairs(module.items) do
            if item.name == example.member then
                found = item
            end
            assert(not item.name:find(example.hidden, 1, true), item.name)
        end
        assert(found, example.name .. "." .. example.member)
        assert(found.path == example.name .. "." .. example.member, found.path)
        local markdown = doc.markdown({module})
        assert(markdown:find('<a id="' .. found.path .. '"></a>', 1, true))
        assert(found.signature:find("function " .. found.path, 1, true), found.signature)
        assert(not markdown:find("cliModule.", 1, true), "a private export alias leaked")
    end
end

function M.annotationReferencePointersUseGeneratedItemsAndProse()
    local reference = require("nupp.tools.reference")
    local annotationapi = require("nupp.tools.doc.annotationapi")
    for _, item in ipairs(annotationapi.items()) do
        local pointer = "docs/api.md#" .. item.path
        local sections = reference.pointerSections(pointer)
        assert(#sections == 1 and sections[1].section.title == item.name, pointer)
        assert(sections[1].section.body:find(item.doc.text, 1, true), pointer)
    end
    assert(
        #reference.pointerSections("docs/reference/annotations.md#aot", HERE .. "/..") == 0,
        "the removed reference route remains an alias"
    )
end

function M.generatedDeriveExampleUsesThePublicProvider()
    local annotationapi = require("nupp.tools.doc.annotationapi")
    local parser = require("nupp.compiler.syntax.parser")
    local check = require("helpers.fragment")
    local env = require("nupp.compiler.project.env").new(HERE .. "/..")
    local example
    for _, item in ipairs(annotationapi.items()) do
        if item.name == "@derive" then
            example = item.doc.text:match("```nupp\n(.-)\n```")
        end
    end
    assert(example, "the generated derive reference has no runnable example")
    local filename = "derive_documentation.nupp"
    local parsed = parser.parse(
        example .. "\nlocal point: types.Debug = new Point(x = 1, y = 2)\nreturn point:debug()\n",
        filename
    )
    assert(#parsed.errors == 0, parsed.errors[1] and parsed.errors[1].msg)
    local diagnostics = check.check(parsed, filename, env)
    for _, diagnostic in ipairs(diagnostics) do
        assert(
            diagnostic.severity == "warning" or diagnostic.severity == "note",
            diagnostic.code .. ": " .. diagnostic.msg
        )
    end
end

function M.stdlibIndexHoldsTheLibrariesTheCompilerDeclares()
    local stdlib = require("nupp.tools.doc.stdlib")

    assert(stdlib.page(nil) == nil)

    local page = assert(stdlib.page({path = "luajit"}))
    assert(page.path == "luajit")
    assert(page.title == "API reference")
    local sections = {"Functions", "Globals", "Annotations"}
    for _, section in ipairs(sections) do
        assert(page.markdown:find("\n## " .. section .. "\n", 1, true), "no section for " .. section)
    end
    assert(page.markdown:find("**modules**", 1, true), "no modules overview")
    assert(
        assert(page.markdown:find("**functions**", 1, true)) < assert(page.markdown:find("**modules**", 1, true)),
        "functions must precede modules in the main API overview"
    )
    -- Library declarations live on their module page; this page retains index links.
    assert(page.markdown:find("[`string`](../modules/string/index.html)", 1, true))
    assert(not page.markdown:find("### `string.format`", 1, true), "library documentation duplicated in its index")
    local libraries = {}
    for _, module in ipairs(page.modules) do
        libraries[module.name] = module
    end
    assert(libraries.string.items[1] and libraries.string.path == nil, "no real virtual library module")
    local format
    for _, item in ipairs(libraries.string.items) do
        if item.name == "format" then
            format = item
        end
    end
    assert(format and format.kind == "function" and format.params[1].name == "fmt")
    assert(format.signature:find("@nosuspend function<Format is string>", 1, true))
    assert(format.doc.text ~= "" and format.returns[1].type == "string")
    local rendered = doc.markdown({libraries.string})
    assert(
        rendered:find(require("nupp.tools.doc.api").displaySignature(format), 1, true)
        and rendered:find(format.doc.text, 1, true),
        "the module page lost the builtin signature or documentation"
    )
    assert(page.markdown:find("### `print`", 1, true), "no ambient global")
    local functions = assert(page.markdown:match("\n## Functions\n(.-)\n## Globals\n"))
    local globalsSection = assert(page.markdown:match("\n## Globals\n(.-)\n## "))
    assert(functions:find('### `print`', 1, true) and not functions:find('### `_G`', 1, true))
    assert(functions:find('### `assert`', 1, true), "a callable global is missing from functions")
    assert(globalsSection:find('### `_G`', 1, true) and globalsSection:find('### `_VERSION`', 1, true))
    assert(not globalsSection:find('### `print`', 1, true))
    assert(not globalsSection:find('### `assert`', 1, true))
    local globals = {}
    for _, item in ipairs(page.globalItems) do
        globals[item.name] = item
    end
    local api = require("nupp.tools.doc.api")
    assert(api.displaySignature(globals.dofile) == "function(path: string?): any")
    assert(not globals.dofile.readOnly, "a mutable global was marked read-only")
    assert(globals.ipairs.readOnly, "the const global lost its read-only status")
    assert(api.displaySignature(globals.ipairs):find("@nosuspend function", 1, true))
    assert(page.markdown:find("**Read-only binding.**", 1, true), "the Markdown reference lost the const restriction")
    assert(not page.markdown:find("### `io.File`", 1, true), "file type leaked into the root index")
end

function M.publicFunctionSignaturesDoNotExposeImplementationBindings()
    local module = assert(
        doc.extract(
            [[
module example
const implementation: function(value: string): string = function(value: string): string return value end
export = {call = implementation}
]],
            "src/example.nupp",
            "example"
        )
    )
    local item = assert(module.items[1])
    local signature = require("nupp.tools.doc.api").displaySignature(item)
    assert(signature == "function(value: string): string", signature)
    assert(not item.readOnly, "a const implementation does not make the exported field read-only")
end

function M.tableBuiltinsUseFunctionCategoriesAndLuaBadges()
    local page = assert(require("nupp.tools.doc.stdlib").page({path = "api"}))
    local library
    for _, module in ipairs(page.modules) do
        if module.name == "table" then
            library = module
        end
    end
    assert(library, "the table module is missing")
    local items = {}
    for _, item in ipairs(library.items) do
        items[item.name] = item
        assert(item.kind == "function", item.name .. " was grouped as a value")
    end
    for _, name in ipairs({"insert", "move"}) do
        local item = assert(items[name], "missing table." .. name)
        assert(item.lua and item.kind == "function", "table." .. name .. " lost its Lua function badge")
        assert(item.signature:find("&", 1, true), "the overloads were lost")
    end
    assert(#items.insert.params == 3 and items.insert.params[2].name == "pos")
    assert(#items.move.params == 5 and items.move.params[5].name == "destination")
    assert(items.move.returns[1].type == "{V}" and items.move.returns[1].text == "the destination table")
    local summary = doc.markdown({library})
    assert(summary:find("**functions**", 1, true), summary)
    assert(not summary:find("**values**", 1, true), "table acquired a bogus Values category")
    local model = require("testjson").decode(doc.json({library}))
    local found = {}
    for _, item in ipairs(model.modules[1].items) do
        found[item.name] = item
    end
    assert(found.insert.kind == "function" and found.insert.lua)
    assert(found.move.kind == "function" and found.move.lua)
    local dir = tempProject({["src/demo.nupp"] = "module demo\nexport const ready = true\n"})
    assert(
        doc.build(dir, {include = {"src"}}, {sources = {"src"}, stdlib = {path = "api"}}, {
            format = "site",
            output = "site"
        }) == 0
    )
    local rendered = readFile(dir .. "/site/modules/table/index.html")
    assert(rendered:find('id="table.insert"', 1, true) and rendered:find('id="table.move"', 1, true))
    assert(not rendered:find(">Values</h3>", 1, true), "the rendered table page has a bogus Values category")
    os.execute("rm -rf '" .. dir .. "'")
end

-- The page is an index, and an index is searched. An editor frame holds text the
-- browser's own find cannot reach, so every fence on it is a plain code block.
function M.stdlibIndexIsStaticThroughout()
    local stdlib = require("nupp.tools.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))

    assert(page.markdown:find("```nupp\n", 1, true), "no Nupp fence at all")
    assert(not page.markdown:find(":playground", 1, true), "a fence would open as an editor")
end

-- Public descriptor types belong to their library pages.
function M.stdlibTypesBelongToTheirNamespaces()
    local stdlib = require("nupp.tools.doc.stdlib")
    local page = assert(stdlib.page({path = "api"}))
    assert(not page.markdown:find("\n## Reflection\n", 1, true), "retired reflection section")
    local libraries = {}
    for _, module in ipairs(page.modules) do
        libraries[module.name] = module
    end
    for _, contract in ipairs({
        {"types", "types.Layout", "types.Layout.Field"},
        {"io", "io.File"},
        {"assert", "assert.Assertion"},
        {"os", "os.DateFields"},
    }) do
        local rendered = require("nupp.tools.doc").markdown({assert(libraries[contract[1]])})
        for index = 2, #contract do
            assert(rendered:find('<a id="' .. contract[index] .. '"></a>', 1, true), "missing " .. contract[index])
        end
    end
    for _, name in ipairs({"Layout", "LayoutField", "LuaFile", "Assertion", "DateFields"}) do
        assert(not page.symbols[name], "retired global type " .. name)
    end
end

-- A global's anchor is the name a program writes. `print` is not a member of the file
-- that declares it, and `string.format` is not a member of the page's own name.
function M.stdlibIndexAnchorsEveryNameTheWayItIsWritten()
    local stdlib = require("nupp.tools.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))

    assert(page.markdown:find('<a id="print"></a>', 1, true), "print anchored as a member")
    assert(page.markdown:find("[`string`](../modules/string/index.html)", 1, true), "string lost its module link")
    assert(not page.markdown:find('<a id="globals.', 1, true), "anchored a global to its file")
end

-- What the prelude declares for the compiler rather than for a program stays off the
-- page: `nupp` has module pages of its own, and the aliases behind `string.format`'s
-- parameter pack are private vocabulary with no section to land on. The pack still
-- names one in the signature, because that is what the declaration says and a signature
-- the checker does not enforce would be worse than an unfamiliar name.
function M.stdlibIndexLeavesTheCompilersOwnDeclarationsOut()
    local stdlib = require("nupp.tools.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))

    assert(not page.markdown:find("### `__Nupp", 1, true), "documented private vocabulary")
    assert(not page.markdown:find('<a id="__Nupp', 1, true), "anchored private vocabulary")
    assert(not page.markdown:find("\n## `nupp`", 1, true), "documented the nupp namespace")
    assert(not page.markdown:find("### `nupp.", 1, true), "documented a nupp declaration")
end

-- A manifest that asks for the page gets it at the route it named.
function M.stdlibIndexIsWrittenWhereTheManifestAsked()
    local linkedSource = SOURCE .. table.concat(
        {
            "--- An owned handle.",
            "record Handle is own.Closeable",
            "   --- Its backing Lua stream.",
            "   file: io.File",
            "   --- Closes it.",
            "   function close(takes self): nil",
            "   end",
            "end",
        },
        "\n"
    ) .. "\n"
    local dir = tempProject({
        ["src/math.nupp"] = linkedSource,
        ["src/own.nupp"] = "--[[\nOwnership contracts.\n]]\n",
        [
            "src/nupp/compiler/prelude.d.nupp"
        ] = table.concat(
            {
                "@!internal",
                "--- A deterministic resource.",
                "interface own.Affine<const cleanup: function> end",
                "interface own.Closeable is own.Affine<self.close>",
                "   close: @nosuspend function(takes self: own.Closeable): nil",
                "end",
            },
            "\n"
        ) .. "\n",
    })
    local config = {include = {"src"}}
    assert(
        doc.build(dir, config, {sources = {"src"}, stdlib = {path = "reference/luajit"}}, {
            format = "site",
            output = "site"
        }) == 0
    )
    local page = readFile(dir .. "/site/reference/luajit/index.html")
    assert(page:find("API reference", 1, true), page:sub(1, 400))
    assert(page:find("modules/string/index.html", 1, true), "the API index lost a builtin module")
    local dofile = assert(page:match('<section class="nuppdoc%-api%-item" id="dofile">(.-)</section>'))
    assert(not dofile:find("keyword%-local"), "dofile is not a local binding")
    assert(not dofile:find("Read%-only binding"), "dofile is not declared const")
    assert(dofile:find('>Arguments<a', 1, true) and dofile:find('<dl class="nuppdoc-api-details">', 1, true), dofile)
    assert(dofile:find('>Returns<a', 1, true), dofile)
    assert(dofile:find("the file to run", 1, true) and dofile:find("whatever the chunk returns", 1, true), dofile)
    assert(page:find('id="dofile-function-lua"', 1, true), "the previous heading anchor was lost")
    assert(page:find('href="#dofile"', 1, true), "the outline must use the explicit public anchor")
    assert(page:find('id="g-variable"', 1, true), "the _G heading anchor was lost")
    assert(page:find('id="version-variable"', 1, true), "the _VERSION heading anchor was lost")
    local ipairs = assert(page:match('<section class="nuppdoc%-api%-item" id="ipairs">(.-)</section>'))
    assert(ipairs:find("Read-only binding", 1, true), "ipairs lost its const restriction")
    local markdown = readFile(dir .. "/site/reference/luajit/llms.txt")
    assert(markdown:find("### `dofile`", 1, true), "the Markdown reference lost dofile")
    local stringPage = readFile(dir .. "/site/modules/string/index.html")
    assert(stringPage:find('id="string.format"', 1, true), "the module page rendered without its declarations")
    local packagePage = readFile(dir .. "/site/modules/package/index.html")
    local loadlib = assert(
        packagePage:match('<section class="nuppdoc%-api%-item" id="package%.loadlib">(.-)</section>')
    )
    assert(not loadlib:find("keyword%-local"), "package.loadlib is not a local binding")
    assert(not loadlib:find("Read%-only binding"), "package.loadlib is not declared read-only")
    local packageMarkdown = readFile(dir .. "/site/modules/package/llms.txt")
    assert(packageMarkdown:find("function%(Interface%): function%(%)"), packageMarkdown)
    local sidebar = assert(page:match('<aside class="nuppdoc%-sidebar".-</aside>'), "the page has a sidebar")
    assert(
        sidebar:find(
            '<details open><summary><a aria-current="page" href="../../reference/luajit/index.html">API reference</a></summary>',
            1,
            true
        ),
        sidebar
    )
    assert(not sidebar:find(">LuaJIT</a>", 1, true), sidebar)
    assert(not sidebar:find(">LuaJIT standard library</a>", 1, true), sidebar)
    local modulePage = readFile(dir .. "/site/modules/math/index.html")
    assert(not modulePage:find("nuppdoc-code-link", 1, true), "a module signature was automatically linked")
    assert(
        modulePage:find('href="../../modules/own/index.html#own.Closeable"', 1, true),
        "the implements overview did not link own.Closeable"
    )

    local dir2 = tempProject({["src/math.nupp"] = SOURCE})
    assert(doc.build(dir2, config, {sources = {"src"}}, {format = "site", output = "site"}) == 0)
    assert(not io.open(dir2 .. "/site/reference/luajit/index.html", "rb"), "a manifest that asked for no page got one")
    os.execute("rm -rf '" .. dir .. "' '" .. dir2 .. "'")
end

-- A declaration file whose bindings are globals documents each shape-typed one as the
-- library it is: `strings.format` is what a reader writes, and the file the binding was
-- declared in is no part of that name. A binding carrying `@namespace` is left alone,
-- because it names modules an ordinary run documents already.
function M.shapeTypedGlobalsDocumentAsTheirOwnLibraries()
    local source = table.concat(
        {
            "--- Text handling.",
            "local strings: {",
            "    --- Formats a value.",
            "    format: function(fmt: string): string",
            "}",
            "",
            "--- Prints a value.",
            "local say: function(v: any)",
            "",
            "--- Compiler facilities.",
            "--- @namespace demo",
            "local demo: {",
            "    --- Data handling.",
            "    data: {",
            "        --- Encodes a value.",
            "        encode: function(v: any): string",
            "    }",
            "}",
        },
        "\n"
    ) .. "\n"

    local module, errors, libraries = doc.extract(source, "prelude.d.nupp", "globals", {shapesAsModules = true})
    assert(module, errors and errors[1] and errors[1].msg)
    assert(#module.items == 1 and module.items[1].name == "say", "a global was consumed")
    assert(#libraries == 1, #libraries .. " libraries for one shape-typed global")
    assert(libraries[1].name == "strings", libraries[1].name)
    assert(libraries[1].text == "Text handling.", libraries[1].text)
    assert(#libraries[1].items == 1 and libraries[1].items[1].name == "format")
    assert(libraries[1].items[1].path == "strings.format", libraries[1].items[1].path)

    local plain, _, namespaces = doc.extract(source, "prelude.d.nupp", "globals")
    assert(plain, "the same file must still document as one module")
    assert(#namespaces == 1 and namespaces[1].name == "demo.data", "@namespace stopped working")
end

function M.builtinNavigationKeepsEveryDeclaredGlobalAndLibrary()
    local page = assert(require("nupp.tools.doc.stdlib").page({path = "reference/lua"}))
    local catalog = assert(page.navigation)
    local globals, libraries = {}, {}
    for _, entry in ipairs(catalog.globals) do
        globals[entry.name] = entry
    end
    for _, entry in ipairs(catalog.libraries) do
        libraries[entry.name] = entry
    end
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/lua.d.nupp")
    local module, errors, shapes = doc.extract(source, "lua.d.nupp", "globals", {shapesAsModules = true})
    assert(module, errors and errors[1] and errors[1].msg)
    for _, item in ipairs(module.items) do
        if not item.module and (item.kind == "function" or item.kind == "variable") then
            assert(globals[item.name], "missing runtime global " .. item.name)
        end
    end
    for _, library in ipairs(shapes) do
        assert(libraries[library.name], "missing library " .. library.name)
    end
    for _, name in ipairs({"ffi", "string.buffer", "jit.util", "jit.profile", "jit.zone", "jit.vmdef"}) do
        assert(libraries[name], "missing required builtin " .. name)
    end
    for _, name in ipairs({
        "print",
        "type",
        "tostring",
        "tonumber",
        "pairs",
        "ipairs",
        "next",
        "select",
        "rawget",
        "rawset",
        "rawequal",
        "rawlen",
        "setmetatable",
        "getmetatable",
        "assert",
        "error",
        "pcall",
        "xpcall",
        "unpack",
        "require",
        "collectgarbage",
        "load",
        "loadstring",
        "loadfile",
        "setfenv",
        "getfenv",
        "dofile",
        "gcinfo",
        "newproxy",
        "_G",
        "_VERSION",
        "warn"
    }) do
        assert(globals[name], "lost a callable, array, value or function global: " .. name)
    end
    assert(not globals.arg, "raw host argv became a checked public global")
    assert(not globals.__nuppCloseFile, "compiler helper became a public global")
    assert(not libraries.number and not libraries.int32, "primitive types became runtime namespaces")
    assert(not libraries.lpeg and not libraries.re, "third-party modules became Lua builtins")

    local function anchors(entries)
        for _, entry in ipairs(entries) do
            assert(page.markdown:find('<a id="' .. entry.path .. '"></a>', 1, true), "missing anchor " .. entry.path)
            anchors(entry.items or {})
        end
    end

    anchors(catalog.globals)
    anchors(catalog.types)
    for _, library in ipairs(catalog.libraries) do
        assert(page.markdown:find("[`" .. library.name .. "`](", 1, true), "missing module link " .. library.name)
    end
end

function M.builtinNavigationMergesOwnedRootsAndStartsCollapsed()
    local function library(name, members)
        local binding = name:match("([^.]+)$")
        local lines = {"module " .. name, "--[[Public operations.]]", "local " .. binding .. " = {}"}
        for _, member in ipairs(members) do
            lines[#lines + 1] = "--- Performs the operation."
            lines[#lines + 1] = "function " .. binding .. "." .. member .. "(): nil end"
        end
        lines[#lines + 1] = "return " .. binding

        return table.concat(lines, "\n")
    end

    local dir = tempProject({
        ["src/io/init.nupp"] = library("io", {
            "write",
            "style"
        }),
        ["src/io/example.nupp"] = library("io.example", {"join"}),
        ["src/assert.nupp"] = library("assert", {"equal"}),
        ["src/io/cli.nupp"] = library("io.cli", {"parse"}),
        ["src/warn.nupp"] = library("warn", {"emit"}),
        ["src/types/init.nupp"] = library("types", {"newStore"}),
        ["src/example/tools/widget.nupp"] = library("example.tools.widget", {"work"}),
        ["docs/guide.md"] = "# Guide\n\nRead the library.\n"
    })
    assert(
        doc.build(
            dir,
            {include = {"src"}},
            {
                sources = {"src"},
                stdlib = {path = "reference/lua"},
                pages = {{path = "guide", source = "docs/guide.md"}}
            },
            {format = "site", output = "site"}
        ) == 0
    )
    local nested = readFile(dir .. "/site/modules/io/example/index.html")
    local sidebar = assert(nested:match('<aside class="nuppdoc%-sidebar".-</aside>'))
    assert(
        sidebar:find(
            '<details open><summary><a href="../../../reference/lua/index.html">API reference</a></summary>',
            1,
            true
        )
    )
    local api = assert(sidebar:match('>API reference</a></summary>(.*)'))
    assert(not api:find('<details open', 1, true), "an API branch starts open, including the active one")
    for _, name in ipairs({
        "io.cli",
        "assert",
        "warn",
        "io",
        "os",
        "math",
        "string",
        "table",
        "coroutine",
        "bit",
        "jit",
        "debug",
        "package",
        "ffi"
    }) do
        local _, count = api:gsub('data%-module="' .. name .. '"', '')
        assert(count == 1, name .. " has " .. count .. " roots")
    end
    for _, name in ipairs({"string.buffer", "jit.util", "jit.profile", "jit.zone", "jit.vmdef"}) do
        assert(api:find('data-module="' .. name .. '"', 1, true), "missing nested builtin " .. name)
    end
    assert(api:find('>functions</a>', 1, true), "global functions need their own group")
    assert(api:find('>globals</a>', 1, true), "global variables need their own group")
    assert(not api:find('>Intrinsic types</a>', 1, true), "empty root type category")
    assert(not api:find('>Layout reflection</a>', 1, true), "retired root reflection category")
    assert(api:find('<code>types</code>', 1, true), "the public types root disappeared")
    for _, anchor in ipairs({"io.write", "io.style", "io.open", "_G", "print"}) do
        assert(not api:find("#" .. anchor .. '\"', 1, true), "a declaration became a left navigation leaf: " .. anchor)
    end
    assert(api:find('href="../../../modules/assert/index.html"', 1, true), "callable global lost its module page")
    assert(api:find('href="../../../modules/io/cli/index.html"', 1, true), "the CLI module lost its page")
    assert(not api:find('data-module="arg"', 1, true), "the retired argument library has a page")
    assert(api:find('data-module="io.example"', 1, true), "a submodule disappeared")
    assert(api:find('href="../../../modules/io/example/index.html"', 1, true), "a submodule lost its page link")
    for _, name in ipairs({"example", "example.tools", "example.tools.widget"}) do
        assert(api:find('data-module="' .. name .. '"', 1, true), "a qualified namespace disappeared: " .. name)
    end
    local sectionAnchors = {functions = true, globals = true, types = true, annotations = true}
    for anchor in api:gmatch('href="[^\"]*#([^\"]+)"') do
        assert(sectionAnchors[anchor], "a declaration became a left navigation leaf: " .. anchor)
    end
    assert(api:find('href="../../../reference/lua/index.html#globals"', 1, true), "global content link missing")
    assert(api:find('href="../../../reference/lua/index.html#functions"', 1, true), "function content link missing")
    local tableNode = assert(api:match('<li data%-module="table">(.-)</li>'), "a leaf module is not a plain link")
    assert(tableNode:find('href="../../../modules/table/index.html"', 1, true), "a leaf module lost its page")
    assert(not tableNode:find("<details", 1, true), "a leaf module has an empty expander")
    local outline = assert(nested:match('<aside class="nuppdoc%-outline".-</aside>'))
    assert(outline:find('#io.example.join', 1, true), "a declaration disappeared from the page outline")
    assert(nested:find('id="io.example.join"', 1, true), "a declaration disappeared from the body")
    assert(not api:find(">LuaJIT</a>", 1, true), "obsolete LuaJIT navigation entry")
    local aggregate = readFile(dir .. "/site/reference/lua/index.html")
    for anchor in api:gmatch('href="%.%./%.%./%.%./reference/lua/index%.html#([^"]+)"') do
        assert(aggregate:find('id="' .. anchor .. '"', 1, true), "navigation target does not exist: " .. anchor)
    end
    local guide = readFile(dir .. "/site/guide/index.html")
    local guideSidebar = assert(guide:match('<aside class="nuppdoc%-sidebar".-</aside>'))
    assert(not guideSidebar:find('<details open', 1, true), "unrelated API or page branch starts open")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.builtinDeclarationsShareEveryModuleOutputWithOwnedMembers()
    local dir = tempProject({
        [
            "src/io/init.nupp"
        ] = [=[module io
--[[Owned input and output.]]
local io = {}
--- Writes through the owned contract.
function io.write(): string return "owned" end
--- Styles terminal output.
function io.style(): string return "styled" end
return io
]=],
        ["src/debug/bench.nupp"] = [=[module debug.bench
--[[Measures a workload.]]
export const ready = true
]=],
        [
            "src/string/extension.nupp"
        ] = [=[module string.extension
--[[Extends text handling.]]
export const ready = true
]=],
        [
            "src/assert.nupp"
        ] = [=[module assert
--[[Checks program results.]]
local assert = {}
--- Compares two values.
function assert.equal(): nil end
return assert
]=],
        [
            "src/io/cli.nupp"
        ] = [=[module io.cli
--[[Parses command arguments.]]
local cli = {}
--- Parses the arguments.
function cli.parse(): nil end
return cli
]=],
        [
            "src/warn.nupp"
        ] = [=[module warn
--[[Reports warnings.]]
local warn = {}
--- Emits a warning.
function warn.emit(): nil end
return warn
]=],
        [
            "src/jit/zone.nupp"
        ] = [=[module jit.zone
--[[Describes profiler zones.]]
record Zone
    --- A user extension.
    extra: string
end
]=],
    })
    local settings = {sources = {"src"}, stdlib = {path = "reference/lua"}}
    local stdlib = require("nupp.tools.doc.stdlib")
    local original, extractions = stdlib.page, 0
    stdlib.page = function(...)
        extractions = extractions + 1
        return original(...)
    end
    local ok, result = pcall(doc.build, dir, {include = {"src"}}, settings, {format = "both", output = "site"})
    stdlib.page = original
    assert(ok and result == 0, tostring(result))
    assert(extractions == 1, "the index must reuse the module extraction")
    local ioPage = readFile(dir .. "/site/modules/io/index.html")
    assert(ioPage:find('id="io.open"', 1, true), "builtin io.open is absent from the owned page")
    assert(ioPage:find('id="io.style"', 1, true), "owned io.style disappeared")
    local _, writes = ioPage:gsub('id="io%.write"', '')
    assert(writes == 1, "a collided declaration has more than one anchor")
    local ioText = readFile(dir .. "/site/modules/io/llms.txt")
    assert(ioText:find("function(): string", 1, true), "builtin signature replaced the owned contract")
    assert(ioText:find("Writes through the owned contract.", 1, true), "builtin prose replaced owned prose")
    assert(ioText:find("### `open`", 1, true) and ioText:find('<a id="io.style"></a>', 1, true))
    local debug = readFile(dir .. "/site/modules/debug/index.html")
    assert(debug:find('id="debug.getinfo"', 1, true) and debug:find('modules/debug/bench/index.html', 1, true))
    local stringPage = readFile(dir .. "/site/modules/string/index.html")
    assert(stringPage:find('id="string.format"', 1, true))
    assert(not stringPage:find('Nothing is required by this name', 1, true), "builtin kept a namespace placeholder")
    for _, name in ipairs({"assert", "warn"}) do
        local text = readFile(dir .. "/site/modules/" .. name .. "/llms.txt")
        assert(text:find('<a id="' .. name .. '"></a>', 1, true), "missing global declaration on " .. name)
        local _, anchors = text:gsub('<a id="' .. name .. '"></a>', '')
        assert(anchors == 1, "global and module headings duplicate their anchor")
        local rendered = readFile(dir .. "/site/modules/" .. name .. "/index.html")
        local _, renderedAnchors = rendered:gsub('id="' .. name .. '"', '')
        assert(renderedAnchors == 1, "rendered global and module anchors collide")
        assert(text:find("function", 1, true), "global signature missing from " .. name)
    end
    local ffi = readFile(dir .. "/site/modules/ffi/index.html")
    assert(ffi:find('id="ffi.new"', 1, true), "returned record was not projected into the library")
    assert(not ffi:find('id="ffi.ffi"', 1, true), "private returned wrapper became public")
    local util = readFile(dir .. "/site/modules/jit/util/index.html")
    assert(util:find('id="jit.util.funcinfo"', 1, true), "typed returned binding was not projected")
    local zone = readFile(dir .. "/site/modules/jit/zone/index.html")
    for _, anchor in ipairs({"jit.zone.__call", "jit.zone.Zone", "jit.zone.Zone.extra", "jit.zone.Zone.get"}) do
        assert(zone:find('id="' .. anchor .. '"', 1, true), "lost a returned callable/type member: " .. anchor)
    end
    local index = readFile(dir .. "/site/reference/lua/llms.txt")
    assert(not index:find('<a id="ffi.ffi.new"></a>', 1, true), "obsolete wrapper anchor retained")
    for _, name in ipairs({"io", "debug.bench", "string.extension", "assert", "io.cli", "ffi", "jit.util"}) do
        assert(index:find("[`" .. name .. "`](", 1, true), "index misses module " .. name)
    end
    assert(not index:find("```nupp\nlocal open:", 1, true), "index duplicates library signatures")
    assert(not index:find("### `arg`", 1, true), "index duplicates the owned global declaration")
    assert(index:find("### `_G`", 1, true) and index:find("### `_VERSION`", 1, true))
    local api = readFile(dir .. "/site/api.md")
    assert(api:find('<a id="io.open"></a>', 1, true) and api:find('<a id="io.style"></a>', 1, true))
    assert(doc.build(dir, {include = {"src"}}, settings, {format = "json", output = "modules.json"}) == 0)
    local decoded = assert(require("testjson").decode(readFile(dir .. "/modules.json")))
    local modules = {}
    for _, module in ipairs(decoded.modules) do
        modules[module.name] = module
    end
    local names = {}
    for _, item in ipairs(modules.io.items) do
        names[item.path] = item
    end
    assert(names["io.open"] and names["io.style"] and names["io.write"].signature == "function io.write(): string")
    assert(names["io.write"].lua == true, "owned implementations must retain their Lua identity")
    assert(names["io.open"].lua == true and not names["io.style"].lua, "Lua identity is based on the exact public path")

    local function luaHeading(text, id)
        local section = text:match('id="' .. id:gsub("%.", "%%.") .. '"[^>]*><h%d>(.-)</h%d>')
        return section and section:find('>Lua</span>', 1, true) ~= nil
    end

    assert(luaHeading(ioPage, "io.write"), "owned Lua function lacks its badge")
    assert(luaHeading(ioPage, "io.open"), "builtin Lua function lacks its badge")
    assert(not luaHeading(ioPage, "io.style"), "Nupp-only addition was labeled Lua")
    assert(not luaHeading(ffi, "ffi.new"), "LuaJIT-only extension was labeled standard Lua")
    local globalPage = readFile(dir .. "/site/reference/lua/index.html")
    assert(globalPage:find('nuppdoc-kind-Lua">Lua</span>', 1, true), "global Lua function lacks its badge")
    assert(index:find("`print` _[^_]+_ _Lua_"), "Markdown lost Lua provenance")
    local fileRead
    for _, item in ipairs(modules.io.items) do
        if item.path == "io.File" then
            for _, member in ipairs(item.members) do
                if member.name == "read" then
                    fileRead = member
                end
            end
        end
    end
    assert(fileRead and fileRead.lua == true, "Lua file methods lack provenance")
    local globalAssert
    for _, item in ipairs(modules.assert.items) do
        if item.path == "assert" then
            globalAssert = item
        end
    end
    assert(globalAssert and globalAssert.lua, "callable globals with named function types need Lua identity")

    assert(modules.ffi and modules["string.buffer"] and modules["jit.vmdef"])
    assert(not modules.re and not modules.lpeg and not modules.number)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A route a page used to answer at keeps answering, by way of a stub that names
-- where the page went. An overview's redirects have to survive being folded onto
-- the module's own page, which is the one that answers there afterwards.
function M.aMovedPageLeavesAStubWhereItUsedToAnswer()
    local dir = tempProject({
        [
            "nupp.lua"
        ] = [[return {
   include = {"src"},
   build = {default = "docs", targets = {
      docs = {kind = "docs", sources = {"src"}, format = "site",
         outDir = "site", title = "Example", name = "Example",
         pages = {
            {path = "guide", title = "Guide", source = "docs/guide.md",
               redirects = {"tooling/guide", "/manual/guide/index.html"}},
            {path = "modules/math", title = "Arithmetic",
               source = "docs/math-overview.md", redirects = {"library/math"}},
         },
      },
   }},
}
]],
        ["docs/guide.md"] = "# Guide\n\nSetup instructions.\n",
        ["docs/math-overview.md"] = "Prose above the generated API.\n",
        [
            "src/math.nupp"
        ] = table.concat(
            {
                "--[[ Arithmetic. ]]",
                "local math = {}",
                "--- Adds two numbers.",
                "function math.add(left: number, right: number): number",
                "   return left + right",
                "end",
                "return math",
            },
            "\n"
        ) .. "\n",
    })
    capture(("cd '%s' && '%s' build"):format(dir, NUPP))

    local stub = readFile(dir .. "/site/tooling/guide/index.html")
    assert(stub:find('url=../../guide/index.html"', 1, true), stub)
    assert(stub:find('rel="canonical" href="../../guide/index.html"', 1, true), stub)
    assert(stub:find(">Documentation moved</a>", 1, true), stub)

    -- a former route is cleaned the way `path` is, so this spelling lands too
    local rooted = readFile(dir .. "/site/manual/guide/index.html")
    assert(rooted:find('url=../../guide/index.html"', 1, true), rooted)

    -- an overview's former route follows it onto the module's own page
    local module = readFile(dir .. "/site/library/math/index.html")
    assert(module:find('url=../../modules/math/index.html"', 1, true), module)

    -- and the pages themselves still answer where they say they do
    assert(readFile(dir .. "/site/guide/index.html"):find("Setup instructions", 1, true))
    assert(readFile(dir .. "/site/modules/math/index.html"):find("Prose above the generated API", 1, true))
    os.execute("rm -rf '" .. dir .. "'")
end

function M.publicAliasesProjectPrivateDeclarations()
    local dir = tempProject({
        [
            "src/package/init.nupp"
        ] = [[
module package
const implementation = require("package.internal.model")
--- A public message.
export type Message = implementation.Message
]],
        [
            "src/package/internal/model.nupp"
        ] = [[
module package.internal.model
--- The one declaration behind the public name.
export record Message
    --- The message text.
    text: string
    @private token: integer
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local text = readFile(dir .. "/api.md")
    assert(text:find("A public message.", 1, true), text)
    assert(text:find("The message text.", 1, true), "a public alias must document its fields")
    assert(not text:find("private token", 1, true), "a projected alias must preserve member privacy")
    assert(not text:find("# `package.internal.model`", 1, true), "the declaration file remains private")
    assert(not text:find("implementation.Message", 1, true), "the public declaration must not expose the import alias")
    os.execute("rm -rf '" .. dir .. "'")
end

-- A projected declaration is published under the alias's name, so its signature has
-- to spell that name too, whichever way the declaring module wrote it. A declaration
-- file writes it qualified, and every mention of it inside the signature follows the
-- rename; an ordinary module writes it bare, and then only the declared name belongs
-- to the alias. The component here is the case that separates them: its type names a
-- second declaration spelled exactly the way the alias is, and that one keeps its own
-- name.
function M.publicAliasesRenameTheDeclarationHoweverItWasSpelled()
    local dir = tempProject({
        [
            "src/package/init.nupp"
        ] = [[
module package
const model = require("package.internal.model")
const declared = require("package.internal.declared")
--- The transform recorded last frame.
export const PreviousTransform2D = model.PreviousTransform2DComponent
--- One typed range.
export type Buffer = declared.Range
]],
        [
            "src/package/internal/model.nupp"
        ] = [[
module package.internal.model
const components = require("package.components")
--- A transform.
export record PreviousTransform2D
    --- Horizontal offset.
    x: number
end
--- The component describing it.
export const PreviousTransform2DComponent: components.FFIComponent<PreviousTransform2D> = components.make()
]],
        [
            "src/package/internal/declared.nupp"
        ] = [[
module package.internal.declared
local declared = {}

--- One typed range.
record declared.Range
    --- How many elements it holds.
    @readonly count: integer
    --- Narrows it to a shorter one.
    slice: function(borrows self: declared.Range, count: integer): declared.Range
end

return declared
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local text = readFile(dir .. "/api.md")
    -- bare: the binding takes the alias's name, while the type argument keeps the
    -- record's own
    assert(
        text:find("const PreviousTransform2D: components.FFIComponent<PreviousTransform2D>", 1, true),
        "a bare origin declaration kept a name the alias does not publish"
    )
    assert(
        not text:find("PreviousTransform2DComponent", 1, true),
        "the page names a declaration the aliasing module does not export"
    )
    -- qualified: the declaration and every mention of it lose the implementation
    -- qualifier together
    assert(text:find("record Buffer", 1, true), "a qualified origin declaration was not renamed")
    assert(
        text:find("function(borrows self: Buffer, count: integer): Buffer", 1, true),
        "a qualified mention of the projected declaration kept the implementation name"
    )
    assert(not text:find("record declared.Range", 1, true), "the projected declaration exposes the implementation name")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.publicAliasSignaturesUseTheirExportedTypeProvenance()
    local dir = tempProject({
        [
            "src/package/init.nupp"
        ] = [[
module package
const model = require("package.internal.model")
const {type Reader} = require("package.internal.messages")
export type Stream<T> = Reader<T>
export type Envelope = model.Request
export type Other = model.Envelope
export const read = model.read
export const submitted = model.Submitted
]],
        [
            "src/client.nupp"
        ] = [[
module client
const model = require("package.internal.model")
export const fetch = model.read
]],
        [
            "src/package/internal/model.nupp"
        ] = [[
module package.internal.model
const messages = require("package.internal.messages")
const {type Reader} = require("package.internal.messages")
export record Envelope
    value: string
end
export record Request
    reader: messages.Reader<string>
    nested: {read: function<Reader>(value: Reader): Reader, source: Reader<string>}
    label: "package.internal.messages.Reader"
    generic: function<Reader>(value: Reader): Reader
    plucked: Reader<string>
    hidden: Hidden
end
record Hidden
    token: integer
end
export function read(request: Request): messages.Reader<string>
    error("documentation fixture")
end
@comptime export function Submitted<F>(value: F): typepack
    error("documentation fixture")
end
]],
        [
            "src/package/internal/messages.nupp"
        ] = [[
module package.internal.messages
export record Reader<T>
    value: T
    next: Reader<T>?
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = assert(require("testjson").decode(readFile(dir .. "/api.json")))
    local items = {}
    for _, module in ipairs(model.modules) do
        assert(not module.name:find("internal", 1, true), "private source became a public module")
        for _, item in ipairs(module.items) do
            items[item.path] = item
        end
    end
    local request, stream = assert(items["package.Envelope"]), assert(items["package.Stream"])
    local fields = {}
    for _, field in ipairs(request.members) do
        fields[field.name] = field
    end
    assert(fields.reader.type == "Stream<string>", fields.reader.type)
    assert(request.signature == "record Envelope", request.signature)
    assert(fields.generic.type == "function<Reader>(value: Reader): Reader", fields.generic.type)
    assert(fields.plucked.type == "Stream<string>", fields.plucked.type)
    assert(fields.hidden.type == "Hidden", "an unexported type was invented")
    assert(fields.nested.type:find("function<Reader>(value: Reader): Reader", 1, true), fields.nested.type)
    assert(fields.nested.type:find("source: Stream<string>", 1, true), fields.nested.type)
    assert(fields.label.type == '"package.internal.messages.Reader"', "a string literal was rewritten")
    assert(stream.signature == "record Stream<T>", stream.signature)
    assert(stream.members[1].type == "T", "the generic binder was rewritten")
    assert(stream.members[2].type == "Stream<T>?", stream.members[2].type)
    assert(stream.members[2].path == "package.Stream.next", stream.members[2].path)
    local read = assert(items["package.read"])
    assert(read.params[1].type == "Envelope", read.params[1].type)
    assert(read.returns[1].type == "Stream<string>", read.returns[1].type)
    assert(read.signature == "function read(request: Envelope): Stream<string>", read.signature)
    local fetch = assert(items["client.fetch"])
    assert(fetch.params[1].type == "package.Envelope", fetch.params[1].type)
    assert(fetch.returns[1].type == "package.Stream<string>", fetch.returns[1].type)
    local submitted = assert(items["package.submitted"])
    assert(submitted.signature == "@comptime function submitted<F>(value: F): typepack", submitted.signature)
    assert(submitted.comptimeKind == "function", "projection lost the compile-time phase")
    assert(submitted.annotations[1] == "@comptime", "projection lost the annotation")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.indexedProviderAliasesKeepTheirDeclaredFunctionContracts()
    local dir = tempProject({
        [
            "src/api/init.nupp"
        ] = [[
module api
const contract = require("api.contract")
const implementation = require("api.internal.selected")
export type Resource = contract.Resource
export function direct(): contract.Resource
    error("documentation fixture")
end
export const retain: contract.Provider.["retain"] = implementation.retain
export const create: contract.Provider.["create"] = implementation.create
export const describe: contract.Provider.["describe"] = implementation.describe
export const available: implementation.Available = implementation.available
export const unknown: contract.Provider.["missing"] = implementation.unknown
]],
        [
            "src/api/contract.nupp"
        ] = [[
module api.contract
const source = require("api.internal.contract")
export type Provider = source.Provider
export type Resource = source.Resource
]],
        [
            "src/api/internal/selected.nupp"
        ] = [[
module api.internal.selected
export type Available = function(): boolean
]],
        [
            "src/api/internal/contract.nupp"
        ] = [[
module api.internal.contract
export record Resource
    close: @nosuspend function(takes self: Resource): nil
end
export type Create = function<A..., R...>(body: function(A...): R...): thread
export type Describe = @comptime function<T>(value: T): type
export interface Provider
    --- Keeps the borrowed resource through the callback.
    @readonly retain: @nosuspend function<T>(borrows resource: Resource, body: function(Resource): T): T
    @readonly create: Create
    @readonly describe: Describe
end
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = assert(require("testjson").decode(readFile(dir .. "/api.json")))
    local items = {}
    for _, module in ipairs(model.modules) do
        for _, item in ipairs(module.items) do
            items[item.path] = item
        end
    end
    local direct = assert(items["api.direct"])
    assert(direct.kind == "function" and direct.signature == "function direct(): contract.Resource", direct.signature)
    local retain = assert(items["api.retain"])
    assert(retain.kind == "function", retain.kind)
    assert(retain.signature:find("@nosuspend function<T>", 1, true), retain.signature)
    assert(retain.params[1].mode == "borrows", "the provider's borrow mode was lost")
    assert(retain.params[1].type == "Resource", retain.params[1].type)
    assert(retain.params[2].type == "function(Resource): T", retain.params[2].type)
    assert(retain.returns[1].type == "T", retain.returns[1].type)
    assert(retain.typeargs[1].name == "T", "the provider's generic binder was lost")
    assert(retain.doc.text:find("borrowed resource", 1, true), retain.doc.text)
    local create = assert(items["api.create"])
    assert(create.kind == "function" and #create.typeargs == 2, create.signature)
    assert(create.params[1].type == "function(A...): R...", create.params[1].type)
    assert(create.returns[1].type == "thread", create.returns[1].type)
    local describe = assert(items["api.describe"])
    assert(describe.kind == "function" and describe.comptimeKind == "function", describe.signature)
    assert(describe.typeargs[1].name == "T" and describe.returns[1].type == "type", describe.signature)
    local available = assert(items["api.available"])
    assert(available.kind == "function" and available.returns[1].type == "boolean", available.signature)
    assert(available.signature == "const available: function(): boolean", available.signature)
    local unknown = assert(items["api.unknown"])
    assert(unknown.kind == "variable", "an unresolved contract field acquired a callable signature")
    assert(unknown.signature == 'const unknown: contract.Provider.["missing"]', unknown.signature)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.gpuDocumentsApplicationOperationsAndHidesGeneratedBindings()
    local source = readFile(HERE .. "/../src/io/gpu/init.nupp")
    local module = assert(doc.extract(source, "src/io/gpu/init.nupp", "io.gpu"))
    local foundOpen, foundContext = false, false
    for _, item in ipairs(module.items) do
        if item.name == "io.gpu.open" or item.name == "open" then
            foundOpen = true
        end
        assert(
            item.name ~= "Kernel" and item.name ~= "ArtifactSet" and item.name ~= "Binding",
            "generated GPU bindings are implementation details"
        )
        if item.name == "Context" then
            foundContext = true
            for _, member in ipairs(item.members) do
                assert(
                    member.name ~= "compileGenerated"
                    and member.name ~= "bindKernel"
                    and member.name ~= "compilegenerated"
                    and member.name ~= "bindkernel",
                    "generated binding hooks are private Context fields"
                )
            end
        end
    end
    assert(foundOpen and foundContext, "GPU documentation must contain callable application declarations")
end

function M.gpuPublicPageExpandsItsExplicitAliases()
    local files = {}
    for _, path in ipairs({
        "init.nupp",
        "api.nupp",
        "types.nupp",
        "operations.nupp",
        "internal.nupp",
        "layout.nupp",
        "layoutfacts.nupp"
    }) do
        local base = (path == "init.nupp" or path == "layout.nupp") and "src/io/gpu/" or "src/nupp/gpu/"
        files[base .. path] = readFile(HERE .. "/../" .. base .. path)
    end
    local dir = tempProject(files)
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local text = readFile(dir .. "/api.md")
    assert(
        text:find("Opens a compute device through the selected provider", 1, true),
        "open must have a callable declaration"
    )
    assert(
        text:find("Number of logical elements in this buffer or view", 1, true),
        "generic Buffer must document its members"
    )
    assert(
        text:find("Allocates a typed resident device buffer", 1, true),
        "Context must document application operations"
    )
    for _, hidden in ipairs({
        "compileGenerated",
        "bindKernel",
        "compilegenerated",
        "bindkernel",
        "ArtifactSet",
        "# `nupp.gpu.internal`"
    }) do
        assert(not text:find(hidden, 1, true), "public GPU documentation exposes " .. hidden)
    end
    assert(not text:find("implementation%.%w"), "public GPU signatures expose an implementation alias")
    -- Private implementations must not create a second application-facing Binding.
    for _, relative in ipairs({
        "src/io/gpu/spi.nupp",
        "src/nupp/runtime/provider/nativegpu.nupp",
        "src/nupp/runtime/browser/webgpu/internal.nupp",
    }) do
        local destination = dir .. "/" .. relative
        assert(os.execute("mkdir -p '" .. destination:match("^(.*)/[^/]+$") .. "'") == 0)
        local file = assert(io.open(destination, "wb"))
        file:write(readFile(HERE .. "/../" .. relative))
        file:close()
    end
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = require("testjson").decode(readFile(dir .. "/api.json"))
    local providerBinding
    for _, module in ipairs(model.modules) do
        local paths = {}
        for _, item in ipairs(module.items) do
            assert(not paths[item.path], "duplicate declaration " .. item.path)
            paths[item.path] = true
            if item.path == "io.gpu.Buffer" then
                assert(item.kind == "interface", "a private implementation replaced the exported Buffer contract")
            end
            assert(item.path ~= "io.gpu.Binding", "a private provider record leaked onto the application API")
            if item.path == "io.gpu.spi.Binding" then
                providerBinding = item
            end
        end
    end
    assert(providerBinding and #providerBinding.members > 0, "the real provider Binding contract disappeared")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.ioPublicPageKeepsStorageAndScalarContracts()
    local files = {}
    for _, path in ipairs({
        "nupp/runtime/standardio.nupp",
        "nupp/io.nupp",
        "nupp/io/internal/bytes.nupp",
        "nupp/io/internal/scalars.nupp",
    }) do
        files["src/" .. path] = readFile(HERE .. "/../src/" .. path)
    end
    local dir = tempProject(files)
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local text = readFile(dir .. "/api.md")
    for _, public in ipairs({
        "readspan",
        "writespan",
        "reservewrite",
        "readinto",
        "readuint32",
        "Reader.scalar",
        "Writer.scalar",
        "Buffer.reader",
        "Buffer.writer",
        "ByteView.reader",
        "ScalarStream",
        "Reader.lines"
    }) do
        assert(text:find(public, 1, true), "I/O documentation lost " .. public)
    end
    for _, hidden in ipairs({
        "_pending",
        "_ownsBuffer",
        "newsreader",
        "newswriter",
        "Buffer.newreader",
        "Buffer.newwriter",
        "# `nupp.io.internal",
        "bytes.Reader",
        "scalars.ScalarReader"
    }) do
        assert(not text:find(hidden, 1, true), "I/O documentation exposes " .. hidden)
    end
    os.execute("rm -rf '" .. dir .. "'")
end

function M.nestedAliasesShowTheirPublicContracts()
    local testAssert = require("assert")
    local dir = tempProject({
        [
            "src/errors.nupp"
        ] = [[@!internal
module errors
export record Error
    --- Routes standard error.
    type Mode = "pipe" | "inherit"
end
]],
        [
            "src/shared.nupp"
        ] = [[@!internal
module shared
const {type Error} = require("errors")
--- Options for starting a child.
export type Options = {
    --- The executable and its arguments.
    args: {string},
    --- Routes standard error.
    stderr: Error.Mode?
}
--- How a child ended.
export interface Exit
    --- The exit status.
    exitcode: integer
end
--- Captured child output.
export record Cycle
    --- Refers to the containing type.
    type Same = Cycle
end
export record Result
    --- How the child ended.
    exit: Exit
    --- Captured bytes.
    output: string
end
]],
        [
            "src/implementation.nupp"
        ] = [[@!internal
module implementation
local shared = require("shared")
local implementation = {}
record implementation.Reader
    @private state: integer
    @private hiddenMethod: function(self: implementation.Reader): nil
    --- Whether input has ended.
    function isended(self): boolean return true end
end
record implementation.Process
    --- A readable stream.
    type Reader = implementation.Reader
    --- Starts a child.
    type Options = shared.Options
    --- Describes an exit.
    type Exit = shared.Exit
    --- Holds captured output.
    type Result = shared.Result
end
function implementation.Reader.hiddenMethod(self): nil end
export = implementation
]],
        [
            "src/api.nupp"
        ] = [[module api
local implementation = require("implementation")
local shared = require("shared")
local errors = require("errors")
--- An I/O failure.
export type Error = errors.Error
--- A recursive alias.
export type Cycle = shared.Cycle
--- A running child.
export type Process = implementation.Process
]],
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "json", output = "api.json"}) == 0)
    local model = require("testjson").decode(readFile(dir .. "/api.json"))
    local process
    for _, module in ipairs(model.modules) do
        for _, item in ipairs(module.items) do
            if item.path == "api.Process" then
                process = item
            end
        end
    end
    assert(process)
    local members = {}
    for _, member in ipairs(process.members) do
        members[member.name] = member
    end
    assert(members.Options.isType and members.Exit.isType and members.Result.isType and members.Reader.isType)
    testAssert.eq(members.Reader.members[1].path, "api.Process.Reader.isended")
    testAssert.eq(#members.Reader.members, 1, "private fields and their out-of-line bodies stay hidden")
    testAssert.eq(members.Options.members[1].path, "api.Process.Options.args")
    testAssert.eq(members.Options.members[1].text, "The executable and its arguments.")
    testAssert.eq(members.Options.members[2].type, "Error.Mode?")
    testAssert.eq(members.Exit.members[1].path, "api.Process.Exit.exitcode")
    testAssert.eq(members.Result.members[1].type, "Process.Exit")
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local markdown = readFile(dir .. "/api.md")
    assert(not markdown:find("shared.Options", 1, true), markdown)
    assert(not markdown:find("shared.Exit", 1, true), markdown)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Every module the site publishes says something. A page with neither a blurb nor a
-- documented member is a name in the index that answers nothing when followed, and it
-- reaches the site by default: the extractor publishes whatever is not `@!internal`.
-- Both ways out are one line -- `@!internal` when the module is wiring nobody outside
-- the tree requires, a sentence above `module` when it is public -- so this asks for
-- no judgement about which.
--
-- The namespace index pages are exempt. `nupp.io` is a name the modules beneath it
-- imply rather than a file anyone wrote, and its page is generated from what it holds.
function M.everyPublishedModuleSaysWhatItIs()
    local root = HERE .. "/.."
    local config = assert(require("nupp.tools.build.manifest").load(root))
    local settings = assert(doc.manifestSettings(config, "docs"))
    local output = os.tmpname()
    assert(doc.build(root, config, settings, {format = "json", output = output}) == 0)
    local model = require("testjson").decode(readFile(output))
    os.remove(output)

    local empty = {}
    for _, module in ipairs(model.modules) do
        if not module.namespace and module.text == "" and #module.items == 0 then
            empty[#empty + 1] = module.name .. " (" .. tostring(module.path) .. ")"
        end
    end
    assert(#model.modules > 0, "documented no modules at all")
    assert(
        #empty == 0,
        "modules published with nothing on their page:\n  " .. table.concat(
            empty,
            "\n  "
        ) .. "\nMark each `@!internal` or give it a blurb above `module`."
    )
end

-- The versions table in the distribution reference is a registry: every number that
-- versions a format another process reads, beside where it is declared. Each row is
-- read back out of its declaration here, so bumping one without the other fails.
local VERSION_SOURCES = {
    ["Native provider ABI"] = {"native/include/nupp_native.h", "#define NUPP_NATIVE_ABI_VERSION (%d+)u"},
    ["Embedding ABI"] = {"native/crates/host/src/embed.rs", "const EMBED_ABI_VERSION: u32 = (%d+);"},
    ["Compiler host ABI"] = {"src/nupp/tools/build/package.nupp", "local hostAbiVersion = (%d+)"},
    ["Payload trailer"] = {"native/crates/host/src/payload.rs", "const FORMAT_VERSION: u32 = (%d+);"},
    ["AOT runtime ABI"] = {"native/crates/native/c/ks_rt.c", "#define KS_RT_ABI_VERSION (%d+)u"},
    ["Browser application manifest"] = {"runtime/luajit/app-runtime.mjs", "manifest%.schema !== (%d+)"},
    ["AOT units manifest"] = {"src/nupp/tools/build/aot.nupp", "aot%.UNITS_SCHEMA_VERSION = (%d+)"},
    [
        "AOT component manifest"
    ] = {"src/nupp/tools/build/aot.nupp", "document = sortedJson%({%s*schemaVersion = (%d+),%s*component"},
    ["Link kit"] = {"src/nupp/tools/build/aotllvm.nupp", "manifest%.schemaVersion ~= (%d+)"},
    ["Documentation model"] = {"src/nupp/tools/doc/init.nupp", "schemaVersion = (%d+), modules = model"},
    ["Coverage report"] = {"src/nupp/tools/coverage.nupp", "export const SCHEMA_VERSION = (%d+)"},
    ["Test report"] = {"src/nupp/tools/cli/test.nupp", "schemaVersion = {%s*type = \"integer\",%s*enum = {(%d+)}"},
    ["Bench record"] = {"src/debug/bench.nupp", "bench%.schema = (%d+)"},
    ["Optimizer remarks"] = {"src/nupp/tools/cli/compile.nupp", "local document = {%s*schema = (%d+),"},
    ["Trace reason catalog"] = {"src/debug/profile/trace.nupp", "trace%.catalogversion = (%d+)"},
    ["GPU cost records"] = {"native/crates/gpu/src/costs.rs", "values%[\"schemaVersion\"%] = json!%((%d+)%)"},
}

function M.theVersionsRegistryMatchesTheConstants()
    local root = HERE .. "/.."
    -- A Windows checkout carries CRLF line endings; the table is read as text.
    local page = readFile(root .. "/docs/reference/distribution.md"):gsub("\r\n", "\n")
    local section = assert(page:match("\n## Versions\n(.-)\n## "), "distribution.md has a Versions section")
    local listed = {}
    for format, version in section:gmatch("\n| ([^|]-) | (%d+) | [^\n]*") do
        listed[format] = tonumber(version)
    end
    for format, source in pairs(VERSION_SOURCES) do
        assert(listed[format], "the Versions table has no row for " .. format)
        local text = readFile(root .. "/" .. source[1])
        local declared = tonumber(text:match(source[2]))
        assert(declared, format .. ": no version found in " .. source[1])
        assert(
            declared == listed[format],
            ("%s is %d in %s and %d in the Versions table"):format(format, declared, source[1], listed[format])
        )
    end
    for format in pairs(listed) do
        assert(VERSION_SOURCES[format], "the Versions table lists " .. format .. ", which nothing checks")
    end
end

function M.omitsVoidReturnsAndKeepsNullableAndMultipleResults()
    for _, case in ipairs({
        {source = "export function finish(): nil end", returns = false},
        {
            source = "export record Worker\nfunction finish(self): nil end\nflush: function(self: Worker): nil\nend",
            returns = false
        },
        {source = "export function fetch(): string? end", returns = true},
        {source = "export function fetch(): (nil, string) end", returns = true},
    }) do
        local module = assert(doc.extract(case.source, "src/example.nupp", "example"))
        local rendered = {}
        renderMarkdownItem(rendered, module.items[1])
        local html = table.concat(rendered)
        local markdown = doc.markdown({module})
        assert((html:find(">Returns<a", 1, true) ~= nil) == case.returns, html)
        assert((markdown:find(" Returns\n", 1, true) ~= nil) == case.returns, markdown)
    end
end

return M
