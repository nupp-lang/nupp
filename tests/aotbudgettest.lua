-- Native code-size budgets for `@aot` kernels, read from the code generator's own
-- account of what it emitted.
--
-- `nupp aot --emit asm` heads each function with its instruction, vector, load, store,
-- branch, call and stack-slot counts. For a pinned LLVM and a named target and tier
-- those are properties of the compiler's output, the same on every machine and under
-- any load, so they can be held to a ceiling where a timing cannot. A ceiling is set a
-- little above what the kernel compiles to today; raising one is a decision, and the
-- message says which count moved. Two counts are held exactly: a hot kernel makes no
-- calls, because a call there is a vector operation the tier failed to select and
-- scalarized into a library routine -- which is how the AVX2 tier once spent eight
-- `fmaf` calls and a spill per lane on every Mandelbrot iteration.
--
-- The kernels are the benchmark's own, so the budget and the measurement are of one
-- program: bench/simd-mandelbrot times what this reads.

local test = require("assert")

local HERE = assert(debug.getinfo(1, "S").source:match("^@(.*)[/\\]"))
if not HERE:match("^/") then
    local p = assert(io.popen("pwd"))
    HERE = p:read("*l") .. "/" .. HERE
    p:close()
end
local ROOT = HERE .. "/.."
local NUPP = ROOT .. "/bin/nupp"
local KERNELS = "bench/simd-mandelbrot/mandelbrot.nupp"

local M = {}

--- The per-function counts `nupp aot --emit asm` prints for one target and tier.
local function counts(target, tier, name)
    local command = ("cd '%s' && '%s' aot --triple %s --features %s --emit asm --function %s %s 2>&1"):format(
        ROOT,
        NUPP,
        target,
        tier,
        name,
        KERNELS
    )
    local pipe = assert(io.popen(command))
    local out = pipe:read("*a")
    pipe:close()
    local found = {}
    for symbol, role, rest in out:gmatch("\n%-%- ([%w_]+) %([%w_]+%), (%a+): ([^\n]+)") do
        local entry = {role = role}
        for value, key in rest:gmatch("(%d+) (%a+)") do
            entry[key] = tonumber(value)
        end
        found[symbol] = entry
    end

    return found, out
end

-- Ceilings about a tenth above what each kernel compiles to at the commit that set
-- them: instructions, vector instructions, and stack slots. Calls are held at zero.
local BUDGETS = {
    {
        target = "aarch64-apple-darwin",
        tier = "neon",
        func = "mandelbrot",
        symbol = "ks_mandelbrot",
        instructions = 70,
        stack = 0,
    },
    {
        target = "aarch64-apple-darwin",
        tier = "neon",
        func = "mandelbrotSimd",
        symbol = "ks_mandelbrot_simd",
        instructions = 550,
        stack = 12,
    },
    {
        target = "x86_64-unknown-linux-gnu",
        tier = "avx2",
        func = "mandelbrotSimd",
        symbol = "ks_mandelbrot_simd",
        instructions = 220,
        stack = 20,
    },
    {
        target = "x86_64-unknown-linux-gnu",
        tier = "avx512f",
        func = "mandelbrotSimd",
        symbol = "ks_mandelbrot_simd",
        instructions = 200,
        stack = 20,
    },
}

function M.theBenchmarkKernelsStayWithinTheirNativeCodeBudgets()
    local failures = {}
    for _, budget in ipairs(BUDGETS) do
        local found, out = counts(budget.target, budget.tier, budget.func)
        local entry = found[budget.symbol]
        local where = ("%s on %s/%s"):format(budget.symbol, budget.target, budget.tier)
        assert(entry and entry.instructions, where .. " was not reported:\n" .. out)
        test.equal(entry.role, "kernel", where .. " is the timed kernel")
        if entry.calls ~= 0 then
            failures[#failures + 1] = ("%s makes %d calls; a hot kernel makes none"):format(where, entry.calls)
        end
        if entry.instructions > budget.instructions then
            failures[#failures + 1] = ("%s is %d instructions, over its budget of %d"):format(
                where,
                entry.instructions,
                budget.instructions
            )
        end
        if entry.stack > budget.stack then
            failures[#failures + 1] = ("%s touches %d stack slots, over its budget of %d"):format(
                where,
                entry.stack,
                budget.stack
            )
        end
    end
    assert(#failures == 0, table.concat(failures, "\n"))
end

-- A Wasm kernel module is compiled and linked by the code generator itself, and its
-- size is what a browser downloads and instantiates per kernel. Two small kernels come
-- to about 1.7 KB when this was set; a module that starts carrying a libc, a runtime
-- or unstripped debug sections shows as a multiple of that.
local WASM_MODULE_BYTES = 2560

function M.aWasmKernelModuleStaysSmall()
    local dir = os.tmpname()
    os.remove(dir)
    assert(os.execute("mkdir -p '" .. dir .. "/src'") == 0)
    local function write(path, text)
        local handle = assert(io.open(dir .. "/" .. path, "wb"))
        handle:write(text)
        handle:close()
    end
    write(
        "nupp.lua",
        'return {include = {"src"}, build = {targets = {native = {\n'
            .. '   kind = "modules", entries = {"k"}, outDir = "build/native",\n'
            .. '   aot = "require-wasm", host = "browser",\n}}}}\n'
    )
    write("src/k.nupp", table.concat({
        "module k",
        "",
        'local span = require("nupp.mem.span")',
        "",
        "@aot",
        "local function scale(exclusive out: span.WriteSpan<float>, borrows input: span.Span<float>, factor: number): nil",
        "    if #out ~= #input then",
        '        error("length mismatch", 2)',
        "    end",
        "    for i = 1, #out do",
        "        out[i] = input[i] * factor + 1.0",
        "    end",
        "end",
        "",
        "@aot",
        "local function total(borrows input: span.Span<uint8>): number",
        "    local sum = 0.0",
        "    for i = 1, #input do",
        "        sum = sum + input[i]",
        "    end",
        "    return sum",
        "end",
        "",
        "export = {scale = scale, total = total}",
        "",
    }, "\n"))
    local pipe = assert(io.popen(("cd '%s' && '%s' build --target native 2>&1"):format(dir, NUPP)))
    local out = pipe:read("*a")
    pipe:close()
    -- Sized by the shell that found them: on Windows the paths find prints are
    -- MSYS spellings (/c/Users/...) that LuaJIT's io.open cannot open.
    local listing = assert(io.popen(("find '%s/build' -name '*.wasm' -exec wc -c {} \\;"):format(dir)))
    local modules = {}
    for line in listing:lines() do
        local size, path = line:match("^%s*(%d+)%s+(.+)$")
        modules[#modules + 1] = {path = assert(path, line), size = tonumber(size)}
    end
    listing:close()
    os.execute("rm -rf '" .. dir .. "'")
    -- One source compiles to one module per tier: its SIMD128 kernels and their
    -- scalar twins. Each is held to the budget on its own.
    assert(#modules > 0, "no Wasm module for the source: " .. out)
    local tiers = {}
    for _, module in ipairs(modules) do
        local tier = assert(module.path:match("%.([%w]+)%.%x+%.wasm$"), module.path)
        assert(not tiers[tier], "two " .. tier .. " modules for one source: " .. out)
        tiers[tier] = true
        assert(
            module.size <= WASM_MODULE_BYTES,
            ("the %s Wasm module is %d bytes, over the budget of %d"):format(tier, module.size, WASM_MODULE_BYTES)
        )
    end
end

return M
