-- Seeded random programs for the optimizer differential in `optimizetest`.
--
-- A program is gradual Nupp built from the shapes each Lua `OPT-n` pass rewrites:
-- table writes after `local t = {}`, `ipairs` over a literal, string accumulation in
-- a loop, constants that fold, and single-return helpers that inline. Every
-- program prints what it computes, so running it at `-O0` and at `-O2` and
-- comparing the transcripts says whether the optimizer kept its meaning.
--
-- The generator is a pure function of its seed. A failing seed therefore names
-- one program forever, and `optimizetest` prints the source when two levels
-- disagree.

local P = {}

--- A Park-Miller generator returning an integer in `1..bound`.
function P.rng(seed)
    local state = seed % 2147483647
    if state <= 0 then
        state = state + 2147483646
    end
    return function(bound)
        state = (state * 16807) % 2147483647
        return (state % bound) + 1
    end
end

--- The top-level statements of one program, as source text. `avoid` names shapes
--- to leave out, by the finding that made them disagree, while that finding is open.
function P.build(seed, avoid)
    avoid = avoid or {}
    local R = P.rng(seed)
    local function pick(list)
        return list[R(#list)]
    end
    local ivars, svars, helpers, shelpers = {}, {}, {}, {}
    local counter = 0
    local function fresh(prefix)
        counter = counter + 1
        return prefix .. counter
    end

    local iexpr, sexpr, bexpr
    -- integer names in scope besides the top-level ones: loop variables, parameters
    local scopeI = {}

    local function anyInt()
        local pool = {}
        for _, v in ipairs(ivars) do
            pool[#pool + 1] = v
        end
        for _, v in ipairs(scopeI) do
            pool[#pool + 1] = v
        end
        if #pool == 0 then
            return tostring(R(9))
        end
        return pick(pool)
    end

    iexpr = function(d)
        local c = d > 2 and R(3) or R(14)
        if c == 1 then
            return tostring(R(20) - 5)
        elseif c == 2 then
            return anyInt()
        elseif c == 3 then
            return "(" .. anyInt() .. ")"
        elseif c == 4 then
            return "(" .. iexpr(d + 1) .. " " .. pick({"+", "-", "*"}) .. " " .. iexpr(d + 1) .. ")"
        elseif c == 5 then
            return "(" .. iexpr(d + 1) .. " " .. pick({"//", "%"}) .. " " .. tostring(R(4)) .. ")"
        elseif c == 6 then
            return "-" .. anyInt()
        elseif c == 7 and #helpers > 0 then
            local h = pick(helpers)
            local args = {}
            for i = 1, h.arity do
                args[i] = (R(2) == 1) and anyInt() or iexpr(d + 1)
            end
            return h.name .. "(" .. table.concat(args, ", ") .. ")"
        elseif c == 8 then
            return "(" .. bexpr(d + 1) .. " and " .. iexpr(d + 1) .. " or " .. iexpr(d + 1) .. ")"
        elseif c == 9 then
            return "#" .. sexpr(d + 1)
        elseif c == 10 and not avoid["FRONTEND-07"] then
            return "(" .. anyInt() .. " ^ 2)"
        elseif c == 11 then
            return "(" .. iexpr(d + 1) .. " " .. pick({"&", "|", "~", "<<", ">>", "~>>"}) .. " " .. tostring(R(5) - 1) .. ")"
        elseif c == 12 then
            return "(" .. bexpr(d + 1) .. " ? " .. iexpr(d + 1) .. " : " .. iexpr(d + 1) .. ")"
        elseif c == 13 then
            return "(nil ?? " .. iexpr(d + 1) .. ")"
        end
        return anyInt()
    end

    sexpr = function(d)
        local c = d > 2 and R(3) or R(9)
        if c == 1 then
            return pick({'"a"', '"bc"', '""', '"x\\ny"', "'q'"})
        elseif c == 2 and #svars > 0 then
            return pick(svars)
        elseif c == 3 then
            return "tostring(" .. iexpr(d + 1) .. ")"
        elseif c == 4 then
            return "(" .. sexpr(d + 1) .. " .. " .. sexpr(d + 1) .. ")"
        elseif c == 5 then
            return "(" .. sexpr(d + 1) .. " .. " .. iexpr(d + 1) .. ")"
        elseif c == 6 and #shelpers > 0 then
            return pick(shelpers).name .. "(" .. sexpr(d + 1) .. ")"
        elseif c == 7 then
            return "string.rep(" .. sexpr(d + 1) .. ", 2)"
        elseif c == 8 then
            return "(" .. bexpr(d + 1) .. " and " .. sexpr(d + 1) .. " or " .. sexpr(d + 1) .. ")"
        end
        return '"s"'
    end

    bexpr = function(d)
        local c = d > 2 and R(2) or R(7)
        if c == 1 then
            return pick({"true", "false"})
        elseif c == 2 then
            return "(" .. iexpr(d + 1) .. " " .. pick({"<", "<=", "==", "~=", ">", ">="}) .. " " .. iexpr(d + 1) .. ")"
        elseif c == 3 then
            return "not " .. bexpr(d + 1)
        elseif c == 4 then
            return "(" .. bexpr(d + 1) .. " " .. pick({"and", "or"}) .. " " .. bexpr(d + 1) .. ")"
        elseif c == 5 then
            return "(" .. sexpr(d + 1) .. " == " .. sexpr(d + 1) .. ")"
        elseif c == 6 then
            return "(" .. sexpr(d + 1) .. " < " .. sexpr(d + 1) .. ")"
        end
        return "true"
    end

    local stmt
    local function block(depth, n)
        local out = {}
        for _ = 1, n or R(3) do
            out[#out + 1] = stmt(depth + 1)
        end
        return table.concat(out, "\n")
    end

    local function withLoopVar(name, f)
        scopeI[#scopeI + 1] = name
        local body = f()
        scopeI[#scopeI] = nil
        return body
    end

    stmt = function(depth)
        local c = depth > 2 and R(4) or R(22)
        if c == 1 and #ivars > 0 then
            return pick(ivars) .. " = " .. iexpr(0)
        elseif c == 2 then
            return "print(" .. iexpr(0) .. ", " .. sexpr(0) .. ")"
        elseif c == 3 then
            return "print(" .. bexpr(0) .. ")"
        elseif c == 4 and #ivars > 0 then
            return pick(ivars) .. " " .. pick({"+=", "-=", "*="}) .. " " .. iexpr(0)
        elseif c == 5 then
            return "if " .. bexpr(0) .. " then\n" .. block(depth) .. "\nelseif " .. bexpr(0) .. " then\n"
                .. block(depth) .. "\nelse\n" .. block(depth) .. "\nend"
        elseif c == 6 then
            local v = fresh("i")
            local a, b = R(5) - 2, R(6) - 1
            local step = R(3) == 1 and (", " .. pick({"1", "2", "-1"})) or ""
            return "for " .. v .. " = " .. a .. ", " .. b .. step .. " do\n"
                .. withLoopVar(v, function() return block(depth) end) .. "\nend"
        elseif c == 7 then
            -- ipairs over a literal inside a function (OPT-2)
            local f, t, acc, i, v = fresh("fi"), fresh("t"), fresh("n"), fresh("k"), fresh("v")
            local items = {}
            for j = 1, R(4) do
                local choice = R(6)
                if avoid["FRONTEND-01"] then
                    items[j] = iexpr(1)
                elseif choice == 1 then
                    items[j] = "nil"
                elseif choice == 2 then
                    items[j] = "..."
                else
                    items[j] = iexpr(1)
                end
            end
            local call = pick({"", "1", "1, 2", "1, nil, 3", iexpr(0) .. ", " .. iexpr(0)})
            return ("local function %s(...)\n  local %s = {%s}\n  local %s = 0\n  for %s, %s in ipairs(%s) do\n"
                .. "    %s = %s + %s\n  end\n  return %s\nend\nprint(%s(%s))")
                :format(f, t, table.concat(items, ", "), acc, i, v, t, acc, acc, i, acc, f, call)
        elseif c == 8 then
            -- string accumulation (OPT-5)
            local acc, i = fresh("acc"), fresh("j")
            local exit = pick({
                "",
                "",
                "if " .. i .. " == 2 then break end\n",
                avoid["FRONTEND-03"] and "" or ("if " .. i .. " == 2 then goto " .. acc .. "done end\n"),
            })
            local body = withLoopVar(i, function()
                local piece = pick({sexpr(1), iexpr(1), sexpr(1) .. " .. " .. iexpr(1)})
                return acc .. " = " .. acc .. " .. " .. piece
            end)
            local label = exit:find("goto") and ("\n::" .. acc .. "done::") or ""
            local tail = R(2) == 1 and ("print(" .. acc .. ")") or ("print(#" .. acc .. ", " .. acc .. ")")
            return ("do\nlocal %s = \"\"\nfor %s = 1, %d do\n%s%s\nend%s\n%s\nend")
                :format(acc, i, R(4), exit, body, label, tail)
        elseif c == 9 then
            -- presize (OPT-1)
            local t = fresh("tb")
            local lines = {"local " .. t .. " = {}"}
            local keys = {"a", "b", "c", "d"}
            for _ = 1, R(4) do
                local k = keys[R(4)]
                if R(4) == 1 then
                    lines[#lines + 1] = t .. "[" .. R(3) .. "] = " .. iexpr(1)
                else
                    lines[#lines + 1] = t .. "." .. k .. " = " .. (R(3) == 1 and (t .. ".a or 0") or iexpr(1))
                end
            end
            local length = avoid["FRONTEND-22"] and "" or (", #" .. t)
            lines[#lines + 1] = ("print(%s.a, %s.b, %s.c, %s.d, %s[1], %s[2]%s)"):format(t, t, t, t, t, t, length)
            return "do\n" .. table.concat(lines, "\n") .. "\nend"
        elseif c == 10 then
            local v = fresh("w")
            return ("do\nlocal %s = 0\nwhile %s < %d do\n%s = %s + 1\n%s\nend\nprint(%s)\nend")
                :format(v, v, R(4), v, v, withLoopVar(v, function() return block(depth) end), v)
        elseif c == 11 then
            -- closures capturing loop variables
            local fs, i = fresh("fs"), fresh("c")
            return ("do\nlocal %s = {}\nfor %s = 1, 3 do\n%s[#%s + 1] = function() return %s + %s end\nend\n"
                .. "for _, f in ipairs(%s) do print(f()) end\nend")
                :format(fs, i, fs, fs, i, withLoopVar(i, function() return iexpr(1) end), fs)
        elseif c == 12 then
            -- a block local shadowing a top-level one
            if #ivars == 0 then
                return "print(0)"
            end
            local v = pick(ivars)
            return ("do\nlocal %s = %s\n%s\nprint(%s)\nend"):format(v, iexpr(0), block(depth), v)
        elseif c == 13 and not avoid["FRONTEND-04"] then
            -- a loop variable shadowing a top-level one
            if #ivars == 0 then
                return "print(1)"
            end
            return ("for %s = 1, 2 do\n%s\nend"):format(pick(ivars), block(depth))
        elseif c == 14 then
            local i = fresh("q")
            return ("for %s = 1, 4 do\nif %s %% 2 == 0 then\ncontinue\nend\n%s\nend")
                :format(i, i, withLoopVar(i, function() return block(depth) end))
        elseif c == 15 then
            return "print(pcall(function() return " .. iexpr(0) .. " end))"
        elseif c == 16 then
            local v = fresh("r")
            return ("do\nlocal %s = 0\nrepeat\n%s = %s + 1\n%s\nuntil %s >= %d\nprint(%s)\nend")
                :format(v, v, v, withLoopVar(v, function() return block(depth) end), v, R(3), v)
        elseif c == 17 then
            local v = fresh("sv")
            return ("do\nlocal %s = %s\n%s = %s .. %s\nprint(%s)\nend"):format(v, sexpr(0), v, v, sexpr(0), v)
        elseif c == 18 then
            return "print(" .. sexpr(0) .. ")"
        elseif c == 19 and #ivars > 0 then
            return pick(ivars) .. " ??= " .. iexpr(0)
        elseif c == 20 then
            -- a local function whose body calls the helpers
            local f = fresh("g")
            return ("local function %s(p)\n%s\nreturn %s\nend\nprint(%s(%s))"):format(
                f,
                withLoopVar("p", function() return block(depth) end),
                withLoopVar("p", function() return iexpr(0) end),
                f,
                iexpr(0)
            )
        end
        return "print(" .. iexpr(0) .. ")"
    end

    local stmts = {}
    for _ = 1, R(3) do
        local v = fresh("x")
        stmts[#stmts + 1] = "local " .. v .. " = " .. iexpr(0)
        ivars[#ivars + 1] = v
    end
    for _ = 1, R(2) do
        local v = fresh("s")
        stmts[#stmts + 1] = "local " .. v .. " = " .. sexpr(0)
        svars[#svars + 1] = v
    end
    for _ = 1, R(3) do
        local h = fresh("h")
        local arity = R(3) - 1
        local params = {}
        for i = 1, arity do
            params[i] = "a" .. i
            scopeI[#scopeI + 1] = params[i]
        end
        local body = iexpr(0)
        for _ = 1, arity do
            scopeI[#scopeI] = nil
        end
        stmts[#stmts + 1] = ("local function %s(%s) return %s end"):format(h, table.concat(params, ", "), body)
        helpers[#helpers + 1] = {name = h, arity = arity}
    end
    do
        local h = fresh("sh")
        stmts[#stmts + 1] = ("local function %s(z) return z .. %s end"):format(h, sexpr(1))
        shelpers[#shelpers + 1] = {name = h}
    end
    for _ = 1, R(10) + 2 do
        stmts[#stmts + 1] = stmt(0)
    end
    return stmts
end

return P
