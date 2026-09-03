local doc = require("nupp.compiler.doc")
local highlight = require("nupp.compiler.doc.highlight")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local pipe = assert(io.popen("pwd"))
    HERE = pipe:read("*l") .. "/" .. HERE
    pipe:close()
end
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

-- An example is the one place a doc comment writes a line that looks like a tag and
-- is not one, so a fence has to suspend tag parsing rather than eat the annotation
-- the example exists to show.
function M.aFencedExampleKeepsAnAnnotationRatherThanReadingItAsATag()
    local source = table.concat(
        {
            "--- Renders a value.",
            "---",
            "--- ```nupp",
            "--- @derive(nupp.derive.Debug)",
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
        render.doc.text:find("@derive(nupp.derive.Debug)", 1, true),
        "the annotation stays in the example: " .. render.doc.text
    )
    assert(render.doc.tags.derive == nil, "and never became a tag")
    assert(
        render.returns[1] and render.returns[1].text == "the rendering",
        "a tag written after the fence is still read"
    )
end

function M.tildeDocFencesSuspendTagParsingUntilTheirMatchingCloser()
    local parsed = require("nupp.compiler.docblock").parse({
        "Example:",
        "~~~~nupp",
        "@raises shown, not declared",
        "~~~",
        "~~~~",
        "@raises declared",
    })
    assert(parsed.text:find("@raises shown, not declared", 1, true), parsed.text)
    assert(#parsed.raises == 1 and parsed.raises[1] == "declared")
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
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num", {includeAll = true}))
    assert(module.text == "# Numbers\n\nDeclarations for the **number** library.", module.text)
end

function M.documentsTypedBindingsAsTheFunctionsTheyDeclare()
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num", {includeAll = true}))
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

function M.documentsComptimeCallablesAndTypeHandlesAsCompilerOnly()
    local source = table.concat(
        {
            "--- Builds a type.",
            "comptime function newType(T: type): type",
            "   return T",
            "end",
            "",
            "--- Another type builder.",
            "local factory: comptime function(T: type): type",
            "",
            "--- A type handle.",
            "local text: comptime type",
            "",
            "--- Compiler operations.",
            "local record Compiler",
            "   --- Builds through a member.",
            "   build: comptime function(T: type): type",
            "",
            "   --- Holds a type through a member.",
            "   value: comptime type",
            "end",
        },
        "\n"
    ) .. "\n"
    local module = assert(doc.extract(source, "src/meta.d.nupp", "meta", {includeAll = true}))
    local items = {}
    for _, item in ipairs(module.items) do
        items[item.name] = item
    end

    assert(items.newType.kind == "function", items.newType.kind)
    assert(items.newType.comptimeKind == "function", items.newType.comptimeKind)
    assert(items.newType.signature == "comptime function newType(T: type): type", items.newType.signature)
    assert(items.factory.kind == "function" and items.factory.comptimeKind == "function")
    assert(items.text.kind == "variable" and items.text.comptimeKind == "type")

    local members = {}
    for _, member in ipairs(items.Compiler.members) do
        members[member.name] = member
    end
    assert(members.build.isFunction and members.build.comptimeKind == "function")
    assert(not members.value.isFunction and members.value.comptimeKind == "type")

    local api = require("nupp.compiler.doc.api")
    local summary = api.moduleSummary(module)
    assert(not summary:find("<h3>Constructors</h3>", 1, true), summary)
    assert(summary:find("nuppdoc-kind-comptime-function", 1, true), summary)
    assert(summary:find(">comptime function</span>", 1, true), summary)
    assert(summary:find("nuppdoc-kind-comptime-type", 1, true), summary)

    local rendered = {}
    api.renderHtmlItem(rendered, items.Compiler)
    local html = table.concat(rendered)
    assert(html:find("nuppdoc-kind-comptime-function", 1, true), html)
    assert(html:find("nuppdoc-kind-comptime-type", 1, true), html)

    local markdown = doc.markdown({module})
    assert(markdown:find("### `newType` _comptime function_", 1, true), markdown)
    assert(markdown:find("comptime function newType(T: type): type", 1, true), markdown)
    assert(markdown:find("##### `build` _comptime function_", 1, true), markdown)
    assert(markdown:find("##### `value` _comptime type_", 1, true), markdown)

    local model = require("testjson").decode(doc.json({module}))
    assert(model.schemaVersion == 2)
    local modelItems = {}
    for _, item in ipairs(model.modules[1].items) do
        modelItems[item.name] = item
    end
    assert(modelItems.newType.comptimeKind == "function")
    assert(modelItems.text.comptimeKind == "type")
end

function M.documentsFunctionTypedRecordFieldsAsMethods()
    local module = assert(doc.extract(DECLARATIONS, "src/num.d.nupp", "num", {includeAll = true}))
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
    local markdown = doc.markdown({module})
    assert(markdown:find("#### Methods", 1, true), "methods section missing")
    assert(markdown:find("###### Arguments", 1, true), "method arguments missing")
    assert(markdown:find("#### Fields", 1, true), "fields section missing")
    assert(markdown:find('<a id="num.Counter.count"></a>', 1, true), "field anchor missing")
    assert(markdown:find("##### `count`", 1, true), "field sub-heading missing")
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
    local module = assert(doc.extract(NESTED_DECLARATIONS, "src/config.d.nupp", "config", {includeAll = true}))
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
    assert(markdown:find("#### Types", 1, true), "types section missing")
    assert(markdown:find("##### `Settings` _record_", 1, true), "nested type heading missing")
    assert(markdown:find("###### Methods", 1, true), "nested type's own methods section missing")
    assert(markdown:find("###### `enabled`", 1, true), "nested type's own field sub-heading missing")
    assert(
        markdown:find('<a id="config.Config.Settings.enabled"></a>', 1, true),
        "nested type's own field anchor missing"
    )
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
    local module = assert(doc.extract(ANNOTATED_DECLARATIONS, "src/handle.d.nupp", "handle", {includeAll = true}))
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
    local module = assert(doc.extract(ANNOTATED_DECLARATIONS, "src/handle.d.nupp", "handle", {includeAll = true}))
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
    assert(markdown:find("| `takes self` |", 1, true), "the parameter mode is not rendered")
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
    local module = assert(doc.extract(source, "src/view.nupp", "view", {includeAll = true}))
    local view = assert(module.items[1])
    assert(view.signature == "function view(borrows source: uint8[?]): ByteSpan", view.signature)
    assert(view.returns[1].type == "ByteSpan", view.returns[1].type)

    local markdown = doc.markdown({module})
    assert(markdown:find("function view(borrows source: uint8[?]): ByteSpan", 1, true), markdown)
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
    local module = assert(doc.extract(source, "src/client.nupp", "client", {includeAll = true}))
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
    local module = assert(doc.extract(source, "src/task.nupp", "task", {includeAll = true, includePrivate = true}))
    local task = module.items[1]
    assert(
        task.signature == table.concat(
            {
                "record Task<T is Value> is Named, Runnable where true",
                "    metamethod __call: function(self, value: T): self",
                "    function describe(prefix: string): string end",
                "end",
            },
            "\n"
        ),
        task.signature
    )
    assert(not task.signature:find("---", 1, true), task.signature)
    assert(task.members[1].name == "__call" and task.members[1].isMetamethod)
    assert(task.members[2].name == "describe" and task.members[2].isFunction)
    assert(task.members[2].params[1].name == "prefix")
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
            "--- @raises when it already stopped",
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
    local module = assert(doc.extract(source, "src/job.nupp", "job", {includeAll = true, includePrivate = true}))
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
    assert(stop.raises[1] == "when it already stopped", "raises must fold in too")
    assert(#worker.members == 2, "folding must not duplicate a declared method")
    -- A type this module does not document has nowhere to fold into, and dropping the
    -- method would lose it entirely.
    assert(listed["Elsewhere:extend"], "an orphan method stays a listed function")
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
            "--- @raises when it already stopped",
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
    assert(stop.raises[1] == "when it already stopped", "raises must fold in too")
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
    local module = assert(doc.extract(source, "src/user.nupp", "user", {includeAll = true, includePrivate = true}))
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
    assert(
        named.signature == table.concat({"interface Named", "    function label(self): string end", "end",}, "\n"),
        named.signature
    )
    assert(
        user.signature == table.concat(
            {
                "record User is Named",
                "    name: string",
                "    constructor(name: string) end",
                "",
                "    function label(self): string end",
                "end",
            },
            "\n"
        ),
        user.signature
    )
    for _, signature in ipairs({named.signature, user.signature}) do
        assert(not signature:find("prefix", 1, true), signature)
        assert(not signature:find("return", 1, true), signature)
        assert(not signature:find("self.name =", 1, true), signature)
    end
end

function M.documentsDeclarationsWrappedInAnnotations()
    local source = table.concat(
        {
            "--- Opens an owned handle.",
            "--- @param path Where to open it.",
            "--- @return The owned handle.",
            "function resources.open(path: string): affine(LuaFile, close)",
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
    local bytes = assert(byName["Bytes"], "the record was not documented")
    assert(bytes.signature:find("affine(Reader, _)", 1, true), bytes.signature)
    assert(not bytes.signature:find("__destroyReader", 1, true), bytes.signature)
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
    local module, errors, extra = doc.extract(source, "src/lib.d.nupp", "lib", {includeAll = true})
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

    local private, privateErrors, privateExtra = doc.extract(source, "src/lib.d.nupp", "lib", {
        includeAll = true,
        includePrivate = true,
    })
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
            "   --- Data helpers.",
            "   data: {",
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
        extra and extra[1] and extra[1].name == "nupp.data",
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
        if candidate.name == "nupp.types" then
            types = candidate
        end
    end
    assert(types, "the prelude did not synthesize nupp.types")

    local foundType, foundFunction = false, false
    for _, item in ipairs(types.items) do
        if item.name == "string" then
            foundType = item.comptimeKind == "type"
        elseif item.name == "optional" then
            foundFunction = item.comptimeKind == "function"
        end
    end
    assert(foundType, "nupp.types.string lost its comptime type kind")
    assert(foundFunction, "nupp.types.optional lost its comptime function kind")
end

-- The public JSON module documents its own complete surface; the host declaration is
-- only an implementation boundary.
function M.standardJsonApiHasCompleteDocumentation()
    local path = "src/nupp/data/json/init.nupp"
    local source = readFile(HERE .. "/../" .. path)
    local module, errors = doc.extract(source, path, "nupp.data.json")
    assert(module, errors and errors[1] and errors[1].msg)

    local expected = {
        EncodedValue = true,
        EncodedString = true,
        JSONEncodable = true,
        Writer = true,
        decode = true,
        pull = true,
        arrayOf = true,
        asArray = true,
        asObject = true,
        isArray = true,
        encode = true,
        serialize = true,
        encoded = true,
        encodedString = true,
        verified = true,
        verifiedString = true,
        writer = true,
        decodeAs = true,
        encodeAs = true,
        encodeRecord = true,
        writeAs = true,
        writeRecord = true,
        newCodec = true,
        NULL = true,
        EMPTY_ARRAY = true,
        EMPTY_OBJECT = true,
    }
    local callable = {
        decode = true,
        pull = true,
        arrayOf = true,
        asArray = true,
        asObject = true,
        isArray = true,
        encode = true,
        serialize = true,
        encoded = true,
        encodedString = true,
        verified = true,
        verifiedString = true,
        writer = true,
        decodeAs = true,
        encodeAs = true,
        encodeRecord = true,
        writeAs = true,
        writeRecord = true,
        newCodec = true,
    }
    local writer
    for _, item in ipairs(module.items) do
        local prefix = "nupp.data.json." .. item.name
        assert(expected[item.name], prefix .. " is not part of the expected surface")
        expected[item.name] = nil
        assert(item.doc.text ~= "", prefix .. " has no documentation")
        if callable[item.name] then
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
    assert(writer, "the JSON module did not document nupp.data.json.Writer")
    for _, member in ipairs(writer.members or {}) do
        local prefix = "nupp.data.json.Writer." .. member.name
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

-- The data module owns hashes, UUIDs, and Bitset directly; only substantial sibling
-- facilities remain separate modules.
function M.standardDataApiHasCompleteDocumentation()
    local modules = {"src/nupp/data/utf8.nupp", "src/nupp/data/init.nupp",}
    for _, relative in ipairs(modules) do
        local source = assert(readFile(HERE .. "/../" .. relative), "no module at " .. relative)
        local name = relative:match("src/nupp/(.+)%.nupp"):gsub("/", "."):gsub("%.init$", "")
        local module, errors = doc.extract(source, relative, "nupp." .. name)
        assert(module, errors and errors[1] and errors[1].msg)
        assert(module.text ~= "", "nupp." .. name .. " has no module documentation")
        for _, item in ipairs(module.items) do
            local prefix = "nupp." .. name .. "." .. item.name
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

-- io is four modules now rather than one record in the prelude, so what used to be
-- asserted about nested declarations is asserted about each module's own surface.
function M.standardIOApiHasCompleteDocumentation()
    local modules = {
        [
            "src/nupp/io/init.nupp"
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
            "src/nupp/io/path/init.nupp"
        ] = {types = {Path = true,}, functions = {newPath = true, currentDirectory = true, separator = true,},},
        [
            "src/nupp/io/uri.nupp"
        ] = {types = {URI = true, Components = true,}, functions = {newURI = true, validate = true, isURI = true,},},
        [
            "src/nupp/io/files.nupp"
        ] = {
            types = {File = true, TemporaryPath = true, Info = true, Entry = true,},
            functions = {info = true, open = true, read = true, glob = true,},
        },
    }
    for relative, expected in pairs(modules) do
        local source = assert(readFile(HERE .. "/../" .. relative), "no module at " .. relative)
        local name = relative:match("src/nupp/(.+)%.nupp"):gsub("/", "."):gsub("%.init$", "")
        local module, errors = doc.extract(source, relative, "nupp." .. name)
        assert(module, errors and errors[1] and errors[1].msg)
        assert(module.text ~= "", "nupp." .. name .. " has no module documentation")
        local foundTypes, foundFunctions = {}, {}
        for _, item in ipairs(module.items) do
            local prefix = "nupp." .. name .. "." .. item.name
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
            assert(foundTypes[member], "nupp." .. name .. " did not document " .. member)
        end
        for member in pairs(expected.functions) do
            assert(foundFunctions[member], "nupp." .. name .. " did not document " .. member)
        end
    end

    -- Paths are interned by `newPath`; direct construction is intentionally
    -- unavailable.
    local path = assert(readFile(HERE .. "/../src/nupp/io/path/init.nupp"))
    local module = assert(doc.extract(path, "src/nupp/io/path/init.nupp", "nupp.io.path"))
    local factory
    for _, item in ipairs(module.items) do
        if item.name == "newPath" then
            factory = item
        end
    end
    assert(factory, "nupp.io.path did not document newPath")
    assert(factory.doc.text:find("#### Examples", 1, true), "path.newPath has no examples")
    assert(
        factory.doc.text:find('path.newPath("src", "main.nupp")', 1, true),
        "path.newPath has no component-joining example"
    )

    -- URIs are likewise interned by `newURI`; their exported record is a value type,
    -- not a public construction surface.
    local uri = assert(readFile(HERE .. "/../src/nupp/io/uri.nupp"))
    local uriModule = assert(doc.extract(uri, "src/nupp/io/uri.nupp", "nupp.io.uri"))
    local uriFactory
    for _, item in ipairs(uriModule.items) do
        if item.name == "newURI" then
            uriFactory = item
        end
    end
    assert(uriFactory, "nupp.io.uri did not document newURI")
    assert(uriFactory.doc.text:find("#### Examples", 1, true), "uri.newURI has no examples")
    assert(
        uriFactory.doc.text:find('uri.newURI("https://example.com/a?b=1")', 1, true),
        "uri.newURI has no parsing example"
    )
end

function M.standardPegApiDocumentsItsTypesExpressionsAndExamples()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors = doc.extract(source, "src/nupp/compiler/decls/prelude.d.nupp", "nupp.compiler.decls.prelude")
    assert(module, errors and errors[1] and errors[1].msg)

    local peg
    for _, item in ipairs(module.items) do
        if item.name == "peg" then
            peg = item
        end
    end
    assert(peg, "the prelude did not document nupp.peg")
    assert(peg.doc.text:find("## Expression syntax", 1, true), "nupp.peg has no expression guide")
    assert(peg.doc.text:find("const Identifier = comptime do", 1, true), "nupp.peg has no static matcher example")
    assert(
        peg.doc.text:find("function(Definitions): nupp.peg.Peg<integer>", 1, true),
        "nupp.peg has no definition factory example"
    )

    local expected = {
        Backend = true,
        Action = true,
        Actions = true,
        Definitions = true,
        CompileOptions = true,
        Peg = true,
        compile = true,
    }
    for _, member in ipairs(peg.members) do
        if expected[member.name] then
            assert(member.text ~= "", "nupp.peg." .. member.name .. " has no documentation")
            expected[member.name] = nil
        end
        if member.name == "Peg" then
            assert(peg.signature:find("match: function", 1, true), "nupp.peg.Peg does not expose match")
        elseif member.name == "compile" then
            assert(#member.params == 2, "nupp.peg.compile lost its parameters")
            assert(
                member.params[1].text ~= "" and member.params[2].text ~= "",
                "nupp.peg.compile parameters need documentation"
            )
            assert(#member.returns == 1 and member.returns[1].text ~= "", "nupp.peg.compile return needs documentation")
        end
    end
    for name in pairs(expected) do
        error("the prelude did not document nupp.peg." .. name)
    end
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
    assert(reflect, "the prelude did not document nupp.reflect")

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
        fieldCodec = true,
    }
    local examples = {
        AnnotationArgument = true,
        Field = true,
        Node = true,
        SoAInfo = true,
        Info = true,
        FieldCodec = true,
        fieldCodec = true,
    }
    local _, moduleExamples = reflect.doc.text:gsub("```nupp", "")
    assert(moduleExamples >= 2, "nupp.reflect needs root and graph examples")
    for _, member in ipairs(reflect.members) do
        if expected[member.name] then
            assert(member.text ~= "", "nupp.reflect." .. member.name .. " has no documentation")
            expected[member.name] = nil
        end
        if examples[member.name] then
            assert(member.text:find("```nupp", 1, true), "nupp.reflect." .. member.name .. " has no source example")
            examples[member.name] = nil
        end
        if member.name == "fieldCodec" then
            assert(member.comptimeKind == "function", "nupp.reflect.fieldCodec must document its comptime-only phase")
        end
    end
    for name in pairs(expected) do
        error("the prelude did not document nupp.reflect." .. name)
    end
    for name in pairs(examples) do
        error("the prelude did not keep the nupp.reflect." .. name .. " example")
    end
end

-- A host boundary is an implementation detail of the module that stands on it, so it
-- must never reach the documented surface. These used to be invisible by sitting
-- under nupp.compiler.decls, where the internal root hid them. They sit beside their
-- modules now, inside the namespace a reader browses, so each has to say so itself.
function M.hostBoundariesDeclareThemselvesInternal()
    local boundaries = {"src/nupp/workers/native.d.nupp",}
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

    local expected = {["nupp.math.vec2"] = "add", ["nupp.peg"] = "compile",}
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
    assert(closeable.module == "nupp", "Closeable is not owned by the nupp module")
    assert(
        closeable.signature:find("affine interface nupp.Closeable", 1, true),
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
    -- Math, Vec2 and the three fixed-width namespaces retain private top-level backing
    -- records. Nothing nests one any more: Files.Library was the last, and it left with
    -- io.
    assert(topLevelLibraries == 5, "private docs lost top-level backing records")
    assert(nestedLibraries == 0, "private docs grew a nested backing record")
end

function M.standardMathApiHasCompleteDocumentation()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    local module, errors, extra = doc.extract(
        source,
        "src/nupp/compiler/decls/prelude.d.nupp",
        "nupp.compiler.decls.prelude"
    )
    assert(module, errors and errors[1] and errors[1].msg)

    local mathModule, vec2Module
    for _, candidate in ipairs(extra or {}) do
        if candidate.name == "nupp.math" then
            mathModule = candidate
        end
        if candidate.name == "nupp.math.vec2" then
            vec2Module = candidate
        end
    end
    assert(mathModule, "the prelude did not synthesize nupp.math")
    assert(vec2Module, "the prelude did not synthesize nupp.math.vec2")
    assert(#vec2Module.items > 0, "nupp.math.vec2 has no operations")
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
    for _, item in ipairs(mathModule.items) do
        assert(item.name ~= "vec2", "vec2 must be a nested module, not a value")
    end
    for _, item in ipairs(module.items) do
        assert(
            item.name ~= "MathLibrary" and item.name ~= "Vec2Library",
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

function M.standardManagedGroupApiHasCompleteDocumentation()
    local source = readFile(HERE .. "/../src/nupp/compiler/decls/prelude.d.nupp")
    assert(source:find("interface nupp.ManagedGroup", 1, true), "the root ownership surface lost ManagedGroup")
    assert(source:find("managedGroup: function", 1, true), "the root ownership surface lost its ManagedGroup factory")
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
    assert(listed["m.reserve"], "the module's own function must stay listed")
    assert(
        not listed["malloc"] and not listed["Header"],
        "a cdef this module only calls is not part of what it publishes"
    )
    local complete = assert(doc.extract(plumbing, "src/m.nupp", "m", {includeAll = true}))
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
    local public = assert(doc.extract(source, "src/public.nupp", "public"))
    local signature
    for _, item in ipairs(public.items) do
        if item.name == "Public" then
            signature = item.signature
        end
    end
    assert(signature:find("visible", 1, true), signature)
    for _, hidden in ipairs({"_secret", "_calculate", "_Backing", "_Key", "spare"}) do
        assert(not signature:find(hidden, 1, true), hidden .. " leaked into the rendered declaration: " .. signature)
    end
    local complete = assert(doc.extract(source, "src/public.nupp", "public", {includePrivate = true}))
    for _, item in ipairs(complete.items) do
        if item.name == "Public" then
            signature = item.signature
        end
    end
    for _, shown in ipairs({"_secret", "_calculate", "_Backing", "_Key", "spare"}) do
        assert(signature:find(shown, 1, true), "private docs lost " .. shown .. ": " .. signature)
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
    assert(record.signature:find("__eq", 1, true), record.signature)
    assert(not record.signature:find("_scratch", 1, true), record.signature)
    assert(not record.signature:find("__len", 1, true), record.signature)
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
            "   --- Parsing.",
            "   peg: {",
            "      --- Matches a subject.",
            "      match: function(): boolean",
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
    local module, errors, extra = doc.extract(source, "src/lib.d.nupp", "lib", {includeAll = true})
    assert(module, errors and errors[1] and errors[1].msg)
    local byName = {}
    for _, mod in ipairs(extra or {}) do
        byName[mod.name] = mod
    end
    assert(byName["lib.peg"], "a public namespace was dropped")
    assert(not byName["lib.internal"], "a namespace named internal leaked into public docs")

    local private, privateErrors, privateExtra = doc.extract(source, "src/lib.d.nupp", "lib", {
        includeAll = true,
        includePrivate = true,
    })
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
    assert(markdown:find("| The `left` value. |", 1, true), markdown)
end

function M.markdownMatchesTheNuppdocShape()
    local module = assert(doc.extract(SOURCE, "src/math.nupp", "math"))
    local markdown = doc.markdown({module}, "Example API")
    assert(markdown:find("# `math`", 1, true))
    assert(markdown:find("```nupp\nfunction add", 1, true))
    -- the declaration is the first thing under the member heading
    assert(
        markdown:find(
            "```nupp\nfunction add(left: number, right: number): number\n```\n\nArithmetic helpers.",
            1,
            true
        ),
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
                "   readonly point: Point",
                "   writeonly replacement: Point",
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
        ),
        {Point = "#math.Point"}
    )
    assert(html:find("nuppdoc-token-comment", 1, true))
    assert(html:find("nuppdoc-token-keyword", 1, true))
    assert(html:find("nuppdoc-token-function", 1, true))
    assert(html:find("nuppdoc-token-type", 1, true))
    assert(html:find("nuppdoc-token-number", 1, true))
    assert(html:find("nuppdoc-token-operator", 1, true))
    assert(html:find("keyword-record", 1, true), html)
    assert(html:find("keyword-readonly", 1, true), html)
    assert(html:find("keyword-writeonly", 1, true), html)
    assert(html:find("keyword-local", 1, true), html)
    assert(html:find('href="#math.Point"', 1, true))
end

function M.highlightsCurrentNuppSyntaxWithTheParser()
    local html = doc.highlight(
        table.concat(
            {
                "@!internal",
                "local interface Factory<P...>",
                "   constructor(self, ...: P...)",
                "   end",
                "   satisfies |self| -> self.ready",
                "end",
                "local function worker(): const unknown & Serializable",
                "   yields (number) resumes (boolean)",
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

function M.highlightsAssociatedTypeAndDirectiveKeywordsWithTheParser()
    local html = doc.highlight(
        table.concat(
            {
                "interface Matcher",
                "    associated type Result = R",
                "end",
                "local compiled = comptime do return 1 end",
                "nosuspend do end",
            },
            "\n"
        )
    )
    assert(html:find("keyword-associated", 1, true), html)
    assert(html:find("keyword-type", 1, true), html)
    -- `comptime`/`nosuspend` get the directive colour, not the ordinary keyword one.
    assert(html:find('class="token directive nuppdoc-token-meta">comptime<', 1, true), html)
    assert(html:find('class="token directive nuppdoc-token-meta">nosuspend<', 1, true), html)
    assert(not html:find("keyword-comptime", 1, true), html)
    assert(not html:find("keyword-nosuspend", 1, true), html)
end

function M.linksOnlyTheDeclaredMembersOfAContainerSignature()
    local html = highlight.nuppSource(
        table.concat({"interface Buffer", "    length: function(self: Buffer): integer", "end",}, "\n"),
        nil,
        {length = "#Buffer.length"}
    )
    assert(
        html:find(
            '<a class="nuppdoc-code-link nuppdoc-code-link-property" '
            .. 'href="#Buffer.length"><span class="token property '
            .. 'nuppdoc-token-property">length</span></a>',
            1,
            true
        ),
        html
    )
    assert(
        not html:find(
            'href="#Buffer.length"><span class="token variable ' .. 'nuppdoc-token-variable">self</span>',
            1,
            true
        ),
        html
    )
end

function M.scintilluaLexerUnderstandsCurrentNuppSyntax()
    local root = HERE .. "/.."
    highlight.configureScintillua(root, {lexers = "docs/lexers"})
    local html = assert(
        highlight.scintilluaSource(
            table.concat(
                {
                    "@!internal",
                    "local type Events<T> = {readonly [K in keyof T as `${K}Changed`]: nosuspend function(value: T.[K]): nil}",
                    "local type Writable<T> = {writeonly [K in writekeyof T]: writeof T.[K]}",
                    "local type First<T> = T.[1]",
                    "local function worker<P..., const Format: string>(...: unpackof Arguments<Format>): unpackof Results<Format>",
                    "   yields (number) resumes (boolean)",
                    "   return new Factory(count = 1_000)",
                    "end",
                    "local function preserve(scoped callback: function(): nil, takes value: affine(voidptr)): voidptr preserves value return value end",
                    "local compiled = comptime do return {answer = 42} end",
                    "nosuspend do end",
                    "handle suspension with cancel do cancel() end",
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
    for _, keyword in ipairs({
        "handle",
        "keyof",
        "preserves",
        "scoped",
        "suspension",
        "unpackof",
        "with",
        "writekeyof",
        "writeof",
        "sealed",
    }) do
        assert(html:find("keyword-" .. keyword, 1, true), html)
    end
    assert(html:find("keyword-yields", 1, true), html)
    assert(html:find("keyword-resumes", 1, true), html)
    assert(html:find("keyword-new", 1, true), html)
    assert(html:find("keyword-associated-type", 1, true), html)
    assert(html:find("nuppdoc-token-type", 1, true), html)
    assert(html:find("nuppdoc-token-number", 1, true), html)
    -- `comptime`/`nosuspend` get the directive colour, not the ordinary keyword one.
    assert(html:find('class="token directive nuppdoc-token-meta">comptime<', 1, true), html)
    assert(html:find('class="token directive nuppdoc-token-meta">nosuspend<', 1, true), html)
end

function M.scintilluaLexerHighlightsNuppPegGrammar()
    local root = HERE .. "/.."
    highlight.configureScintillua(root, {lexers = "docs/lexers"})
    local html = assert(
        highlight.scintilluaSource(
            table.concat(
                {
                    "-- A complete list.",
                    "start <- item (',' item)* !.",
                    "item <- { [%a_][%w_]* } -> name / <fallback>",
                    "fallback <- \"unknown\" ^+4",
                },
                "\n"
            ),
            "npeg"
        )
    )
    assert(html:find("nuppdoc-token-comment", 1, true), html)
    assert(html:find("nuppdoc-token-function", 1, true), html)
    assert(html:find("nuppdoc-token-variable", 1, true), html)
    assert(html:find("nuppdoc-token-string", 1, true), html)
    assert(html:find("nuppdoc-token-type", 1, true), html)
    assert(html:find("nuppdoc-token-number", 1, true), html)
    assert(html:find("nuppdoc-token-operator", 1, true), html)
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
    assert(names.limit, "a declaration file must document without --all")
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
    local output = capture(("cd '%s' && '%s' doc markdown -o api.md"):format(dir, NUPP))
    assert(output == "", output)
    local api = readFile(dir .. "/api.md")
    assert(api:find("# `math`", 1, true), api)
    assert(not api:find("copied", 1, true), "documented a hidden directory")
    assert(not api:find("extra", 1, true), "documented outside the include list")
    os.execute("rm -rf '" .. dir .. "'")
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

function M.internalInitHidesItsDocumentationTree()
    local dir = tempProject({
        ["src/nupp/compiler/init.nupp"] = "@!internal\nreturn {}\n",
        ["src/nupp/compiler/parser.nupp"] = "function parse(): number return 1 end\n",
        ["src/public.nupp"] = "function visible(): number return 2 end\n",
    })
    local config = {include = {"src"}}
    assert(doc.build(dir, config, {sources = {"src"}}, {format = "markdown", output = "public.md"}) == 0)
    local public = readFile(dir .. "/public.md")
    assert(public:find("# `public`", 1, true), public)
    assert(not public:find("# `nupp.compiler`", 1, true), public)
    assert(not public:find("# `nupp.compiler.parser`", 1, true), public)

    assert(
        doc.build(dir, config, {sources = {"src"}, includePrivate = true}, {
            format = "markdown",
            output = "complete.md"
        }) == 0
    )
    local complete = readFile(dir .. "/complete.md")
    assert(complete:find("# `nupp.compiler`", 1, true), complete)
    assert(complete:find("# `nupp.compiler.parser`", 1, true), complete)
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
    assert(
        public:find('href="../../modules/nupp/index.html#nupp.JSON"', 1, true),
        "qualified return type did not link to its declaration"
    )
    assert(
        not io.open(dir .. "/site/modules/nupp/compiler/prelude/index.html", "rb"),
        "the hidden declaration module was documented"
    )
    os.execute("rm -rf '" .. dir .. "'")
end

function M.constructorPatternDecidesTheConstructorsGroup()
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
    local config = {include = {"src"}}
    local function render(settings, out)
        local dir = tempProject(files)
        settings.sources = {"src"}
        assert(doc.build(dir, config, settings, {format = "site", output = out}) == 0)
        local page = readFile(dir .. "/" .. out .. "/modules/engine/index.html")
        local markdown = readFile(dir .. "/" .. out .. "/modules/engine.md")
        os.execute("rm -rf '" .. dir .. "'")

        return page, markdown
    end

    local function constructors(page)
        return page:match("<h3>Constructors</h3>(.-)</table>")
    end

    local function functions(page)
        return page:match("<h3>Functions</h3>(.-)</table>")
    end

    local default, defaultMarkdown = render({}, "site")
    assert(constructors(default):find("newEngine", 1, true), default)
    assert(functions(default):find("makeEngine", 1, true), default)
    local defaultConstructorsAt = assert(default:find('<h2 id="constructors">Constructors', 1, true))
    local defaultFunctionsAt = assert(default:find('<h2 id="functions">Functions', defaultConstructorsAt, true))
    assert(default:find('id="engine.newEngine"><h3>', defaultConstructorsAt, true) < defaultFunctionsAt, default)
    assert(
        default:find(
            'id="engine.newEngine"><h3><code>newEngine</code>'
            .. '<span class="nuppdoc-kind-badge nuppdoc-kind-constructor">constructor</span>',
            defaultConstructorsAt,
            true
        ),
        default
    )
    assert(default:find('id="engine.makeEngine"><h3>', defaultFunctionsAt, true), default)
    local defaultMarkdownConstructorsAt = assert(defaultMarkdown:find("\n## Constructors\n", 1, true))
    local defaultMarkdownFunctionsAt = assert(
        defaultMarkdown:find("\n## Functions\n", defaultMarkdownConstructorsAt, true)
    )
    assert(
        defaultMarkdown:find("`newEngine`", defaultMarkdownConstructorsAt, true) < defaultMarkdownFunctionsAt,
        defaultMarkdown
    )
    assert(defaultMarkdown:find("### `newEngine` _constructor_", defaultMarkdownConstructorsAt, true), defaultMarkdown)
    assert(defaultMarkdown:find("`makeEngine`", defaultMarkdownFunctionsAt, true), defaultMarkdown)

    local renamed, renamedMarkdown = render({constructorPattern = "^make"}, "renamed")
    assert(constructors(renamed):find("<th>Constructor</th><th>Description</th>", 1, true), renamed)
    assert(constructors(renamed):find("makeEngine", 1, true), renamed)
    assert(
        renamed:find(
            'id="engine.makeEngine"><h3><code>makeEngine</code>'
            .. '<span class="nuppdoc-kind-badge nuppdoc-kind-constructor">constructor</span>',
            1,
            true
        ),
        renamed
    )
    assert(
        renamed:find(
            'id="engine.newEngine"><h3><code>newEngine</code>'
            .. '<span class="nuppdoc-kind-badge nuppdoc-kind-function">function</span>',
            1,
            true
        ),
        renamed
    )
    assert(functions(renamed):find("newEngine", 1, true), renamed)
    local renamedConstructorsAt = assert(renamedMarkdown:find("\n## Constructors\n", 1, true))
    local renamedFunctionsAt = assert(renamedMarkdown:find("\n## Functions\n", renamedConstructorsAt, true))
    assert(renamedMarkdown:find("`makeEngine`", renamedConstructorsAt, true) < renamedFunctionsAt, renamedMarkdown)
    assert(renamedMarkdown:find("`newEngine`", renamedFunctionsAt, true), renamedMarkdown)

    -- an empty pattern is how a project says its functions are just functions
    local none, noneMarkdown = render({constructorPattern = ""}, "none")
    assert(not none:find("<h3>Constructors</h3>", 1, true), none)
    assert(none:find("<h3>Functions</h3>", 1, true), none)
    assert(not none:find('<h2 id="constructors">', 1, true), none)
    assert(none:find('<h2 id="functions">Functions', 1, true), none)
    assert(not noneMarkdown:find("\n## Constructors\n", 1, true), noneMarkdown)
    assert(noneMarkdown:find("\n## Functions\n", 1, true), noneMarkdown)
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
    assert(api:find("## Submodules", 1, true), api)
    assert(api:find("| [`engine.audio`](#engine.audio) | Audio helpers. |", 1, true), api)
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
                "   --- Parsing-expression grammars.",
                "   --- @namespace",
                "   peg: nupp.peg",
                "}",
                "",
                "--- Compile parsing-expression grammars.",
                "record nupp.peg",
                "   --- Selects the matcher implementation.",
                "   type Backend = 'auto' | 'lpeg'",
                "",
                "   --- Compiles a grammar.",
                "   compile: function(source: string): nupp.peg.Peg<any>",
                "",
                "   --- A compiled grammar.",
                "   record Peg<T>",
                "      --- Matches text.",
                "      match: function(self, subject: string): T?",
                "   end",
                "end",
            },
            "\n"
        ) .. "\n",
    })
    assert(doc.build(dir, {include = {"src"}}, {sources = {"src"}}, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    local nestedAt = assert(api:find('<a id="nupp.peg"></a>', 1, true), api)
    local parent = api:sub(1, nestedAt - 1)
    local nested = api:sub(nestedAt)
    assert(parent:find("## Submodules", 1, true), parent)
    assert(parent:find("[`nupp.peg`](#nupp.peg)", 1, true), parent)
    assert(not parent:find("### `peg` _record_", 1, true), parent)
    assert(not parent:find("record nupp.peg", 1, true), parent)
    assert(nested:find("Compile parsing%-expression grammars%."), nested)
    assert(nested:find("### `Backend` _type_", 1, true), nested)
    assert(nested:find("### `Peg` _record_", 1, true), nested)
    assert(nested:find("### `compile` _function_", 1, true), nested)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aNamespaceAndTheModuleImplementingItShareOnePage()
    local dir = tempProject({
        [
            "src/nupp.nupp"
        ] = table.concat(
            {
                "--- @namespace nupp",
                "--- @export",
                "local nupp: {",
                "   --- Generates checked members on a declaration.",
                "   --- @namespace",
                "   derive: nupp.derive",
                "}",
                "",
                "record nupp.derive",
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
            "src/nupp/derive.nupp"
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
    local page = readFile(dir .. "/site/modules/nupp/derive/index.html")
    assert(page:find("Generates checked members on a declaration%."), page)
    assert(page:find('id="nupp.derive.implement"', 1, true), page)
    local _, anchors = page:gsub('id="nupp%.derive%.Debug"', "")
    assert(anchors == 1, page)
    assert(page:find("Renders the declaration fields%."), page)
    assert(doc.build(dir, config, settings, {format = "markdown", output = "api.md"}) == 0)
    local api = readFile(dir .. "/api.md")
    local _, sections = api:gsub('<a id="nupp%.derive"></a>', "")
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
    assert(model.schemaVersion == 2, "documentation model version missing")
    assert(model.modules[1].name == "math", "module name missing from JSON model")
    assert(model.modules[1].items[1].name == "add", "declaration missing from JSON model")
    assert(model.modules[1].items[1].params[1].name == "left", "parameter missing from JSON model")
    os.execute("rm -rf '" .. dir .. "'")
end

function M.aPageDirectoryPublishesEveryDocumentAndGeneratesItsIndex()
    local dir = tempProject({
        ["src/math.nupp"] = SOURCE,
        [
            "docs/neps/index.md"
        ] = table.concat(
            {"---", 'title: "NEP 0: Index"', "---", "", "# NEP 0: Index", "", "Why things are the way they are.",},
            "\n"
        ) .. "\n",
        [
            "docs/neps/0001-process.md"
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
            "docs/neps/0002-widgets.md"
        ] = table.concat(
            {"---", "title: Widgets", "status: Draft", "---", "", "## Summary", "", "Widgets.",},
            "\n"
        ) .. "\n",
    })
    local config = {include = {"src"}}
    local settings = {sources = {"src"}, pages = {{path = "neps", title = "NEPs", directory = "docs/neps"},}}
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    local index = readFile(dir .. "/site/neps/index.html")
    assert(index:find("Why things are the way they are.", 1, true), "the index lost the prose it was written with")
    assert(
        index:find('<a href="../neps/0001-process/index.html">Proposal process</a>', 1, true),
        "the generated index did not list and link a document"
    )
    assert(index:find(">Widgets</a>", 1, true), "a document nothing named was left out of the index")
    assert(index:find(">Draft<", 1, true), "the index lost a status")
    assert(
        not index:find("0002-widgets/index.html\">Widgets</a></li>", 1, true),
        "a collection document was listed in the sidebar beside its index"
    )

    local first = readFile(dir .. "/site/neps/0001-process/index.html")
    assert(first:find(">NEP 1: Proposal process<", 1, true), "the number and title were not generated into the heading")
    assert(first:find("Status:", 1, true) and first:find("Active", 1, true), "the frontmatter status was not rendered")
    assert(
        first:find('href="../../neps/0002-widgets/index.html"', 1, true),
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
        ["docs/neps/index.md"] = "# Proposals\n",
        ["docs/neps/0001-process.md"] = "---\ntitle: Process\n---\n\n## Summary\n",
    })
    local config = {include = {"src"}}
    local settings = {
        sources = {"src"},
        pages = {{glob = "docs/**.md"}, {path = "reference/neps", title = "NEPs", directory = "docs/neps"},}
    }
    assert(doc.build(dir, config, settings, {format = "site", output = "site"}) == 0)

    assert(
        io.open(dir .. "/site/reference/neps/0001-process/index.html", "rb"),
        "the collection publishes its documents"
    )
        :close()
    assert(
        not io.open(dir .. "/site/neps/0001-process/index.html", "rb"),
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
                "drop(resource)",
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
    assert(home:find('<a href="https://nupp.org/modules/nupp/index.html">API</a>', 1, true), home)
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
    -- inside it, a top-level branch is a library and stands open on every page,
    -- while the nesting below one stays shut until the reader is in it
    assert(
        guide:match(
            '<details open><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine">'
        ),
        "a top-level module branch must stand open"
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
    assert(
        guide:find('href="../modules/math/index.html#math.Point"', 1, true),
        "custom-page Nupp example did not link to the API reference"
    )
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
    assert(module:find("Module contents", 1, true), module)
    -- a module page opens the API reference instead, with its top-level branches
    -- open as everywhere else and the nesting open only along the branch
    -- reaching the module itself
    assert(module:find('<details open><summary>API reference</summary>', 1, true), module)
    assert(module:find('<li><a href="../../guide/index.html">Guide</a></li>', 1, true), module)
    assert(
        module:match(
            '<details open><summary class="nuppdoc%-module%-branch%-link">' .. '<a href="[^"]*" aria%-label="engine">'
        ),
        "a top-level module branch must stand open"
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
    assert(typesAt < pointAt and pointAt < functionsAt and functionsAt < addAt, module)
    assert(not module:find('<section class="nuppdoc-api-item" id="math.add"><h2>', 1, true), module)
    assert(
        module:find('href="../../modules/math/index.html#math.Point.x"', 1, true),
        "record members in the complete signature must link to their docs"
    )
    assert(
        module:find(
            '<li class="nuppdoc-outline-section"><details open><summary>'
            .. '<a href="#types" title="Types">Types</a></summary><ol><li>'
            .. '<a href="#math.Point" title="Point">Point</a>',
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
    local moduleMarkdown = readFile(dir .. "/site/modules/math.md")
    local markdownTypesAt = assert(moduleMarkdown:find("\n## Types\n", 1, true))
    local markdownFunctionsAt = assert(moduleMarkdown:find("\n## Functions\n", markdownTypesAt, true))
    assert(moduleMarkdown:find("\n### `Point`", markdownTypesAt, true) < markdownFunctionsAt, moduleMarkdown)
    assert(moduleMarkdown:find("\n### `add`", markdownFunctionsAt, true), moduleMarkdown)
    assert(not moduleMarkdown:find("\n## Records\n", 1, true), moduleMarkdown)
    assert(not moduleMarkdown:find("\n## Variables\n", 1, true), moduleMarkdown)
    assert(module:find("Functions", 1, true), module)
    assert(module:find("Types", 1, true), module)
    assert(module:find("nuppdoc%-kind%-badge"), module)
    assert(module:find("Previous", 1, true), module)

    -- a configured page whose path is a module's route is that module's
    -- overview: prose above the generated API rather than a second page beside it
    assert(module:find("<h1><code>math</code></h1>", 1, true), module)
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
        module:find("Where to start", 1, true) < module:find("Module contents", 1, true),
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
            '<details open><summary class="nuppdoc-module-branch-link">'
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

    -- a module's page lists the modules nested under it, so a namespace is
    -- somewhere a reader can arrive at rather than only pass through
    assert(branchModule:find('<h2 id="modules">Submodules</h2>', 1, true), branchModule)
    assert(
        branchModule:find(
            '<a href="../../modules/engine/audio/index.html">'
            .. "<code>engine.audio</code></a></td><td>Audio helpers.</td>",
            1,
            true
        ),
        branchModule
    )
    assert(branchModule:find('<a href="../../modules/engine/render/index.html">', 1, true), branchModule)
    -- engine.gpu has no module of its own, so it is a namespace: a page of its
    -- own, described by what it holds rather than by a blurb it has not got
    assert(
        branchModule:find(
            '<a href="../../modules/engine/gpu/index.html">' .. "<code>engine.gpu</code></a></td><td>1 module</td>",
            1,
            true
        ),
        branchModule
    )
    assert(
        branchModule:find('<a href="#modules" title="Submodules">', 1, true),
        "the outline did not list the nested modules"
    )
    assert(
        not readFile(dir .. "/site/modules/engine/audio/index.html"):find('<h2 id="modules">', 1, true),
        "a module with nothing nested under it still rendered a Modules table"
    )

    local namespace = readFile(dir .. "/site/modules/engine/gpu/index.html")
    assert(namespace:find("<h1><code>engine.gpu</code></h1>", 1, true), namespace)
    assert(namespace:find("Nothing is required by this name itself", 1, true), namespace)
    assert(
        namespace:find(
            '<a href="../../../modules/engine/gpu/vulkan/index.html">'
            .. "<code>engine.gpu.vulkan</code></a></td><td>The Vulkan backend.</td>",
            1,
            true
        ),
        namespace
    )
    -- it holds no declarations, and nothing ever suggested it would
    assert(not namespace:find("No public declarations", 1, true), namespace)
    assert(not namespace:find("Module contents", 1, true), namespace)
    -- and it is a page this generator started writing, so no former URL points at
    -- it and it gets no redirect stub
    local stub = io.open(dir .. "/site/modules/engine/gpu.html")
    if stub then
        stub:close()
    end
    assert(not stub, "a namespace was given a legacy redirect")

    -- a constructor is grouped apart from the functions, and its kind is the
    -- word "function" on every row, so that column is left off
    assert(
        branchModule:find(
            "<h3>Constructors</h3><table><thead><tr>" .. "<th>Constructor</th><th>Description</th>",
            1,
            true
        ),
        branchModule
    )
    assert(branchModule:find('<a href="#engine.newEngine"><code>newEngine</code></a>', 1, true), branchModule)
    assert(
        branchModule:find(
            "<h3>Functions</h3><table><thead><tr>" .. "<th>Function</th><th>Kind</th><th>Description</th>",
            1,
            true
        ),
        branchModule
    )
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
    assert(engineMarkdown:find("## Submodules", 1, true), engineMarkdown)
    assert(engineMarkdown:find("| `engine.gpu` | 1 module |", 1, true), engineMarkdown)
    assert(readFile(dir .. "/site/modules/engine/gpu/llms.txt"):find("# `engine.gpu`", 1, true))
    -- the same references in markdown: an anchor when the document holds what it
    -- names, and the bare name when it does not
    assert(engineMarkdown:find("[`engine.Engine`](#engine.Engine)", 1, true), engineMarkdown)
    assert(engineMarkdown:find("Sound comes out of audio.", 1, true), engineMarkdown)
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
    -- nupp.compiler.doc.assets), so these check for the rules themselves rather
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
    assert(compact:find("nuppdoc%-content%{font%-size:1rem%}"), css)
    -- one mechanism clears the sticky header; two would stack into twice the gap
    assert(compact:find("scroll%-margin%-top:calc%(var%(%-%-nuppdoc%-header%-height%) ?%+ ?1%.4rem%)"), css)
    assert(not compact:find("scroll-padding-top", 1, true), css)
    -- The spaces around that `+` are load-bearing: `calc(a+b)` is not valid CSS.
    -- `compact` closes up the one before the operator and leaves the one after it,
    -- so it cannot say whether the declaration a browser receives is well formed,
    -- and the source is what answers that.
    assert(css:find("calc(var(--nuppdoc-header-height) + 1.4rem)", 1, true), css)

    local legacy = readFile(dir .. "/site/modules/math.html")
    assert(legacy:find("math/index.html", 1, true), legacy)
    os.execute("rm -rf '" .. dir .. "'")
end

-- Markdown is lunamark's now. These are the cases the pattern-based renderer
-- it replaced got wrong, so they are the ones worth pinning.
function M.markdownIsRenderedByLunamark()
    local html = require("nupp.compiler.doc.html")
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
    local html = require("nupp.compiler.doc.html")
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
    local laterOption = html.markdownHtml("```lua [] [good.lua] :line-numbers-extra :line-numbers=9\nprint(1)\n```", {})
    assert(laterOption:find("<figcaption>good.lua</figcaption>", 1, true), laterOption)
    assert(laterOption:find("<span>9</span>", 1, true), laterOption)
end

-- A group where only some fences carry captions still shows every fence: the
-- uncaptioned ones tab under their language rather than silently vanishing.
function M.aCodeGroupKeepsItsUncaptionedFences()
    local html = require("nupp.compiler.doc.html")
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
    local doc = require("nupp.compiler.doc")
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
    local frontmatter = require("nupp.compiler.doc.frontmatter")
    local fields, body = frontmatter.parse("---\r\ntitle: Guide\r\nredirects: old/guide\r\n---\r\n\r\nBody\r\n")
    assert(fields.title == "Guide", tostring(fields.title))
    assert(fields.redirects == "old/guide", tostring(fields.redirects))
    assert(body == "Body\n", ("%q"):format(body))
end

-- The same endings must not cost a collection's document its title and status.
function M.collectionFrontmatterSurvivesWindowsLineEndings()
    local collection = require("nupp.compiler.doc.collection")
    local dir = tempProject({
        ["docs/neps/0001-example.md"] = "---\r\ntitle: Example\r\nstatus: Draft\r\n" .. "---\r\n\r\n## Why\r\n",
    })
    local pages = assert(collection.expand(dir, {directory = "docs/neps", path = "neps", title = "NEPs",}))
    local page = pages[2]
    assert(page, "the collection published no document")
    assert(page.name == "Example", page.name)
    assert(page.status == "Draft", tostring(page.status))
    assert(page.title == "NEP 1: Example", page.title)
    os.execute("rm -rf '" .. dir .. "'")
end

-- A Nupp example is highlighted text until it asks for an editor, and a request to
-- number an excerpt's lines outranks that ask.
function M.nuppFencesBecomeInlinePlaygroundsOnRequest()
    local html = require("nupp.compiler.doc.html")
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
    local html = require("nupp.compiler.doc.html")
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
    local html = require("nupp.compiler.doc.html")
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
function M.headingsKeepTheirAnchors()
    local html = require("nupp.compiler.doc.html")
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
    local diagnostics = require("nupp.compiler.doc.diagnostics")
    local explain = require("nupp.compiler.explain")

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
    local diagnostics = require("nupp.compiler.doc.diagnostics")
    local page = assert(diagnostics.page({path = "diagnostics"}, {["docs/reference/lints.md"] = true}))

    local at = assert(page.markdown:find("#### NUPP2107\n", 1, true))
    local body = page.markdown:sub(at, (page.markdown:find("\n#### ", at + 5, true)))
    local reported = assert(body:find("```nupp [Reported]", 1, true))
    local accepted = assert(body:find("```nupp [Accepted]", 1, true))
    assert(reported < accepted)
    assert(not body:find(":playground", 1, true), "an index section embedded an editor")
    assert(body:find("`exhaustiveness` lint", 1, true), body)
    assert(body:find("](docs/reference/lints.md)", 1, true), body)
    assert(body:find("/playground/#source=", 1, true), body)
end

-- Every link the page writes has somewhere to land: a related code that has no
-- section is named rather than anchored, and so is a reference the site does not
-- publish.
function M.diagnosticIndexOnlyLinksWhatExists()
    local diagnostics = require("nupp.compiler.doc.diagnostics")
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
function M.stdlibIndexHoldsTheLibrariesTheCompilerDeclares()
    local stdlib = require("nupp.compiler.doc.stdlib")

    assert(stdlib.page(nil) == nil)

    local page = assert(stdlib.page({path = "luajit"}))
    assert(page.path == "luajit")
    assert(page.title == "LuaJIT standard library")
    local sections = {
        "Globals",
        "`string`",
        "`table`",
        "`math`",
        "`os`",
        "`package`",
        "`io`",
        "`coroutine`",
        "`bit`",
        "`jit`",
        "`debug`",
        "`ffi`",
        "`string.buffer`",
        "`jit.util`",
        "`jit.profile`",
        "`jit.zone`",
        "Types",
        "Reflection",
    }
    for _, section in ipairs(sections) do
        assert(page.markdown:find("\n## " .. section .. "\n", 1, true), "no section for " .. section)
    end
    -- A library's member is headed by the name a program writes, so the heading agrees
    -- with the anchor beside it and with what a reader searches for.
    assert(page.markdown:find("### `string.format`", 1, true), "no member of a library table")
    assert(page.markdown:find("### `print`", 1, true), "no ambient global")
    assert(page.markdown:find("### `LuaFile`", 1, true), "no ambient LuaFile type")
    assert(page.symbols and page.symbols.LuaFile == "LuaFile", "LuaFile has no generated-page symbol")
end

-- The page is an index, and an index is searched. An editor frame holds text the
-- browser's own find cannot reach, so every fence on it is a plain code block.
function M.stdlibIndexIsStaticThroughout()
    local stdlib = require("nupp.compiler.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))

    assert(page.markdown:find("```nupp\n", 1, true), "no Nupp fence at all")
    assert(not page.markdown:find(":playground", 1, true), "a fence would open as an editor")
end

-- Layout is reached by asking about a reified type rather than by calling a library,
-- so its graph sits apart from the types the signatures above merely name. Semantic
-- reflection owns its graph under `nupp.reflect` instead of leaking ambient types.
function M.stdlibIndexSectionsReflectionApartFromTypes()
    local stdlib = require("nupp.compiler.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))
    local reflection = assert(page.markdown:find("\n## Reflection\n", 1, true))
    local types = assert(page.markdown:find("\n## Types\n", 1, true))

    assert(types < reflection, "reflection is a section of its own after the types")
    assert(page.markdown:find("### `Layout`", 1, true) > reflection, "Layout left behind")
    assert(not page.markdown:find("### `TypeInfo`", 1, true), "TypeInfo still ambient")
    assert(page.markdown:find("### `LuaFile`", 1, true) < reflection, "an ordinary type was moved")
end

-- A global's anchor is the name a program writes. `print` is not a member of the file
-- that declares it, and `string.format` is not a member of the page's own name.
function M.stdlibIndexAnchorsEveryNameTheWayItIsWritten()
    local stdlib = require("nupp.compiler.doc.stdlib")
    local page = assert(stdlib.page({path = "luajit"}))

    assert(page.markdown:find('<a id="print"></a>', 1, true), "print anchored as a member")
    assert(page.markdown:find('<a id="string.format"></a>', 1, true), "string.format lost its anchor")
    assert(not page.markdown:find('<a id="globals.', 1, true), "anchored a global to its file")
end

-- What the prelude declares for the compiler rather than for a program stays off the
-- page: `nupp` has module pages of its own, and the aliases behind `string.format`'s
-- parameter pack are private vocabulary with no section to land on. The pack still
-- names one in the signature, because that is what the declaration says and a signature
-- the checker does not enforce would be worse than an unfamiliar name.
function M.stdlibIndexLeavesTheCompilersOwnDeclarationsOut()
    local stdlib = require("nupp.compiler.doc.stdlib")
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
            "record Handle is nupp.Closeable",
            "   --- Its backing Lua stream.",
            "   file: LuaFile",
            "   --- Closes it.",
            "   function close(takes self): nil",
            "   end",
            "end",
        },
        "\n"
    ) .. "\n"
    local dir = tempProject({
        ["src/math.nupp"] = linkedSource,
        ["src/nupp/init.nupp"] = "--[[\nCore facilities.\n]]\n",
        [
            "src/nupp/compiler/prelude.d.nupp"
        ] = table.concat(
            {
                "@!internal",
                "--- A deterministic resource.",
                "affine interface nupp.Closeable",
                "   terminal close: nosuspend function(takes self: nupp.Closeable): nil",
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
    assert(page:find("LuaJIT standard library", 1, true), page:sub(1, 400))
    assert(page:find("string.format", 1, true), "the page rendered without its declarations")
    local modulePage = readFile(dir .. "/site/modules/math/index.html")
    assert(
        modulePage:find('href="../../reference/luajit/index.html#LuaFile"', 1, true),
        "a module signature did not link the ambient LuaFile type"
    )
    assert(
        modulePage:find('href="../../modules/nupp/index.html#nupp.Closeable"', 1, true),
        "a module signature did not link nupp.Closeable"
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

return M
