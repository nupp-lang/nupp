-- Run after a normal compiler build. The effect sets and cleanup helpers come
-- from that build, not from an approximation of require reachability.
local json = require("nupp.runtime.provider.lunajson")
local parser = require("nupp.compiler.syntax.parser")
local compat = require("nupp.compiler.compat")
local native = require("nupp.compiler.native")

local function read(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local source = file:read("*a")
    file:close()

    return source
end

local state = json.decode(assert(read(arg[1] or "build/.nupp-state.json")))
local report = {
    policy = compat.VERSION,
    compilerHash = state.compilerHash,
    modules = {},
    totals = {
        modules = 0,
        sourceSyntaxAccepted = 0,
        withSyntax = 0,
        protectedCleanup = 0,
        protectedCleanupWithSuspension = 0,
        directSuspension = 0,
        transitiveSuspension = 0
    }
}

local function chain(effect, seen)
    if effect == "runtime.suspension" then
        return {effect}
    end
    seen = seen or {}
    if seen[effect] then
        return nil
    end
    seen[effect] = true
    local feature = native.feature(effect)
    for _, requirement in ipairs(feature and feature.requires or {}) do
        local tail = chain(requirement, seen)
        if tail then
            table.insert(tail, 1, effect);
            return tail
        end
    end
end

for name, entry in pairs(state.modules) do
    if name:match("^nupp%.") then
        local stem = "src/" .. name:gsub("%.", "/")
        local source, path
        for _, suffix in ipairs({".nupp", ".g.nupp", "/init.nupp", ".lua"}) do
            source, path = read(stem .. suffix), stem .. suffix
            if source then
                break
            end
        end
        if source then
            local parsed = parser.parse(source, path)
            assert(#parsed.errors == 0, path)
            local reasons = {}
            compat.syntax(parsed, function(at, reason)
                reasons[#reasons + 1] = {line = at.line, reason = reason}
            end)
            local withCount, yieldCount = 0, 0

            local function visit(node)
                if node.trivia then
                    return
                end
                if node.kind == "withStmt" then
                    withCount = withCount + 1
                end
                if node.kind == "dotIndex"
                    and node.name.text == "yield"
                    and node.obj.kind == "name"
                    and node.obj.token.text == "coroutine"
                then
                    yieldCount = yieldCount + 1
                end
                for _, child in ipairs(node) do
                    visit(child)
                end
            end

            visit(parsed.root)
            local code = assert(read(entry.output), entry.output)
            local protected = code:find("suppressed=secondary", 1, true) ~= nil
            local effects = {}
            for _, effect in ipairs(entry.effects or {}) do
                effects[effect] = true
            end
            local suspends = native.expand(effects)["runtime.suspension"] == true
            local chains = {}
            if suspends then
                for effect in pairs(effects) do
                    local path = chain(effect)
                    if path then
                        chains[#chains + 1] = path
                    end
                end
                table.sort(chains, function(a, b)
                    return table.concat(a, "/") < table.concat(b, "/")
                end)
            end
            local row = {
                module = name,
                path = path,
                syntaxRejections = reasons,
                withCount = withCount,
                authoredCoroutineYieldReads = yieldCount,
                protectedCleanup = protected,
                effects = entry.effects,
                suspensionChains = chains,
                cleanupRejected = protected and suspends
            }
            report.modules[#report.modules + 1] = row
            local t = report.totals
            t.modules = t.modules + 1
            if #reasons == 0 then
                t.sourceSyntaxAccepted = t.sourceSyntaxAccepted + 1
            end
            if withCount > 0 then
                t.withSyntax = t.withSyntax + 1
            end
            if protected then
                t.protectedCleanup = t.protectedCleanup + 1
            end
            if protected and suspends then
                t.protectedCleanupWithSuspension = t.protectedCleanupWithSuspension + 1
                if effects["runtime.suspension"] then
                    t.directSuspension = t.directSuspension + 1
                else
                    t.transitiveSuspension = t.transitiveSuspension + 1
                end
            end
        end
    end
end
table.sort(report.modules, function(a, b)
    return a.module < b.module
end)
print(json.encode(report))
