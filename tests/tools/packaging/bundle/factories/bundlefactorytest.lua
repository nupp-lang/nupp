local fixture = require("helpers.bundlefixture")
local NUPP = fixture.NUPP
local tempProject = fixture.tempProject
local readFile = fixture.readFile
local run = fixture.run
local MANIFEST = fixture.MANIFEST

local M = {}

function M.algorithmFactoryReferencesCarryTheirSelectedProviders()
    local dir = tempProject({
        ["nupp.lua"] = MANIFEST:gsub('kind = "bundle"', 'kind = "modules"'),
        [
            "src/app/main.nupp"
        ] = [[
local {checksum, compress} = require("bytes")
local catalog = require("bytes")
local {digest, mac, formats} = catalog
assert(checksum("crc32"):compute("123456789") == 0xcbf43926ULL)
assert(digest("sha256"):computehex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
assert(#mac("hmac-sha256"):computehex("key", "message") == 64)
local gzip = compress("gzip")
assert(gzip:decompress(gzip:compress("hello")) == "hello")
assert(table.concat(formats("compression"), ",") == "deflate-raw,gzip,zlib")
print("factories carried")
]],
    })
    local output, built = run(dir, "'" .. NUPP .. "' build")
    assert(built, output)
    for _, family in ipairs({"checksum", "digest", "mac", "nativecompression"}) do
        assert(readFile(dir .. "/build/nupp/runtime/provider/" .. family .. ".lua"), family .. " provider is staged")
    end
    local result, ran = run(dir, "LUA_PATH='./build/?.lua;;' luajit build/app/main.lua")
    assert(ran and result == "factories carried\n", result)
    os.execute("rm -rf '" .. dir .. "'")
end

function M.formatListingsDoNotNeedAlgorithmFactoryReferences()
    for _, host in ipairs({"native", "browser"}) do
        local manifest = MANIFEST:gsub('kind = "bundle"', 'kind = "modules"')
        if host == "browser" then
            manifest = manifest:gsub('kind = "modules",', 'kind = "modules", host = "browser",')
        end
        local compression = host == "native"
            and 'assert(table.concat(formats("compression"), ",") == "deflate-raw,gzip,zlib")'
            or 'assert(#formats("compression") == 0)'
        local dir = tempProject({
            ["nupp.lua"] = manifest,
            [
                "src/app/main.nupp"
            ] = [[
local {formats} = require("bytes")
assert(table.concat(formats("digest"), ",") == "md5,sha1,sha256,sha512")
assert(table.concat(formats("checksum"), ",") == "adler32,crc32,crc32c,crc64-ecma,crc64nvme")
assert(table.concat(formats("mac"), ",") == "hmac-sha256")
]]
            .. compression
            .. '\nprint("catalogs carried")\n',
        })
        local output, built = run(dir, "'" .. NUPP .. "' build")
        assert(built, output)
        for _, family in ipairs({"checksum", "digest", "mac"}) do
            assert(readFile(dir .. "/build/nupp/runtime/provider/" .. family .. ".lua"), family .. " catalog is staged")
        end
        if host == "native" then
            local result, ran = run(dir, "LUA_PATH='./build/?.lua;;' luajit build/app/main.lua")
            assert(ran and result == "catalogs carried\n", result)
        else
            assert(readFile(dir .. "/build/nupp/runtime/browser/crc.lua"), "browser CRC backend is staged")
        end
        os.execute("rm -rf '" .. dir .. "'")
    end
end

return M
