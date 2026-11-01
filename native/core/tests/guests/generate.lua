-- Random programs in the core's Lua subset, written twice: as a typed Nupp
-- module and as the plain Lua the reference interpreter runs. Integers only
-- (wrapping, as Lua's do), Booleans from comparisons, if/while/numeric for,
-- `and`/`or`, integer-keyed tables, pairs traversals and local functions.
-- Every program exports one integer checksum, and every loop and divisor is
-- bounded or guarded so the two can be compared word for word.
local generate = {}

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
            if a ~= b then
                emit(a .. ", " .. b .. " = " .. b .. ", (" .. a .. " + " .. expression(1) .. ") % 1000003")
            end
        elseif roll == 11 then
            emit(target() .. " = bump(" .. expression(1) .. ")")
        elseif roll == 13 then
            -- // and math.floor answer number in Nupp's types, so they feed text.
            local d = literals[pick(#literals - 2) + 1]
            local forms = {
                expression(1),
                "(" .. expression(1) .. " // " .. d .. ")",
                "math.floor((" .. expression(1) .. " % 100000) / " .. d .. ")",
                -- Float text: Lua 5.5's 15- or 17-digit form.
                "(" .. expression(1) .. " / " .. d .. ")",
                "(-(" .. expression(1) .. ") / 7)"
            }
            emit("s = s .. tostring(" .. forms[pick(5)] .. ") .. \",\"")
        elseif roll == 14 and depth == 0 then
            arrays = arrays + 1
            local name = "u" .. arrays
            local items = expression(1) .. ", " .. expression(1) .. ", " .. expression(1)
            emit("local " .. name .. ": {integer} = {" .. items .. "}", "local " .. name .. " = {" .. items .. "}")
            emit(target() .. " = (" .. name .. "[1] + " .. name .. "[3] * 2 + #" .. name .. ") % 1000003")
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

    emit("local t: {[integer]: integer} = {}", "local t = {}")
    emit("local c: integer = 0", "local c = 0")
    emit("local s: string = \"\"", "local s = \"\"")
    emit("local function bump(n: integer): integer", "local function bump(n)")
    emit("    c = (c + n) % 1000003")
    emit("    return c")
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
    ) .. "\n", "-- Generated twin of generated" .. seed .. ".nupp.\n" .. table.concat(lua, "\n") .. "\n"
end

return generate
