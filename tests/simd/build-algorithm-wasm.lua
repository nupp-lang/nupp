-- Package the C-safe owned-algorithm differential corpus for the browser guest.
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

local imports, corpus, probes
local entry = "algorithm"
local random = true
write("src/corpusmath.g.nupp", snapshot("tests/simd/corpusmath.lua"))
if name == "utf8simd" then
    copy("bench/utf8simd/src/utf8simd.nupp", "utf8simd.nupp")
    copy("bench/utf8simd/src/utf8reference.nupp", "utf8reference.nupp")
    imports = 'local simd=require("utf8simd"); local reference=require("utf8reference"); local shipped=require("nupp.text.utf8")\n'
    corpus = body(snapshot("bench/utf8simd/tests/run.lua"), "local checks = 0", 'print(("ok - %d UTF-8')
    probes = {utf8simd = {"validPrefix"}}
elseif name == "base64simd" then
    copy("bench/base64simd/src/base64simd.nupp", "base64simd.nupp")
    copy("bench/base64simd/src/base64reference.nupp", "base64reference.nupp")
    imports = 'local simd=require("base64simd"); local reference=require("base64reference")\n'
    corpus = body(snapshot("bench/base64simd/tests/run.lua"), "local checks = 0", 'print(("ok - %d base64')
    local removed
    corpus, removed = corpus:gsub(
        '\n    if shipped%.encode%(value%) ~= want then\n        error%(%(%"reference disagrees with nupp%.codec%.base64 on %%s %(%%d bytes%)%"%):format%(what, #value%), 0%)\n    end',
        ""
    )
    assert(removed == 1, "missing shipped Base64 comparison")
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
local runner = "__nupp_wasm_runner"
write(
    "src/" .. runner .. ".g.nupp",
    (
        "local entry=require(%q)\nif __nuppWasmBeforeRun then __nuppWasmBeforeRun() end\nlocal cases=entry.run()\nlocal fingerprint=entry.randomFingerprint and entry.randomFingerprint()\nif fingerprint then return string.format('{\"cases\":%%.0f,\"randomFingerprint\":\"%%s\"}',cases,fingerprint) end\nreturn string.format('{\"cases\":%%.0f}',cases)\n"
    ):format(entry)
)
r.write(
    directory .. "/nupp.lua",
    (
        'return {include={"src",%q},build={targets={app={kind="bundle",entries={%q},sources={"src"},output="dist/app.lua",outDir="build/app",dialect="luajit",host="browser",optimize=1,aot="require-wasm",aotFeatures={minimum="simd128",maximum="simd128"}}}}}\n'
    ):format(root .. "/src", runner)
)
local compiler = os.getenv("NUPP_WASM_CC") or os.getenv("EMCC") or "emcc"
local nupp = os.getenv("NUPP_SIMD_NUPP") or root .. "/bin/nupp"
-- Through LLVM nupp compiles the Wasm itself and no Emscripten is asked for.
local compilerEnvironment = ""
if os.getenv("NUPP_AOT_BACKEND") ~= "llvm" then
    local resolvedCompiler = r.command("command -v " .. q(compiler), directory .. "/compiler-path.log"):match("[^\r\n]+")
    local compilerDirectory = assert(resolvedCompiler and resolvedCompiler:gsub("\\", "/"):match("^(.*)/[^/]+$"))
    compilerEnvironment = "PATH=" .. q(compilerDirectory .. ":" .. (os.getenv("PATH") or "")) .. " "
end
r.command(
    "cd " .. q(
        directory
    ) .. " && " .. compilerEnvironment .. "NUPP_WASM_CC=" .. q(compiler) .. " " .. q(nupp) .. " build --target app",
    directory .. "/build.log"
)
r.writeJson(directory .. "/corpus.json", {
    algorithm = name,
    compiler = nupp,
    entry = entry,
    probes = probes,
    oracleSources = oracleSources,
    coverage = {
        {
            family = "owned-algorithm",
            algorithm = name,
            contract = "shared scalar expectations with portable correctness PRNG"
        }
    }
})
print(directory)
