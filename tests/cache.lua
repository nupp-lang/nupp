-- Passing results are reusable only for explicitly covered input contracts.
-- This module uses the compiler's parser, dependency headers and fingerprints;
-- it never learns dependencies from a previous execution.
local fs = require("nupp.compiler.fs")
local fingerprint = require("nupp.compiler.project.fingerprint")
local parser = require("nupp.compiler.syntax.parser")
local header = require("nupp.compiler.project.header")
local cst = require("nupp.compiler.syntax.cst")
local files = require("io.internal.files")
local digest = fingerprint.contentDigest()
local M = {}

-- Selection and presentation do not change a package's answer. Unknown options
-- stay in the key; case selections never reach the package cache at all.
function M.flags(arguments)
    local flags = {}
    for _, value in ipairs(arguments) do
        if value:sub(1, 1) == "-"
            and value ~= "--json"
            and value ~= "--verbose"
            and value ~= "--color"
            and value ~= "--no-color"
            and value ~= "--timings"
            and not ({
                jobs = true,
                scope = true,
                group = true,
                exclude = true,
                ["exclude-group"] = true,
                color = true,
                timings = true
            })[value:match("^%-%-([^=]+)=")]
        then
            flags[#flags + 1] = value
        end
    end

    return table.concat(flags, "\0")
end

function M.open(options)
    if options.workerHost and not options.runtime and not os.getenv("NUPP_VM_BINARY") then
        return nil
    end
    local json = options.json
    local root = fs.absolute(options.root)
    local directories, selected = {}, {}
    for _, suite in ipairs(options.catalog) do
        directories[suite.path:match("^(.*)/") or "."] = true
    end
    for _, suite in ipairs(options.selected) do
        selected[suite.name] = true
    end
    local activeDirectories = {}
    for _, suite in ipairs(options.catalog) do
        if selected[suite.name] then
            activeDirectories[suite.path:match("^(.*)/") or "."] = true
        end
    end
    local environment, environmentNames = {}, {}
    -- Include all NUPP_* variables, including ones a new runtime introduces.
    -- Reading the entire environment also covers ordinary library/tool variables.
    local pipe = io.popen("env -0", "r")
    if not pipe then
        return nil
    end
    local values = pipe:read("*a") or ""
    pipe:close()
    if not values:find("\0", 1, true) then
        return nil
    end
    for item in values:gmatch("([^%z]+)") do
        local name = item:match("^([^=]+)=")
        if name then
            environment[#environment + 1] = item;
            environmentNames[name] = true
        end
    end
    table.sort(environment)
    local identity = {options.runner, options.flags, table.concat(environment, "\0"), _VERSION}
    if jit then
        identity[#identity + 1] = tostring(jit.version) .. tostring(jit.os) .. tostring(jit.arch)
    end
    -- The native compiler supplies its exact runtime/image paths. Legacy hosts
    -- supply their development provider and pinned toolchain artifacts instead.
    for _, name in ipairs({
        "<host>",
        "NUPP_VM_BINARY",
        "NUPP_VM_CLI_IMAGE",
        "NUPP_NATIVE_LIBRARY",
        "NUPP_STAGE0",
        "NUPP_TEST_BIN"
    }) do
        local path = name == "<host>" and options.runtime or os.getenv(name)
        if path and path ~= "" then
            local text = fs.readFile(path)
            if not text then
                return nil
            end
            identity[#identity + 1] = path .. "\0" .. digest(text)
        end
    end
    if jit then
        local executable = io.popen("command -v luajit", "r")
        local path = executable and executable:read("*l")
        if executable then
            executable:close()
        end
        local bytes = path and fs.readFile(path)
        if not bytes then
            return nil
        end
        identity[#identity + 1] = digest(bytes)
    end
    identity[#identity + 1] = fingerprint.subsystemFingerprint({"assert"})
    local base = digest(table.concat(identity, "\0"))
    local store = fs.absolute(options.build) .. "/.nupp-test-results"
    local cache = {packages = {}, reasons = {}}
    local env
    -- Share reads within one snapshot, then discard them before validating the
    -- post-run snapshot. A test or concurrent edit must invalidate a stored pass.
    local snapshots, listings, programs, sourceListings = {}, {}, {}, {}

    local function snapshot(path)
        local saved = snapshots[path]
        if not saved then
            local text = fs.readFile(path)
            local _, _, modified = files.stat(path)
            saved = {hash = text and digest(text), modified = modified}
            snapshots[path] = saved
        end

        return saved
    end

    local function listing(path)
        if not listings[path] then
            listings[path] = fs.listFiles(path)
        end
        return listings[path]
    end

    local function program(name)
        if not programs[name] then
            local quoted = "'" .. name:gsub("'", "'\"'\"'") .. "'"
            local pipe = io.popen("command -v " .. quoted .. " 2>/dev/null", "r")
            local path = pipe and pipe:read("*l")
            if pipe then
                pipe:close()
            end
            -- `command -v` names shell builtins without a path. Their code is
            -- the shell executable, not a file named `pwd` in the checkout.
            programs[name] = path and (path:find("/", 1, true) or path:find("\\", 1, true)) and fs.absolute(path)
                or path and name ~= "sh" and program("sh")
                or false
        end

        return programs[name]
    end

    local function sources(path)
        if not sourceListings[path] then
            local function quote(value)
                return "'" .. value:gsub("'", "'\"'\"'") .. "'"
            end

            local pipe = io.popen(
                "git -C " .. quote(
                    fs.absolute(root .. "/..")
                ) .. " ls-files -z --cached --others --exclude-standard -- " .. quote(path),
                "r"
            )
            if not pipe then
                return nil
            end
            local output = pipe:read("*a") or ""
            local ok = pipe:close()
            if not ok or output == "" then
                return nil
            end
            local paths = {}
            for relative in output:gmatch("([^%z]+)") do
                local path = fs.absolute(root .. "/../" .. relative)
                if files.stat(path) then
                    paths[#paths + 1] = path
                end
            end
            if #paths == 0 then
                return nil
            end
            sourceListings[path] = paths
        end

        return sourceListings[path]
    end

    local function key(directory, policy)
        local inputs, recent, compiler, visited = {}, false, false, {}

        local function add(path)
            path = fs.absolute(path)
            if inputs[path] then
                return true
            end
            local saved = snapshot(path)
            if not saved.hash then
                return false
            end
            inputs[path] = saved.hash
            local modified = saved.modified
            if not modified or tonumber(modified) / 1000 > os.time() - 2 then
                recent = true
            end

            return true
        end

        local function tree(path, packageRoot)
            path = fs.absolute(path)
            local kind = files.stat(path)
            if kind == "file" then
                return add(path)
            end
            if kind ~= "directory" then
                return false
            end
            for _, file in ipairs(listing(path)) do
                local relative = file:sub(#root + 2)
                local nested = false
                if packageRoot then
                    for other in pairs(directories) do
                        if other ~= directory
                            and (directory == "." or other:sub(1, #directory + 1) == directory .. "/")
                            and relative:sub(1, #other + 1) == other .. "/"
                        then
                            nested = true
                        end
                    end
                end
                if not nested and not add(file) then
                    return false
                end
            end

            return true
        end

        local function module(name)
            if visited[name] then
                return true
            end
            visited[name] = true
            if name:match("^nupp%.compiler[%.]?") or name:match("^nupp%.tools[%.]?") then
                compiler = true
                return true
            end
            local path
            if name:match("^helpers%.") then
                path = root .. "/" .. name:gsub("%.", "/") .. ".lua"
            end
            if not path then
                env = env or require("nupp.compiler.project.env").new(".")
                path = require("nupp.compiler.project.env").findRuntimeModulePath(env, name)
            end
            if not path then
                return false
            end
            -- Hash the artifact the ordinary loader executes as well as source.
            for pattern in package.path:gmatch("[^;]+") do
                local artifact = pattern:gsub("%?", name:gsub("%.", "/"))
                if fs.readFile(artifact) ~= nil then
                    if not add(artifact) then
                        return false
                    end
                    break
                end
            end

            return cache.source(path, add, module)
        end

        if not tree(root .. "/" .. directory, true) then
            return nil, recent, inputs
        end
        for _, input in ipairs(policy.inputs or {}) do
            if not tree(input) then
                return nil, recent, inputs, "missing declared input: " .. input
            end
        end
        for _, input in ipairs(policy.sources or {}) do
            local paths = sources(input)
            if not paths then
                return nil, recent, inputs, "unavailable source root: " .. input
            end
            for _, path in ipairs(paths) do
                if not tree(path) then
                    return nil, recent, inputs, "unreadable source: " .. path
                end
            end
        end
        for _, input in ipairs(policy.optionalInputs or {}) do
            if files.stat(input) then
                if not tree(input) then
                    return nil, recent, inputs, "unreadable optional input: " .. input
                end
            else
                inputs[fs.absolute(input)] = "missing"
            end
        end
        if policy.toolchain then
            local prefix = os.getenv("NUPP_LAUNCHER_TOOLCHAIN_PREFIX")
            inputs["<toolchain-prefix>"] = prefix or "missing"
            if prefix then
                for _, name in ipairs({"luajit", "lua51", "luarocks", "lpeg"}) do
                    local path = fs.absolute(prefix .. "/" .. name)
                    if files.stat(path) then
                        if not tree(path) then
                            return nil, recent, inputs, "unreadable toolchain: " .. path
                        end
                    else
                        inputs[path] = "missing"
                    end
                end
            end
        end
        -- A closed contract replaces inference for generated source, loadfile,
        -- and subprocesses. It must name their source/fixture roots and tools.
        if policy.closed
            and (
                not policy.compiled
                or #(policy.inputs or {}) + #(policy.sources or {}) == 0
                or #(policy.commands or {}) == 0
            )
        then
            return nil, recent, inputs, "incomplete closed input contract"
        end
        if policy.compiled then
            for _, source in ipairs(listing(fs.absolute(policy.compiled))) do
                if source:match("%.nupp$") or source:match("%.lua$") then
                    local relative = source:sub(#fs.absolute(policy.compiled) + 2):gsub("%.nupp$", ".lua")
                    local artifact = fs.absolute(options.build .. "/" .. relative)
                    if not add(artifact) then
                        if files.stat(artifact) then
                            return nil, recent, inputs, "unreadable compiled artifact: " .. artifact
                        end
                        inputs[artifact] = "missing"
                    end
                end
            end
        end
        for _, name in ipairs(policy.commands or {}) do
            local path = program(name)
            inputs["<command:" .. name .. ">"] = path or "missing"
            if path and not add(path) then
                return nil, recent, inputs, "unreadable command: " .. name
            end
        end
        local complete = true
        for _, suite in ipairs(options.catalog) do
            if (suite.path:match("^(.*)/") or ".") == directory then
                complete = cache.source(root .. "/" .. suite.path, add, module) and complete
            end
        end
        if not complete and not policy.closed then
            return nil, recent, inputs, "opaque or unresolved module inputs"
        end
        if compiler then
            inputs["<compiler>"] = fingerprint.subsystemFingerprint({
                "nupp.compiler.project.env",
                "nupp.tools.cli.compile"
            })
        end
        local pieces = {base}
        for path, hash in pairs(inputs) do
            pieces[#pieces + 1] = path .. "\0" .. hash
        end
        table.sort(pieces)

        return digest(table.concat(pieces, "\0")), recent, inputs
    end

    function cache.source(path, add, module)
        local ok, text = add(path)
        text = text or fs.readFile(path)
        if not ok or not text then
            return false
        end
        local parsed = parser.parse(text, path)
        if #parsed.errors > 0 then
            return false
        end
        local requires, literal = {}, {}
        local opaque = false

        local function walk(node)
            if cst.isToken(node) then
                if node.text == "require" then
                    requires[node] = true
                end
                if node.text == "popen"
                    or node.text == "execute"
                    or node.text == "loadfile"
                    or node.text == "dofile"
                    or node.text == "loadlib"
                    or node.text == "capture"
                then
                    opaque = true
                end
                return
            end
            if node.kind == "call" and node.obj and node.obj.kind == "name" and node.obj.token.text == "require" then
                local argument = node.args and node.args.exprs and node.args.exprs[1]
                if argument and argument.kind == "string" then
                    literal[node.obj.token] = true
                else
                    opaque = true
                end
            end
            for _, child in ipairs(node) do
                walk(child)
            end
        end

        walk(parsed.root)
        for token in pairs(requires) do
            if not literal[token] then
                opaque = true
            end
        end
        local complete = not opaque
        for _, name in ipairs(header.of(path, nil, parsed).dependencies) do
            complete = module(name) and complete
        end

        return complete
    end

    for directory in pairs(activeDirectories) do
        local policy = (options.policies or {})[directory] or {}
        cache.reasons[directory] = policy.reason or "no input contract"
        if policy.cache == true then
            local complete = true
            local members = {}
            for _, suite in ipairs(options.catalog) do
                if (suite.path:match("^(.*)/") or ".") == directory then
                    members[suite.name] = true
                    if not selected[suite.name] then
                        complete = false
                    end
                end
            end
            if complete then
                local hash, recent, inputs, reason = key(directory, policy)
                cache.reasons[directory] = reason or "input contract could not be resolved"
                if hash then
                    cache.reasons[directory] = recent and "recent input; execute without storing"
                        or "no matching passing result"
                    local path = store .. "/" .. digest(directory) .. ".json"
                    local item = {
                        key = hash,
                        path = path,
                        recent = recent,
                        inputs = inputs,
                        members = members,
                        policy = policy
                    }
                    cache.packages[directory] = item
                    local text = fs.readFile(path)
                    local ok, old = pcall(json.decode, text or "")
                    if ok
                        and type(old) == "table"
                        and old.key == hash
                        and type(old.tests) == "table"
                        and type(old.suites) == "table"
                        and #old.tests > 0
                    then
                        local checked, valid = pcall(function()
                            local seen, counts, rows = {}, {}, {}
                            for _, record in ipairs(old.tests) do
                                if type(record) ~= "table"
                                    or not members[record.suite]
                                    or record.status ~= "passed"
                                    or type(record.name) ~= "string"
                                    or record.id ~= record.suite .. "/" .. record.name
                                    or type(record.durationMs) ~= "number"
                                    or seen[record.id]
                                then
                                    return false
                                end
                                seen[record.id] = true
                                counts[record.suite] = (counts[record.suite] or 0) + 1
                            end
                            for _, row in ipairs(old.suites) do
                                if type(row) ~= "table"
                                    or rows[row.suite]
                                    or not members[row.suite]
                                    or row.tests ~= counts[row.suite]
                                    or not counts[row.suite]
                                then
                                    return false
                                end
                                rows[row.suite] = true
                            end
                            for member in pairs(members) do
                                if not rows[member] then
                                    return false
                                end
                            end

                            return true
                        end)
                        if checked and valid then
                            item.hit = old
                            cache.reasons[directory] = "hit"
                        end
                    end
                end
            else
                cache.reasons[directory] = "partial package selection"
            end
        end
    end

    function cache.save(results, suites)
        snapshots, listings, programs, sourceListings = {}, {}, {}, {}
        for directory, item in pairs(cache.packages) do
            if not item.hit and not item.recent then
                local tests, rows, ok = {}, {}, true
                for _, record in ipairs(results) do
                    if item.members[record.suite] then
                        tests[#tests + 1] = record;
                        ok = ok and record.status == "passed"
                    end
                end
                local seen = {}
                for _, row in ipairs(suites) do
                    if item.members[row.suite] then
                        rows[#rows + 1] = row;
                        seen[row.suite] = true
                    end
                end
                for member in pairs(item.members) do
                    if not seen[member] then
                        ok = false
                    end
                end
                local after, recent = key(directory, item.policy)
                if ok and #tests > 0 and after == item.key and not recent then
                    files.mkdir(store)
                    fs.writeFile(item.path, json.encode({key = item.key, tests = tests, suites = rows}))
                end
            end
        end
    end

    function cache.audit()
        local directory
        for _, suite in ipairs(options.selected) do
            local name = suite.path:match("^(.*)/") or "."
            assert(directory == nil or directory == name, "--audit requires suites from one test package")
            directory = name
        end
        assert(directory, "--audit requires a selected test package")
        local policy = (options.policies or {})[directory] or {}
        local _, _, allowed = key(directory, policy)
        allowed = allowed or {}
        local findings, declared = {}, {}
        for _, list in ipairs({policy.inputs or {}, policy.optionalInputs or {}}) do
            for _, input in ipairs(list) do
                declared[#declared + 1] = fs.absolute(input)
            end
        end

        local function known(path)
            if allowed[path] then
                return true
            end
            for _, input in ipairs(declared) do
                if path == input or path:sub(1, #input + 1) == input .. "/" then
                    return true
                end
            end
            local owner
            for name in pairs(directories) do
                local prefix = fs.absolute(root .. "/" .. name) .. "/"
                if path:sub(1, #prefix) == prefix and (not owner or #name > #owner) then
                    owner = name
                end
            end

            return owner == directory
        end

        local open, getenv = io.open, os.getenv
        io.open = function(path, mode, ...)
            local reads = mode == nil or mode:sub(1, 1) == "r" or mode:find("+", 1, true) and mode:sub(1, 1) ~= "w"
            if rawget(_G, "__NUPP_TEST_AUDIT_ACTIVE")
                and reads
                and type(path) == "string"
                and not known(fs.absolute(path))
            then
                findings["audit: undeclared file " .. path] = true
            end

            return open(path, mode, ...)
        end
        os.getenv = function(name)
            if rawget(_G, "__NUPP_TEST_AUDIT_ACTIVE") and not environmentNames[name] then
                findings["audit: environment lookup " .. tostring(name)] = true
            end
            return getenv(name)
        end

        return function()
            io.open, os.getenv = open, getenv
            local sorted = {}
            for finding in pairs(findings) do
                sorted[#sorted + 1] = finding
            end
            table.sort(sorted)
            for _, finding in ipairs(sorted) do
                io.stderr:write(finding .. "\n")
            end
            io.stderr:write("audit: parent file/environment accesses only; child and native reads are not covered\n")
        end
    end

    return cache
end

return M
