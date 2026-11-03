-- Observe completed native calls from this artifact's registered replacements.
-- Enumerating replacements also finds bodies cached inside ownership tables.
return function(module, exercise)
    local artifact = assert(package.searchpath(module, package.path), "missing algorithm artifact " .. module)
    local registry = assert(rawget(_G, "__nuppAotCompiled"), "no AOT replacement registry")
    local builders = {}
    for _, entries in pairs(rawget(_G, "__nuppAotBuilderModules") or {}) do
        for _, fn in pairs(entries) do
            if type(fn) == "function" and debug.getinfo(fn, "S").what == "C" then
                builders[fn] = true
            end
        end
    end
    local saved, calls = {}, 0

    local function pack(...)
        return {n = select("#", ...), ...}
    end

    for fn in pairs(registry) do
        if type(fn) == "function" and debug.getinfo(fn, "S").source == "@" .. artifact then
            for at = 1, 128 do
                local name, native = debug.getupvalue(fn, at)
                if not name then
                    break
                end
                if (name:match("^ks_.*_native$") and type(native) == "cdata") or builders[native] then
                    saved[#saved + 1] = {fn, at, native}
                    debug.setupvalue(fn, at, function(...)
                        local results = pack(native(...))
                        calls = calls + 1
                        return unpack(results, 1, results.n)
                    end)
                end
            end
        end
    end
    assert(#saved > 0, "no observable native entry in " .. module)
    local enabled = jit.status()
    jit.off()
    local ok, why = pcall(exercise)
    for _, original in ipairs(saved) do
        debug.setupvalue(original[1], original[2], original[3])
    end
    if enabled then
        jit.on()
    end
    assert(ok, why)
    assert(calls > 0, module .. " did not execute its compiled C entry")
    print("SIMD_NATIVE_CALLS=" .. calls)

    return calls
end
