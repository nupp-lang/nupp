-- Random programs in the core's Lua subset, written twice: as a typed Nupp
-- module and as the plain Lua the reference interpreter runs. Integers only
-- (wrapping, as Lua's do), Booleans from comparisons, if/while/numeric for,
-- `and`/`or`, integer-keyed tables, pairs traversals and local functions.
-- Every program exports one integer checksum, and every loop and divisor is
-- bounded or guarded so the two can be compared word for word.
local generate = {}

-- Nupp's float text (Decision 13), for the twin: the shorter of the decimal
-- and exponent texts that read back exactly, the decimal on a tie, as Rust's
-- `{:?}` and `{:e}` write them. One line, so the twin keeps its lines.
local NUPPTEXT = "local function nupptext(x) if math.type(x) ~= \"float\" then return tostring(x) end if x ~= x then return \"nan\" elseif x == math.huge then return \"inf\" elseif x == -math.huge then return \"-inf\" elseif x == 0 then return 1 / x < 0 and \"-0.0\" or \"0.0\" end local mantissa, exponent for precision = 0, 16 do local text = string.format(\"%.\" .. precision .. \"e\", x) if tonumber(text) == x then mantissa, exponent = text:match(\"^(-?[%d.]+)e([-+]%d+)$\") break end end local sign = mantissa:sub(1, 1) == \"-\" and \"-\" or \"\" local digits = mantissa:gsub(\"^-\", \"\"):gsub(\"%.\", \"\") local power = tonumber(exponent) local rest = digits:sub(2) local scientific = sign .. digits:sub(1, 1) .. (rest ~= \"\" and \".\" .. rest or \"\") .. \"e\" .. power local magnitude = math.abs(x) if magnitude < 1e-4 or magnitude >= 1e16 then return scientific end local decimal if power >= 0 then local whole = digits:sub(1, power + 1) .. string.rep(\"0\", power + 1 - #digits) local fraction = digits:sub(power + 2) decimal = sign .. whole .. \".\" .. (fraction ~= \"\" and fraction or \"0\") else decimal = sign .. \"0.\" .. string.rep(\"0\", -power - 1) .. digits end return #scientific < #decimal and scientific or decimal end"

local function chooser(seed)
    local state = seed % 2147483647
    if state <= 0 then
        state = state + 2147483646
    end

    return function(n)
        state = (state * 48271) % 2147483647
        return state % n + 1
    end
end

function generate.program(seed, size)
    local pick = chooser(seed)
    local lines, lua = {}, {}
    local variables = {}
    local depth = 0

    local function emit(nupp, plain)
        local indent = string.rep("    ", depth)
        lines[#lines + 1] = indent .. nupp
        lua[#lua + 1] = indent .. (plain or nupp)
    end

    local function variable()
        return variables[pick(#variables)]
    end

    -- An assignable local: numeric for control variables are read-only.
    local function target()
        local candidates = {}
        for _, name in ipairs(variables) do
            if name:sub(1, 1) == "v" then
                candidates[#candidates + 1] = name
            end
        end

        return candidates[pick(#candidates)]
    end

    local literals = {"0", "1", "2", "3", "7", "10", "255", "1000", "65536", "1000003", "123456789", "-5", "-1"}

    local expression

    local function atom()
        local roll = pick(3)
        if roll == 1 or #variables == 0 then
            return literals[pick(#literals)]
        end

        return variable()
    end

    expression = function(level)
        if level <= 0 or pick(3) == 1 then
            return atom()
        end
        local roll = pick(8)
        local a, b = expression(level - 1), expression(level - 1)
        if roll >= 7 then
            roll = pick(6)
        end
        if roll == 1 then
            return "(" .. a .. " + " .. b .. ")"
        elseif roll == 2 then
            return "(" .. a .. " - " .. b .. ")"
        elseif roll == 3 then
            return "(" .. a .. " * " .. b .. ")"
        elseif roll == 4 then
            -- A modulo by a nonzero literal: Lua raises for zero.
            return "(" .. a .. " % " .. literals[pick(#literals - 2) + 1] .. ")"
        elseif roll == 5 then
            return "(t[" .. "(" .. a .. ") % 16" .. "] or " .. b .. ")"
        end

        if pick(4) == 1 then
            return "(- " .. a .. ")"
        end

        return "(" .. a .. " * 3 + 1)"
    end

    local function condition()
        local ops = {"<", "<=", ">", ">=", "==", "~="}
        local base = expression(1) .. " " .. ops[pick(#ops)] .. " " .. expression(1)
        if pick(4) == 1 then
            return base .. " and " .. expression(1) .. " < " .. expression(1)
        elseif pick(4) == 1 then
            return base .. " or " .. expression(1) .. " == " .. expression(1)
        end

        return base
    end

    local statement

    local function block(count)
        for _ = 1, count do
            statement()
        end
    end

    local loops = 0
    local closures = 0
    local arrays = 0
    local traversals = 0
    local searches = 0
    statement = function()
        local roll = pick(14)
        if roll <= 3 or #variables < 2 then
            if depth == 0 and #variables < 6 and (pick(2) == 1 or #variables < 2) then
                local name = "v" .. (#variables + 1)
                local value = expression(2)
                emit("local " .. name .. ": integer = " .. value, "local " .. name .. " = " .. value)
                variables[#variables + 1] = name
            else
                emit(target() .. " = " .. expression(2))
            end
        elseif roll == 4 then
            emit("t[(" .. expression(1) .. ") % 16] = " .. expression(2))
        elseif roll == 5 and depth < 3 then
            emit("if " .. condition() .. " then")
            depth = depth + 1
            block(pick(2))
            depth = depth - 1
            if pick(2) == 1 then
                emit("else")
                depth = depth + 1
                block(1)
                depth = depth - 1
            end
            emit("end")
        elseif roll == 6 and depth < 3 and loops < 3 then
            loops = loops + 1
            local index = "i" .. loops
            emit("for " .. index .. " = 1, " .. pick(12) .. " do")
            depth = depth + 1
            variables[#variables + 1] = index
            block(pick(2))
            variables[#variables] = nil
            depth = depth - 1
            emit("end")
        elseif roll == 7 and depth < 3 and loops < 3 then
            loops = loops + 1
            local counter = "w" .. loops
            emit("local " .. counter .. ": integer = 0", "local " .. counter .. " = 0")
            emit("while " .. counter .. " < " .. pick(8) .. " do")
            depth = depth + 1
            emit(counter .. " = " .. counter .. " + 1")
            block(1)
            depth = depth - 1
            emit("end")
        elseif roll == 8 and pick(2) == 1 then
            -- A variadic call with zero to two extra arguments, directly, through
            -- a forwarder that spreads them, or spread back out of a return.
            local extras = {}
            for index = 1, pick(3) - 1 do
                extras[index] = ", " .. expression(1)
            end
            local how = pick(3)
            local a, b = target(), target()
            if how == 3 and a ~= b then
                emit(
                    a .. ", " .. b .. " = pass(" .. expression(
                        1
                    ) .. ", " .. expression(1) .. table.concat(extras) .. ")"
                )
            else
                local name = how == 2 and "fwd" or "many"
                emit(a .. " = " .. name .. "(" .. expression(1) .. table.concat(extras) .. ")")
            end
        elseif roll == 8 then
            emit(target() .. " = f(" .. expression(1) .. ", " .. expression(1) .. ")")
        elseif roll == 9 and pick(2) == 1 then
            -- A traversal of t folded into a sum, so the order pairs visits
            -- the keys in (which Lua leaves unspecified) cannot show.
            traversals = traversals + 1
            local sum = "p" .. traversals
            emit("local " .. sum .. ": integer = 0", "local " .. sum .. " = 0")
            emit("for k, v in pairs(t) do")
            emit("    " .. sum .. " = " .. sum .. " + k * 7 + v % 1000")
            emit("end")
            local into = target()
            emit(into .. " = (" .. into .. " + " .. sum .. ") % 1000003")
        elseif roll == 10 then
            local a, b = target(), target()
            if a ~= b and pick(2) == 1 then
                -- Two results from one call fill both targets.
                emit(a .. ", " .. b .. " = two(" .. expression(1) .. ", " .. expression(1) .. ")")
            elseif a ~= b then
                emit(a .. ", " .. b .. " = " .. b .. ", (" .. a .. " + " .. expression(1) .. ") % 1000003")
            end
        elseif roll == 9 and pick(3) == 1 and depth < 3 then
            -- A protected call that raises for some inputs.
            local a, b = target(), target()
            if pick(2) == 1 then
                emit("if pcall(guard, " .. expression(1) .. ") then")
            else
                -- xpcall: its handler runs on the failures, counting them.
                emit("if xpcall(guard, onError, " .. expression(1) .. ") then")
            end
            emit("    " .. a .. " = (" .. a .. " + 3) % 1000003")
            emit("else")
            emit("    " .. b .. " = (" .. b .. " + 5) % 1000003")
            emit("end")
        elseif roll == 9 then
            -- A record method, for its value or as a statement, one written in
            -- the record's body, or a static one called through its table.
            local how = pick(5)
            if how == 5 then
                local into = target()
                local argument = expression(1)
                emit(
                    "local box" .. into .. " = Box(" .. argument .. ")",
                    "local box" .. into .. " = newBox(" .. argument .. ")"
                )
                emit(into .. " = (" .. into .. " + box" .. into .. ".value) % 1000003")
            elseif how == 1 then
                emit(target() .. " = acc:add(" .. expression(1) .. ")")
            elseif how == 2 then
                emit("acc:add(" .. expression(1) .. ")")
            elseif how == 3 then
                emit(target() .. " = acc:scaled(" .. expression(1) .. " % 97)")
            else
                emit(target() .. " = Acc.seed(" .. expression(1) .. ")")
            end
        elseif roll == 11 and pick(2) == 1 then
            -- A generic function, its type parameter erased on the core.
            emit(target() .. " = choose(" .. condition() .. ", " .. expression(1) .. ", " .. expression(1) .. ")")
        elseif roll == 11 then
            emit(target() .. " = bump(" .. expression(1) .. ")")
        elseif roll == 13 and pick(3) == 1 then
            -- Every result of a string library call, or of a function
            -- returning one, over the text built so far.
            searches = searches + 1
            local a, b, c = "q" .. searches .. "a", "q" .. searches .. "b", "q" .. searches .. "c"
            local how = pick(8)
            local into = target()
            if how == 1 then
                emit("local " .. a .. ", " .. b .. " = s:find(\"%d+\")")
                emit(into .. " = (" .. into .. " + (" .. a .. " or 0) + (" .. b .. " or 0) * 3) % 1000003")
            elseif how == 2 then
                emit("local " .. a .. ", " .. b .. " = string.match(s, \"(%d)(%d+)\")")
                emit(into .. " = (" .. into .. " + #(" .. a .. " or \"\") * 5 + #(" .. b .. " or \"\")) % 1000003")
            elseif how == 3 then
                emit("local " .. a .. ", " .. b .. ", " .. c .. " = s:byte(" .. pick(3) .. ", " .. pick(4) .. ")")
                emit(
                    into
                    .. " = ("
                    .. into
                    .. " + ("
                    .. a
                    .. " or 0) + ("
                    .. b
                    .. " or 1) * 3 + ("
                    .. c
                    .. " or 2) * 7) % 1000003"
                )
            elseif how == 4 then
                emit("local " .. a .. ", " .. b .. ", " .. c .. " = s:find(\"(%d)(,)\", " .. pick(3) .. ")")
                emit(
                    into
                    .. " = ("
                    .. into
                    .. " + ("
                    .. a
                    .. " or 0) + ("
                    .. b
                    .. " or 0) * 3 + #("
                    .. c
                    .. " or \"\")) % 1000003"
                )
            elseif how == 6 then
                -- gsub with a string replacement, its captures swapped.
                emit("local " .. a .. ", " .. b .. " = s:gsub(\"(%d)(%d)\", \"%2%1\", " .. pick(3) .. ")")
                emit(into .. " = (" .. into .. " + #" .. a .. " * 3 + " .. b .. ") % 1000003")
                emit("s = " .. a)
            elseif how == 7 then
                -- gsub with a table replacement, digits it lacks kept.
                emit("local " .. a .. " = string.gsub(s, \"%d\", digits)")
                emit(into .. " = (" .. into .. " + #" .. a .. ") % 1000003")
            else
                emit("local " .. a .. ", " .. b .. " = span(s)")
                emit(into .. " = (" .. into .. " + (" .. a .. " or 0) * 11 + (" .. b .. " or 0)) % 1000003")
            end
        elseif roll == 13 then
            -- // and math.floor answer number in Nupp's types, so they feed text.
            local d = literals[pick(#literals - 2) + 1]
            local forms = {
                expression(1),
                "(" .. expression(1) .. " // " .. d .. ")",
                "math.floor((" .. expression(1) .. " % 100000) / " .. d .. ")",
                -- Float text: Nupp's shorter exact text, which the twin
                -- writes through nupptext.
                "(" .. expression(1) .. " / " .. d .. ")",
                "(-(" .. expression(1) .. ") / 7)",
                -- The string library over the text built so far.
                "(s:find(\"1\", 1, true) or 0)",
                "#s:sub(2, -2)",
                "(s:byte(-2) or 0)",
                "#(s:match(\"%d+\") or \"\")"
            }
            local form = forms[pick(9)]
            emit("s = s .. tostring(" .. form .. ") .. \",\"", "s = s .. nupptext(" .. form .. ") .. \",\"")
        elseif roll == 14 and depth == 0 then
            arrays = arrays + 1
            local name = "u" .. arrays
            local items = expression(1) .. ", " .. expression(1) .. ", " .. expression(1)
            emit("local " .. name .. ": {integer} = {" .. items .. "}", "local " .. name .. " = {" .. items .. "}")
            emit(target() .. " = (" .. name .. "[1] + " .. name .. "[3] * 2 + #" .. name .. ") % 1000003")
        elseif roll == 14 then
            -- A table whose misses read through __index: its own keys, the
            -- defaults behind them, and a change to a default.
            local how = pick(3)
            if how == 1 then
                emit("cfg.n" .. pick(3) .. " = " .. expression(1) .. " % 1000")
            elseif how == 2 then
                emit("Defaults.bonus = " .. expression(1) .. " % 100")
            else
                local into = target()
                emit(
                    into
                    .. " = ("
                    .. into
                    .. " + (cfg.bonus or 0) + (cfg.n1 or 0) * 3 + (cfg.n2 or 0) + (dyn.key"
                    .. pick(
                        9
                    ) .. " or 0)) % 1000003"
                )
            end
        elseif roll == 12 and depth > 0 and closures < 3 then
            -- A closure made in this block, capturing what is in scope here.
            closures = closures + 1
            local name = "g" .. closures
            local body = expression(2)
            emit("local " .. name .. " = function(x: integer): integer", "local " .. name .. " = function(x)")
            emit("    return (x + " .. body .. ") % 65521")
            emit("end")
            emit(target() .. " = " .. name .. "(" .. expression(1) .. ")")
        else
            emit(target() .. " = (" .. variable() .. " + " .. expression(1) .. ") % 1000003")
        end
    end

    emit("local record Acc", "local Acc = {}")
    lines[#lines + 1] = "    value: integer"
    -- Methods written in the body: an instance one and a static one.
    lines[#lines + 1] = "    function scaled(self, k: integer): integer"
    lines[#lines + 1] = "        return (self.value * k + k) % 1000003"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = "    function seed(n: integer): integer"
    lines[#lines + 1] = "        return (n * 7 + 1) % 65521"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = "end"
    lua[#lua + 1] = "function Acc.scaled(self, k)"
    lua[#lua + 1] = "    return (self.value * k + k) % 1000003"
    lua[#lua + 1] = "end"
    lua[#lua + 1] = "function Acc.seed(n)"
    lua[#lua + 1] = "    return (n * 7 + 1) % 65521"
    lua[#lua + 1] = "end"
    emit("function Acc:add(n: integer): integer", "function Acc:add(n)")
    emit("    self.value = (self.value + n) % 1000003")
    emit("    return self.value")
    emit("end")
    emit("local acc = Acc(value = 0)", "local acc = setmetatable({value = 0}, {__index = Acc})")
    -- A record built by its constructor, with a field default.
    lines[#lines + 1] = "local record Box"
    lines[#lines + 1] = "    value: integer"
    lines[#lines + 1] = "    scale: integer = 3"
    lines[#lines + 1] = "    constructor(self, v: integer)"
    lines[#lines + 1] = "        self.value = v * self.scale % 65521"
    lines[#lines + 1] = "    end"
    lines[#lines + 1] = "end"
    lua[#lua + 1] = "local function newBox(v)"
    lua[#lua + 1] = "    local self = {scale = 3}"
    lua[#lua + 1] = "    self.value = v * self.scale % 65521"
    lua[#lua + 1] = "    return self"
    lua[#lua + 1] = "end"
    emit("local t: {[integer]: integer} = {}", "local t = {}")
    emit("local Defaults: {[string]: integer} = {bonus = 5}", "local Defaults = {bonus = 5}")
    emit(
        "local cfg: {[string]: integer} = setmetatable({}, {__index = Defaults})",
        "local cfg = setmetatable({}, {__index = Defaults})"
    )
    emit("local dyn: {[string]: integer} = setmetatable({}, {", "local dyn = setmetatable({}, {")
    emit("    __index = function(t: {[string]: integer}, k: string): integer", "    __index = function(t, k)")
    emit("        return #k * 7 + (Defaults.bonus or 0)")
    emit("    end")
    emit("})")
    emit("local c: integer = 0", "local c = 0")
    emit("local s: string = \"\"", "local s = \"\"")
    emit("local function bump(n: integer): integer", "local function bump(n)")
    emit("    c = (c + n) % 1000003")
    emit("    return c")
    emit("end")
    emit("local function many(a: integer, ...: integer): integer", "local function many(a, ...)")
    emit(
        "    return (a + select(\"#\", ...) * 7 + (... or 0) + (select(\"#\", ...) > 0 and select(-1, ...) or 0) * 3) % 65521"
    )
    emit("end")
    emit("local function guard(n: integer): integer", "local function guard(n)")
    emit("    if n % 7 == 3 then")
    emit("        error(\"guarded\")")
    emit("    end")
    emit("    return n")
    emit("end")
    emit("local function onError(message: string): integer", "local function onError(message)")
    emit("    c = (c + 1) % 1000003")
    emit("    return 0")
    emit("end")
    emit("local function fwd(...: integer): integer", "local function fwd(...)")
    emit("    return many(1, ...)")
    emit("end")
    emit("local function pass(...: integer): (integer, integer)", "local function pass(...)")
    emit("    return ...")
    emit("end")
    emit(
        "local digits: {[string]: string} = {[\"1\"] = \"one\", [\"7\"] = \"\"}",
        "local digits = {[\"1\"] = \"one\", [\"7\"] = \"\"}"
    )
    emit("local function span(x: string): (integer?, integer?)", "local function span(x)")
    emit("    return x:find(\",\", 2, true)")
    emit("end")
    emit("local function choose<T>(c: boolean, a: T, b: T): T", "local function choose(c, a, b)")
    emit("    if c then")
    emit("        return a")
    emit("    end")
    emit("    return b")
    emit("end")
    emit("local function two(a: integer, b: integer): (integer, integer)", "local function two(a, b)")
    emit("    return (a + b) % 65521, (a * 3 - b) % 65521")
    emit("end")
    emit("local function f(a: integer, b: integer): integer", "local function f(a, b)")
    depth = 1
    emit("if a < b then")
    emit("    return (a * 31 + b) % 65521")
    emit("end")
    emit("return (b * 17 - a) % 65521")
    depth = 0
    emit("end")
    block(size)
    local sum = {}
    for _, name in ipairs(variables) do
        sum[#sum + 1] = name
    end
    sum[#sum + 1] = "c"
    sum[#sum + 1] = "acc.value"
    sum[#sum + 1] = "#s"
    for k = 0, 15, 5 do
        sum[#sum + 1] = "(t[" .. k .. "] or 0)"
    end
    emit(
        "export = (" .. table.concat(sum, " + ") .. ") % 1000000007",
        "return (" .. table.concat(sum, " + ") .. ") % 1000000007"
    )

    return "module nupp.core.generated" .. seed .. "\n\n" .. table.concat(
        lines,
        "\n"
    ) .. "\n", NUPPTEXT .. " -- Generated twin of generated" .. seed .. ".nupp.\n" .. table.concat(lua, "\n") .. "\n"
end

return generate
