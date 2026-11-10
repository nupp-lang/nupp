local ROOT = require("helpers.paths").absoluteTests .. "/.."
local hash = require("nupp.compiler.hash")
local json = require("serde.json")
local driver = require("nupp.tools.vm.producerdriver")
local M = {}

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
                "mkdir -p %s/scripts %s/src %s/src/nupp/core %s/%s %s/%s"
            ):format(quote(root), quote(root), quote(root), quote(root), pair, quote(root), producer)
        ) == 0
    )
    root = require("nupp.compiler.fs").canonical(root)
    local okay, problem = pcall(function()
        write("scripts/native-producer", read(ROOT .. "/scripts/native-producer"))
        write("src/carried.nupp", "return 1\n")
        write("src/nupp/core/builder.nupp", "return 'builder'\n")
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
        inputs[
            #inputs + 1
        ] = {path = "scripts/native-producer", sha256 = hash.sha256(read(root .. "/scripts/native-producer"))}
        local identity = {
            format = "nupp-native-producer/2",
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
        write(pair .. "/runtime", "changed base runtime")
        assert(not valid(), "a different base runtime is never reused")
    end)
    os.remove(root, true)
    assert(okay, problem)
end

return M
