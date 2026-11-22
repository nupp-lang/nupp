-- The builtin closure harness: what a core binary carries of one registered
-- builtin (`nupp.compiler.project.builtins`), proven by building programs and
-- reading what was written.
--
-- For one builtin it builds, as core binaries, a program that does not reach the
-- builtin (`hello`), one that does (`uses`), and `uses` again built without the
-- builtin. It checks the bundle's carried modules and its `@lib/` references, the
-- library and notice files in each package, the symbols every staged binary
-- exports and imports, and the refusal of the stripped build, and it records the
-- package sizes. A library spec runs it for its own entry on each platform:
--
--     local closure = require("tools.packaging.builtinclosure")
--     local result = closure.run({
--         name = "sqlite",
--         hello = FIXTURES .. "/hello",
--         uses = FIXTURES .. "/uses",
--         reaches = {"sqlite"},
--         chain = {"src/main.nupp", "src/app/store.nupp"},
--     })
--     assert(#result.problems == 0, table.concat(result.problems, "\n"))
--
-- `entry` registers a fixture builtin for the builds instead of naming a real one
-- (`NUPP_BUILTIN_FIXTURE`); a fixture's `hello` is also built with nothing
-- registered and must be byte-identical, which is the strongest statement that an
-- unreached builtin costs nothing.
local json = require("testjson")

local ROOT = require("helpers.paths").root
local NUPP = ROOT .. "/bin/nupp"

local closure = {}

local function quote(text)
    return "'" .. tostring(text):gsub("'", "'\\''") .. "'"
end

local function succeeded(...)
    local first, _, code = ...

    return first == true or first == 0 or code == 0
end

local function run(command)
    assert(succeeded(os.execute(command)), "failed: " .. command)
end

local function capture(command)
    local pipe = assert(io.popen(command))
    local text = pipe:read("*a")
    local ok, _, code = pipe:close()

    return text, ok == true or ok == 0 or code == 0
end

local function read(path)
    local file = io.open(path, "rb")
    if file == nil then
        return nil
    end
    local text = file:read("*a")
    file:close()

    return text
end

local function write(path, text)
    local file = assert(io.open(path, "wb"))
    file:write(text)
    file:close()
end

local function lines(text)
    local found = {}
    for line in (text or ""):gmatch("[^\r\n]+") do
        found[#found + 1] = line
    end

    return found
end

--- The host's platform: darwin, linux or windows.
function closure.platform()
    if package.config:sub(1, 1) == "\\" then
        return "windows"
    end
    local name = (capture("uname -s 2>/dev/null")):lower()

    return name:find("darwin", 1, true) and "darwin" or "linux"
end

--- The file name a library base name has on this platform.
function closure.filename(base)
    local platform = closure.platform()
    if platform == "windows" then
        return base .. ".dll"
    elseif platform == "darwin" then
        return "lib" .. base .. ".dylib"
    end

    return "lib" .. base .. ".so"
end

--- Why the harness cannot run here, or nil: it builds core binaries.
function closure.unavailable()
    if os.getenv("NUPP_CORE_RUNTIME") == nil then
        return "core binaries are built by the native core, and this run is not on it"
    end

    return nil
end

local function copyProject(source)
    local directory = os.tmpname()
    os.remove(directory)
    run("mkdir -p " .. quote(directory))
    run("cp -R " .. quote(source) .. "/. " .. quote(directory))
    run("rm -rf " .. quote(directory .. "/build"))

    return directory
end

--- Builds the project at `directory` as a core binary with `arguments`, with
--- the fixture registry `fixture` names when one does. Answers the decoded
--- `--json` report, whether the build succeeded, and its standard error.
function closure.build(directory, arguments, fixture)
    local environment = "NUPP_RUNTIME=core"
    if fixture ~= nil then
        environment = environment .. " NUPP_BUILTIN_FIXTURE=" .. quote(fixture)
    end
    local errors = directory .. "/.build-stderr"
    local text, ok = capture(
        "cd " .. quote(directory) .. " && env " .. environment .. " " .. quote(NUPP) .. " build --json "
        .. (arguments or "") .. " 2>" .. quote(errors)
    )
    local decoded = text ~= "" and json.decode(text) or {ok = false, diagnostics = {}}

    return decoded, ok and decoded.ok == true, read(errors) or ""
end

-- Every file of a package generation, by its path under the generation.
local function generationFiles(generation)
    local files = {}
    for _, path in ipairs(lines(capture("cd " .. quote(generation) .. " && find . -type f -o -type l"))) do
        files[#files + 1] = path:gsub("^%./", "")
    end
    table.sort(files)

    return files
end

-- The generation directory a launcher at `artifact` runs.
local function generationOf(artifact)
    local launcher = read(artifact) or ""
    local relative = launcher:match('bundle="%$here"/\'([^\']+)\'') or launcher:match('bundle="%$here"/(%S+)')
    if relative == nil then
        return nil
    end

    return (artifact:match("^(.*)/[^/]+$") or ".") .. "/" .. relative
end

-- The external symbols `file` defines and the ones it imports, as sets.
local function symbols(file)
    local platform = closure.platform()
    local defined, imported = {}, {}

    local function collect(command, into)
        for _, line in ipairs(lines(capture(command .. " 2>/dev/null"))) do
            local name = line:match("(%S+)$")
            if name then
                into[name] = true
            end
        end
    end

    if platform == "darwin" then
        collect("nm -gU " .. quote(file), defined)
        collect("nm -gu " .. quote(file), imported)
    elseif platform == "linux" then
        collect("nm -D --defined-only " .. quote(file), defined)
        collect("nm -D --undefined-only " .. quote(file), imported)
    else
        local text = capture("llvm-objdump -p " .. quote(file) .. " 2>/dev/null")
        local section = nil
        for _, line in ipairs(lines(text)) do
            if line:find("Export Table", 1, true) then
                section = defined
            elseif line:find("Import Tables", 1, true) then
                section = imported
            elseif section ~= nil then
                local name = line:match("^%s+%d+%s+(%S+)$") or line:match("^%s+%S+%s+%d+%s+(%S+)$")
                if name then
                    section[name] = true
                end
            end
        end
    end

    return defined, imported
end

-- The shared libraries `file` loads by name.
local function dependencies(file)
    local platform = closure.platform()
    local command = platform == "darwin" and "otool -L " .. quote(file)
        or platform == "linux" and "readelf -d " .. quote(file)
        or "llvm-objdump -p " .. quote(file)

    return capture(command .. " 2>/dev/null")
end

local function binaries(generation)
    local found = {}
    for _, relative in ipairs(generationFiles(generation)) do
        if relative == "runtime" or relative == "runtime.exe" or relative:match("^lib/") or relative:match("%.dll$") then
            found[#found + 1] = relative
        end
    end

    return found
end

local function bytesOf(generation)
    local total = 0
    for _, relative in ipairs(generationFiles(generation)) do
        total = total + #(read(generation .. "/" .. relative) or "")
    end

    return total
end

local function reported(report, name)
    for _, builtin in ipairs(report.builtins or {}) do
        if builtin.name == name then
            return builtin
        end
    end

    return nil
end

--- Runs the harness for one builtin. `options`:
---   name     the builtin
---   entry    a fixture registry entry to register for the builds, or nil
---   hello    a project that does not reach the builtin
---   uses     a project that does
---   reaches  modules of the builtin `uses` must carry
---   chain    the files, relative to `uses`, the stripped build must name
---   record   a path to write the result to as JSON, or nil
--- Answers `{problems = {...}, sizes = {...}, ...}`; no problem is a pass.
function closure.run(options)
    local result = {name = options.name, problems = {}, sizes = {}}
    local problems = result.problems

    local function problem(format, ...)
        problems[#problems + 1] = format:format(...)
    end

    local fixture = nil
    local scratch = os.tmpname()
    os.remove(scratch)
    run("mkdir -p " .. quote(scratch))
    if options.entry ~= nil then
        fixture = scratch .. "/builtins.json"
        write(fixture, json.encode({[options.name] = options.entry}))
    end
    local entry = options.entry
    if entry == nil then
        entry = require("nupp.compiler.project.builtins").REGISTRY[options.name]
    end
    if entry == nil then
        problem("%s is not a registered builtin", options.name)
        return result
    end
    local files, notices = {}, {}
    for _, library in ipairs(entry.libraries or {}) do
        files[#files + 1] = closure.filename(library.file)
        for _, notice in ipairs(library.notices or {}) do
            notices[#notices + 1] = notice
        end
    end

    -- uses: carries the builtin, its references, its libraries and notices.
    local uses = copyProject(options.uses)
    local usesReport, usesBuilt, usesErrors = closure.build(uses, "", fixture)
    local usesGeneration = usesBuilt and generationOf(uses .. "/" .. usesReport.artifact) or nil
    local exported = {}
    if not usesBuilt or usesGeneration == nil then
        problem("uses did not build: %s", usesErrors:sub(-2000))
    else
        local carried = reported(usesReport, options.name)
        if carried == nil then
            problem("uses does not report carrying %s", options.name)
        else
            local modules = {}
            for _, module in ipairs(carried.modules) do
                modules[module] = true
            end
            for _, module in ipairs(options.reaches or {}) do
                if not modules[module] then
                    problem("uses does not carry %s", module)
                end
            end
        end
        local bundle = read(usesGeneration .. "/" .. usesReport.artifact:match("([^/]+)$") .. ".bundle") or ""
        for _, file in ipairs(files) do
            if not bundle:find("@lib/" .. file, 1, true) then
                problem("uses's bundle names no @lib/%s", file)
            end
            local staged = usesGeneration .. "/lib/" .. file
            if read(staged) == nil then
                problem("uses's package has no lib/%s", file)
            else
                for name in pairs((symbols(staged))) do
                    exported[name] = true
                end
            end
        end
        for _, notice in ipairs(notices) do
            if read(usesGeneration .. "/notices/" .. notice) == nil then
                problem("uses's package has no notices/%s", notice)
            end
        end
        if next(exported) == nil and #files > 0 then
            problem("the symbols of %s were not read", table.concat(files, ", "))
        end
        result.sizes.uses = bytesOf(usesGeneration)
        result.usesBuiltins = carried
    end

    -- hello: carries none of it, and no binary it stages names its symbols.
    local hello = copyProject(options.hello)
    local helloReport, helloBuilt, helloErrors = closure.build(hello, "", fixture)
    local helloGeneration = helloBuilt and generationOf(hello .. "/" .. helloReport.artifact) or nil
    if not helloBuilt or helloGeneration == nil then
        problem("hello did not build: %s", helloErrors:sub(-2000))
    else
        if reported(helloReport, options.name) ~= nil then
            problem("hello reports carrying %s", options.name)
        end
        local bundle = read(helloGeneration .. "/" .. helloReport.artifact:match("([^/]+)$") .. ".bundle") or ""
        for _, file in ipairs(files) do
            if bundle:find("@lib/" .. file, 1, true) then
                problem("hello's bundle names @lib/%s", file)
            end
        end
        for _, relative in ipairs(generationFiles(helloGeneration)) do
            for _, file in ipairs(files) do
                if relative == "lib/" .. file or relative == file then
                    problem("hello's package stages %s", relative)
                end
            end
            for _, notice in ipairs(notices) do
                if relative == "notices/" .. notice then
                    problem("hello's package stages %s", relative)
                end
            end
        end
        for _, relative in ipairs(binaries(helloGeneration)) do
            local path = helloGeneration .. "/" .. relative
            local defined, imported = symbols(path)
            for name in pairs(exported) do
                if defined[name] then
                    problem("hello's %s exports %s", relative, name)
                end
                if imported[name] then
                    problem("hello's %s imports %s", relative, name)
                end
            end
            local loads = dependencies(path)
            for _, file in ipairs(files) do
                if loads:find(file, 1, true) then
                    problem("hello's %s loads %s", relative, file)
                end
            end
        end
        result.sizes.hello = bytesOf(helloGeneration)

        -- With nothing registered, hello is the same package byte for byte.
        -- It is built where it was, since a bundle names its sources' paths.
        if fixture ~= nil then
            local registered = helloGeneration:match("([^/]+)$")
            local kept = scratch .. "/hello-registered"
            run("cp -R " .. quote(helloGeneration) .. " " .. quote(kept))
            helloGeneration = kept
            run("rm -rf " .. quote(hello .. "/build"))
            local plain = hello
            local plainReport, plainBuilt, plainErrors = closure.build(plain, "", nil)
            local plainGeneration = plainBuilt and generationOf(plain .. "/" .. plainReport.artifact) or nil
            if plainGeneration == nil then
                problem("hello did not build with nothing registered: %s", plainErrors:sub(-2000))
            else
                local left, right = generationFiles(helloGeneration), generationFiles(plainGeneration)
                if table.concat(left, "\n") ~= table.concat(right, "\n") then
                    problem("hello's package files differ with %s registered", options.name)
                else
                    for _, relative in ipairs(left) do
                        if read(helloGeneration .. "/" .. relative) ~= read(plainGeneration .. "/" .. relative) then
                            problem("hello's %s differs with %s registered", relative, options.name)
                        end
                    end
                end
                if registered ~= plainGeneration:match("([^/]+)$") then
                    problem("hello's generation differs with %s registered", options.name)
                end
            end
        end
    end

    -- uses, stripped: refused with the chain, and nothing written.
    local stripped = copyProject(options.uses)
    local strippedReport, strippedBuilt = closure.build(stripped, "--without " .. options.name, fixture)
    if strippedBuilt then
        problem("uses built --without %s", options.name)
    else
        local diagnostic = (strippedReport.diagnostics or {})[1]
        if diagnostic == nil or diagnostic.code ~= "NUPP0006" then
            problem("the stripped build did not report NUPP0006: %s", json.encode(strippedReport.diagnostics or {}))
        else
            result.refusal = diagnostic.message
            if not diagnostic.message:find("built without " .. options.name, 1, true) then
                problem("the refusal does not name %s: %s", options.name, diagnostic.message)
            end
            for _, file in ipairs(options.chain or {}) do
                if not diagnostic.message:find(file .. ":", 1, true) then
                    problem("the refusal does not name %s: %s", file, diagnostic.message)
                end
            end
            if #(diagnostic.related or {}) ~= #(options.chain or {}) then
                problem("the refusal relates %d places, not %d", #(diagnostic.related or {}), #(options.chain or {}))
            end
        end
        if strippedReport.artifact ~= nil or read(stripped .. "/build/binary") ~= nil then
            problem("the stripped build wrote an artifact")
        end
    end
    if usesGeneration ~= nil and helloGeneration ~= nil then
        result.sizes.difference = result.sizes.uses - result.sizes.hello
    end
    for _, directory in ipairs({uses, hello, stripped}) do
        run("rm -rf " .. quote(directory))
    end
    run("rm -rf " .. quote(scratch))
    if options.record ~= nil then
        write(options.record, json.encode({name = result.name, sizes = result.sizes, problems = problems}))
    end

    return result
end

return closure
