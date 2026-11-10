local ROOT = require("helpers.paths").absoluteTests .. "/.."
local hash = require("nupp.compiler.hash")
local json = require("serde.json")
local driver = require("helpers.providerstate").instance({
    ["nupp.tools.vm.producerdriver"] = true
})("nupp.tools.vm.producerdriver")
local M = {}

function M.sharedInventoryMatchesTheInstalledImage()
    local carried = require("nupp.compiler.imagemodules").carriedModules()
    local original = driver.carriedModules()
    for name in pairs(carried) do
        assert(original[name], "shared inventory added a module the installed image does not carry")
    end
    for name in pairs(original) do
        assert(carried[name], "shared inventory dropped an installed module")
    end
end

function M.pieceProducerHashesSourceUnlessTheImageCarriesItsModule()
    local fs = require("nupp.compiler.fs")
    local instances = require("helpers.providerstate")
    local root = os.tmpname()
    os.remove(root)
    assert(fs.mkdir(root .. "/src/nupp/core"))
    assert(fs.mkdir(root .. "/src/test"))
    local generation = string.rep("a", 64)
    local pair = root .. "/.nupp/vm-cli/" .. generation
    assert(fs.mkdir(pair))
    root = fs.canonical(root)
    pair = root .. "/.nupp/vm-cli/" .. generation
    local image = pair .. "/compiler.image"
    local builder = root .. "/src/test/builder.nupp"
    local okay, problem = pcall(function()
        assert(fs.writeFile(root .. "/src/nupp/core/guestbuild.nupp", 'return require("test.builder")\n'))
        assert(fs.writeFile(builder, "return 'builder'\n"))
        assert(fs.writeFile(root .. "/program.nupp", "return 1\n"))
        assert(fs.writeFile(image, "image data mentions /test/builder.nupp"))
        local environment = setmetatable(
            {
                getenv = function(name)
                    return name == "NUPP_VM_CLI_IMAGE" and image or nil
                end
            },
            {__index = os}
        )

        local function key(inventory)
            local load = instances.instance(
                {["nupp.core.piecestore"] = true, ["nupp.compiler.imagemodules"] = true},
                {["nupp.vm.persist"] = {}},
                nil,
                {os = environment, __nupp_image_modules = inventory or false}
            )
            local store = assert(
                load("nupp.core.piecestore").open(root, {
                    modules = {{name = "test.program", path = root .. "/program.nupp"}},
                    entry = 0,
                    cyclic = {}
                })
            )

            return assert(store.key(1))
        end

        local function inventory()
            return {digests = {["nupp.core.guestbuild"] = "fixed guest builder"}}
        end

        local original = key(inventory)
        assert(fs.writeFile(builder, "return 'changed builder'\n"))
        assert(key(inventory) ~= original, "a path literal does not freeze executable source")
        local unavailable = key(nil)
        assert(fs.writeFile(builder, "return 'changed again'\n"))
        assert(key(nil) ~= unavailable, "an unavailable inventory conservatively hashes executable source")

        local function failedInventory()
            error("fixture inventory unavailable")
        end

        local failed = key(failedInventory)
        assert(failed == key(nil), "a failed inventory hashes the same complete source closure")
        assert(fs.writeFile(builder, "return 'changed after inventory failure'\n"))
        assert(key(failedInventory) ~= failed, "an inventory failure does not freeze executable source")

        local function carried()
            return {digests = {["nupp.core.guestbuild"] = "fixed guest builder", ["test.builder"] = "fixed builder"}}
        end

        local frozen = key(carried)
        assert(fs.writeFile(builder, "return 'source edit to frozen builder'\n"))
        assert(key(carried) == frozen, "an actually carried module keeps the same producer identity")
        assert(fs.mkdir(root .. "/src/nupp/compiler"))
        local computed = root .. "/src/nupp/compiler/computed.nupp"
        assert(fs.writeFile(root .. "/src/nupp/core/guestbuild.nupp", 'return require("nupp.compiler." .. name)\n'))
        assert(fs.writeFile(computed, 'return require("test.builder")\n'))
        local uncarried = key(carried)
        assert(fs.writeFile(computed, 'return require("test.builder") -- changed computed compiler body\n'))
        assert(
            key(carried) ~= uncarried,
            "an uncarried computed compiler module changes ordinary piece producer identity"
        )
        local modules = require(
            "nupp.core.producermodules"
        ).reached(root, {"nupp.core.guestbuild"}, require("nupp.core.kernelcompiler").reachedModules)
        local before = driver.sourceInputs(root, modules, {["nupp.core.guestbuild"] = true, ["test.builder"] = true})
        assert(#before == 1 and before[1].path == "src/nupp/compiler/computed.nupp")
        assert(fs.writeFile(computed, 'return require("test.builder") -- changed again\n'))
        local after = driver.sourceInputs(root, modules, {["nupp.core.guestbuild"] = true, ["test.builder"] = true})
        assert(after[1].sha256 ~= before[1].sha256, "the private producer validates the same uncarried computed source")
    end)
    os.remove(root, true)
    assert(okay, problem)
end

function M.frozenProducerKeepsProgramEditsAndRejectsBuilderChanges()
    local root = os.tmpname()
    os.remove(root)

    local function quote(value)
        return "'" .. value:gsub("'", "'\\''") .. "'"
    end

    local function write(path, text)
        local file = assert(io.open(root .. "/" .. path, "wb"))
        file:write(text)
        file:close()
    end

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local base, generation = string.rep("a", 64), string.rep("b", 64)
    local pair, producer = ".nupp/vm-cli/" .. base, ".nupp/native-producer/" .. generation
    assert(
        os.execute(
            (
                "mkdir -p %s/scripts %s/src/nupp/tools/vm %s/src/nupp/core %s/%s %s/%s"
            ):format(quote(root), quote(root), quote(root), quote(root), pair, quote(root), producer)
        ) == 0
    )
    root = require("nupp.compiler.fs").canonical(root)
    local okay, problem = pcall(function()
        write("scripts/native-producer", read(ROOT .. "/scripts/native-producer"))
        write("src/carried.nupp", "return 1\n")
        write("src/nupp/core/builder.nupp", "return 'builder'\n")
        local projectPath = "src/nupp/tools/vm/project.nupp"
        local projectText = 'local ROOT_EXTRAS = "test.compiler"\n'
        write(projectPath, projectText)
        for _, path in ipairs({
            "nupp.lua",
            "scripts/native-producer-build.lua",
            "scripts/native-producer-driver.lua",
            "scripts/toolchain",
            "scripts/toolchain.pins",
            "scripts/sccache-wrapper"
        }) do
            write(path, "external packaging input")
        end

        write(".nupp/vm-cli/current", base .. "\n")
        local baseImage = "fixed compiler image /nupp/core/builder.nupp"
        write(pair .. "/compiler.image", baseImage)
        write(pair .. "/runtime", "fixed compiler runtime")
        write(".nupp/native-producer/current", generation .. "\n")
        write(producer .. "/compiler.image", "complete producer image")
        write(producer .. "/runtime", "complete producer runtime")
        assert(os.execute("git -C " .. quote(root) .. " init -q") == 0)
        local listing = assert(
            io.popen(
                "git -C " .. quote(
                    root
                )
                .. " ls-files --cached --others --exclude-standard -z -- src native/crates/vm/lib native/crates/vm/decls"
            )
        )
        local paths = {}
        for path in listing:read("*a"):gmatch("[^%z]+") do
            paths[#paths + 1] = path
        end
        listing:close()
        table.sort(paths)
        local carried = driver.carriedModules()
        assert(not carried["test.builder"], "a path literal is not an executable module")
        carried["test.carried"] = true
        local inputs = driver.sourceInputs(
            root,
            {["test.builder"] = "src/nupp/core/builder.nupp", ["test.carried"] = "src/carried.nupp"},
            carried
        )
        assert(#inputs == 1 and inputs[1].path == "src/nupp/core/builder.nupp")
        carried["nupp.tools.vm.project"] = true
        inputs = driver.producerInputs(
            root,
            {
                ["test.builder"] = "src/nupp/core/builder.nupp",
                ["test.carried"] = "src/carried.nupp",
                ["nupp.tools.vm.project"] = projectPath
            },
            carried
        )
        local identity = {
            format = "nupp-native-producer/3",
            root = root,
            base = base,
            baseImage = hash.sha256(baseImage),
            baseRuntime = hash.sha256("fixed compiler runtime"),
            inventory = hash.sha256(table.concat(paths, "\0")),
            inputs = inputs,
            extras = "test.producer"
        }
        local sealed = {
            identity.format,
            root,
            base,
            identity.baseImage,
            identity.baseRuntime,
            identity.inventory,
            identity.extras
        }
        for _, input in ipairs(inputs) do
            sealed[#sealed + 1], sealed[#sealed + 2] = input.path, input.sha256
        end
        identity.seal = hash.sha256(table.concat(sealed, "\0"))
        write(
            producer .. "/receipt.json",
            json.encodevalue({
                format = "nupp-vm-cli-1",
                linked = true,
                imageSha256 = hash.sha256("complete producer image"),
                runtimeSha256 = hash.sha256("complete producer runtime"),
                privateProducer = identity
            })
        )

        local function valid()
            return driver.selected(root, base) ~= nil
        end

        assert(valid(), "unchanged producer is reusable")
        write(projectPath, 'local ROOT_EXTRAS = "test.changed"\n')
        assert(not valid(), "changed shipping ROOT_EXTRAS invalidates even a carried project module")
        write(projectPath, projectText)
        assert(valid(), "restoring packaging inputs restores reuse")

        write("src/carried.nupp", "return 2\n")
        assert(valid(), "a carried program edit keeps the fixed producer")
        write("src/nupp/core/builder.nupp", "return 'changed builder'\n")
        assert(not valid(), "executed builder changes require a new producer")
        write("src/nupp/core/builder.nupp", "return 'builder'\n")
        assert(valid(), "restoring builder inputs restores reuse")
        write("src/shadow.nupp", "return true\n")
        assert(not valid(), "new source resolution invalidates the producer")
        os.remove(root .. "/src/shadow.nupp")
        assert(valid(), "restoring the source inventory restores reuse")
        local receipt = read(root .. "/" .. producer .. "/receipt.json")
        local legacy = json.decodevalue(receipt)
        legacy.privateProducer.format = "nupp-native-producer/2"
        legacy.privateProducer.seal = assert(driver.identitySeal(legacy.privateProducer))
        write(producer .. "/receipt.json", json.encodevalue(legacy))
        assert(not valid(), "older receipts do not prove the computed compiler dependency closure")
        write(producer .. "/receipt.json", receipt)
        local changedReceipt = json.decodevalue(receipt)
        changedReceipt.privateProducer.inputs = {}
        write(producer .. "/receipt.json", json.encodevalue(changedReceipt))
        assert(not valid(), "a damaged dependency list cannot bypass input validation")
        write(producer .. "/receipt.json", receipt)
        local incomplete = json.decodevalue(receipt)
        incomplete.imageSha256, incomplete.runtimeSha256 = nil, nil
        write(producer .. "/receipt.json", json.encodevalue(incomplete))
        os.remove(root .. "/" .. producer .. "/compiler.image")
        os.remove(root .. "/" .. producer .. "/runtime")
        assert(not valid(), "missing artifacts and missing hashes cannot match")
        write(producer .. "/receipt.json", receipt)
        write(producer .. "/compiler.image", "complete producer image")
        write(producer .. "/runtime", "complete producer runtime")
        write(producer .. "/compiler.image", "corrupt image")
        assert(not valid(), "a corrupt artifact is never reused")
        write(producer .. "/compiler.image", "complete producer image")
        local process = require("nupp.compiler.process")
        local getenv, run = os.getenv, process.run
        os.getenv = function(name)
            return name == "NUPP_COMPILER_ROOT" and root or getenv(name)
        end
        local invoked = {}
        process.run = function(command, options)
            invoked[#invoked + 1] = {command = command, options = options}
            return 0
        end
        local ran, issue = pcall(function()
            assert(driver.main({"--emit-only", "loadsource"}) == 0)
            assert(driver.main({"loadsource"}) == 0)
            assert(#invoked == 2)
            for _, call in ipairs(invoked) do
                assert(call.command[6] == "../guests/run.lua" and call.command[7] == "loadsource")
                assert(call.options.cwd == root .. "/tests/core/units")
            end
            assert(invoked[1].options.env.NUPP_GUEST_EMIT_ONLY == "1")
            assert(invoked[2].options.env.NUPP_GUEST_EMIT_ONLY == "0")
        end)
        os.getenv, process.run = getenv, run
        assert(ran, issue)
        local instances = require("helpers.providerstate")

        local function running(describe, binary, identify)
            local environment = setmetatable(
                {
                    getenv = function(name)
                        if name == "NUPP_VM_CLI_IMAGE" then
                            return root .. "/" .. producer .. "/compiler.image"
                        end
                        if name == "NUPP_VM_BINARY" then
                            return binary or root .. "/" .. producer .. "/runtime"
                        end

                        return getenv(name)
                    end
                },
                {__index = os}
            )
            local load = instances.instance(
                {["nupp.core.produceridentity"] = true, ["nupp.compiler.imagemodules"] = true,},
                nil,
                nil,
                {
                    os = environment,
                    __nupp_image_modules = describe or false,
                    __nupp_image_identity = identify == nil and function()
                        return hash.digest("complete producer image")
                    end or identify,
                }
            )

            return load("nupp.core.produceridentity").running(root)
        end

        local function inventory()
            return {
                digests = {
                    ["nupp.compiler.project.incremental"] = "fixed checker",
                    ["nupp.core.guestprogramproducer"] = "fixed producer",
                }
            }
        end

        assert(running(inventory), "the actual verified host image authorizes a fixed producer")
        assert(running(inventory, nil, false) == nil, "missing actual image identity authorizes nothing")
        assert(
            running(inventory, nil, function()
                return "another image"
            end) == nil,
            "matching module names cannot authorize a different running image"
        )
        assert(running(nil) == nil, "inherited producer paths without host inventory authorize nothing")
        assert(
            running(function()
                error("inventory unavailable")
            end) == nil,
            "failed inventory authorizes nothing"
        )
        assert(
            running(inventory, root .. "/" .. pair .. "/runtime") == nil,
            "a different actual runtime pair authorizes nothing"
        )
        write(pair .. "/runtime", "changed base runtime")
        assert(not valid(), "a different base runtime is never reused")
    end)
    os.remove(root, true)
    assert(okay, problem)
end

return M
