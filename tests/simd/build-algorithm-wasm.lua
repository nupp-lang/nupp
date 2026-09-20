-- Package the existing owned-algorithm differential corpus for the stock host.
-- Checked boundaries exclude only native setup and optional timing code.
local r = require("tests.simd.runner")
local name, directory = assert(arg[1]), assert(arg[2])
local root, q = r.root(), r.quote
local existing = io.open(directory .. "/corpus.json", "rb")
if existing then
    existing:close();
    error("refusing to overwrite algorithm evidence")
end
local preparation = os.tmpname()
r.command("mkdir -p " .. q(directory .. "/src"), preparation)
r.write(directory .. "/prepare.log", r.read(preparation))
os.remove(preparation)
local oracleSources = {}

local function write(relative, source)
    local path = directory .. "/" .. relative
    r.command("mkdir -p " .. q(assert(path:match("^(.*)/"))), directory .. "/directories.log")
    r.write(path, source)
end

local function snapshot(path)
    local source = r.read(root .. "/" .. path)
    write("oracle-sources/" .. path, source)
    local hash = r.command(
        "node -e " .. q(
            'const fs=require("fs"),c=require("crypto"); console.log(c.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"))'
        ) .. " " .. q(root .. "/" .. path),
        directory .. "/hash.log"
    )
        :match("(%x+)")
    assert(hash and #hash == 64)
    oracleSources[#oracleSources + 1] = {path = path, sha256 = hash}

    return source
end

local function body(source, first, last)
    local start = assert(source:find(first, 1, true), "missing corpus beginning")
    assert(not source:find(first, start + #first, true), "ambiguous corpus beginning")
    local finish = assert(source:find(last, start, true), "missing corpus ending")
    return source:sub(start, finish - 1)
end

local function copy(path, target)
    write("src/" .. target, r.read(root .. "/" .. path))
end

local imports, corpus, probes, eagerVariant
local entry = name == "fused-json" and "nupp.algorithm" or "algorithm"
local random = name ~= "fused-json"
if random then
    write("src/corpusmath.g.nupp", snapshot("tests/simd/corpusmath.lua"))
end
if name == "utf8simd" then
    copy("bench/utf8simd/src/utf8simd.nupp", "utf8simd.nupp")
    copy("bench/utf8simd/src/utf8reference.nupp", "utf8reference.nupp")
    imports = 'local simd=require("utf8simd"); local reference=require("utf8reference"); local shipped=require("nupp.text.utf8")\n'
    corpus = body(snapshot("bench/utf8simd/tests/run.lua"), "local checks = 0", 'print(("ok - %d UTF-8')
    probes = {utf8simd = {"validPrefix"}}
elseif name == "base64simd" then
    copy("bench/base64simd/src/base64simd.nupp", "base64simd.nupp")
    copy("bench/base64simd/src/base64reference.nupp", "base64reference.nupp")
    imports = 'local simd=require("base64simd"); local reference=require("base64reference"); local shipped=require("nupp.codec.base64")\n'
    corpus = body(snapshot("bench/base64simd/tests/run.lua"), "local checks = 0", 'print(("ok - %d base64')
    probes = {base64simd = {"encode"}}
elseif name == "simd-json" then
    copy("bench/simd-json/src/simd_json/indexer.nupp", "simd_json/indexer.nupp")
    copy("bench/simd-json/src/simd_json/indexer_reference.nupp", "simd_json/indexer_reference.nupp")
    write(
        "src/tape.g.nupp",
        [[
local array = require("nupp.mem.array")
local span = require("nupp.mem.span")
local indexer = require("simd_json.indexer")
local u32 = nupp.math.u32
local function indexed(source: string, capacity: integer): ({number}, number, number)
    local storage = array.scalar(array.uint32, capacity)
    local count, status, position = u32.wrap(0), u32.wrap(0), u32.wrap(0)
    do
        local writable = storage:write()
        count, status, position = indexer.index(span.fromString(source), writable)
    end
    local positions: {number} = {}
    local readable = storage:read()
    for offset = 1, count do positions[#positions + 1] = readable[u32.wrap(offset)] as number end
    return positions, status as number, position as number
end
return {indexed = indexed}
]]
    )
    imports = 'local indexed=require("tape").indexed; local reference=require("simd_json.indexer_reference")\n'
    corpus = "local checks = 0\n" .. body(
        snapshot("bench/simd-json/tests/index.lua"),
        "local function describe",
        'print(("ok - %d structural index'
    )
    probes = {["simd_json/indexer"] = {"index"}}
elseif name == "fused-json" then
    snapshot("bench/fused-json/tests/differential.lua")
    snapshot("src/nupp/runtime/vendor/lunajson/decoder.lua")
    snapshot("src/nupp/runtime/provider/lunajson.nupp")
    local source = r.read(root .. "/src/nupp/codec/json/internal/decoder/fused.nupp")
    eagerVariant = assert(
        tonumber(source:match("function fused%.decodeEager%(.+return decodeFused%(source, (%d+),")),
        "missing authored eager variant"
    )
    source = source:gsub(
        "module nupp%.codec%.json%.internal%.decoder%.fused\n",
        "module nupp.codec.json.internal.decoder.fusedbench\n",
        1
    )
        :gsub("\n    borrows source: string | Buffer,", "\n    source: string,")
    assert(not source:find("borrows source", 1, true), "fused benchmark signature rewrite incomplete")
    write("src/nupp/codec/json/internal/decoder/fusedbench.nupp", source)
    -- The full provider is native-only. Keep its decode/error contract and
    -- typed eager alias verbatim; only the dependency points at the separately
    -- compiled builder. The corpus below still asserts every original value
    -- and first-error position, and the runner proves this builder returned.
    local eager = snapshot("src/nupp/codec/json/internal/decoder/eager.nupp")
    eager = eager:gsub(
        "module nupp%.codec%.json%.internal%.decoder%.eager",
        "module nupp.codec.json.internal.decoder.eagerbench",
        1
    )
        :gsub(
            'require%("nupp%.codec%.json%.internal%.decoder%.fused"%)',
            'require("nupp.codec.json.internal.decoder.fusedbench")'
        )
    write("src/nupp/codec/json/internal/decoder/eagerbench.nupp", eager)
    local provider = snapshot("src/nupp/codec/json/aot.nupp")
    local decode = body(provider, "local function failDecode", "local function classify")
    write(
        "src/nupp/algorithmaot.g.nupp",
        'local eagerDecoder=require("nupp.codec.json.internal.decoder.eagerbench")\nlocal json={}\nlocal ARRAY_MARKER,OBJECT_MARKER,ARRAY_SHAPE,SERDE_MARKERS={},{},{},{}\n'
        .. decode
        .. '\nreturn json\n'
    )
    local suite = snapshot("tests/jsonfuseddifferentialtest.lua")
    local count
    suite, count = suite:gsub('require%("nupp%.codec%.json%.aot"%)', 'require("nupp.algorithmaot")')
    assert(count == 1, "missing fused corpus dependency")
    imports = "local suite=(function()\n" .. suite .. "\nend)()\n"
    corpus = 'local names={} for name in pairs(suite) do names[#names+1]=name end table.sort(names) for _, name in ipairs(names) do suite[name]() end local checks=#names\n'
    probes = {}
else
    error("unknown owned algorithm: " .. name)
end
local prelude = random and 'local math=require("corpusmath")\n' or ""
write(
    "src/" .. entry:gsub("%.", "/") .. ".g.nupp",
    prelude .. imports .. "local function run()\n" .. corpus .. "\nreturn checks end\nreturn {run=run" .. (
        random and ",randomFingerprint=math.fingerprint" or ""
    ) .. "}\n"
)
r.write(
    directory .. "/nupp.lua",
    (
        'return {include={"src",%q},build={targets={app={kind="bundle",entries={%q},sources={"src"},output="dist/app.lua",outDir="build/app",dialect="lua51",optimize=1,aot="require-wasm",aotFeatures={minimum="simd128",maximum="simd128"}}}}}\n'
    ):format(root .. "/src", entry)
)
local compiler = os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc"
local nupp = os.getenv("NUPP_SIMD_NUPP") or root .. "/bin/nupp"
r.command(
    "cd " .. q(directory) .. " && NUPP_WASM_CC=" .. q(compiler) .. " " .. q(nupp) .. " build --target app",
    directory .. "/build.log"
)
if name == "fused-json" then
    local source = r.read(directory .. "/dist/app.lua")
    local eager = assert(
        source:match("if%s+variant%s*==%s*" .. eagerVariant .. "%s+then%s+return%s+(__nuppConst_decodeFused_%x+)"),
        "missing actual eager specialization dispatch"
    )
    probes = {["nupp/codec/json/internal/decoder/fusedbench"] = {eager}}
end
r.writeJson(directory .. "/corpus.json", {
    algorithm = name,
    compiler = nupp,
    entry = entry,
    probes = probes,
    oracleSources = oracleSources,
    logical = name == "fused-json" and "decodeEager" or nil,
    variant = eagerVariant,
    coverage = {
        {
            family = "owned-algorithm",
            algorithm = name,
            contract = random and "shared scalar expectations with portable correctness PRNG"
            or "shared fused decoder expectations through the exact provider decode body"
        }
    }
})
print(directory)
