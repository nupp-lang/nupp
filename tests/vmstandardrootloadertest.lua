local test = require("assert")
local environment = require("nupp.compiler.project.env")
local runtime = require("nupp.compiler.runtime")
local compile = require("nupp.tools.cli.compile")
local ROOT = assert(environment.compilerRoot())
local M = {}

local function withLoaders(compiler, loaded, body)
    local before = {}
    for _, loader in ipairs(package.loaders) do
        before[loader] = true
    end
    local env = environment.new(ROOT, {config = {include = {}}, cache = false})
    env.roots = {}
    local remove = runtime.install(env, compiler, nil, nil, loaded)
    local added = {}
    for _, loader in ipairs(package.loaders) do
        if not before[loader] then
            added[#added + 1] = loader
        end
    end
    local ok, reason = pcall(body, added)
    remove()
    assert(ok, reason)
end

function M.finalStandardRootsUseTheExistingCompilerSourceLoader()
    local reached = {}
    local marker = {}
    withLoaders(
        function(path, _, name, source)
            reached[name] = {path = path, source = source}
            return "source-token"
        end,
        function()
            return function()
                return marker
            end
        end,
        function(loaders)
            for _, name in ipairs({"types", "own", "utf8", "io.internal.files", "nupp.digest.digest"}) do
                local loader = loaders[#loaders](name)
                test.eq(type(loader), "function", name)
                test.eq(loader(), marker, name)
                local selected = reached[name]
                assert(
                    selected.source ~= nil and selected.path == name or selected.path:find("/src/", 1, true),
                    selected.path
                )
            end
            local reason = loaders[#loaders]("application.nonexistent")
            test.eq(type(reason), "string")
            assert(reason:find("no standard library source for module 'application.nonexistent'", 1, true), reason)
        end
    )
end

function M.dynamicPublicSimdUsesTheFrozenHostObject()
    local loadImage = assert(rawget(_G, "__nupp_load_image"))
    local reached, compiledName
    withLoaders(
        function(path, env, name)
            reached, compiledName = path, name
            return compile.image(path, env, name)
        end,
        function(image)
            return loadImage(image)
        end,
        function(loaders)
            local chunk = loaders[1]("simd")
            test.eq(type(chunk), "function")
            test.eq(reached, ROOT .. "/native/crates/vm/lib/nupp/vm/simdbinding.nupp")
            test.eq(compiledName, "nupp.vm.simdbinding")
            local value = chunk()
            test.eq(value, package.loaded["nupp.simd"])
            test.eq(value.vectors(), nil)
            test.raises(
                function()
                    value.species()
                end,
                "SIMD operation requires a statically resolved call"
            )
        end
    )
end

function M.erasedCompileTimeNamespacesDoNotLoadRuntimeModules()
    local source = [[
@comptime local function Refuse(info: types.derive.Info): types.derive.Result<any>
    return types.derive.error("unsupported declaration", info.reference)
end
@comptime local function Items(Element: type): type
    return types.array(Element)
end
local store = require("types").Store.create()
return type(store)
]]
    local env = environment.new(ROOT, {cache = false})
    local image = assert(compile.image("metadata-comptime.nupp", env, "metadatacomptime", nil, source, false))
    local chunk = assert(assert(rawget(_G, "__nupp_load_image"))(image))
    test.eq(chunk(), "table", "ordinary runtime namespace remains available")
end

function M.coldExternalProjectsRetainDeclaredStandardLibraryTypes()
    local fs = require("nupp.compiler.fs")
    local project = require("nupp.tools.vm.project")
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    assert(fs.writeFile(dir .. "/nupp.lua", 'return {include = {"src"}}\n'))
    assert(
        fs.writeFile(
            dir .. "/src/coldlibraries.nupp",
            [[
module coldlibraries
const gzip = bytes.compress("gzip")
local main = {}
function main.run(): integer
    assert(gzip ~= nil)
    local facts = os.info()
    assert(facts.pointerbits == 32 or facts.pointerbits == 64)
    assert(facts.parallelism >= 1)
    local buffer = bytes.Buffer.create("abc")
    local reader: io.Reader = buffer:reader()
    assert(reader:read(3) == "abc")
    local algorithm = bytes.digest("sha256")
    assert(algorithm.digestsize == 32)
    local context = algorithm:create()
    context:write("abc")
    assert(context:hexdigest() == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    return 42
end
export = main
]]
        )
    )
    local ok, problem = pcall(function()
        local image = project.emit(dir, "coldlibraries", "")
        local chunk = assert(assert(rawget(_G, "__nupp_load_image"))(image))
        test.eq(chunk().run(), 42, "a cold external image retains IO ownership and descriptor contracts")
    end)
    os.execute("rm -rf '" .. dir .. "'")
    assert(ok, problem)
end

local function coroutineContext()
    local project = require("nupp.tools.vm.project")
    local env = environment.new(ROOT, {
        cache = false,
        nativeCompilerServices = false,
        compilerServices = require("nupp.compiler.hostservices"),
        config = project.manifest(ROOT .. "/nupp.lua"),
    })
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/lib")
    table.insert(env.roots, 1, ROOT .. "/native/crates/vm/decls")
    env.managedCoroutines = true
    env.globals.coroutine.t = assert(environment.resolveModule(env, "nupp.vm.ownedCoroutine"))

    return env
end

local function checkedCoroutine(source, env)
    local parser = require("nupp.compiler.syntax.parser")
    local checker = require("helpers.fragment")
    local parsed = parser.parse(source, "native-coroutine-contract.nupp")
    test.eq(#parsed.errors, 0)
    local codes, messages = {}, {}
    for _, diagnostic in ipairs(
        checker.check(parsed, "native-coroutine-contract.nupp", env, {
            moduleName = "nupp.tests.nativecoroutine",
        })
    ) do
        if not diagnostic.severity or diagnostic.severity == "error" then
            codes[#codes + 1] = diagnostic.code
            messages[#messages + 1] = diagnostic.msg
        end
    end

    return parsed, table.concat(codes, ","), table.concat(messages, "\n")
end

function M.nativeCoroutineFacadeRetainsThePublicNullaryBodyType()
    local env = coroutineContext()
    local exports = assert(environment.resolveModuleExports(env, "nupp.tasks"))
    local body = assert(exports.types.Nullary, "the VM task declaration must expose main's Nullary alias")
    test.eq(body.tag, "func")
    test.eq(#body.params, 0)
    test.eq(#body.rets, 1)
    test.eq(body.rets[1].tag, "any")
    local _, codes, messages = checkedCoroutine(
        [[
local body: coroutine.Nullary = function(): integer return 7 end
local answer: any = body()
assert(answer == 7)
]],
        env
    )
    test.eq(codes, "", messages)
end

function M.managedCoroutineNamespacesRetainOwnedFunctionsAndExtendFinalMembers()
    local members = require("nupp.compiler.types.members")
    local env = coroutineContext()
    local namespace = env.globals.coroutine.t
    test.eq(namespace.tag, "shape")
    local path = ROOT .. "/native/crates/vm/decls/nupp/vm/ownedCoroutine.d.nupp"
    local parsed = assert(env.loadedPaths[path].result)
    local original

    local function find(node)
        if type(node) ~= "table" then
            return
        end
        if node.kind == "recordDecl" and node.name.text == "Coroutines" then
            original = assert(node.resolvedType)
        end
        for _, child in ipairs(node) do
            find(child)
        end
    end

    find(parsed.root)
    local projected = members.view(namespace)
    local count = 0
    for _, member in ipairs(members.view(assert(original)).ordered) do
        count = count + 1
        test.eq(projected.byname[member.name].readType, member.readType, member.name .. " read contract")
        test.eq(projected.byname[member.name].writeType, member.writeType, member.name .. " write contract")
    end
    test.eq(count, 8)
    local _, codes, messages = checkedCoroutine(
        [[
local tasks = require("coroutine")
local cancelled = tasks.iscancelled
local scope = tasks.scope
do local child = coroutine.create(function(): nil end) ;
    coroutine.resume(child)
end
return cancelled("ordinary reason"), scope
]],
        env
    )
    test.eq(codes, "", messages)
    _, codes, messages = checkedCoroutine(
        [[
local coroutine = {iscancelled = function(value: integer): integer return value + 1 end}
return coroutine.iscancelled(2)
]],
        env
    )
    test.eq(codes, "", messages)
    _, codes = checkedCoroutine(
        [[
local child = coroutine.create(function(): nil end)
coroutine.close(child)
return coroutine.status(child)
]],
        env
    )
    test.eq(codes, "NUPP2601", "namespace shape retains owned take/close refusals")
end

function M.nativeTaskDeclarationsKeepCanonicalFunctionResultsAndScopeBorrows()
    local env = coroutineContext()
    local _, codes, messages = checkedCoroutine(
        [[
local type Work = function(integer): (integer, string?, nil)
local queued: coroutine.Status = "queued"
local running: coroutine.Status = "running"
local done: coroutine.Status = "done"
local failed: coroutine.Status = "failed"
local cancelled: coroutine.Status = "cancelled"
local function inspect(borrows task: coroutine.Task<Work>): (integer, string?, nil)
    local status: coroutine.Status = task:status()
    return task:await()
end
local function work(n: integer): (integer, string?, nil)
    return n, "kept", nil
end
local worker = {}
function worker.run(n: integer): (integer, string?, nil)
    return n, "forked", nil
end
do local scope = coroutine.scope() ;
    local child = scope:spawn(7, work)
    local n: integer, text: string?, tail: nil = inspect(child)
    assert(n == 7 and text == "kept" and tail == nil)
    local forked = scope:work(9, worker.run)
    local m: integer, other: string?, last: nil = inspect(forked)
    assert(m == 9 and other == "forked" and last == nil)
end
]],
        env
    )
    test.eq(codes, "", messages)
    _, codes = checkedCoroutine(
        [[
local type Work = function(): integer
do local scope = coroutine.scope() ;
    local task: coroutine.Task<Work> = scope:spawn(function(): integer return 7 end)
end
]],
        env
    )
    test.eq(codes, "NUPP2603", "a plain annotation cannot erase a task scope loan")
    _, codes = checkedCoroutine("local type Invalid = coroutine.Task<integer>", env)
    test.eq(codes, "NUPP2130", "Task takes a function type, not the native result pack")
    _, codes = checkedCoroutine('local bad: coroutine.Status = "other"', env)
    test.eq(codes, "NUPP2001", "Status keeps its five scheduler states")
    _, codes = checkedCoroutine(
        [[
local function escape(): coroutine.Task<function(): integer>
    do local scope = coroutine.scope() ;
        return scope:spawn(function(): integer return 7 end)
    end
end
]],
        env
    )
    assert(codes:find("NUPP2608", 1, true), "a task cannot escape its owning scope: " .. codes)
end

function M.nativeCoroutineFacadeReusesTaskConstructorsAndCompleteResults()
    local env = coroutineContext()
    local parsed, codes, messages = checkedCoroutine(
        [[
local private = require("nupp.tasks")
local public = require("coroutine")
assert(public.Scope == private.Scope, "public Scope must reuse the private constructor")
assert(public.Cancellation == private.Cancellation, "public Cancellation must reuse the private constructor")
local type Work = function(integer): (integer, string?, nil)
local function inspect(borrows task: coroutine.Task<Work>): (integer, string?, nil)
    return task:await()
end
local function work(n: integer): (integer, string?, nil)
    return n, "kept", nil
end
do local scope = coroutine.scope() ;
    local child = scope:spawn(7, work)
    local n, text, tail = inspect(child)
    assert(n == 7 and text == "kept" and tail == nil, "spawn preserves heterogeneous result positions")
    assert(select("#", inspect(child)) == 3, "spawn preserves the trailing nil result count")
    local forked = scope:work(9, work)
    local m, other, last = inspect(forked)
    assert(m == 9 and other == "kept" and last == nil, "fork preserves heterogeneous result positions")
    assert(select("#", inspect(forked)) == 3, "fork preserves the trailing nil result count")
end
return true
]],
        env
    )
    test.eq(codes, "", messages)
    test.eq(require("program").run(parsed, "nativecoroutineconstructors"), true)
end

return M
