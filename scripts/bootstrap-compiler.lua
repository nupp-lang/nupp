-- Bootstrap with current declarations and the checkout's checked namespace reader.
-- Private imports retain the same checks across standard module moves.
local bootstrap = {}

local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("*a")
    file:close()
    return bytes
end

local function extras(root)
    local source = read(root .. "/src/nupp/tools/vm/project.nupp")
    local expression = assert(source:match("project%.ROOT_EXTRAS%s*=%s*(.-)\n\n"), "root extras declaration required")
    local names = {}
    local rest = expression:gsub('"([%w%._,]+)"', function(value)
        names[#names + 1] = value
        return ""
    end):gsub("%.%.", "")
    assert(#names > 0 and rest:match("^%s*$"), "root extras must be literal module names")

    return table.concat(names)
end

-- The seed checks this exact source function and its private dependency before
-- the emitter checks a new standard-library root. Keep the environment module's
-- identity: existing moduleAccess functions retain that table.
function bootstrap.reader(root)
    local source = read(root .. "/src/nupp/compiler/project/env.nupp")
    local _, rootsCount = source:gsub("\nlocal STANDARD_ROOTS:", "")
    local _, readerCount = source:gsub("\nfunction envMod%.packageNamespace%b()%s*:%s*string\n", "")
    assert(rootsCount == 1, "one standard namespace declaration required")
    assert(readerCount == 1, "one package namespace reader required")
    local roots = assert(source:match("(local STANDARD_ROOTS:.-\n})\n"), "standard namespace declaration required")
    local arguments, body = source:match("function envMod%.packageNamespace(%b())%s*:%s*string\n(.-)\nend")
    assert(arguments and body, "package namespace reader required")
    local partial = "module nupp.compiler.bootstrapnamespace\n"
        .. roots
        .. "\nexport function packageNamespace"
        .. arguments
        .. ": string\n"
        .. body
        .. "\nend\n"
    local environment = require("nupp.compiler.project.env")
    local context = environment.new(root, {
        config = {include = {}},
        cache = false,
        memoryOnly = true,
        nativeCompilerServices = false,
    })
    local diagnostics = {}
    local image = require(
        "nupp.tools.cli.compile"
    ).image(
        root .. "/build/vm-cli/bootstrapnamespace.nupp",
        context,
        "nupp.compiler.bootstrapnamespace",
        diagnostics,
        partial
    )
    if not image then
        local messages = {}
        for _, diagnostic in ipairs(diagnostics) do
            messages[#messages + 1] = diagnostic.code .. ": " .. diagnostic.msg
        end
        error("bootstrap namespace reader: " .. table.concat(messages, "\n"), 0)
    end
    local load = assert(rawget(_G, "__nupp_load_image"), "native image loader required")
    local chunk = assert(load(image))
    local current = chunk()
    assert(type(current.packageNamespace) == "function", "checked package namespace function required")
    environment.packageNamespace = current.packageNamespace

    return #image
end

function bootstrap.emit(root, output, additions)
    local modules = additions or extras(root)
    local manifest = assert(loadfile(root .. "/nupp.lua"))()
    local generated = require("nupp.compiler.vm.resources").source(root, manifest)
    local current = assert(loadstring(generated))()
    local carried = require("nupp.vm.cliResources")
    -- The checker may already retain this exact table. Rebind its contents,
    -- rather than installing a different table behind the cached reference.
    for key in pairs(carried) do
        carried[key] = nil
    end
    local count = 0
    for key, value in pairs(current) do
        assert(type(key) == "string" and type(value) == "string", "source resource expected")
        carried[key] = value
        count = count + 1
    end
    assert(count > 0, "compiler resources required")
    package.preload["nupp.embedded"] = function()
        return carried
    end
    assert(
        require(
            "nupp.compiler.bundled"
        ).source("/decls/prelude.d.nupp") == read(root .. "/src/nupp/compiler/decls/prelude.d.nupp"),
        "bootstrap prelude differs from source"
    )
    io.stderr:write("bootstrap declarations: ", tostring(count), " source resources\n")
    io.stderr:write("bootstrap namespace reader: ", tostring(bootstrap.reader(root)), " bytes\n")
    local image = require("nupp.tools.vm.project").emit(root, "nupp.tools.vm.root", modules)
    local file = assert(io.open(output, "wb"))
    file:write(image)
    file:close()
end

if arg and arg[1] == "emit" then
    bootstrap.emit(assert(arg[2]), assert(arg[3]), arg[4])
end

return bootstrap
