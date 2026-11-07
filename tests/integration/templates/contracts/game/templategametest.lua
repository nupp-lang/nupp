local fixture = require("helpers.templatefixture")
local testAssert = fixture.testAssert
local template = fixture.template
local write = fixture.write
local tempDirectory = fixture.tempDirectory
local remove = fixture.remove
local templateDirectory = fixture.templateDirectory

local M = {}

function M.aGameShapedManifestNeedsNoFieldsTheBuildDoesNotHave()
    -- The claim the whole Tecs case rests on: a template that wants a graphics
    -- host, a native dependency, assets and a run task asks for it in fields
    -- `nupp.lua` already validates. The Tecs template itself belongs in the Tecs
    -- repository; what belongs here is the evidence that it will not need a
    -- build change, checked by the validator rather than by reading.
    --
    -- The Cargo shape is the part worth pinning down, because the obvious
    -- spelling is wrong. `source = {git = ..., rev = ...}` is a `c` dependency
    -- key; a Cargo dependency names a local crate with `manifest`, and that
    -- crate's own Cargo.toml is what pins the engine.
    local manifest = require("nupp.tools.build.manifest")
    local dir = templateDirectory({
        ["template.lua"] = [[return {description = "a game", raw = {"assets/**"}}]],
        [
            "nupp.lua"
        ] = [[
         return {
            include = {"src"},
            dependencies = {
               host = {kind = "cargo", manifest = "host/Cargo.toml", library = "tecs_host"},
            },
            build = {
               outDir = "build",
               default = "game",
               targets = {
                  game = {
                     kind = "binary",
                     entries = {"main"},
                     dependencies = {"host"},
                     stub = "tecs",
                     resources = {"assets/**"},
                     output = "build/${name}",
                  },
               },
            },
            tasks = {play = {description = "Run it", argv = {"nupp", "run", "src/main.nupp"}}},
         }
      ]],
        ["src/main.nupp"] = "return {}",
        ["host/Cargo.toml"] = '[package]\nname = "tecs_host"\n',
        ["assets/sprite.bin"] = "\0\1\2\3",
    })
    local into = tempDirectory()
    local plan = assert(template.plan({kind = "directory", path = dir}, into, {name = "mygame"}))

    local assets
    for _, file in ipairs(plan.files) do
        if file.output == "assets/sprite.bin" then
            assets = file
        end
    end
    assert(assets, "the asset was carried")
    assert(assets.verbatim, "a raw glob keeps a binary file out of substitution")
    testAssert.eq(assets.text, "\0\1\2\3", "byte for byte")

    assert(template.write(plan))
    local config, err = manifest.load(into)
    assert(config, "the scaffolded manifest does not validate: " .. tostring(err))
    testAssert.eq(config.dependencies.host.kind, "cargo", "the cargo dependency stands")
    testAssert.eq(config.build.targets.game.stub, "tecs", "and so does a non-default stub")
    testAssert.eq(config.build.targets.game.output, "build/mygame", "with the project name substituted into it")
    remove(dir)
    remove(into)
end

return M
