-- A checked fragment as a running program: lowered by the VM's own lowering
-- (`nupp.compiler.vm.lower`) to an image the running VM loads, which is how
-- `nupp run` and `nupp test` execute Nupp.
local lower = require("nupp.compiler.vm.lower")

local program = {}

--- The image a checked parse lowers to. `listing`, when given, receives the
--- bytecode listing the lowering keeps for `nupp bc`.
function program.image(result, name, path, listing)
    name = name or "main"
    local tree = result.root
    tree.vmModuleExports = result.moduleExports

    -- Structs are laid out for the machine running the fragment, as `nupp run`
    -- lays them out.

    return lower.emit(
        name,
        {},
        function(candidate)
            return candidate == name and (path or name .. ".nupp") or nil
        end,
        function()
            return tree
        end,
        nil,
        listing,
        require("nupp.compiler.targetlayout").hostKey()
    )
end

-- A fragment's own `require` of a module the running image does not carry
-- compiles that module from source, as `nupp test` does for a suite on the VM.
local sourceModules = false

local function installSourceModules(loadImage)
    if sourceModules then
        return
    end
    sourceModules = true
    local compile = require("nupp.tools.cli.compile")
    local envMod = require("nupp.compiler.project.env")
    local env = envMod.new(".")
    local root = envMod.compilerRoot() or "."
    table.insert(env.roots, 1, root .. "/native/crates/vm/lib")
    table.insert(env.roots, 1, root .. "/native/crates/vm/decls")
    require("nupp.compiler.runtime").install(
        env,
        function(modulePath, e, name, source)
            local strict
            if source ~= nil then
                strict = false
            end
            local image = compile.image(modulePath, e, name, nil, source, strict)

            return image, image == nil and "type errors" or nil
        end,
        nil,
        nil,
        function(image)
            return loadImage(image)
        end
    )
end

--- Installs that loader on the VM, for a helper that loads modules itself.
function program.installSourceModules()
    local loadImage = rawget(_G, "__nupp_load_image")
    if loadImage then
        installSourceModules(loadImage)
    end
end

--- Whether fragments run on the VM.
function program.onVm()
    return rawget(_G, "__nupp_load_image") ~= nil
end

local function hasModuleSyntax(result)
    for _, block in ipairs(result.root.blocks) do
        for _, stat in ipairs(block.stats) do
            if stat.kind == "moduleStmt" or stat.kind == "exportStmt" then
                return true
            end
        end
    end

    return false
end

-- What a fragment body holds outside every function body: its `return`
-- statements, whether it reads `...`, and whether it declares an `@aot`
-- function.
local function chunkLevel(root)
    local returns, varargs, aot = {}, false, false

    local function visit(node)
        if type(node) ~= "table" or node.trivia ~= nil or node.kind == "funcbody" then
            return
        end
        if node.kind == "returnStmt" then
            returns[#returns + 1] = node
        elseif node.kind == "vararg" then
            varargs = true
        elseif (node.kind == "pragmaStmt" or node.kind == "annotationApply") and node.name and node.name.text == "aot" then
            aot = true
        end
        for _, child in ipairs(node) do
            visit(child)
        end
    end

    visit(root)

    return returns, varargs, aot
end

local PACK = "__nupp_fragment_results"

-- `source` with each of `returns` publishing its results as one packed
-- table, or nil where a return has no tokens to rewrite around.
local function packedReturns(source, returns)
    local cst = require("nupp.compiler.syntax.cst")
    local edits = {}
    for _, stat in ipairs(returns) do
        local keyword = cst.firstToken(stat)
        local last = #stat.exprs > 0 and cst.lastToken(stat.exprs[#stat.exprs]) or keyword
        if keyword == nil or keyword.text ~= "return" or last == nil then
            return nil
        end
        edits[#edits + 1] = {at = keyword.offset + #keyword.text, text = " " .. PACK .. "("}
        edits[#edits + 1] = {at = last.offset + #last.text, text = ")"}
    end
    table.sort(edits, function(a, b)
        return a.at > b.at
    end)
    for _, edit in ipairs(edits) do
        source = source:sub(1, edit.at - 1) .. edit.text .. source:sub(edit.at)
    end

    -- On the first line, so every line keeps its number.
    return "local function " .. PACK .. "(...: any): any return {n = select('#', ...), ...} end " .. source
end

-- On the native core there is no image to load. The chunk compiler the core
-- compiler carries compiles the fragment's source as a module instance, as
-- `nupp run` compiles a program there, and loading that chunk runs it.
local function coreLoad(result, name, path)
    local carried, corechunk = pcall(require, "nupp.compiler.vm.corechunk")
    if not carried or type(result.source) ~= "string" then
        return nil, "fragments run on the VM or the native core"
    end
    local display = path or (name or "main") .. ".nupp"
    local isBody = not hasModuleSyntax(result)
    local source = result.source
    local packed = false
    if isBody then
        local returns, varargs, aot = chunkLevel(result.root)
        local rewritten = aot and not varargs and packedReturns(source, returns)
        if rewritten then
            -- An `@aot` function is refused inside another function, so a
            -- body declaring one stays the module initializer, and each of
            -- its returns publishes every result, nils included, as one table.
            source, packed = rewritten, true
        else
            -- A module initializer publishes one value. A fragment body runs
            -- as a function so the caller receives every result, including
            -- nils.
            source = "return function(...: any): ...any " .. source .. "\nend\n"
        end
    end
    -- Checked as the module the fragment was checked as, which is what
    -- decides the modules it may import, as the VM's lowering of that
    -- checked tree does.
    local module = result.moduleName or name or "main"
    local compiled, bytes, problem = pcall(corechunk.compileProgram, source, display, "@" .. display, module)
    if not compiled then
        return nil, tostring(bytes)
    elseif not bytes then
        return nil, problem
    end

    return function(...)
        local value, failure = load(bytes, "@" .. display, "b")
        if failure ~= nil then
            error(failure, 0)
        end
        if packed then
            assert(select("#", ...) == 0, "a fragment declaring an @aot function takes no arguments on the core")
            if value == nil then
                return
            end
            return (table.unpack or unpack)(value, 1, value.n)
        elseif isBody then
            return value(...)
        end

        return value
    end
end

local function checkedCoreImage(result, name, path)
    local checked = assert(result.fragmentCheck, "checked fragment diagnostics are unavailable")
    assert(checked.root == result.root and checked.symbols == result.symbols, "fragment was checked again")
    assert(checked.moduleName == name and result.moduleName == name, "checked fragment module identity differs")
    assert(result.declaredModuleName == name, "a checked fragment function entry is not yet available on the core")
    assert(path == checked.path, "checked fragment path differs")
    local catalog = require(
        "helpers.recordfactory"
    ).describe({{name = name, path = path, parsed = result, diagnostics = checked.diagnostics,}}, name)
    local version = 8
    local lowered = require(
        "nupp.compiler.vm.programgraph"
    ).compile(catalog, require("nupp.compiler.vm.taggedprofile").forVersion(version))
    local executable = require("nupp.compiler.vm.coregraphexecutable").fromChecked(lowered, version)

    return require("nupp.compiler.vm.coreartifact").chunk(executable)
end

local function coreModule(result, name, path)
    local bytes = checkedCoreImage(result, name, path)

    -- Loading a module chunk starts its initializer. Defer that work until
    -- the caller runs the fragment, as the VM's image loader does.
    return function(...)
        assert(select("#", ...) == 0, "checked module fragments do not accept arguments on the core")
        local value, problem = load(bytes, "@" .. path, "b")
        if problem ~= nil then
            error(problem, 0)
        end

        return value
    end
end

--- Loads a checked parse as a function that runs the fragment's body and
--- answers what it returns. Answers nil and a reason when it cannot load.
function program.load(result, name, path)
    local loadImage = rawget(_G, "__nupp_load_image")
    if not loadImage then
        local checked = result.fragmentCheck
        local module = name or "main"
        if checked and result.declaredModuleName == module then
            local ok, chunk = pcall(coreModule, result, module, path or checked.path)
            return ok and chunk or nil, not ok and tostring(chunk) or nil
        end
        return coreLoad(result, name, path)
    end
    installSourceModules(loadImage)
    local ok, image = pcall(program.image, result, name, path)
    if not ok then
        return nil, tostring(image)
    end
    local loaded, chunk, problem = pcall(loadImage, image)
    if not loaded then
        return nil, tostring(chunk)
    end

    return chunk, problem
end

--- Whether an image holds the string constant `s`: a graph image keeps each
--- string once, behind its length, which for a short string is one byte.
function program.names(image, s)
    assert(#s < 127, "a short string")
    return image:find(string.char(#s + 1) .. s, 1, true) ~= nil
end

--- Loads and runs a checked parse, raising when it does not load.
function program.run(result, name, path, ...)
    local chunk, problem = program.load(result, name, path)
    assert(chunk, problem)

    return chunk(...)
end

return program
