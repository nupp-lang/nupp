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
    return lower.emit(name, {}, function(candidate)
        return candidate == name and (path or name .. ".nupp") or nil
    end, function()
        return tree
    end, nil, listing, require("nupp.compiler.targetlayout").hostKey())
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
    local env = require("nupp.compiler.project.env").new(".")
    require("nupp.compiler.runtime").install(env, function(modulePath, e, name)
        local image = compile.image(modulePath, e, name)
        return image, image == nil and "type errors" or nil
    end, nil, nil, function(image)
        return loadImage(image)
    end)
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

--- Loads a checked parse as a function that runs the fragment's body and
--- answers what it returns. Answers nil and a reason when it cannot load.
function program.load(result, name, path)
    local loadImage = rawget(_G, "__nupp_load_image")
    if not loadImage then
        return nil, "fragments run on the VM"
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
